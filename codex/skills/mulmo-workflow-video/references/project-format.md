# 制作形式と実行方法

## ツールの役割

- `script.mulmo.json`：話す内容と、場面ごとの画像・動画・音声の参照。安定したbeat IDを使う。
- `video-plan.json`：切り出し位置、字幕、画面レイアウト、成果物の種類など、このFFmpeg実装の編集設定。
- `speech.py`：OpenAI音声生成と、台本に対応付けた字幕の時刻取得。明示実行時だけネットワークを使う。
- `video.py`：ローカル素材の映像化、結合、字幕合成、検証。ネットワークを使わない。

このアダプターはMulmoCast CLIの代替をすべて実装したものではない。`image.type` が `image` / `movie`、`source.kind` が `path` の素材と、ローカル音声を扱う。画像生成は適切な画像生成ツールで行い、画像をプロジェクトへ保存してからパスを設定する。

HTML、slide DSL、Mermaid、動画生成プロンプトなどを直接描画したい場合は、対象環境のMulmoCast CLI・スキーマを確認するか、先にローカル画像・動画として作る。nativeのBGM、字幕設定、トランジション、音声padding等はこのスクリプトへ黙って持ち込まない。必要ならnative CLIまたは事前の素材加工を使う。

## 最初の準備

FFmpeg（`ffmpeg` と `ffprobe`、libx264対応）とPython 3.10以降、Pillowが必要。既存の利用可能な環境があれば再利用する。依存がなければプロジェクトまたは一時ディレクトリのvenvへ入れる。

```bash
python3 -m venv .venv
.venv/bin/pip install -r /path/to/mulmo-workflow-video/scripts/requirements.txt
.venv/bin/python /path/to/mulmo-workflow-video/scripts/video.py init ./video-project --kind workflow
```

初期化は `script.mulmo.json`、`video-plan.json`、`media/` を作る。サンプルのメディア参照は生成済みファイルではないので、自分の台本・素材へ置き換える。既存のプロジェクトファイルは上書きしない。

`kind` は `standalone`、`workflow`、`bridge`、`assembly-test`。`coverage` に「原稿編集」「公開」「完了表示」のように、実際に含む内容を記す。字幕や音声の生成前に、今回求められた成果物の範囲と一致させる。

## 作成・改訂

```bash
python /path/to/skill/scripts/speech.py tts ./video-project/script.mulmo.json
python /path/to/skill/scripts/speech.py align ./video-project/script.mulmo.json
python /path/to/skill/scripts/video.py plan ./video-project/script.mulmo.json
python /path/to/skill/scripts/video.py render ./video-project/script.mulmo.json --jobs 2
python /path/to/skill/scripts/video.py verify ./video-project/build/latest.json
```

音声APIのキーは `OPENAI_API_KEY`。必要なら `--api-key-env KEY_NAME` または、使用が認められた `--env-file /path/to/settings.env` を `speech.py` に渡す。キーの値をコマンド文字列・原稿・ログへ埋め込まない。キャッシュだけで済む実行ではキーを要求しない。

`speech.py` の対象を限定する例：

```bash
python /path/to/skill/scripts/speech.py tts script.mulmo.json --beat 02-complete
python /path/to/skill/scripts/speech.py align script.mulmo.json --beat 02-complete
```

同じ設定と内容の場面は再生成しない。音声の途中切れや認識の失敗を確認してやり直すときだけ、対象beatを指定して `--force` を使う。動画修正のたびに全音声・全字幕を強制生成し直さない。複数の制作プロセスで同じプロジェクトのキャッシュへ同時に書かない。

## 編集設定

```json
{
  "version": 1,
  "kind": "workflow",
  "coverage": ["原稿確認", "完了操作"],
  "fps": 30,
  "header_px": 64,
  "caption_px": 136,
  "font": "/path/to/Japanese-capable-font.ttc",
  "pronunciations": {"Claude Code": "クロードコード"},
  "beats": {
    "02-complete": {
      "title": "完了の表示まで確認する",
      "label": "操作デモ：架空データ",
      "in": 5.2,
      "out": 17.5,
      "speed": 1,
      "fit": "contain"
    }
  },
  "verify_times": [23.5]
}
```

- `in` / `out`：元動画の秒数。`speed` を指定した場合、選択区間の映像速度を変更する。beat側の `movieParams.speed` も読めるが、plan指定を優先する。
- `duration`：編集後の場面の長さを指定する場合だけ使う。ナレーションを切る長さは拒否する。
- 通常の尺は、ナレーションと選択した映像区間の長い方。短い映像は最終フレームを保持し、短い音声は無音で埋める。フレーム単位に切り上げて時間割りする。
- `plan` の出力に、映像末尾を保持する秒数と映像を省略する秒数が出る。操作完了の場面が切れていないか、不要な長い停止画面にならないか確認する。
- `fit: contain` は画像全体を保持する。`cover` ははみ出す部分を切るので、画面操作や文字を失わない場合だけ使う。
- `font` は省略するとmacOSのヒラギノやLinuxのNoto CJKを探す。対象言語を表示できるフォントを選ぶ。小さな出力でも字幕は最低16pxにし、2行分の領域を確保する。
- `pronunciations` は読み方の明示的な置換辞書。短すぎるキーで別の単語まで置換しないよう、製品名などを十分な長さで指定する。
- `verify_times` は動画全体の秒数。最後の「送信済み」等、章の中央以外に見たい場面を指定する。

## 既存音声と字幕

beatの `audio: {"type":"audio","source":{"kind":"path","path":"audio/clip.wav"}}` を指定すると、音声生成より優先する。素材を明示した後に声の設定だけ変えても、その素材は自動で別の声にはならない。

通常、字幕は音声と元の `text` を場面ごとに照合して作る。声・原稿・発音指定が変われば必要な音声を作り直し、音声ファイルまたは台本が変われば字幕の整合性を再確認する。元原稿にない認識結果を、そのまま字幕にしない。

既に検証した字幕がある場合は、planの各beatへ `captions_file` を指定できる。内容は `[{"start":0,"end":2.5,"text":"説明文です。"}]` のような配列で、時刻はそのbeatの先頭から。手動字幕と音声の内容の整合性は人が確認する。音声を変更したとき、手動字幕の時刻を流用しない。

字幕を付けないことが明示されている場面は `captions: false`。別の音声と元動画の音声を黙って二重に再生しない。元動画の音声を使う場合は、textを空にし `keep_source_audio: true` とする（`audioParams.movieVolume: 1` も対応）。意図的に混ぜる場合は事前に音声素材を作るかnative CLIを使う。

## 単体版の結合

完成済みの動画をそのまま部品にするときは、音声や字幕を再生成しない。

```json
{
  "title": "説明と操作本編",
  "canvasSize": {"width":1920,"height":1080},
  "modules": [
    {"path":"intro.mp4","title":"道具の説明","coverage":["概要"]},
    {"path":"workflow.mp4","title":"操作本編","coverage":["原稿確認","完了操作"]}
  ]
}
```

```bash
python /path/to/skill/scripts/video.py assemble modules.json --kind workflow
python /path/to/skill/scripts/video.py verify assembly/build/latest.json
```

各moduleに `sha256` を付けると、指定した動画が差し替わっていた場合に停止する。結合の入力動画は同じサイズ・fps・音声形式へそろえ、元の字幕と音声を保持する。完成版の種類は `--kind` で明示する。入門と補足だけの結合を、操作本編として扱わない。

## 出力

`output/<kind>-<fingerprint>.mp4` に保存する。版が変わると別ファイルになる。`build/latest.json` に再生ファイル、ハッシュ、尺、内容、素材、字幕、検証状態を記録する。機械検証はそのファイルのハッシュに結び付く。

`build/verification/contact-sheet.jpg` と、重要な場面の元サイズ画像を目視確認する。字幕検証は描画された字幕の画素も比較し、表示が止まったり時刻がずれたりしていないかを見る。機械検証の成功だけで、操作の意味や説明内容が正しいことにしない。
