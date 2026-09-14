# エージェント通知音

通知音の判定・音源・音量は `scripts/agent-notify.py` で管理する。ターミナルの種類には依存しない。

- Codex: `notify` → Computer Use の既存ラッパー → `codex/notify-chime.sh` → 共通スクリプト。
- Claude Code: `claude/settings.json` の `Stop` / `Notification` → 共通スクリプト。
- Cursor CLI: `~/.cursor/hooks.json` の `stop` → 共通スクリプト。`scripts/install-cursor-notify.py` が既存フックを残して登録し、`deploy.sh` からも実行する。
- MulmoTerminal: `soundKinds: []` でアプリ側の通知音を無効にする。Web Push は別設定。

## 鳴る条件

Codex・Claude Code の完了音は通知イベントだけでは再生しない。Codex は同じターンIDの `task_complete`、Claude Code は最終応答の `end_turn` と Stop フック後の `turn_duration` を確認し、一度だけ再生する。終了記録があれば追加の待ち時間は設けない。Codex の通知とログでは同じターンでも本文の表現が異なる場合があるため、本文の完全一致は要求しない。

Cursor は明示的な終了イベント `stop` の `status: completed` のみで再生する。`aborted`・`error`・中間応答・`subagentStop` は対象外。会話IDと generation ID の組で重複を防ぐ。入力待ちの通知は未対応。[Cursor Hooks仕様](https://cursor.com/docs/hooks)を参照。別の stop フックが自動継続を返す場合、その継続の有無までは判定しない。

通知がログの書き込みより先に届く場合に限り、0.5秒間隔で最大5回読み直す。時間経過や出力の静けさを完了の根拠にはしない。読み直しても終了記録を確認できなければ鳴らさない。

中間応答・ツール実行・中断・子エージェントの終了・次のターンが始まった古い通知は鳴らさない。Claude Code の確認待ちは `permission_prompt` / `elicitation_dialog` / `elicitation_url_dialog` が対象。`idle_prompt` は完了後のリマインダーにもなるので鳴らさない。Codex のこの `notify` 経路は完了通知のみを扱う。

音源は `SOUNDS`、音量は `VOLUME` で変更できる。再生済みIDのハッシュだけを `~/.cache/agent-completion-chime/` に保存し、同じ通知の二重再生を防ぐ。会話本文は保存しない。

## 反映と検証

Codex は既存のスクリプト呼び出し先を保っているので、次の通知から適用される。Claude Code は設定を読み直すためセッションを再起動すると確実。MulmoTerminal の音設定を変えた場合は開いているページも再読み込みする。

Cursor は `python3 ~/dotfiles/scripts/install-cursor-notify.py` を実行後、CLIセッションを起動し直す。2026.09.10-fd3934a の対話モードが対象で、`--print` は `stop` が発火しないため対象外。

`~/.cursor/hooks.json` は他のアプリも書く共有ファイルなのでシンボリックリンクにせず、通知フックだけ追加する。既存の MulmoTerminal の状態転送フックは保持する。MulmoTerminal 4.23.0 は独自フックの混在するファイルを自動更新しないため、ポートや Node のパスを変更する場合は既存の転送コマンドも見直す必要がある。MulmoTerminal の状態表示・Web Push と通知音は別であり、`soundKinds: []` は音だけを止める。

```sh
python3 -m unittest discover -s scripts -p test_agent_notify.py -v
python3 -m unittest discover -s scripts -p test_install_cursor_notify.py -v
bash -n codex/notify-chime.sh
```

テストは音声再生をモックするので実際の音は鳴らない。現在のログ形式で確認しているため、CLIの更新で形式が変わった場合やログが読めない場合は誤通知を避けて無音にする。ここで確認するのはエージェントのターン終了であり、依頼全体の達成や将来の自動継続を判定するものではない。
