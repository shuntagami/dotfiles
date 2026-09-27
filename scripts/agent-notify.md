# エージェント通知音

Codex・Claude Codeの独自通知音は `scripts/agent-notify.py` で管理する。Cursor CLIはMulmoTerminal標準の通知を使う。

- Codex: `notify` → Computer Use の既存ラッパー → `codex/notify-chime.sh` → 共通スクリプト。
- Claude Code: `claude/settings.json` の `Stop` / `Notification` → 共通スクリプト。
- Cursor CLI: MulmoTerminalが管理する `~/.cursor/hooks.json` → MulmoTerminalの通知音。独自の音声フックは追加しない。
- MulmoTerminal: `soundKinds: ["finished", "waiting"]` で既定の通知対象を有効にする。音を再生するブラウザでも通知音をオンにする。Web Push は別設定。

## 鳴る条件

Codex・Claude Code の完了音は通知イベントだけでは再生しない。Codex は同じターンIDの `task_complete`、Claude Code は最終応答の `end_turn` と Stop フック後の `turn_duration` を確認し、一度だけ再生する。終了記録があれば追加の待ち時間は設けない。Codex の通知とログでは同じターンでも本文の表現が異なる場合があるため、本文の完全一致は要求しない。

Cursorの完了通知はMulmoTerminal標準のStopイベント処理に従う。Cursorの承認待ちイベントは標準連携の制約があり、入力待ち音が常に使えるわけではない。

通知がログの書き込みより先に届く場合に限り、0.5秒間隔で最大5回読み直す。時間経過や出力の静けさを完了の根拠にはしない。読み直しても終了記録を確認できなければ鳴らさない。

中間応答・ツール実行・中断・子エージェントの終了・次のターンが始まった古い通知は鳴らさない。Claude Code の確認待ちは `permission_prompt` / `elicitation_dialog` / `elicitation_url_dialog` が対象。`idle_prompt` は完了後のリマインダーにもなるので鳴らさない。Codex のこの `notify` 経路は完了通知のみを扱う。

音源は `SOUNDS`、音量は `VOLUME` で変更できる。再生済みIDのハッシュだけを `~/.cache/agent-completion-chime/` に保存し、同じ通知の二重再生を防ぐ。会話本文は保存しない。

## 反映と検証

Codex は既存のスクリプト呼び出し先を保っているので、次の通知から適用される。Claude Code は設定を読み直すためセッションを再起動すると確実。MulmoTerminal の音設定を変えた場合は開いているページも再読み込みする。

Cursorの旧通知フックは `python3 ~/dotfiles/scripts/remove-cursor-notify.py` で除去する（deployでも実行）。ほかのフックは保持する。Cursor CLIのセッションを再開して設定を読み直す。

MulmoTerminalは独自フックが混在したファイルの自動更新を見送る。旧フックが混在した状態でNodeを更新すると、削除されたCellar内のNodeを参照し続ける場合がある。独自フックを除去し、MulmoTerminalが自身の状態通知フックを管理できる状態に戻す。通常ターミナルから起動したCursorの独自通知音は、この移行で提供しなくなる。

```sh
python3 -m unittest discover -s scripts -p test_agent_notify.py -v
python3 -m unittest discover -s scripts -p test_remove_cursor_notify.py -v
bash -n codex/notify-chime.sh
```

テストは音声再生をモックするので実際の音は鳴らない。現在のログ形式で確認しているため、CLIの更新で形式が変わった場合やログが読めない場合は誤通知を避けて無音にする。ここで確認するのはエージェントのターン終了であり、依頼全体の達成や将来の自動継続を判定するものではない。
