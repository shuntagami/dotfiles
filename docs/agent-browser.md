# 普段の Chrome に接続する

ブラウザ操作は **MacBook で開いている通常の Chrome** に、Playwright Extension 経由で接続する。
Mac mini からも同じ Chrome を使う。別の Chrome プロセスや自動操作用プロファイルを起動しない。

```text
MacBook のエージェント ───────────────┐
                                    ├─ MacBook の Playwright MCP --extension
Mac mini のエージェント ─ SSH/stdio ─┘       └─ 通常 Chrome の選択したプロファイル
```

Playwright MCP は `@playwright/mcp@0.0.82` に固定している。接続ごとに独立した MCP プロセスを使う。
Chrome 拡張機能はエージェントごとにタブグループを分ける。同じタブを複数の接続に渡さない。
Cookie・ログイン状態はその Chrome プロファイルで共有される。

## 最初のセットアップ

1. MacBook の通常 Chrome で、使いたいプロファイルを開く。
2. そのプロファイルに [Playwright Extension](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm) を入れる。
   拡張機能が求めるサイト・タブの操作権限を確認して許可する。
3. `info@ele-inc.com` も使うなら、そのプロファイルにも拡張機能を入れる。
4. 両 Mac にこの版の `bin/agent-browser` と `bin/playwright-mcp` を反映する。
5. MCP の登録は `mcp/servers.json` を原本とし、`node mcp/sync-mcp.mjs` で各クライアントに反映する。
6. 一時停止中なら **両 Mac で** `agent-browser resume` を実行する。
7. エージェントの新しいセッションでブラウザツールを使い、Chrome に出る接続・タブ選択画面を操作する。

通常 Chrome が閉じている、プロファイルや拡張機能が無い、MacBook に SSH できない場合は
理由を表示して失敗する。別のブラウザや他のマシンへの自動フォールバックはしない。
拡張機能がインストール済みでも無効なら、Chrome で有効化して接続を再試行する。

## どのプロファイルを使うか

| MCP 名 | 選択 |
|---|---|
| `playwright` | MacBook の通常 Chrome が最後に使ったプロファイル |
| `playwright-info` | `Profile 8`（現在の `info@ele-inc.com`）を明示指定 |

通常は ELE（`shun.tagami@ele-inc.com`、現在の `Profile 2`）を開いてから接続する。
選択は **MCP プロセスの起動時** に通常 Chrome の `Local State` から読み取り、
`--profile-dir-name` で固定する。操作中に別のウィンドウを前面に出しても接続先は変わらない。
プロフィールを切り替えたら MCP 接続を作り直す。接続先は stderr と `status` で確認できる。

```sh
agent-browser status
agent-browser status --profile-dir-name 'Profile 8'
PLAYWRIGHT_MCP_PROFILE_DIR_NAME='Profile 2' playwright-mcp
```

プロファイルを作り直してディレクトリ名が変わった場合は、
`agent-browser status` と Chrome の表示を照合し、`mcp/servers.json` の
`playwright-info.args` を更新して再同期する。

## Mac mini からの接続

既定のブラウザホストは `shun-tagami-mbp`。同名の MacBook 上では直接起動し、
それ以外では SSH で MacBook 上の同じスクリプトを実行する。
SSH は Tailscale の既存のホスト設定と鍵認証を使う。

```sh
# Mac mini で実行しても、MacBook 上のプロファイル状態を表示する
agent-browser status

# 必要な場合だけホストを明示する
AGENT_BROWSER_HOST=local agent-browser status
AGENT_BROWSER_HOST=shun-tagami-mbp playwright-mcp
```

SSH の stdin/stdout が MCP の通信になる。`9222` 番ポートの公開・転送や常設トンネルは不要。
MacBook がスリープ中・到達不能なら接続できない。MCP の起動に失敗したときは
表示された SSH の理由を解決して再接続する。

ブラウザから見た `localhost` とアップロード・ダウンロード先は **MacBook**。
Mac mini の開発サーバーは Tailscale で到達できるアドレスを使うか、必要なアプリのポートだけを
別途転送する。ローカルファイルを自動で両 Mac 間コピーする機能はない。

## 一時停止と診断

```sh
agent-browser pause    # このマシンからの新しい接続を止める
agent-browser status   # 実際のブラウザホスト・アカウント・拡張機能・停止状態
agent-browser resume   # このマシンの新しい接続を許可する
```

停止ファイルは `${XDG_CONFIG_HOME:-~/.config}/agent-browser/paused`。
`pause` は既存接続を切断しない。稼働中の接続は拡張機能の接続一覧またはエージェント側で閉じる。
送信元と MacBook のどちらかが停止中なら MCP は起動しない。
`status` はブラウザホストの状態を表示するため、送信元の停止ファイルは別途確認する。

接続トークンをコードや設定ファイルに保存しない構成。通常の接続承認画面を使う。
`PLAYWRIGHT_MCP_EXTENSION_TOKEN` はプロファイル固有であり、このラッパは SSH コマンドや
ログに転送しない。別のプロファイルのトークンを使い回さない。

## 旧構成からの変更

- `agent-browser up/down/endpoint` は廃止。ブラウザの起動・終了を管理しない。
- `AGENT_BROWSER_PORT/MODE/PROFILE/AUTO/START_BUDGET` による旧 CDP 起動・切り替えは廃止。
- `--cdp-endpoint`、`--user-data-dir`、`--isolated` など接続方式を変更する引数は受け付けない。
- 旧 `~/Library/Application Support/agent-browser/Chrome` のデータは自動削除・コピーしない。
- 普段の Chrome の既定ブラウザ設定や `gh` の開き先を変更する必要はない。

過去の構成は同じ `Google Chrome.app` を別データ領域で起動していたため、
macOS の外部リンクが自動操作用プロセスへ渡る問題があった。
既存 Chrome への拡張機能接続に統一して、この二重起動をなくす。

## 検証

```sh
python3 -m unittest discover -s tests -v
bash -n bin/playwright-mcp
```

[Playwright Extension の公式説明](https://github.com/microsoft/playwright/tree/main/packages/extension)
