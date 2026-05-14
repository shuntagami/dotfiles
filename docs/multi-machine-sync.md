# 複数マシン間で AI セッション履歴を同期する

Mac mini（メイン）と MacBook Pro（外出・補助）で **Claude Code / Codex CLI / screenpipe** のセッション履歴を双方向リアルタイム同期するための運用メモ。

新しいマシンを買い替えた時もこの手順をなぞれば再構築できる。所要時間は約 15 分（インストール除く）。

## ゴール

- どちらの Mac で作業しても、もう一方の Mac から `claude --resume` / `codex` で会話を続けられる
- 業務開始 / 休憩状態（`work-start` 等の screenpipe ローカルログ）が両機で揃う
- 両機同時稼働の並列開発も問題なし（別セッションは別ファイルなので衝突しない）

## 構成

| レイヤ | 役割 |
|---|---|
| **Tailscale** | 別ネットワーク同士でも互いに到達可能にする P2P トンネル。外出先 MacBook ↔ 自宅 Mac mini を繋ぐ |
| **Syncthing** | P2P ファイル同期。クラウドを介さない（プライバシー◯）、append-only な小ファイルに強い |

両方 Brewfile に入れているので、新マシンでは `brew bundle --file ~/dotfiles/misc/Brewfile` 一発で揃う。

## 同期するもの

| 対象 | パス | 内容 |
|---|---|---|
| Claude Code | `~/.claude/projects/` | セッション jsonl、メモリ、todos |
| Codex CLI | `~/.codex/sessions/` | セッション履歴 |
| Codex CLI | `~/.codex/memories/` | メモリ |
| screenpipe | `~/.screenpipe/work-state/` | `work.jsonl` / `breaks.jsonl` / `config.env` |

## 同期しないもの（意図的に除外）

- `~/.claude/statsig/`, `~/.claude/shell-snapshots/` — マシン固有
- `~/.codex/auth.json`, `installation_id`, `logs_*.sqlite*`, `state_*.sqlite`, `cache/`, `models_cache.json`, `shell_snapshots/`, `.tmp/` — マシン固有 or 巨大 or 機密
- `~/.screenpipe/db.sqlite` および録画・OCR・音声データ — 数 GB〜数十 GB 規模、sqlite を Syncthing で同期すると破損リスク
- `~/.screenpipe/work-state/config.env` — README ポリシー上は端末ごと管理だが、現在は両機同じ webhook を使う運用のため Ignore Patterns に入れず同期している。webhook を分けたくなった時のみ Ignore Patterns に `config.env` を追加する

## 新規マシンのセットアップ手順

### 1. 基本セットアップ

```bash
bash -c "$(curl -fsSL raw.githubusercontent.com/shuntagami/dotfiles/main/scripts/install-dotfiles.sh)"
cd ~/dotfiles
brew bundle --file misc/Brewfile
```

これで Tailscale (`tailscale-app` cask) と Syncthing (`syncthing` formula) が入る。

### 2. Tailscale サインイン（1 分）

1. Applications → **Tailscale.app** 起動
2. **Add Account...**（▼ボタンじゃない方）→ ブラウザで既存アカウントにサインイン
3. macOS が Network Extension の許可を求めるダイアログを出したら全部許可
4. メニューバーアイコンが青く点灯すれば成功
5. 既存マシン（Mac mini など）も同じアカウントでサインイン済みであることを確認

### 3. Syncthing 起動とペアリング（5 分）

```bash
brew services start syncthing
open http://localhost:8384
```

GUI で：
1. **Settings** → **General** → Device Name をわかりやすい名前に（例 `MacBookPro`）
2. **Settings** → **GUI** → GUI Authentication User/Password を設定（localhost のみだが念のため）
3. **Actions** → **Show ID** で自機の Device ID をコピー

既存マシンの Syncthing GUI で：
4. **Add Remote Device** → 上記 Device ID を貼り付け → Save
5. 数秒後、自機側に「既存マシンが接続したい」バナーが出る → Add Device

両機の Remote Devices 欄で互いが **Connected**（緑）になれば完了。

### 4. 同期フォルダを追加（5 分）

以下 4 つのフォルダを **既存マシン側**（Mac mini）で `Add Folder` し、自機（新マシン）と Sharing する。新マシン側ではバナーから Accept するだけ。

| Folder Label | Folder ID | Folder Path |
|---|---|---|
| Claude Projects | `claude-projects` | `/Users/shun.tagami/.claude/projects` |
| Codex Sessions | `codex-sessions` | `/Users/shun.tagami/.codex/sessions` |
| Codex Memories | `codex-memories` | `/Users/shun.tagami/.codex/memories` |
| Screenpipe Work State | `screenpipe-workstate` | `/Users/shun.tagami/.screenpipe/work-state` |

各フォルダで共通設定：
- **Sharing** タブ：相手の Mac を ON
- **File Versioning** タブ：Simple File Versioning / Keep 5（コンフリクト時の救済用）
- **Ignore Patterns**：なし（必要に応じて後付け）

### 5. 動作確認

```bash
ls ~/.claude/projects | head -5
ls ~/.codex/sessions
ls ~/.screenpipe/work-state/
```

両機で同じ内容が見えていれば成功。実テスト：

```bash
# 新マシンで
cd ~/dotfiles
claude --resume
```

→ 既存マシンで動かしていたセッション一覧が出てくれば動作確認 OK。

## 運用上の注意

- **同一セッションを両機で同時にリプレイしない**：別タスク・別 PR の並走は OK（別 jsonl ファイル）。同じ session id を両機で resume して同時操作すると `<file>.sync-conflict-<日付>.jsonl` ができる。Simple Versioning から復旧可能だがそもそも避ける
- **個人マシン専用**：jsonl にはコード片やパス情報がそのまま入るので、職場機材を同じ tailnet に混ぜない
- **Mac mini を常時稼働させる前提**：MacBook 単独稼働時は同期相手がいないので変更はローカル保留 → Mac mini 帰宅時に追いつく

## 既存マシンを追加で増やしたい時

新マシンで上記手順を実行。既存マシンが複数台ある場合は、それぞれの Syncthing で新マシンを Accept Device + Accept Folder すれば三角形以上のメッシュ同期になる（全マシン間で双方向）。

## トラブルシューティング

**Tailscale で "Unable to add a new user"**
- macOS の Network Extension が許可されていない。System Settings → General → Login Items & Extensions → Network Extensions で Tailscale を ON
- それでも駄目なら CLI フォールバック：`sudo /Applications/Tailscale.app/Contents/MacOS/Tailscale up`

**Syncthing で Remote Device が Disconnected のまま**
- 両機の Tailscale が Connected か確認
- 両機が同一 LAN なら Local Discovery で繋がるはず。LAN なし + Tailscale なしの場合は Syncthing 自身の Global Discovery + Relay 経由でも繋がるが遅い
- ファイアウォール（Little Snitch 等）が Syncthing をブロックしていないか

**同期が始まらない / 進まない**
- Syncthing GUI で該当フォルダをクリックして "Last Scan" の時刻を確認、`Rescan` ボタンで強制再スキャン
- 片方だけ Ignore Patterns 入れている場合、整合性が取れない。両機で同じパターンを揃える

## 関連ファイル

- `misc/Brewfile` — `syncthing` formula、`tailscale-app` cask
- `screenpipe/README.md` — work-state のローカルログ仕様、`work-start`/`break-start` の使い方
- `screenpipe/pipes/hourly-work-report/pipe.md` — Slack 投稿に端末名を埋め込む実装
