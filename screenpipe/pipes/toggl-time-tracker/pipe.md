---
schedule: '*/15 8-20 * * *'
enabled: false
preset:
- opus
connections:
- toggl
source_slug: toggl-time-tracker
installed_version: 1
source_hash: 22cab185b6e95d9f
title: Toggl時間記録
description: 画面アクティビティをもとにTogglの時間記録を自動更新する
history: true
---

# 実行指示
以下のタスクをすぐに実行してください。ユーザーに入力を求めないでください。何を実行するかを質問しないでください。下記のコマンドを実行し、結果をログに残してください。

このPipeの目的は、画面アクティビティをもとにTogglの時間記録を自動更新することです。

## 手順

以下の処理を順番に実行してください。ユーザーと会話せず、必要なAPI呼び出しと判断を行ってください。

1. `.env` を読み、`TOGGL_API_KEY` を取得する。
2. Screenpipeからアクティビティ概要とウィンドウタイトルを取得する。
3. 現在のTogglタイマーとTogglプロジェクト一覧を取得する。
4. 現在のタイマーを維持するか、停止して新規開始するか、新規開始するかを判断する。
5. 実行した内容をログに残す。

## Screenpipe APIの呼び出し

次の2つを両方呼び出してください。1つ目は全体像、つまりどのアプリをどれくらい使ったかを取得します。2つ目は、ウィンドウタイトルから具体的な作業文脈を取得します。

```bash
# ステップ1: アクティビティ概要。アプリ別の内訳と音声話者の概要
curl -s "http://localhost:3030/activity-summary?start_time={{start_time}}&end_time={{end_time}}"

# ステップ2: ウィンドウタイトル。accessibilityデータは整理されていてノイズが少ない
curl -s "http://localhost:3030/search?content_type=accessibility&limit=30&max_length=200&start_time={{start_time}}&end_time={{end_time}}"

# ステップ3: 音声データを取得する

# ステップ4: OCRデータを取得する
```

## Toggl APIの呼び出し

最初に `.env` を読み、`TOGGL_API_KEY` を取得してください。その後、下記のcurlコマンドでは実際のキー値を直接入れてください。`$TOGGL_API_KEY` のようなシェル変数は使わないでください。

ベースURL: `https://api.track.toggl.com/api/v9`
認証: APIキーをユーザー名、`api_token` をパスワードとしてBasic認証を使う。

### 現在のタイマーを取得する
```bash
curl -s https://api.track.toggl.com/api/v9/me/time_entries/current \
  -u YOUR_ACTUAL_API_KEY_HERE:api_token
```

### プロジェクト一覧を取得する
```bash
curl -s https://api.track.toggl.com/api/v9/me/projects \
  -u YOUR_ACTUAL_API_KEY_HERE:api_token
```

### ワークスペースIDを取得する
```bash
curl -s https://api.track.toggl.com/api/v9/me \
  -u YOUR_ACTUAL_API_KEY_HERE:api_token | bun -e "const d=JSON.parse(await Bun.stdin.text()); console.log(d.default_workspace_id)"
```

### タイマーを開始する
```bash
WORKSPACE_ID=$(curl -s https://api.track.toggl.com/api/v9/me \
  -u YOUR_ACTUAL_API_KEY_HERE:api_token | bun -e "const d=JSON.parse(await Bun.stdin.text()); console.log(d.default_workspace_id)")

curl -s -X POST "https://api.track.toggl.com/api/v9/workspaces/$WORKSPACE_ID/time_entries" \
  -u YOUR_ACTUAL_API_KEY_HERE:api_token \
  -H "Content-Type: application/json" \
  -d "{
    \"created_with\": \"screenpipe-pipe\",
    \"description\": \"説明をここに入れる\",
    \"project_id\": PROJECT_ID_OR_NULL,
    \"workspace_id\": $WORKSPACE_ID,
    \"start\": \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\",
    \"duration\": -1
  }"
```

### タイマーを停止する
```bash
CURRENT=$(curl -s https://api.track.toggl.com/api/v9/me/time_entries/current \
  -u YOUR_ACTUAL_API_KEY_HERE:api_token)
ENTRY_ID=$(echo "$CURRENT" | bun -e "const d=JSON.parse(await Bun.stdin.text()); console.log(d.id)")
WORKSPACE_ID=$(echo "$CURRENT" | bun -e "const d=JSON.parse(await Bun.stdin.text()); console.log(d.workspace_id)")

curl -s -X PATCH "https://api.track.toggl.com/api/v9/workspaces/$WORKSPACE_ID/time_entries/$ENTRY_ID/stop" \
  -u YOUR_ACTUAL_API_KEY_HERE:api_token
```

## ウィンドウタイトルから作業説明を抽出する方法

accessibilityデータは `[アプリ名] ウィンドウタイトル` のような行を返します。そこから具体的な作業内容を抽出してください。

### 例:

| ウィンドウタイトル | Togglに入れる説明の例 |
|---|---|
| `WezTerm \| ✳ ChatGPT OAuth Integration` | `コーディング: chatgpt oauth` |
| `WezTerm \| ✳ Student Discount Feature` | `コーディング: student discount` |
| `WezTerm \| ✳ Unified Transcription Engine Refactor` | `コーディング: transcription refactor` |
| `Arc \| john@abcd.com \| Inbox \| abcd, inc. \| Intercom` | `カスタマーサポート` |
| `Arc \| Discord \| #welcome \| screenpi.pe` | `コミュニティ: discord` |
| `Arc \| PR #432 - fix audio crash \| GitHub` | `コードレビュー: audio crash fix` |
| `Zoom \| Team standup` | `会議: team standup` |
| `Arc \| YouTube \| How to build pipes` | `調査: youtube` |
| `Figma \| screenpipe landing page` | `デザイン: landing page` |
| `Obsidian \| daily note` | `執筆: notes` |

### 抽出ルール:
1. アクティビティ概要から、最も長く使われている主要アプリを見つける。
2. アプリ名だけでなく、具体的なウィンドウタイトルを使う。`screenpipe development` は曖昧です。`コーディング: chatgpt oauth` のように具体化してください。
3. WezTermに `✳ Claude Code` のような汎用タイトルだけが出ている場合は、同じ時間帯の他のWezTermタイトルを見て実際のタスク名を推定する。汎用タイトルは、Claude Codeが待機中またはタスク間にいる可能性を示します。
4. 複数のタスクが見える場合は、ウィンドウタイトルの出現回数が多いものを主要タスクとして扱う。
5. 形式は `{カテゴリ}: {具体的な文脈}` にする。2から5語程度で簡潔にする。
6. 音声に複数話者が見える場合は会議の可能性が高いので、`会議: {ウィンドウタイトルから分かる文脈}` を使う。

## プロジェクトへの対応付け

Togglのプロジェクト一覧を取得した後、アクティビティに最も近い既存プロジェクトを名前で選んでください。タイマー開始時に `project_id` を設定してください。対応するプロジェクトがない場合は、`project_id` に `null` を使ってください。

## タイマーを切り替えるか維持するか

重要: 現在のタイマー取得エンドポイントを呼び出した後、レスポンスを必ず確認してください。
- レスポンスが `null` または空の場合は、タイマーが動いていません。必ず新しいタイマーを開始してください。
- レスポンスに `"id"` を含むJSONオブジェクトがある場合は、タイマーが動いています。`"description"` フィールドを確認してください。

### 判断ルール

Screenpipeデータから現在の主要タスクを抽出した後、動作中タイマーの説明と比較してください。

1. タイマーが動いていない場合
   - 現在のアクティビティをもとに、必ず新しいタイマーを開始する。
   - タイマーが動いていないのに、何もしない判断をしてはいけない。

2. タイマーが動いていて、現在の作業と一致している場合
   - 両方の説明から主要キーワードを取り出して比較する。
   - 例: タイマーが `コーディング: oauth`、ウィンドウが `ChatGPT OAuth` なら一致。
   - 例: タイマーが `会議: standup`、ウィンドウが `Zoom | Team standup` なら一致。
   - 例: タイマーが `コーディング: oauth`、ウィンドウが `調査: docs` なら不一致。
   - 一致している場合は維持し、何もしない。

3. タイマーが動いていて、現在の作業が異なる場合
   - 次の条件では切り替える。
   - 主要キーワードが異なる。例: コーディングから会議、調査からデザイン。
   - 同じカテゴリでもタスクが異なる。例: `コーディング: oauth` から `コーディング: transcription`。
   - タイマーが45分を超えて動いており、新しい作業が5分以上優勢になっている。
   - 古いタイマーを停止し、新しいタイマーを現在時刻で開始する。

4. Screenpipeのアクティビティデータが空、または画面がアイドル状態の場合
   - 何もしない。動いているタイマーはそのままにする。

### 切り替え前の確認

タイマーを切り替える前に、次を確認してください。
- 新しいアクティビティがウィンドウタイトルに2回以上出ていること。ノイズを除外するためです。
- アクティビティのタイムスタンプが直近10分以内であること。古いデータで判断しないでください。
- タイマー開始から2分未満の場合は、すぐに切り替えず少し待つ。短時間の細かい切り替えを避けるためです。

## 重要ルール

- 最初に `.env` を読み、`TOGGL_API_KEY` を取得してから、curlコマンドに実際の値を入れる。
- 実行した内容を `./output/{{date}}.log` に短く追記する。
- Toggl APIが失敗した場合は、エラーをログに残して処理を続ける。クラッシュしない。
- できるだけ素早く判断する。必要最小限の確認を行い、API呼び出しと判断を完了する。
- 時刻を正確に扱う。現在時刻を確認し、古いアクティビティではなく現在の作業に対応するタイマーになっているか確認する。
- インフラ上の上限があるため、レスポンスは300秒以内に完了させる。
