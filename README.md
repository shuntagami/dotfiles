<div align="center">

# dotfiles

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Zsh](https://img.shields.io/badge/Zsh-F15A24?style=for-the-badge&logo=zsh&logoColor=white)
![Vim](https://img.shields.io/badge/Vim-019733?style=for-the-badge&logo=vim&logoColor=white)
![VSCode](https://img.shields.io/badge/VS_Code-007ACC?style=for-the-badge&logo=visual-studio-code&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=for-the-badge&logo=git&logoColor=white)

### 新しいMacを手に入れた。<br>コマンド1つで、いつもの開発環境が手に入る。

<br>

```bash
bash -c "$(curl -fsSL raw.githubusercontent.com/shuntagami/dotfiles/main/scripts/install-dotfiles.sh)"
```

</div>

---

## 🧩 これは何？

エンジニアの開発環境には、何十ものツール・設定・カスタマイズが詰まっています。
新しいマシンをセットアップするたびに、それを一から手作業でやり直す ── そんな時代は終わりです。

このdotfilesは、**たった1つのコマンドで、自分の理想の開発環境を丸ごと再現する**仕組みです。

---

## ✨ 特長

<table>
<tr>
<td width="50%" valign="top">

### 🚀 コマンド1つで、全部揃う

シェル、エディタ、Git、キーボード設定、macOSのシステム設定、
**100以上のパッケージ** ── すべてが自動でインストール・設定されます。

</td>
<td width="50%" valign="top">

### 🖥️ macOSでもUbuntuでも動く

OSの違いを自動で検知し、それぞれに最適なセットアップを実行。
**WSL2にも対応。** 1つのリポジトリで、どの環境でも同じ体験を。

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 🔧 25以上の自作ユーティリティ

PDF圧縮、通貨換算、URLデコード、git diffへの行番号付与など、
「あったら便利」なツールが `bin/` に揃っています。

</td>
<td width="50%" valign="top">

### 🌳 プロ仕様のGitワークフロー

**40以上のGitエイリアス**を搭載。ログの可視化、ブランチ管理、
rebase、worktree連携まで、Gitが手足のように動きます。

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 🍎 macOSを隅々まで自動設定

ダークモード、トラックパッド、キーボード、Finder、Dock、Safari ──
**22KBに及ぶ設定スクリプト**が、macOSを一瞬で仕上げます。

</td>
<td width="50%" valign="top">

### ⌨️ キーボード操作を極限まで最適化

Karabiner-Elements + Hammerspoon による高度なキーリマップと自動化。
ウィンドウ操作もショートカットも、**すべてキーボードで完結。**

</td>
</tr>
<tr>
<td colspan="2" align="center">

### 🤖 AI時代の開発環境

Claude Desktop、Cursor、MCPサーバー設定を含む、**最新のAIツールとの連携もセットアップに組み込み済み。**

</td>
</tr>
</table>

---

## 📦 使い方

### 事前に必要なもの

| OS | 必要なもの |
|:---|:---|
| 🍎 macOS | XCode Command Line Tools（`xcode-select --install` で取得） |
| 🐧 Ubuntu | 20.04 以上 |

### セットアップ（2ステップで完了）

```bash
# 1. dotfilesをダウンロード
bash -c "$(curl -fsSL raw.githubusercontent.com/shuntagami/dotfiles/main/scripts/install-dotfiles.sh)"

# 2. セットアップを実行（パッケージ、シンボリックリンク、macOS設定、エディタ設定 ── 全部まとめて）
~/dotfiles/scripts/setup.sh
```

> [!TIP]
> これだけで完了です。あとはターミナルを再起動すれば、すべてが整った環境が待っています。

<details>
<summary>📋 個別に実行したい場合</summary>

<br>

各ステップを独立して実行することもできます。

```bash
~/dotfiles/scripts/install-packages.sh  # パッケージのインストール（Homebrew, anyenvなど）
~/dotfiles/scripts/deploy.sh            # dotfilesのシンボリックリンク作成
~/dotfiles/scripts/macos.sh             # macOSシステム設定の適用
~/dotfiles/vscode/setup.sh              # VSCode / Cursor のセットアップ
```

</details>

---

## 🗂️ 管理している主なツール・設定

| カテゴリ | ツール |
|:---|:---|
| **シェル** | [Zsh](https://www.zsh.org/) + [Prezto](https://github.com/sorin-ionescu/prezto)（補完・ハイライト・サジェスト） |
| **エディタ** | [Vim](https://github.com/vim/vim)（[dein.vim](https://github.com/Shougo/dein.vim)）/ [VSCode](https://github.com/microsoft/vscode) / [Cursor](https://www.cursor.com/) |
| **パッケージ管理** | [Homebrew](https://github.com/Homebrew/brew) / [apt](https://github.com/Debian/apt) |
| **バージョン管理** | [anyenv](https://github.com/anyenv/anyenv)（Node.js, Ruby, Python） |
| **ターミナル** | [iTerm2](https://github.com/gnachman/iTerm2) |
| **キーボード** | [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) / [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) |
| **AI** | [Claude Desktop](https://claude.ai/) / Cursor / MCP |
| **システム監視** | [btop](https://github.com/aristocratos/btop) |

---

## 🏛️ 設計思想

> **「設定は、コードである。」**

| 原則 | 説明 |
|:---|:---|
| **宣言的** | Brewfile や設定ファイルに書かれた状態が、そのまま環境の正解になる |
| **冪等** | 何度実行しても同じ結果になる。壊れない |
| **モジュラー** | 全体を一括で実行することも、個別に実行することもできる |
| **クロスプラットフォーム** | OSの差異はスクリプトが吸収する |

---

<div align="center">

**Works on my machine. And yours too.**

</div>
