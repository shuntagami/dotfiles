#!/usr/bin/env python3
"""Generate only changed narration; align canonical captions per beat, with caching."""
from __future__ import annotations
import argparse
import bisect
import concurrent.futures
import difflib
import json
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from video import load_project, read, write, fingerprint, file_hash, duration, local_source, speech_state, speech_payload, audio_source, ff

def api_key(name, env_file):
    import os
    value = os.environ.get(name)
    if not value and env_file:
        for line in Path(env_file).expanduser().read_text().splitlines():
            line = line.strip().removeprefix('export ')
            if '=' in line and not line.startswith('#'):
                key, candidate = line.split('=', 1)
                if key.strip() == name: value = candidate.strip().strip('"').strip("'")
    if not value: raise ValueError(f'Set {name} or supply an authorized --env-file; no credentials are embedded in this skill')
    return value

def api(endpoint, body, content_type, key):
    # Keep keys and signed/opaque response details out of logs and cache metadata.
    for attempt in range(3):
        request = urllib.request.Request('https://api.openai.com/v1/' + endpoint, data=body, headers={'Authorization': 'Bearer ' + key(), 'Content-Type': content_type})
        try:
            with urllib.request.urlopen(request, timeout=180) as response: return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code not in {429, 500, 502, 503, 504} or attempt == 2:
                raise RuntimeError(f'OpenAI {endpoint}: HTTP {exc.code}; inspect account access or request settings') from None
            try: delay = float(exc.headers.get('Retry-After', 2 ** attempt))
            except ValueError: delay = 2 ** attempt
            time.sleep(min(30, max(.2, delay)))
        except urllib.error.URLError:
            if attempt == 2: raise RuntimeError(f'OpenAI {endpoint}: connection failed') from None
            time.sleep(1 + attempt)

def clean(text):
    return ''.join(c for c in unicodedata.normalize('NFKC', text).casefold() if c.isalnum())

def normalize_pairs(pairs, aliases):
    flat=[]
    for char, timestamp in pairs:
        flat.extend((x,timestamp) for x in clean(char))
    aliases=sorted(((clean(a),clean(b)) for a,b in aliases.items() if clean(a)),key=lambda p:-len(p[0]))
    result=[];i=0
    while i<len(flat):
        match=next(((a,b) for a,b in aliases if ''.join(c for c,t in flat[i:i+len(a)])==a),None)
        if match:
            a,b=match;first=flat[i][1];last=flat[min(i+len(a),len(flat)-1)][1]
            result.extend((c,first+(last-first)*j/max(1,len(b))) for j,c in enumerate(b));i+=len(a)
        else:result.append(flat[i]);i+=1
    return result

def canonical_chunks(text):
    sentences=[s.strip() for s in re.split(r'(?<=[。！？!?])\s*|(?<=\.)\s+',text) if s.strip()]
    result=[]
    for sentence in sentences:
        # Keep two-line captions practical; detailed pixel-fit is validated during rendering.
        limit=70 if re.search(r'[\u3040-\u9fff]',sentence) else 140
        while len(sentence)>limit:
            choices=[i for i in range(limit//2,limit+1) if sentence[i-1] in '、,; ']
            cut=choices[-1] if choices else limit
            result.append(sentence[:cut].strip());sentence=sentence[cut:].strip()
        if sentence:result.append(sentence)
    return result

def align_cues(text, words, audio_seconds, aliases, minimum=.92):
    def normalized(t):return ''.join(c for c,_ in normalize_pairs([(c,0) for c in t],aliases))
    source='';chunks=[]
    for sentence in canonical_chunks(text):
        a=len(source);source+=normalized(sentence);chunks.append((sentence,a,len(source)))
    pairs=[]
    for word in words:
        value=word['word'];start=float(word['start']);end=float(word['end'])
        pairs.extend((c,start+(end-start)*i/max(1,len(value))) for i,c in enumerate(value))
    pairs=normalize_pairs(pairs,aliases);recognized=''.join(c for c,_ in pairs)
    matcher=difflib.SequenceMatcher(None,source,recognized,autojunk=False);matched={}
    for block in matcher.get_matching_blocks():
        for i in range(block.size):matched[block.a+i]=pairs[block.b+i][1]
    if matcher.ratio()<minimum or not matched:
        raise ValueError(f'Narration differs from the script ({matcher.ratio():.1%}); inspect/retry this beat, not the whole video')
    keys=sorted(matched)
    def at(i):
        if i>=len(source):return audio_seconds
        if i in matched:return matched[i]
        pos=bisect.bisect_left(keys,i)
        if pos==0:return 0
        if pos==len(keys):return matched[keys[-1]]+(audio_seconds-matched[keys[-1]])*(i-keys[-1])/max(1,len(source)-keys[-1])
        a,b=keys[pos-1],keys[pos];return matched[a]+(matched[b]-matched[a])*(i-a)/(b-a)
    cues=[];coverage=[]
    for sentence,a,b in chunks:
        ratio=sum(i in matched for i in range(a,b))/max(1,b-a);coverage.append(ratio)
        if b-a>=8 and ratio<.6:raise ValueError('An entire sentence may be missing from the audio; inspect this beat')
        cues.append({'start':max(0,min(audio_seconds,at(a)-.05)),'end':max(0,min(audio_seconds,at(b)-.05)),'text':sentence})
    for i in range(len(cues)-1):cues[i]['end']=cues[i+1]['start']
    cues[0]['start']=0;cues[-1]['end']=audio_seconds
    if any(c['end']-c['start']<.1 for c in cues):raise ValueError('Empty or implausibly short subtitle interval; audio may be incomplete')
    return cues,{'match_ratio':matcher.ratio(),'sentence_coverage':coverage}

def tts_one(root, data, plan, beat, state, key, force=False):
    bid=beat['id']
    if beat.get('audio'):
        local_source(root,beat['audio'],bid+' audio');return bid,None,'external audio'
    if not beat.get('text','').strip():return bid,None,'no speech'
    body=speech_payload(data,plan,beat);fp=fingerprint(body);old=state.get(bid,{}).get('tts',{})
    file=root/'build'/'audio'/f'{bid}-{fp[:16]}.wav';file.parent.mkdir(parents=True,exist_ok=True)
    if not force and old.get('fingerprint')==fp and file.is_file() and old.get('audio_sha256')==file_hash(file):return bid,None,'cached'
    for attempt in range(2):
        raw=api('audio/speech',json.dumps(body).encode(),'application/json',key)
        temp=file.with_suffix('.partial.wav');temp.write_bytes(raw)
        try:seconds=duration(temp)
        except Exception:
            temp.unlink(missing_ok=True)
            if attempt:raise ValueError(f'{bid}: invalid TTS audio') from None
            continue
        max_rate=float(plan.get('max_speech_chars_per_second',20 if data.get('lang')=='ja' else 30))
        if seconds<max(.12,len(clean(body['input']))/max_rate):
            temp.unlink(missing_ok=True)
            if attempt:raise ValueError(f'{bid}: TTS ended unexpectedly early')
            continue
        temp.replace(file)
        return bid,{'tts':{'fingerprint':fp,'text':beat['text'],'path':str(file.relative_to(root)),'audio_sha256':file_hash(file),'duration':seconds,'model':body['model'],'voice':body['voice']}},'generated'
    raise ValueError(f'{bid}: failed to generate complete narration')

def multipart_audio(file, language, terms):
    boundary='videoalignment'+uuid.uuid4().hex
    fields=[('model','whisper-1'),('response_format','verbose_json'),('timestamp_granularities[]','word'),('timestamp_granularities[]','segment')]
    if language:fields.append(('language',language.split('-')[0]))
    if terms:fields.append(('prompt',', '.join(terms)[:256]))
    parts=[f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode() for name,value in fields]
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="speech.mp3"\r\nContent-Type: audio/mpeg\r\n\r\n'.encode()+file.read_bytes()+b'\r\n')
    parts.append(f'--{boundary}--\r\n'.encode())
    return b''.join(parts),'multipart/form-data; boundary='+boundary

def align_one(root,data,plan,beat,state,key,force=False):
    bid=beat['id'];opt=plan.get('beats',{}).get(bid,{})
    if not beat.get('text','').strip() or opt.get('captions',True) is False or opt.get('captions_file'):return bid,None,'not needed'
    audio=audio_source(root,beat,state,data,plan)
    sha=file_hash(audio);aliases=plan.get('pronunciations',{});fp=fingerprint({'audio':sha,'text':beat['text'],'aliases':aliases,'model':'whisper-1'})
    old=state.get(bid,{}).get('align',{})
    if not force and old.get('fingerprint')==fp:return bid,None,'cached'
    folder=root/'build'/'alignment';folder.mkdir(parents=True,exist_ok=True);mp3=folder/f'{bid}-{fp[:16]}.mp3';response=folder/f'{bid}-{fp[:16]}.json'
    if not response.exists() or force:
        ff(['-i',audio,'-ar',24000,'-ac',1,'-c:a','libmp3lame','-b:a','96k',mp3])
        body,content_type=multipart_audio(mp3,data.get('lang'),list(aliases))
        result=json.loads(api('audio/transcriptions',body,content_type,key));write(response,result)
    else:result=read(response)
    cues,stats=align_cues(beat['text'],result.get('words',[]),duration(audio),aliases,float(plan.get('min_alignment_ratio',.92)))
    return bid,{'align':{'fingerprint':fp,'text':beat['text'],'audio_sha256':sha,'cues':cues,'stats':stats}},'aligned'

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',choices=['tts','align']);parser.add_argument('script');parser.add_argument('--beat',action='append');parser.add_argument('--jobs',type=int,default=3);parser.add_argument('--api-key-env',default='OPENAI_API_KEY');parser.add_argument('--env-file');parser.add_argument('--force',action='store_true');args=parser.parse_args()
    script,data,plan=load_project(args.script);root=script.parent;state=speech_state(root);chosen=set(args.beat or [b['id'] for b in data['beats']]);unknown=chosen-{b['id'] for b in data['beats']}
    if unknown:raise ValueError(f'Unknown beat IDs: {sorted(unknown)}')
    function=tts_one if args.command=='tts' else align_one
    key=lambda:api_key(args.api_key_env,args.env_file)
    errors=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,args.jobs)) as pool:
        pending={pool.submit(function,root,data,plan,b,state,key,args.force):b['id'] for b in data['beats'] if b['id'] in chosen}
        for future in concurrent.futures.as_completed(pending):
            try:
                bid,change,status=future.result()
                if change:state.setdefault(bid,{}).update(change);write(root/'build'/'speech.json',state)
                print(bid,status,flush=True)
            except Exception as exc:errors.append(f'{pending[future]}: {exc}')
    if errors:raise ValueError('\n'.join(errors))

if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,OSError) as exc:print(str(exc),file=sys.stderr);sys.exit(1)
