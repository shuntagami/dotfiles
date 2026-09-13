import copy
import io
import json
import math
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import video
import speech

def sound(seconds=1.0):
    out=io.BytesIO()
    with wave.open(out,'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(48000)
        w.writeframes(b''.join(struct.pack('<h',int(9000*math.sin(2*math.pi*440*i/48000))) for i in range(round(48000*seconds))))
    return out.getvalue()

class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="video's isolated test ")
        self.root=Path(self.temp.name)
        (self.root/'media').mkdir()
        Image.new('RGB',(640,360),'#cc8844').save(self.root/'media/first image.png')
        video.ff(['-f','lavfi','-i','color=c=blue:s=640x360:r=30','-t',1.2,'-an','-c:v','libx264',self.root/'media/second clip.mp4'])
        (self.root/'media/a.wav').write_bytes(sound(1.07))
        (self.root/'media/b.wav').write_bytes(sound(1.31))
        self.data=video.read(Path(__file__).resolve().parents[2]/'assets/example.mulmo.json')
        self.data['canvasSize']={'width':640,'height':360}
        self.data['title']='検証用の操作動画'
        self.data['beats']=[
            {'id':'one','text':'最初の説明です。次の説明です。','image':{'type':'image','source':{'kind':'path','path':'media/first image.png'}},'audio':{'type':'audio','source':{'kind':'path','path':'media/a.wav'}}},
            {'id':'two','text':'結果を確認します。','image':{'type':'movie','source':{'kind':'path','path':'media/second clip.mp4'}},'audio':{'type':'audio','source':{'kind':'path','path':'media/b.wav'}}}
        ]
        self.plan={'version':1,'kind':'workflow','coverage':['確認','完了'],'fps':30,'header_px':25,'caption_px':56,'beats':{'one':{'title':'前半','captions_file':'one.json'},'two':{'title':'後半','in':.2,'out':1.1,'captions_file':'two.json'}},'verify_times':[.2,.75,1.8]}
        video.write(self.root/'one.json',[{'start':0,'end':.5,'text':'最初の説明です。'},{'start':.5,'end':1.07,'text':'次の説明です。'}])
        video.write(self.root/'two.json',[{'start':0,'end':1.31,'text':'結果を確認します。'}])
        self.script=self.root/'script.mulmo.json'
        self.save()

    def tearDown(self):self.temp.cleanup()
    def save(self):
        video.write(self.script,self.data);video.write(self.root/'video-plan.json',self.plan)

    def test_timeline_rejects_audio_truncation_and_wrong_ids(self):
        _,_,_,timeline=video.build_timeline(self.script)
        self.assertGreater(timeline[1]['hold_tail_seconds'],0)
        self.assertAlmostEqual(timeline[-1]['end']*30,round(timeline[-1]['end']*30))
        self.data['beats'][1]['movieParams']={'speed':2};self.save()
        self.assertEqual(video.build_timeline(self.script)[3][1]['speed'],2)
        self.data['captionParams']={'fontSize':24};self.save()
        with self.assertRaisesRegex(ValueError,'native caption'):video.build_timeline(self.script)
        self.data.pop('captionParams');self.plan['beats']['two']['duration']=.5;self.save()
        with self.assertRaisesRegex(ValueError,'truncate narration'):video.build_timeline(self.script)
        self.plan['beats']['two'].pop('duration');self.plan['beats']['missing']={};self.save()
        with self.assertRaisesRegex(ValueError,'Unknown beat'):video.build_timeline(self.script)

    def test_render_cache_captions_and_file_fingerprint(self):
        first=video.render(self.script)
        self.assertFalse(any(x['video_cache_hit'] for x in first['timeline']))
        checked=video.verify(self.root/'build/latest.json')
        self.assertTrue(checked['verified'])
        self.assertGreaterEqual(len(checked['verification']['subtitle_checks']),3)
        second=video.render(self.script)
        self.assertEqual(first['file'],second['file'])
        self.assertTrue(all(x['video_cache_hit'] for x in second['timeline']))
        self.assertTrue(second['verified'])
        Image.new('RGB',(640,360),'#227744').save(self.root/'media/first image.png')
        third=video.render(self.script)
        self.assertNotEqual(first['file'],third['file'])
        self.assertEqual([x['video_cache_hit'] for x in third['timeline']],[False,True])
        self.assertTrue(Path(first['file']).exists())
        m=video.read(self.root/'build/latest.json');m['sha256']='wrong';video.write(self.root/'build/latest.json',m)
        with self.assertRaisesRegex(ValueError,'changed after rendering'):video.verify(self.root/'build/latest.json')

    def test_frozen_subtitle_is_detected(self):
        m=video.render(self.script);bad=self.root/'frozen.mp4'
        video.ff(['-i',m['file'],'-loop',1,'-i',m['overlays'][0]['path'],'-filter_complex','[0:v][1:v]overlay=0:0:shortest=1[v]','-map','[v]','-map','0:a:0','-t',m['duration'],'-c:v','libx264','-c:a','copy',bad])
        m['file']=str(bad);m['sha256']=video.file_hash(bad);video.write(self.root/'build/latest.json',m)
        with self.assertRaisesRegex(ValueError,'Subtitle timing'):video.verify(self.root/'build/latest.json')

    def test_existing_modules_keep_audio_and_coverage(self):
        m=video.render(self.script)
        video.write(self.root/'modules.json',{'title':'結合確認','canvasSize':{'width':640,'height':360},'modules':[{'path':m['file'],'sha256':m['sha256'],'title':'操作','coverage':['操作']},{'path':m['file'],'sha256':m['sha256'],'title':'補足','coverage':['補足']}]})
        joined=video.assemble(self.root/'modules.json','assembly-test')
        self.assertEqual(joined['coverage'],['操作','補足'])
        self.assertAlmostEqual(joined['duration'],2*m['duration'],places=3)
        self.assertTrue(video.verify(self.root/'assembly/build/latest.json')['verified'])

    def test_tts_cache_and_voice_change_without_network(self):
        beat=copy.deepcopy(self.data['beats'][0]);beat.pop('audio')
        state={};calls=[]
        def fake(endpoint,body,ct,key):calls.append(json.loads(body));return sound(2)
        with patch.object(speech,'api',side_effect=fake):
            bid,record,status=speech.tts_one(self.root,self.data,self.plan,beat,state,lambda:'test-only')
            state[bid]=record
            self.assertEqual(status,'generated')
            self.assertEqual(speech.tts_one(self.root,self.data,self.plan,beat,state,lambda:'test-only')[2],'cached')
            self.assertEqual(len(calls),1)
            changed=copy.deepcopy(self.data);changed['speechParams']['speakers']['Presenter']['voiceId']='cedar'
            with self.assertRaisesRegex(ValueError,'missing or stale'):video.audio_source(self.root,beat,state,changed,self.plan)
            speech.tts_one(self.root,changed,self.plan,beat,state,lambda:'test-only')
            self.assertEqual(len(calls),2)
        long=dict(beat,text='これは途中で途切れてはいけない説明です。'*30)
        with patch.object(speech,'api',return_value=sound(.2)):
            with self.assertRaisesRegex(ValueError,'unexpectedly early'):speech.tts_one(self.root,self.data,self.plan,long,{},lambda:'test-only')

    def test_alignment_rejects_missing_sentence(self):
        text='最初の説明です。次の操作を確認します。'
        words=[{'word':'最初の説明です。','start':0,'end':1},{'word':'次の操作を確認します。','start':1,'end':2}]
        cues,stats=speech.align_cues(text,words,2,{})
        self.assertEqual(len(cues),2);self.assertEqual(stats['match_ratio'],1)
        with self.assertRaises(ValueError):speech.align_cues(text,words[:1],2,{})
        cues,stats=speech.align_cues('Claude Codeで直します。',[{'word':'クロードコードで直します。','start':0,'end':2}],2,{'Claude Code':'クロードコード'})
        self.assertEqual(stats['match_ratio'],1)

if __name__=='__main__':unittest.main()
