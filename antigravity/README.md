# Antigravity CLI 設定（settings.json）

`~/.gemini/antigravity-cli/settings.json` は `agy` がワークスペース信頼（`trustedWorkspaces`）や設定変更時に一時ファイルからの置き換えで保存するため、シンボリックリンクにするとリンクが外れます。また、`trustedWorkspaces` には端末固有・非公開のプロジェクトパスが入ります（この dotfiles リポジトリは公開です）。

そのため、`scripts/sync-antigravity-config.py` でシンボリックリンクではなく共有キーだけをマージ同期します。

```sh
python3 ~/dotfiles/scripts/sync-antigravity-config.py apply            # dotfiles -> この Mac（deploy.sh でも実行）
python3 ~/dotfiles/scripts/sync-antigravity-config.py save             # この Mac -> dotfiles（コミット前に git diff で確認）
python3 ~/dotfiles/scripts/sync-antigravity-config.py apply --dry-run  # 変更予定の確認のみ
```

## 同期方針

- **共有する設定**：`altScreenMode`（MulmoTerminal 上のスクロールで `tmux copy-mode` に落ちて貼り付け保護が壊れる問題を避けるため `"always"` を設定）や `model` などの共通キー。
- **同期しないキー（`LOCAL_KEYS`）**：`trustedWorkspaces` は `apply` で上書きせず、`save` でも dotfiles 側へ取り込みません。
