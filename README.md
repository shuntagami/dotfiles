# dotfiles

**新しいMacを手に入れた。コマンド1つで、いつもの開発環境が手に入る。**

---

## これは何？

エンジニアの開発環境には、何十ものツール・設定・カスタマイズが詰まっています。
新しいマシンをセットアップするたびに、それを一から手作業でやり直す ── そんな時代は終わりです。

このdotfilesは、**たった1つのコマンドで、自分の理想の開発環境を丸ごと再現する**仕組みです。

## 何がすごいのか

### コマンド1つで、全部揃う

シェル、エディタ、Git、キーボード設定、macOSのシステム設定、
100以上のパッケージ ── すべてが自動でインストール・設定されます。

### macOSでもUbuntuでも動く

OSの違いを自動で検知し、それぞれに最適なセットアップを実行します。WSL2にも対応。
1つのリポジトリで、どの環境でも同じ体験を。

### 25以上の自作ユーティリティツール

PDF圧縮、通貨換算、URL デコード、git diffへの行番号付与など、
日々の開発で「あったら便利」なツールが `bin/` に揃っています。

### プロ仕様のGitワークフロー

40以上のGitエイリアスを搭載。コミットログの可視化、ブランチ管理、
インタラクティブrebase、worktree連携まで、Gitが手足のように動きます。

### macOSを隅々まで自動設定

ダークモード、トラックパッド、キーボード、Finder、Dock、Safari ──
22KBに及ぶ設定スクリプトが、macOSをあなた好みに一瞬で仕上げます。

### キーボード操作を極限まで最適化

Karabiner-Elements と Hammerspoon による高度なキーリマップと自動化。
ウィンドウ操作、マークダウン入力、ショートカット ── すべてをキーボードで。

### AI時代の開発環境

Claude Desktop、Cursor、MCP サーバー設定を含む、
最新のAIツールとの連携もセットアップに組み込み済みです。

---

## 使い方

### 事前に必要なもの

| OS | 必要なもの |
|---|---|
| macOS | XCode Command Line Tools (`xcode-select --install` で取得) |
| Ubuntu | 20.04 以上 |

### セットアップ（2ステップで完了）

```bash
# 1. dotfilesをダウンロード
bash -c "$(curl -fsSL raw.githubusercontent.com/shuntagami/dotfiles/main/scripts/install-dotfiles.sh)"

# 2. セットアップを実行（パッケージ、シンボリックリンク、macOS設定、エディタ設定 ── 全部まとめて）
~/dotfiles/scripts/setup.sh
```

これだけです。

### 個別に実行したい場合

```bash
~/dotfiles/scripts/install-packages.sh  # パッケージのインストール（Homebrew, anyenvなど）
~/dotfiles/scripts/deploy.sh            # dotfilesのシンボリックリンク作成
~/dotfiles/scripts/macos.sh             # macOSシステム設定の適用
~/dotfiles/vscode/setup.sh              # VSCode / Cursor のセットアップ
```

---

## 管理している主なツール・設定

| カテゴリ | ツール |
|---|---|
| シェル | [Zsh](https://www.zsh.org/) + [Prezto](https://github.com/sorin-ionescu/prezto) |
| エディタ | [Vim](https://github.com/vim/vim)（[dein.vim](https://github.com/Shougo/dein.vim)）/ [VSCode](https://github.com/microsoft/vscode) / [Cursor](https://www.cursor.com/) |
| パッケージ管理 | [Homebrew](https://github.com/Homebrew/brew) / [apt](https://github.com/Debian/apt) |
| バージョン管理 | [anyenv](https://github.com/anyenv/anyenv)（Node.js, Ruby, Python） |
| ターミナル | [iTerm2](https://github.com/gnachman/iTerm2) |
| キーボード | [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) / [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) |
| AI | [Claude Desktop](https://claude.ai/) / Cursor / MCP |
| システム監視 | [btop](https://github.com/aristocratos/btop) |

---

## 設計思想

- **宣言的** ── Brewfile や設定ファイルに書かれた状態が、そのまま環境の正解になる
- **冪等** ── 何度実行しても同じ結果になる。壊れない
- **モジュラー** ── 全体を一括で実行することも、個別に実行することもできる
- **クロスプラットフォーム** ── OSの差異はスクリプトが吸収する
