#!/usr/bin/env python3
"""Local MulmoScript subset -> cached clips, narration, subtitles and verified MP4."""
from __future__ import annotations
import argparse
import concurrent.futures
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import unicodedata
from functools import lru_cache
from pathlib import Path

KINDS = {'workflow', 'standalone', 'bridge', 'assembly-test'}
FPS_VALUES = {24, 25, 30, 50, 60}
ENGINE_VERSION = 1

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))

def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    tmp.replace(path)

def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()

@lru_cache(maxsize=256)
def _file_hash(path, size, mtime):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def file_hash(path):
    path = Path(path).resolve()
    stat = path.stat()
    return _file_hash(str(path), stat.st_size, stat.st_mtime_ns)

def probe(path):
    return json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)
    ], text=True))

def duration(path):
    return float(probe(path).get('format', {}).get('duration', 0))

def local_source(root, asset, label):
    src = asset.get('source', {})
    if src.get('kind') != 'path':
        raise ValueError(f'{label}: materialize a local asset first; only source.kind=path is supported')
    path = (root / src['path']).resolve()
    if not path.is_file():
        raise ValueError(f'{label}: missing asset {path}')
    return path

def load_project(script):
    script = Path(script).resolve()
    data = read(script)
    plan = read(script.parent / 'video-plan.json')
    if plan.get('kind') not in KINDS:
        raise ValueError(f'kind must be one of {sorted(KINDS)}')
    if int(plan.get('fps', 30)) not in FPS_VALUES:
        raise ValueError(f'fps must be one of {sorted(FPS_VALUES)}')
    beats = data.get('beats', [])
    ids = [b.get('id', '') for b in beats]
    if not ids or len(set(ids)) != len(ids) or any(not re.fullmatch(r'[A-Za-z0-9_-]+', x) for x in ids):
        raise ValueError('Each beat needs a unique nonempty id using letters, digits, _ or -')
    unknown = set(plan.get('beats', {})) - set(ids)
    if unknown:
        raise ValueError(f'Unknown beat IDs in video-plan.json: {sorted(unknown)}')
    w, h = data.get('canvasSize', {}).get('width', 1920), data.get('canvasSize', {}).get('height', 1080)
    if not isinstance(w, int) or not isinstance(h, int) or min(w, h) < 64 or w % 2 or h % 2:
        raise ValueError('Canvas dimensions must be positive even integers >=64')
    native_audio = data.get('audioParams', {})
    if native_audio.get('bgm') or native_audio.get('suppressSpeech') or any(native_audio.get(k, 0) for k in ['padding', 'introPadding', 'closingPadding', 'outroPadding']):
        raise ValueError('Native BGM/speech suppression/audio padding needs MulmoCast or pre-mixed assets; this adapter uses explicit local audio and video-plan durations')
    for spec in [data, *beats]:
        if spec.get('captionParams') or spec.get('texts'):
            raise ValueError('Use video-plan caption settings/captions_file, or render native caption options with MulmoCast')
        movie = spec.get('movieParams', {})
        if any(movie.get(k) for k in ['filters', 'transition', 'fillOption']):
            raise ValueError('Native movie filters/transitions need MulmoCast or pre-rendered media')
    return script, data, plan

def speech_state(root):
    path = root / 'build' / 'speech.json'
    return read(path) if path.exists() else {}

def speech_payload(data, plan, beat):
    speakers = data.get('speechParams', {}).get('speakers', {})
    name = beat.get('speaker') or next(iter(speakers), 'Presenter')
    if speakers and name not in speakers: raise ValueError(f'Unknown speaker: {name}')
    speaker = speakers.get(name, {})
    speaker = dict(speaker, **speaker.get('lang', {}).get(data.get('lang', ''), {}))
    if speaker.get('provider', 'openai') != 'openai':
        raise ValueError('speech.py supports OpenAI; use the selected provider or supply a local audio asset')
    options = dict(speaker.get('speechOptions', {}), **beat.get('speechOptions', {}))
    spoken = beat.get('text', '')
    for source, target in sorted(plan.get('pronunciations', {}).items(), key=lambda pair: -len(pair[0])):
        spoken = spoken.replace(source, target)
    body = {'model': speaker.get('model', 'gpt-4o-mini-tts'), 'voice': speaker.get('voiceId', 'marin'), 'input': spoken, 'response_format': 'wav'}
    if options.get('instruction'): body['instructions'] = options['instruction']
    if options.get('speed') is not None: body['speed'] = options['speed']
    return body

def audio_source(root, beat, state, data, plan):
    if beat.get('audio'):
        if beat['audio'].get('type') != 'audio':
            raise ValueError('Only local audio assets are supported; render MIDI upstream')
        return local_source(root, beat['audio'], beat['id'] + ' audio')
    item = state.get(beat['id'], {}).get('tts', {})
    path = root / item.get('path', '__missing_audio__')
    if path.is_file() and item.get('text') == beat.get('text', '') and item.get('fingerprint') == fingerprint(speech_payload(data, plan, beat)) and item.get('audio_sha256') == file_hash(path):
        return path
    if beat.get('text', '').strip():
        raise ValueError(f'{beat["id"]}: narration is missing or stale; run speech.py tts')
    return None

def validate_cues(cues, maximum):
    previous = 0.0
    for cue in cues:
        a, b = float(cue['start']), float(cue['end'])
        if not (0 <= a < b <= maximum + .06) or a < previous - .001 or not str(cue['text']).strip():
            raise ValueError('Invalid, overlapping, empty or out-of-bounds subtitle cue')
        previous = b
    return cues

def build_timeline(script):
    script, data, plan = load_project(script)
    root, fps, frame = script.parent, int(plan.get('fps', 30)), 0
    state, result = speech_state(root), []
    for beat in data['beats']:
        bid = beat['id']
        opt = plan.get('beats', {}).get(bid, {})
        media = beat.get('image', {})
        kind = media.get('type')
        if kind not in {'image', 'movie'}:
            raise ValueError(f'{bid}: unsupported {kind}; render this beat with MulmoCast or materialize image/movie first')
        source = local_source(root, media, bid)
        audio = audio_source(root, beat, state, data, plan)
        speed = float(opt.get('speed', beat.get('movieParams', {}).get('speed', 1)))
        if speed <= 0:
            raise ValueError('speed must be positive')
        start = float(opt.get('in', 0))
        available = duration(source) if kind == 'movie' else 0
        end = float(opt.get('out', available))
        if kind == 'movie' and not (0 <= start < end <= available + .05):
            raise ValueError(f'{bid}: invalid media interval {start}..{end} of {available}')
        span = (end - start) / speed if kind == 'movie' else 0
        keep_audio = bool(opt.get('keep_source_audio', kind == 'movie' and beat.get('audioParams', {}).get('movieVolume', data.get('audioParams', {}).get('movieVolume', 0)) > 0))
        if keep_audio and (kind != 'movie' or audio):
            raise ValueError(f'{bid}: source audio is exclusive with separate narration; pre-mix intentional combinations')
        if keep_audio and not any(s['codec_type'] == 'audio' for s in probe(source)['streams']):
            raise ValueError(f'{bid}: keep_source_audio requested but movie has no audio')
        ad = duration(audio) if audio else (span if keep_audio else 0)
        default = max(span, ad, float(beat.get('duration', 0) if not beat.get('text', '').strip() else 0)) or 3.0
        requested = float(opt.get('duration', default))
        if requested <= 0 or requested + .001 < ad:
            raise ValueError(f'{bid}: duration would truncate narration; trim or replace the audio explicitly')
        frames = math.ceil(requested * fps - 1e-8)
        length = frames / fps
        cues = []
        if opt.get('captions', True) is not False:
            if opt.get('captions_file'):
                cues = validate_cues(read(root / opt['captions_file']), ad or length)
            elif beat.get('text', '').strip():
                aligned = state.get(bid, {}).get('align', {})
                if not audio or aligned.get('audio_sha256') != file_hash(audio) or aligned.get('text') != beat['text']:
                    raise ValueError(f'{bid}: aligned subtitles missing or stale; run speech.py align or provide captions_file')
                cues = validate_cues(aligned['cues'], ad)
        result.append({
            'id': bid, 'title': opt.get('title', ''), 'label': opt.get('label', ''),
            'start': frame / fps, 'end': (frame + frames) / fps, 'duration': length, 'frames': frames,
            'media_type': kind, 'media': str(source), 'media_sha256': file_hash(source),
            'in': start, 'out': end, 'speed': speed, 'source_seconds': span,
            'audio': str(audio) if audio else None, 'audio_sha256': file_hash(audio) if audio else None,
            'audio_seconds': ad, 'keep_source_audio': keep_audio,
            'full_frame': bool(opt.get('full_frame', False)), 'fit': opt.get('fit', 'contain'),
            'cues': cues, 'hold_tail_seconds': max(0, length - span) if kind == 'movie' else 0,
            'trimmed_source_seconds': max(0, span - length)
        })
        frame += frames
    return script, data, plan, result

def ff(args):
    subprocess.run(['ffmpeg', '-y', '-hide_banner', '-loglevel', 'error', *map(str, args)], check=True)

def concat_file(path, files):
    def quote(value):
        value = str(Path(value).resolve())
        if '\n' in value or '\r' in value:
            raise ValueError('Newlines in media paths are unsupported')
        return "'" + value.replace("'", "'\\''") + "'"
    Path(path).write_text('\n'.join('file ' + quote(f) for f in files) + '\n')

def tempo(speed):
    filters = []
    while speed > 2:
        filters.append('atempo=2'); speed /= 2
    while speed < .5:
        filters.append('atempo=0.5'); speed /= .5
    filters.append(f'atempo={speed:.10f}')
    return ','.join(filters)

def render_parts(root, data, plan, timeline, jobs):
    w, h = data['canvasSize']['width'], data['canvasSize']['height']
    fps = int(plan.get('fps', 30))
    hh, ch = int(plan.get('header_px', round(h * .06))), int(plan.get('caption_px', round(h * .126)))
    if hh < 0 or ch < 0 or hh + ch >= h:
        raise ValueError('Invalid header/caption dimensions')
    cache = root / 'build' / 'parts'; cache.mkdir(parents=True, exist_ok=True)
    def one(item):
        geometry = (w, h, fps, hh, ch, plan.get('background', '#f8f5ee'), plan.get('crf', 19), plan.get('preset', 'fast'))
        vf_key = fingerprint({'engine': ENGINE_VERSION, 'media': item['media_sha256'], 'in': item['in'], 'out': item['out'], 'speed': item['speed'], 'frames': item['frames'], 'geometry': geometry, 'fit': item['fit'], 'full': item['full_frame']})[:20]
        clip = cache / f'{item["id"]}-{vf_key}.mp4'
        reused = clip.exists()
        if not reused:
            if item['media_type'] == 'image':
                args = ['-loop', '1', '-framerate', fps, '-i', item['media']]
            else:
                args = ['-ss', item['in'], '-t', item['out'] - item['in'], '-i', item['media']]
            area_h, y = (h, 0) if item['full_frame'] else (h - hh - ch, hh)
            area_h -= area_h % 2
            if item['fit'] == 'contain':
                size = f'scale={w}:{area_h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:{y}:color={geometry[5]}'
            elif item['fit'] == 'cover':
                size = f'scale={w}:{area_h}:force_original_aspect_ratio=increase,crop={w}:{area_h},pad={w}:{h}:0:{y}:color={geometry[5]}'
            else:
                raise ValueError('fit must be contain or cover')
            # Dense primary frames BEFORE later subtitle overlay; never overlay sparse image frames first.
            filters = f'setpts=(PTS-STARTPTS)/{item["speed"]},{size},setsar=1,fps={fps},tpad=stop_mode=clone:stop_duration={item["duration"]},format=yuv420p'
            ff([*args, '-an', '-vf', filters, '-frames:v', item['frames'], '-c:v', 'libx264', '-preset', geometry[7], '-crf', geometry[6], clip])
        audio_key = fingerprint({'audio': item['audio_sha256'] or (item['media_sha256'] if item['keep_source_audio'] else None), 'in': item['in'] if item['keep_source_audio'] else 0, 'out': item['out'] if item['keep_source_audio'] else 0, 'speed': item['speed'] if item['keep_source_audio'] else 1, 'duration': item['duration']})[:20]
        wav = cache / f'{item["id"]}-{audio_key}.wav'
        if not wav.exists():
            if item['audio']:
                args, filters = ['-i', item['audio']], ''
            elif item['keep_source_audio']:
                args = ['-ss', item['in'], '-t', item['out'] - item['in'], '-i', item['media']]
                filters = tempo(item['speed']) + ','
            else:
                args, filters = ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo'], ''
            ff([*args, '-vn', '-af', filters + f'aresample=48000,apad,atrim=duration={item["duration"]}', '-ar', 48000, '-ac', 2, '-c:a', 'pcm_s16le', wav])
        return dict(item, clip=str(clip), padded_audio=str(wav), video_cache_hit=reused)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        return list(pool.map(one, timeline))

def find_font(root, plan, text):
    if plan.get('font'):
        path = (root / Path(plan['font']).expanduser()).resolve()
        if not path.is_file(): raise ValueError(f'Missing font: {path}')
        return path
    mac = Path('/System/Library/Fonts')
    choices = [p for p in mac.glob('*') if unicodedata.normalize('NFC', p.name) == 'ヒラギノ角ゴシック W3.ttc']
    choices += [Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'), Path('/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc')]
    if not re.search(r'[\u3040-\u9fff]', text): choices.append(Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
    for path in choices:
        if path.is_file(): return path
    raise ValueError('Set video-plan.json font to an installed font that supports the script language')

def wrap(text, font, width):
    if font.getlength(text) <= width: return [text]
    choices = [i for i in range(1, len(text)) if max(font.getlength(text[:i]), font.getlength(text[i:])) <= width]
    if not choices: raise ValueError('Caption exceeds two lines: split this cue into shorter sentences')
    cut = min(choices, key=lambda i: abs(font.getlength(text[:i]) - font.getlength(text[i:])) - (width * .08 if text[i-1] in '、。 ,.!?' else 0))
    return [text[:cut].strip(), text[cut:].strip()]

def stamp(seconds):
    ms = round(seconds * 1000); h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f'{h:02}:{m:02}:{s:02},{ms:03}'

def overlays(root, data, plan, timeline):
    from PIL import Image, ImageDraw, ImageFont
    w, h = data['canvasSize']['width'], data['canvasSize']['height']
    hh, ch = int(plan.get('header_px', round(h * .06))), int(plan.get('caption_px', round(h * .126)))
    needs_text = any(b['cues'] or (hh and not b['full_frame']) for b in timeline)
    font_path = find_font(root, plan, ''.join(c['text'] for b in timeline for c in b['cues']) + data.get('title', '')) if needs_text else None
    get_font = lambda n: ImageFont.truetype(str(font_path), n) if font_path else ImageFont.load_default()
    subtitle = get_font(max(16, round(h * .0315)))
    heading = get_font(max(14, round(h * .025)))
    small = get_font(max(12, round(h * .019)))
    cues = [dict(c, start=c['start'] + b['start'], end=c['end'] + b['start'], beat=b['id']) for b in timeline for c in b['cues']]
    if cues and ch < subtitle.size * 2.7: raise ValueError('caption_px is too small for two subtitle lines')
    srt = '\n'.join(f'{i+1}\n{stamp(c["start"])} --> {stamp(c["end"])}\n' + '\n'.join(wrap(c['text'], subtitle, w * .92)) + '\n' for i, c in enumerate(cues))
    (root / 'build' / 'captions.srt').write_text(srt, encoding='utf-8')
    bounds = sorted({0, timeline[-1]['end'], *[b['start'] for b in timeline], *[c['start'] for c in cues], *[c['end'] for c in cues]})
    folder = root / 'build' / 'overlays'; folder.mkdir(exist_ok=True)
    files, manifest = [], []
    for i, (a, b) in enumerate(zip(bounds, bounds[1:])):
        if b-a < .001: continue
        mid = (a+b)/2
        beat = next(x for x in timeline if x['start'] <= mid < x['end'])
        cue = next((x for x in cues if x['start'] <= mid < x['end']), None)
        image = Image.new('RGBA', (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(image)
        bar = plan.get('bar_color', '#142d46')
        if not beat['full_frame']:
            if hh:
                d.rectangle((0, 0, w, hh), fill=bar)
                title = beat['title'] or data.get('title', '')
                label = beat['label']
                if heading.getlength(title) + small.getlength(label) > w * .92: raise ValueError('Header title/label too long')
                d.text((w*.025, hh*.22), title, font=heading, fill='white')
                d.text((w*.975-small.getlength(label), hh*.29), label, font=small, fill='#c7d9eb')
            if ch: d.rectangle((0, h-ch, w, h), fill=bar)
        if cue:
            # A cue over a full-frame module is explicit, so supply a legible caption band.
            d.rectangle((0, h-ch, w, h), fill=bar)
            lines = wrap(cue['text'], subtitle, w * .92)
            y = h-ch + (ch - len(lines)*subtitle.size*1.3)/2
            for j, line in enumerate(lines): d.text(((w-subtitle.getlength(line))/2, y+j*subtitle.size*1.3), line, font=subtitle, fill='white')
        path = folder / f'{i:04}.png'; image.save(path)
        files.append({'start': a, 'end': b, 'path': str(path), 'has_caption': bool(cue)})
        manifest.extend(["file '" + str(path).replace("'", "'\\''") + "'", f'duration {b-a:.9f}'])
    manifest.append(manifest[-2]); (root/'build'/'overlays.ffconcat').write_text('\n'.join(manifest)+'\n')
    return files

def metadata(path, title, timeline):
    def clean(s): return str(s).replace('\\', '\\\\').replace('=', '\\=').replace(';', '\\;').replace('#', '\\#').replace('\n', ' ')
    text = ';FFMETADATA1\ntitle=' + clean(title) + '\n'
    for b in timeline:
        text += f'\n[CHAPTER]\nTIMEBASE=1/1000\nSTART={round(b["start"]*1000)}\nEND={round(b["end"]*1000)}\ntitle={clean(b["title"] or b["id"])}\n'
    Path(path).write_text(text)

def render(script, jobs=2):
    script, data, plan, timeline = build_timeline(script)
    root = script.parent; build = root/'build'; build.mkdir(exist_ok=True)
    timeline = render_parts(root, data, plan, timeline, jobs)
    overlay = overlays(root, data, plan, timeline)
    # Cues, glyphs and timing belong to the render key, not the cached source-video clips.
    key = fingerprint({'engine': ENGINE_VERSION, 'script': data, 'plan': plan, 'timeline': [{k:v for k,v in x.items() if k!='video_cache_hit'} for x in timeline], 'overlays': [file_hash(x['path']) for x in overlay]})[:16]
    output = root/'output'/f'{plan["kind"]}-{key}.mp4'; output.parent.mkdir(exist_ok=True)
    if not output.exists():
        concat_file(build/'video.ffconcat', [b['clip'] for b in timeline])
        concat_file(build/'audio.ffconcat', [b['padded_audio'] for b in timeline])
        ff(['-f', 'concat', '-safe', 0, '-i', build/'video.ffconcat', '-c', 'copy', build/'picture.mp4'])
        ff(['-f', 'concat', '-safe', 0, '-i', build/'audio.ffconcat', '-c:a', 'pcm_s16le', build/'narration.wav'])
        metadata(build/'chapters.ffmeta', data.get('title', ''), timeline)
        fps = int(plan.get('fps', 30))
        # fps precedes overlay. The input picture is already CFR, which prevents frozen captions.
        graph = f'[0:v]fps={fps},tpad=stop_mode=clone:stop_duration=1[base];[base][1:v]overlay=0:0:format=auto:shortest=0,format=yuv420p[v]'
        ff(['-i', build/'picture.mp4', '-f', 'concat', '-safe', 0, '-i', build/'overlays.ffconcat', '-i', build/'narration.wav', '-i', build/'chapters.ffmeta', '-filter_complex', graph, '-map', '[v]', '-map', '2:a:0', '-map_metadata', 3, '-map_chapters', 3, '-t', timeline[-1]['end'], '-c:v', 'libx264', '-preset', plan.get('preset', 'fast'), '-crf', plan.get('crf', 19), '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', 48000, '-ac', 2, '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', '-progress', build/'progress.txt', output])
    manifest = {'version': 1, 'kind': plan['kind'], 'coverage': plan.get('coverage', []), 'title': data.get('title', ''), 'file': str(output), 'sha256': file_hash(output), 'duration': timeline[-1]['end'], 'fps': int(plan.get('fps', 30)), 'canvas': data['canvasSize'], 'caption_px': int(plan.get('caption_px', round(data['canvasSize']['height']*.126))), 'timeline': timeline, 'overlays': overlay, 'verified': False, 'allow_silent': bool(plan.get('allow_silent', False)), 'verify_times': plan.get('verify_times', [])}
    previous = read(build/'latest.json') if (build/'latest.json').exists() else {}
    if previous.get('sha256') == manifest['sha256'] and previous.get('verified'):
        manifest['verified'] = True
        manifest['verification'] = previous['verification']
    write(build/'latest.json', manifest)
    print(json.dumps({'file': str(output), 'seconds': manifest['duration'], 'clips_reused': sum(b['video_cache_hit'] for b in timeline), 'clips_total': len(timeline)}, ensure_ascii=False))
    return manifest

def verify(manifest_path):
    from PIL import Image, ImageDraw
    path = Path(manifest_path).resolve(); m = read(path); video = Path(m['file'])
    if file_hash(video) != m['sha256']: raise ValueError('Output changed after rendering; rerender before verification')
    info = probe(video); v = next(x for x in info['streams'] if x['codec_type']=='video'); a = next(x for x in info['streams'] if x['codec_type']=='audio')
    fps = m['fps']; tolerance = 1/fps + .025
    if (v['width'], v['height']) != (m['canvas']['width'], m['canvas']['height']): raise ValueError('Wrong output dimensions')
    if a.get('channels') != 2 or a.get('sample_rate') != '48000' or a.get('codec_name') != 'aac' or v.get('codec_name') != 'h264': raise ValueError('Wrong delivery codecs/audio format')
    if abs(float(info['format']['duration'])-m['duration']) > tolerance or abs(float(v['duration'])-float(a['duration'])) > tolerance: raise ValueError('Audio/video duration mismatch')
    if abs(int(v['nb_frames'])-round(m['duration']*fps)) > 1: raise ValueError('Unexpected dropped video frames')
    decoded = subprocess.run(['ffmpeg', '-hide_banner', '-v', 'info', '-xerror', '-i', str(video), '-af', 'volumedetect', '-f', 'null', '-'], capture_output=True, text=True, check=True)
    volume = re.search(r'mean_volume:\s+(-?[\d.]+|-inf) dB', decoded.stderr)
    if not m.get('allow_silent') and (not volume or volume.group(1)=='-inf' or float(volume.group(1)) < -45): raise ValueError('Output is silent or unexpectedly quiet')
    folder = path.parent/'verification'; folder.mkdir(exist_ok=True)
    times = sorted(set([round(b['start']+b['duration']*.61, 3) for b in m['timeline']] + [float(x) for x in m.get('verify_times', [])]))
    if any(t<0 or t>=m['duration'] for t in times): raise ValueError('verify_times outside output duration')
    rows = math.ceil(len(times)/3); sheet = Image.new('RGB', (1440, max(1,rows)*294), '#e9eef5'); draw = ImageDraw.Draw(sheet); checks=[]
    for i, t in enumerate(times):
        frame = folder/f'{i:03}.png'; ff(['-ss', t, '-i', video, '-frames:v', 1, frame])
        image = Image.open(frame).convert('RGB'); thumb = image.copy(); thumb.thumbnail((480,270)); sheet.paste(thumb, ((i%3)*480,(i//3)*294)); draw.text(((i%3)*480+8,(i//3)*294+274), f'{t:.2f}s', fill='#142d46')
        overlay = next((x for x in m.get('overlays', []) if x['start']<=t<x['end']), None)
        if overlay and overlay['has_caption']:
            rect=(0, m['canvas']['height']-m['caption_px'], m['canvas']['width'], m['canvas']['height'])
            expected=Image.open(overlay['path']).convert('RGB').crop(rect); actual=image.crop(rect)
            pixels = lambda image: image.get_flattened_data() if hasattr(image, 'get_flattened_data') else image.getdata()
            am=[min(x)>180 for x in pixels(actual)]; em=[min(x)>180 for x in pixels(expected)]
            iou=sum(x and y for x,y in zip(am,em))/max(1,sum(x or y for x,y in zip(am,em)))
            if iou < .82: raise ValueError(f'Subtitle timing/glyph mismatch at {t}s: {iou:.3f}')
            checks.append({'seconds':t,'subtitle_glyph_iou':iou})
    sheet.save(folder/'contact-sheet.jpg', quality=92)
    m['verified']=True; m['verification']={'media':info, 'mean_volume_db':volume.group(1) if volume else None, 'sampled_times':times, 'subtitle_checks':checks, 'contact_sheet':str(folder/'contact-sheet.jpg'), 'human_visual_review':'required separately'}
    write(path,m); print(json.dumps({'verified':True,'file':str(video),'samples':len(times),'contact_sheet':m['verification']['contact_sheet']},ensure_ascii=False)); return m

def assemble(project, output_kind):
    """Normalize already-finished modules, preserve their existing narration and captions."""
    path=Path(project).resolve(); manifest=read(path); root=path.parent
    if output_kind not in KINDS: raise ValueError('Choose an explicit output kind')
    modules=manifest.get('modules', []); beats=[]; options={}; coverage=[]
    for i, module in enumerate(modules):
        media=(root/module['path']).resolve()
        if module.get('sha256') and module['sha256']!=file_hash(media): raise ValueError('Module fingerprint changed')
        bid=f'module-{i+1:02}'; beats.append({'id':bid,'text':'','image':{'type':'movie','source':{'kind':'path','path':str(media)}},'audioParams':{'movieVolume':1}})
        options[bid]={'keep_source_audio':True,'full_frame':True,'captions':False,'title':module.get('title',bid)}
        coverage.extend(module.get('coverage', []))
    if not beats: raise ValueError('No modules to assemble')
    data=read(Path(__file__).resolve().parent.parent/'assets'/'example.mulmo.json')
    data.update({'title':manifest.get('title',''), 'lang':manifest.get('lang','ja'),'canvasSize':manifest.get('canvasSize',{'width':1920,'height':1080}),'beats':beats})
    work=root/'assembly'; work.mkdir(exist_ok=True); write(work/'script.mulmo.json',data)
    write(work/'video-plan.json',{'version':1,'kind':output_kind,'coverage':sorted(set(coverage)),'fps':manifest.get('fps',30),'header_px':0,'caption_px':0,'beats':options,'allow_silent':manifest.get('allow_silent',False)})
    return render(work/'script.mulmo.json')

def main():
    parser=argparse.ArgumentParser(description=__doc__); sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('init'); p.add_argument('directory'); p.add_argument('--kind',choices=sorted(KINDS),default='workflow')
    for name in ['plan','render']:
        p=sub.add_parser(name); p.add_argument('script'); p.add_argument('--jobs',type=int,default=2)
    p=sub.add_parser('verify'); p.add_argument('manifest')
    p=sub.add_parser('assemble'); p.add_argument('modules'); p.add_argument('--kind',choices=sorted(KINDS),required=True)
    args=parser.parse_args()
    if args.command=='init':
        dest=Path(args.directory); dest.mkdir(parents=True,exist_ok=True); assets=Path(__file__).resolve().parent.parent/'assets'
        for source,name in [('example.mulmo.json','script.mulmo.json'),('example-plan.json','video-plan.json')]:
            if (dest/name).exists(): raise ValueError(f'Will not overwrite existing {dest/name}')
        shutil.copy2(assets/'example.mulmo.json',dest/'script.mulmo.json'); plan=read(assets/'example-plan.json'); plan['kind']=args.kind; write(dest/'video-plan.json',plan); (dest/'media').mkdir(exist_ok=True); print(dest.resolve())
    elif args.command=='plan':
        script,data,plan,timeline=build_timeline(args.script); write(script.parent/'build'/'timeline.json',timeline); print(json.dumps([{'id':b['id'],'seconds':b['duration'],'hold_tail_seconds':b['hold_tail_seconds'],'trimmed_source_seconds':b['trimmed_source_seconds']} for b in timeline],ensure_ascii=False,indent=2))
    elif args.command=='render': render(args.script,max(1,args.jobs))
    elif args.command=='verify': verify(args.manifest)
    else: assemble(args.modules,args.kind)

if __name__=='__main__':
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(str(exc),file=sys.stderr); sys.exit(1)
