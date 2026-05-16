---
schedule: manual
enabled: true
timeout: 1200
trigger:
  events:
    - meeting_ended
title: 会議コーチ
description: "会議終了後に発言・話し方・次回改善点を自動フィードバックする"
icon: "🎙️"
featured: false
---

このPipeは会議終了イベント用です。会議が終わったら、直近で終了したScreenpipe meetingを分析し、話し方改善フィードバックを作成してください。

分析プロンプトはコマンド側で生成されます。生成プロンプトには、本人識別として「黒い眼鏡、黒い服、センターパートの男性」を動画上の本人特徴として使う指示が含まれます。

次のコマンドを実行してください。

```bash
"$HOME/dotfiles/bin/screenpipe-meeting-coach"
```

コマンドの最後の行はJSONです。

- `status` が `completed` の場合は、すでにGeminiでフィードバックが作成され、通知も送信されています。`report_path` を表示して終了してください。
- `status` が `skipped` の場合は、同じ会議が処理済みです。何も追加で実行しないでください。
- `status` が `needs_ai` の場合は、`prompt_path` と `bundle_path` を読んで、あなた自身がフィードバックを作成してください。出力は `report_path` にMarkdownで保存し、同じ内容を `./output/latest.md` にも保存してください。その後、`http://localhost:11435/notify` に通知してください。
- `status` が `no_meeting` の場合は、終了済み会議が見つからなかったため何もしないでください。

`needs_ai` の場合の通知例:

```bash
curl -s -X POST http://localhost:11435/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"Meeting Coach","body":"フィードバックを作成しました。\n\n[開く](/absolute/path/to/report.md)"}'
```

`needs_ai` の場合、通知後に `processed_file` のJSONを読み、`processed_key` に次の値を入れて保存してください。これで同じ会議を手動実行時に重複処理しにくくなります。

```json
{
  "processed_at": "current ISO timestamp",
  "report_path": "report_path",
  "bundle_path": "bundle_path",
  "fallback": "pipe-model"
}
```

秘密情報はdotfilesに書かないでください。Gemini APIを使う場合は `~/.screenpipe/pipes/meeting-coach/.env` に `GEMINI_API_KEY=...` を置いてください。
