# Screenpipe設定

このディレクトリでは、ScreenpipeのPipeプロンプトだけを管理する。

管理するもの:

- `pipes/*/pipe.md`

管理しないもの:

- `~/.screenpipe/db.sqlite`
- 録画、OCR、音声、文字起こしデータ
- Pipeの実行ログ
- Pipeの出力ファイル
- Pipe配下の `.pi/skills/*/SKILL.md`
- `~/.screenpipe/pi-chat/.pi/skills/*/SKILL.md`
- `~/.screenpipe/pi-agent/node_modules/`
- Slack webhookやAPIキーなどの接続情報

`~/dotfiles/scripts/deploy.sh` を実行すると、各 `pipe.md` が `~/.screenpipe/pipes/*/pipe.md` へシンボリックリンクされる。

`.pi/skills` 配下の `SKILL.md` は、Screenpipe/Pi AgentがPipe実行時に使う標準スキルとして複製される。ユーザーが編集するプロンプト本体ではないため、dotfilesでは管理しない。

## 複数端末で使う場合

ScreenpipeのローカルAPIは、その端末で記録された画面・音声だけを見る。

デスクトップとノートPCを行き来して作業する場合は、それぞれの端末でScreenpipeを起動し、このdotfilesをdeployする。Slack連携などの接続情報は端末ごとにScreenpipeアプリ側で設定する。

`hourly-work-report` はSlack投稿に端末名を含めるため、複数端末から投稿されてもどの端末の記録か分かる。
