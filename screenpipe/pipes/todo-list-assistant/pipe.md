---
schedule: every 1h
enabled: false
preset:
- screenpipe-cloud
source_slug: todo-list-assistant
installed_version: 1
source_hash: a4ceb8ac9c927319
icon: 🔔
featured: true
template: true
description: 最近のアクティビティからTODO候補を抽出して通知する
title: フォローアップ通知
---

このPipeはフォローアップ通知用です。以下の指示をそのまま実行してください。どのPipeを実行するかを質問しないでください。

## ステップ1: 既存のTODOリストを読む

`~/.screenpipe/pipes/todo-list-assistant/output/todos.md` を読んでください。存在しない場合は、新規作成する前提で進めてください。

## ステップ2: 直近1時間のアクティビティを検索する

画面と音声から、対応が必要そうな項目を探してください。
- 自分がやると言ったこと
- 自分に割り当てられたタスク
- 言及された期限
- まだ返信していなさそうな未読メッセージ
- 失敗している作業。例: エラー、クラッシュ、ビルド失敗

```bash
curl -s "http://localhost:3030/search?content_type=all&limit=15&start_time=<START_TIME>&end_time=<END_TIME>" -o /tmp/followup.json
```

**結果が空の場合は何も出力せずに終了してください。ファイルも更新しないでください。**

## ステップ3: TODOリストを更新する

`~/.screenpipe/pipes/todo-list-assistant/output/todos.md` に次の形式で書いてください。

```markdown
# TODOリスト
最終更新: [timestamp]

## 今日中
- [ ] タスク - 文脈: どこで、誰が、いつ言及したか

## 今週
- [ ] タスク - 文脈

## 待ち
- [ ] [相手] の対応待ち - [date] に確認

## 完了済み (直近3日)
- [x] タスク - [date] に完了
```

**ルール**:
- 重複を避ける。同じタスクを2回追加しない。
- 完了した証拠が見えた場合は完了扱いにする。例: メール送信済み、返信済み、ビルド成功。
- 7日より古い項目は削除する。

## ステップ4: 通知を送る

```bash
curl -X POST http://localhost:11435/notify \
  -H 'Content-Type: application/json' \
  -d '{"title": "フォローアップ通知", "body": "- タスク1\n- タスク2\n\n一覧: ~/.screenpipe/pipes/todo-list-assistant/output/todos.md"}'
```

新しい緊急項目がある場合だけ通知してください。新しい項目がない場合は何もしないでください。
