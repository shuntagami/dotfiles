# MacBook の普段の Chrome を操作する

通常のブラウザ操作は **MacBook の Chrome** を使う。エージェントが Mac mini で動いていても接続先は MacBook。ユーザーが明示した場合だけ Mac mini を使う。

```text
Mac mini のエージェント ─ SSH/stdio ─┐
                                   ├─ MacBook の Playwright MCP --extension
MacBook のエージェント ─────────────┘     └─ 普段の Chrome / アカウント指定
```

接続先の既定値は `shun-tagami-mbp`。MCP の原本 `mcp/servers.json` にもホストを明記し、`bin/agent-browser` が SSH またはローカル実行を選ぶ。Playwright MCP は `@playwright/mcp@0.0.82` に固定する。

## 普段の操作

新しい作業では、エージェントが `browser_tabs` の `action: "new"` と目的の URL で作業用タブを開く。ユーザーがタブ一覧から無関係なページを選ぶ必要はない。接続先を判断できない場合はまず `agent-browser status` の `browser_host` と `account` を確認する。

| MCP 名 | 接続先 | Chrome アカウント |
|---|---|---|
| `playwright` | MacBook | `shun.tagami@ele-inc.com` |
| `playwright-info` | MacBook | `info@ele-inc.com` |

`--account` は Chrome の `Local State` に記録されたメールアドレスからプロファイルを一意に選ぶ。最後に使ったプロファイルや、マシンごとに異なる `Profile 2` / `Profile 8` には依存しない。該当がない・複数ある場合は理由を表示して停止する。明示的に選びたい場合は `--profile-dir-name` を使う（`--account` と併用不可）。

```sh
agent-browser status
agent-browser status --account info@ele-inc.com
# Mac mini が明示された作業だけ
AGENT_BROWSER_HOST=shun-tagami-mac-mini agent-browser status
# 実行しているマシン自体を診断する場合
agent-browser status --local
```

## 初回の認証設定

1. MacBook の対象アカウントの Chrome に [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm) を入れる。
2. 拡張機能の status ページを開き、`PLAYWRIGHT_MCP_EXTENSION_TOKEN=` の **値だけ**をコピーする。
3. **MacBook のターミナル**で次を実行し、非表示の入力欄へ貼り付ける。

```sh
~/dotfiles/bin/agent-browser setup-auth --local --account shun.tagami@ele-inc.com
# info アカウントを使う場合は、そのプロファイルの別のトークンを登録する
~/dotfiles/bin/agent-browser setup-auth --local --account info@ele-inc.com
```

トークンは macOS キーチェーンの service `Playwright Extension`、account は選ばれたプロファイルのディレクトリ名で保存する。MCP 起動時に **ブラウザを操作するマシン自身**のキーチェーンから読み込む。値を設定ファイル・Git・SSH コマンド引数・ログへ保存しない。別プロファイルや送信元マシンのトークンを使い回さない。

SSH の実行環境からログインキーチェーンを使うと `User interaction is not allowed` になる場合がある。その場合は MacBook のログイン環境で動く `com.shuntagami.agent-browser-keychain` LaunchAgent に読み書きを依頼する。初回に自動登録するが、診断・再登録は `agent-browser install-auth-service --local` で行える。

サービスの定義に認証情報は入らない。通信は `~/Library/Caches/agent-browser/keychain.sock` のローカル Unix ソケットのみ。ディレクトリは `0700`、ソケットは `0600` とし、接続元の UID も確認する。読み書きできるのは `Playwright Extension` service の、存在する Chrome プロファイルの項目だけ。トークンはリクエストや応答のログに出さない。

これは対象 Chrome プロファイルへの継続的な操作アクセスを認める設定。拡張機能でトークンを再生成した場合は `setup-auth` でキーチェーンも更新する。未登録なら手順を表示して直ちに停止し、承認画面を開いたまま無言で待たない。

Chrome のタブがすべて閉じられていた場合など、Playwright が接続用 URL をツールの応答に含めることがある。ラッパは MCP の応答と診断出力に含まれる登録トークンを `***` に置き換える。認証用の環境変数は子プロセスに渡すが、ユーザーやエージェントへの応答に値を返さない。

## 起動・接続

対象の通常 Chrome が閉じている場合、ラッパが `open -a "Google Chrome" --args --profile-directory=…` で起動する。別の `--user-data-dir` や自動操作用 Chrome プロセスは作らない。スリープ中・SSH 到達不能・拡張機能が未導入なら、その理由を解決する。別のマシンやプロファイルへ自動フォールバックしない。

```sh
ssh -o BatchMode=yes shun-tagami-mbp hostname
agent-browser status
```

SSH の stdin/stdout が MCP の通信になる。`9222` 番ポートの公開・常設トンネルは不要。ブラウザから見た `localhost` とアップロード・ダウンロード先は **MacBook**。Mac mini のファイルを添付する場合は、必要なものだけを MacBook の `~/.playwright-mcp/` などの許可された場所へコピーする。

拡張機能経由で `browser_file_upload` が `DOM.setFileInputFiles: Not allowed` になる場合は、ファイル選択をキャンセルし、`browser_drop` で同じファイルを添付欄へ渡す。別ブラウザへ切り替えず、添付後にプレビューの画像表示を確認する。

## 接続画面が出たとき

自動認証が設定済みなら、毎回の `Allow & select` は不要。画面が出たら、エージェントはすぐに「接続設定の画面」「MacBook のどのアカウントか」「何をする必要があるか」を説明し、対象プロファイルとキーチェーンを確認する。無関係なタブの選択を求めたり、タイムアウトまで無言で待ったりしない。

## 一時停止と設定反映

```sh
agent-browser pause
agent-browser resume
agent-browser status
node ~/dotfiles/mcp/sync-mcp.mjs
```

`pause` / `resume` は実行したマシンからの新しい接続を制御する。送信元と MacBook のどちらかに停止ファイル `${XDG_CONFIG_HOME:-~/.config}/agent-browser/paused` があれば MCP は起動しない。既存接続の切断は拡張機能の status ページから行う。

MCP 設定を反映した後はエージェントの新しいセッションを開始する。共通のブラウザ操作指示は `codex/AGENTS.md`（`~/.codex/AGENTS.md` へリンク）に置く。

## 検証

```sh
python3 ~/dotfiles/scripts/test_agent_browser.py
agent-browser status
bash -n ~/dotfiles/bin/playwright-mcp
```

[Playwright Extension の公式説明](https://github.com/microsoft/playwright/tree/main/packages/extension)
