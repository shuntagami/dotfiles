# エージェント通知音

通知音の判定・音源・音量は `scripts/agent-notify.py` で管理する。ターミナルの種類には依存しない。

- Codex: `notify` → Computer Use の既存ラッパー → `codex/notify-chime.sh` → 共通スクリプト。
- Claude Code: `claude/settings.json` の `Stop` / `Notification` → 共通スクリプト。
- MulmoTerminal: `soundKinds: []` でアプリ側の通知音を無効にする。Web Push は別設定。

## 鳴る条件

完了音は通知イベントだけでは再生しない。Codex は対象ターンの `task_complete` と最終応答の一致、Claude Code は最終応答の `end_turn` と Stop フック後の `turn_duration` を確認する。さらに2秒後にも同じ終了状態なら一度だけ再生する。ログの書き込みを最大約3秒待つ。

中間応答・ツール実行・中断・子エージェントの終了・次のターンが始まった古い通知は鳴らさない。Claude Code の確認待ちは `permission_prompt` / `elicitation_dialog` / `elicitation_url_dialog` が対象。`idle_prompt` は完了後のリマインダーにもなるので鳴らさない。Codex のこの `notify` 経路は完了通知のみを扱う。

音源は `SOUNDS`、音量は `VOLUME`、完了確認の待ち時間は `SETTLE_SECONDS` で変更できる。再生済みIDのハッシュだけを `~/.cache/agent-completion-chime/` に保存し、同じ通知の二重再生を防ぐ。会話本文は保存しない。

## 反映と検証

Codex は既存のスクリプト呼び出し先を保っているので、次の通知から適用される。Claude Code は設定を読み直すためセッションを再起動すると確実。MulmoTerminal の音設定を変えた場合は開いているページも再読み込みする。

```sh
python3 -m unittest discover -s scripts -p test_agent_notify.py -v
bash -n codex/notify-chime.sh
```

テストは音声再生をモックするので実際の音は鳴らない。現在のログ形式で確認しているため、CLIの更新で形式が変わった場合やログが読めない場合は誤通知を避けて無音にする。2秒より後に別の自動処理が始まることまでは予測しない。
