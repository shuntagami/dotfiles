# Screenpipe設定

このディレクトリでは、ScreenpipeのPipeプロンプトと、実行時に使われる標準スキルの参照スナップショットを管理する。

管理するもの:

- `pipes/*/pipe.md`
- `runtime-skills/*/SKILL.md`

管理しないもの:

- `~/.screenpipe/db.sqlite`
- 録画、OCR、音声、文字起こしデータ
- Pipeの実行ログ
- Pipeの出力ファイル
- `~/.screenpipe/pipes/*/.pi/skills/*/SKILL.md` の上書きやリンク化
- `~/.screenpipe/pi-chat/.pi/skills/*/SKILL.md` の上書きやリンク化
- `~/.screenpipe/pi-agent/node_modules/`
- Slack webhookやAPIキーなどの接続情報

`~/dotfiles/scripts/deploy.sh` を実行すると、各 `pipe.md` が `~/.screenpipe/pipes/*/pipe.md` へシンボリックリンクされる。

`.pi/skills` 配下の `SKILL.md` は、Screenpipe/Pi AgentがPipe実行時に使う標準スキルとして複製するファイルです。実体把握のために `runtime-skills/` にユニークな内容だけを保存しますが、Screenpipe側の実行ファイルは上書きもリンク化もしません。

## 実行時スキル

現在確認できている `SKILL.md` は、内容としては次の3種類です。

| dotfiles側 | 元の配置 | SHA-256 |
|---|---|---|
| `runtime-skills/screenpipe-api-basic/SKILL.md` | `~/.screenpipe/pi-chat/.pi/skills/screenpipe-api/SKILL.md`、`~/.screenpipe/pipes/toggl-time-tracker/.pi/skills/screenpipe-api/SKILL.md` | `1f24a35f5de36b60261859f4b3f3c118381bd8392bd75c8a8a45fec7ae38aa13` |
| `runtime-skills/screenpipe-api-memory/SKILL.md` | `~/.screenpipe/pipes/focus-assistant/.pi/skills/screenpipe-api/SKILL.md`、`~/.screenpipe/pipes/hourly-work-report/.pi/skills/screenpipe-api/SKILL.md`、`~/.screenpipe/pipes/todo-list-assistant/.pi/skills/screenpipe-api/SKILL.md` | `3ebf6710bb3edfb77977d58ae74bd24bcc8dc93fc0656b42e16dce5877f4a888` |
| `runtime-skills/screenpipe-cli/SKILL.md` | `~/.screenpipe/pi-chat/.pi/skills/screenpipe-cli/SKILL.md`、`~/.screenpipe/pipes/*/.pi/skills/screenpipe-cli/SKILL.md` | `8868c91499a65803222653b8ea66339f7b2eba22ae63cde8a8cab0f25bb3662d` |

`~/.screenpipe/pi-agent/node_modules/.../SKILL.md` は依存パッケージ内のサンプルなので、管理対象に含めません。

## 複数端末で使う場合

ScreenpipeのローカルAPIは、その端末で記録された画面・音声だけを見る。

デスクトップとノートPCを行き来して作業する場合は、それぞれの端末でScreenpipeを起動し、このdotfilesをdeployする。Slack連携などの接続情報は端末ごとにScreenpipeアプリ側で設定する。

`hourly-work-report` はSlack投稿に端末名を含めるため、複数端末から投稿されてもどの端末の記録か分かる。

## 休憩ログ

## 作業ログ

勤務中かどうかは `work-start` / `work-end` で記録する。

```bash
work-start                  # 作業開始
work-start ELE監査          # メモ付きで作業開始
work-status                 # 作業中か確認
work-end                    # 作業終了
work-end 明日はCTA調査から  # メモ付きで作業終了
```

ログは `~/.screenpipe/work-state/work.jsonl` にJSONLで保存される。

初回導入後は、`work-start` するまで勤務外扱いになる。明示的に勤務外状態を残したい場合は、`work-start` していなくても `work-end` を実行できる。

`work-end` 後は、PCが起動したままでも `focus-assistant` と `hourly-work-report` は何もしない。

作業中に `break-start` したまま `work-end` すると、未終了の休憩は自動で終了する。

Slack通知を使う場合は、端末ごとにローカル設定を置く。

```bash
mkdir -p ~/.screenpipe/work-state
chmod 700 ~/.screenpipe/work-state
cat > ~/.screenpipe/work-state/config.env <<'EOF'
WORK_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
EOF
chmod 600 ~/.screenpipe/work-state/config.env
```

既に `BREAK_SLACK_WEBHOOK_URL` や `SLACK_WEBHOOK_URL` がある場合は、それも利用される。

## 休憩ログ

作業中の休憩は、Screenpipeの録画を止めずに休憩ログとして記録する。

```bash
break-start            # 休憩開始
break-start 昼食       # メモ付きで休憩開始
break-status           # 休憩中か確認
break-end              # 休憩終了
break-end 戻りました   # メモ付きで休憩終了
```

ログは `~/.screenpipe/work-state/breaks.jsonl` にJSONLで保存される。

Slack通知を使う場合は、端末ごとにローカル設定を置く。

```bash
mkdir -p ~/.screenpipe/work-state
chmod 700 ~/.screenpipe/work-state
cat > ~/.screenpipe/work-state/config.env <<'EOF'
BREAK_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
EOF
chmod 600 ~/.screenpipe/work-state/config.env
```

このファイルはdotfiles管理しない。

`focus-assistant` は休憩中に通知しない。`hourly-work-report` は直近1時間の休憩時間を作業時間から分けてSlackに投稿する。
