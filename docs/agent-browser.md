# エージェントのブラウザを MacBook 側に置く

AI エージェントにブラウザを操作させると、**自分が使っているブラウザと衝突する**。
その衝突を、別マシンに追い出すことで構造的に無くすための構成。

## なぜ必要か

macOS には、ブラウザが主張するものに対する「セッションごとの名前空間」が無い。

- **URL ハンドラは1つ** — `open`（`gh repo view --web` も中身はこれ）は、そのバンドルの
  どのインスタンスに届くか選べない。自動化用のインスタンスが受け取ると、別ウィンドウに
  開き、使い捨てプロファイルなので自分の設定（縦タブなど）も効かない
- **グローバルショートカットは先に登録した者のもの** — 裏で生きているブラウザは
  ショートカットを保持し続ける
- **後始末されないプロセスが残る** — 実際に15日前と6日前のヘッドレス Chrome が残留し、
  Chrome が起動できない状態を作っていた

いずれも「気をつける」では防げない。取り合う相手を物理的に分けるのが確実。

## 構成

| | |
|---|---|
| エージェントのブラウザ | MacBook 上の **通常の Google Chrome（Default プロファイル）** |
| 経路 | Tailscale 上の **SSH ポートフォワード** |
| 操作 | Playwright MCP の `--cdp-endpoint` |

マシンを分けているので、認証切れの Chrome for Testing を使う必要はない。
MacBook 側のログイン状態・Cookie・拡張をそのままエージェントが使える。

### CDP を公開しない理由

Chrome DevTools Protocol は**無認証で、繋がれば全 Cookie が読める**。なので
MacBook 側では localhost にバインドし、SSH トンネルでこちらに引く。Playwright からは
ローカルの `127.0.0.1:9222` に見えるため、Chrome の DevTools エンドポイントが行う
Host ヘッダ検査も同時に満たせる。

## 使い方

```sh
agent-browser up                 # MacBook の Chrome を CDP 付きで起動し、トンネルを張り、応答を確認
agent-browser status             # 両側の状態
agent-browser down               # トンネルだけ切る（Default プロファイルの Chrome は残す）
agent-browser down --kill-browser  # トンネルを切り、向こうの Chrome も終了
agent-browser endpoint           # CDP のエンドポイントだけを出す
```

`up` は「トンネルが張れた」では成功としない。`/json/version` が応答するかまで見る。
トンネルが上がっていてもブラウザが死んでいれば、エージェントは何も操作できないため。

Chrome は **user-data-dir につき1プロセス**しか許さない。すでに CDP 無しで Chrome が
開いていると、フラグ付きの再起動は無視される。その場合 `up` は一度 Chrome を終了してから
`--remote-debugging-port` 付きで立ち上げ直す。

`down` は既定ではトンネルだけ切る。Default プロファイルは人が使うものなので、
持ち主のいないプロセス扱いにはしない。明示的に止めたいときだけ `--kill-browser`。

環境変数で変えられる。

| 変数 | 既定 | 意味 |
|---|---|---|
| `AGENT_BROWSER_HOST` | `shun-tagami-mbp` | リモートホスト |
| `AGENT_BROWSER_PORT` | `9222` | CDP ポート |
| `AGENT_BROWSER_MODE` | `default` | `default` = 通常 Chrome + Default プロファイル / `testing` = Chrome for Testing + 使い捨てプロファイル |
| `AGENT_BROWSER_PROFILE` | （mode に従う） | リモート側の `--user-data-dir` を上書き |

昔の分離（Chrome for Testing）に戻すには:

```sh
AGENT_BROWSER_MODE=testing agent-browser up
```

## MCP 側は自動で切り替わる

`mcp/servers.json` の playwright は `bin/playwright-mcp` を指す。このラッパは
**CDP が応答するかを見て**、リモートかローカルかを選ぶ。

- 応答する → `--cdp-endpoint` を付けて MacBook のブラウザを使う
- 応答しない → `--isolated` でローカルに起動（外出中に MacBook が鞄の中でも壊れない）

判定に ssh や ping を使わないのは、**「エージェントが操作できるブラウザがある」**ことを
意味するのは CDP の応答だけだから。トンネルが上がっていて中身が空のこともあるし、
別の何かが 9222 を掴んでいることもある（`curl` は 404 でも終了コード 0 を返すので、
HTTP が 2xx で、本文に Playwright が実際に繋ぐ `webSocketDebuggerUrl` があることまで
見る）。

### 誰も `up` しなくても繋がる

**明示的な操作は要らない。** ラッパは CDP が応答しなければ自分で `agent-browser up`
を実行する。MulmoTerminal のセルから Claude Code / Codex / Cursor CLI を普通に
起動すれば、最初の1つが MacBook のブラウザを立ち上げ、以降はそれを共有する。

- MulmoTerminal のグリッドは同時に多数のエージェントを動かすので、**ロックを取る**
  （macOS に `flock(1)` が無いため `mkdir` の原子性を使う）。ロックを取れなかった側は
  相手の起動を待つ。待たずに走ると、2本目のトンネルと迷子の ssh が残る
- **起動には固い上限がある**（既定40秒、`AGENT_BROWSER_START_BUDGET`）。ラッパは MCP
  サーバの起動経路に座っているので、鞄の中の MacBook は数秒のコストで済ませ、
  ハングさせてはならない
- 自動起動を止めたいときは `AGENT_BROWSER_AUTO=0`

`up` が途中で失敗したときは、**その実行が起動したものだけを片付ける**。default モードでは
ロールバックでも向こうの Chrome は止めない（本物のプロファイルだから）。testing モードで
自分が立ち上げたブラウザだけは止める。

設定を変えたら `node mcp/sync-mcp.mjs` で Claude Code / Codex / Cursor に反映する。

## 前提

- 両機で Tailscale が動いていること（`tailscale status`）
- Mac mini から MacBook へ鍵で ssh できること。`misc/ssh/config` の `shun-tagami-mbp`
  が MagicDNS 名で引く。初回だけ `ssh-copy-id -i ~/.ssh/id_ed25519.pub shun-tagami-mbp`
- MacBook に Google Chrome があること（`/Applications/Google Chrome.app`）

## 限界

**寝ている MacBook は起こせない。** Tailscale（WireGuard）に Wake-on-LAN は無い。
同一LANなら WoL が使えるが、macOS のスリープ状態次第で不確実。確実なのは
「起こさない運用」— 電源につないだまま自動スリープを切り、ブラウザ用の常駐マシンとして
扱う。

**MacBook を持ち出すと使えない。** そのときは `playwright-mcp` のフォールバックが
ローカルに切り替わる。エージェントのブラウザは自分の Chrome と同じバンドルに戻るので、
上の衝突は再び起こり得る。

**computer use（実画面の操作）はこの構成では逃がせない。** 実デスクトップを触るので、
MacBook 側でやるならエージェント自体をそちらで動かす必要がある。セッション履歴は
Syncthing で同期しているので `claude --resume` は両機で継続できる
（[multi-machine-sync.md](multi-machine-sync.md)）。

**MulmoTerminal を両機で動かしてスマホから使い分けることはできない。** remote host の
`HOST_ID` が定数（`server/backends/remoteHost/index.ts`）で単一ホスト前提のため、
2台が同じ Firestore コマンドキューを取り合う。MacBook 側で remote host を
接続しない運用なら共存する。

**エージェントは Default プロファイルの Cookie に届く。** CDP は localhost + SSH トンネル
に閉じているが、繋いだエージェントはログイン済みセッションを読める。マシン分離は
URL ハンドラ衝突の回避であって、認証の隔離ではない。
