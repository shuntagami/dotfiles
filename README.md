<div align="center">

# dotfiles

![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)
![Zsh](https://img.shields.io/badge/Zsh-F15A24?style=for-the-badge&logo=zsh&logoColor=white)
![Vim](https://img.shields.io/badge/Vim-019733?style=for-the-badge&logo=vim&logoColor=white)
![VSCode](https://img.shields.io/badge/VS_Code-007ACC?style=for-the-badge&logo=visual-studio-code&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=for-the-badge&logo=git&logoColor=white)

### 新しいMacを手に入れた。<br>コマンド1つで、全部入ってる。

<br>

```bash
bash -c "$(curl -fsSL raw.githubusercontent.com/shuntagami/dotfiles/main/scripts/install-dotfiles.sh)"
```

</div>

---

## 🧩 これは何？

まさか新しいMacを買うたびに、Safariで「Chrome ダウンロード」と検索するところから始めていませんか・・・？

次にSlack、Zoom、LINE ── 気づけば同じことをもう何十回も繰り返して、1時間、2時間、いや3時間と溶けている。

やっとアプリが揃ったと思って、Cursorを開いていざ仕事を始めようと思ったらたら、  
拡張機能も設定も何もない。自動保存すらオフ。

このリポジトリを使えば、**たった1つのコマンドで、プロのエンジニアが理想とする生産性の高いMacの環境がそのまま手に入ります。**

> [!NOTE]
> macOSやLinuxの設定ファイルは「**.**」から始まる名前を持つため、**dotfiles**と呼ばれています。

---

## ✨ 特長

<div align="center">

普段使いのアプリも、開発ツールも、まとめて一発でインストール。

![Google Chrome](https://img.shields.io/badge/Google_Chrome-4285F4?style=flat-square&logo=google-chrome&logoColor=white)
![Slack](https://img.shields.io/badge/Slack-4A154B?style=flat-square&logo=slack&logoColor=white)
![Zoom](https://img.shields.io/badge/Zoom-0B5CFF?style=flat-square&logo=zoom&logoColor=white)
![Discord](https://img.shields.io/badge/Discord-5865F2?style=flat-square&logo=discord&logoColor=white)
![Spotify](https://img.shields.io/badge/Spotify-1DB954?style=flat-square&logo=spotify&logoColor=white)
![Dropbox](https://img.shields.io/badge/Dropbox-0061FF?style=flat-square&logo=dropbox&logoColor=white)
![Figma](https://img.shields.io/badge/Figma-F24E1E?style=flat-square&logo=figma&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Adobe Acrobat](https://img.shields.io/badge/Adobe_Acrobat-EC1C24?style=flat-square&logo=adobe-acrobat-reader&logoColor=white)
![ChatGPT](https://img.shields.io/badge/ChatGPT-74aa9c?style=flat-square&logo=openai&logoColor=white)
![Claude](https://img.shields.io/badge/Claude-D4A27F?style=flat-square&logo=anthropic&logoColor=white)
![GIMP](https://img.shields.io/badge/GIMP-5C5543?style=flat-square&logo=gimp&logoColor=white)

</div>

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
**WSL2にも対応。**1つのリポジトリで、どの環境でも同じ体験を。

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 🔧 25以上の自作ユーティリティ

PDF圧縮、通貨換算、URLデコード、git diffへの行番号付与など、
「あったら便利」なツールが`bin/`に揃っています。

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

Finder、Dock、Safari、トラックパッド、キーボードなど
**数十項目のシステム設定**を一括で適用します。

</td>
<td width="50%" valign="top">

### ⌨️ キーボード操作を極限まで最適化

Karabiner-Elements + Hammerspoonによる高度なキーリマップと自動化。
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

| OS        | 必要なもの                                                 |
| :-------- | :--------------------------------------------------------- |
| 🍎 macOS  | XCode Command Line Tools（`xcode-select --install`で取得） |
| 🐧 Ubuntu | 20.04以上                                                  |

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
~/dotfiles/scripts/install-packages.sh  # パッケージのインストール（Homebrewなど）
~/dotfiles/scripts/deploy.sh            # dotfilesのリンク作成・アプリ設定の反映（MonitorControlなど）
~/dotfiles/scripts/macos.sh             # macOSシステム設定の適用
~/dotfiles/scripts/macos-notifications.sh  # 通知設定（deploy.shに含まれる。Chromeのサイト許可・アプリごとの通知）
bash ~/dotfiles/scripts/macos-default-apps.sh  # 標準アプリ・CleanShot設定（deploy.shに含まれる）
~/dotfiles/vscode/setup.sh              # VSCode/Cursorのセットアップ
```

</details>

### Aqua Voice・Clipyのショートカット

アプリごとの設定は `misc/aqua-voice-hotkeys.json` と `misc/clipy-hotkeys.json` に置き、
`deploy.sh`から専用スクリプトで反映します。`macos.sh`を実行する必要はありません。
実装はNode.jsの標準ライブラリとmacOS標準コマンドを使い、npmパッケージの追加は不要です。
Aqua VoiceはFn（入力）、Control+Space（ロック）、Command+Control+V（直前の文字起こしを貼付）、
Escape（キャンセル）。ClipyはCommand+Option+V（履歴）、Command+Shift+B（スニペット）、履歴数50です。

```bash
~/dotfiles/scripts/macos-aqua-voice.sh --check
~/dotfiles/scripts/macos-clipy.sh --check
# --dry-runで変更予定、オプションなしで適用
```

Aqua Voiceは管理するアクションだけ更新し、そのほかのショートカットや設定を保持します。
Clipyも指定した設定キーだけ更新します。変更前の管理対象キーは
`~/.local/state/dotfiles/app-hotkeys/`に保存します。変更した場合、アプリの再起動後に有効になります。
アプリが未インストールならスキップします。Aqua Voiceの設定ファイルがまだない場合は、
一度アプリを起動してから再実行してください（適用時は終了コード3で報告し、deployは警告を出して続行）。

### 標準アプリ・スクリーンショット

`misc/default-apps.json` で標準アプリとCleanShotの撮影ショートカットを管理します。
動画・音声はIINA、画像はCleanShot X、PDFはAcrobat Pro（なければReader）、HTMLはChromeです。
現在のインストール状況からアプリを選び、`deploy.sh`で毎回適用・確認します。
必要なアプリがない場合は報告して非ゼロで終了します。自動インストールはしません。

```bash
~/dotfiles/scripts/macos-default-apps.sh --dry-run  # 変更予定
~/dotfiles/scripts/macos-default-apps.sh            # 適用して確認
~/dotfiles/scripts/macos-default-apps.sh --check    # 現状確認。不一致なら終了コード1
```

sudo不要で、実行したMacのログインユーザーに適用します。
変更前の関連付けと管理対象のショートカットは `~/.local/state/dotfiles/default-apps/` に保存します。
CleanShotのライセンス・ログイン情報は取り込みません。
撮影はCmd+Shift+3（全画面）、4（範囲をコピー）、5（All-in-One）を設定し、
同じキーを使うmacOS標準のスクリーンショット操作を無効にします。
すでに有効なCleanShot設定は維持します。ショートカットを書き換えた場合は、撮影中の作業を
中断せず、CleanShotの再起動が必要なことを表示して終了コード3を返します。
deployは終了コード3だけを警告として扱って続行し、実際の設定失敗は終了コード1で停止します。
macOS標準の撮影ショートカットを書き換えた場合は、保存状態を確認して即時再読み込みします。

別のアプリに関連付けが変わった場合は再実行して戻せます。
ブラウザ内の再生・PDF表示、FinderのQuick Look、ファイル個別の関連付けは対象外です。
既存のChromeのWeb・メールリンク設定は維持します。OSの標準ブラウザ変更には
Chrome自身かシステム設定での操作が必要です（`deploy.sh`のコメント参照）。
旧 `macos-media-defaults.sh` コマンドも同じ設定を適用します。

### 別のユーザーのMacで使う場合

シェルのパスは `$HOME` を使います。Codex・Claude Code・Claude Desktop・iTerm2の設定は、
`deploy.sh` が実行ユーザーのホームディレクトリに合わせて配置します。
既存の `/Users/shun.tagami/…` と `/Users/shuntagami/…` は設定内のテンプレートとして扱い、
別ユーザーでは `~/.local/share/dotfiles/generated/` に解決済みの設定を作成します。
既存の設定ファイルは置き換え前にバックアップします。
田上のアカウントでは、AI設定をアプリからリポジトリへ保存する既存のリンクを維持します。

MCPの `servers.json` では `${HOME}` を使えます。`sync-mcp.mjs` が各クライアントへの反映時に解決します。
パスの置き換えはログイン情報やAPIキーを移しません。必要なアプリ・プロジェクトの配置と認証は各Macで行ってください。
SSHの接続先、ブラウザ自動操作の接続先・Chromeアカウント、ショートカットなどは共通設定のままです。

### 全リポジトリ共通のGit作業方針

共通方針の本文は [docs/git-workflow.md](docs/git-workflow.md) で管理します。
Codexは `~/.codex/AGENTS.md`、Claude Codeは `~/.claude/rules/git-workflow.md` から参照します。
`deploy.sh` がリンクを配置します。指示のリンクだけ更新する場合は次を実行します。

```sh
python3 ~/dotfiles/scripts/install-user-configs.py agent-instructions
```

実ファイルがすでにある場合は退避し、他のルールは変更しません。ホーム側に独立した本文は作りません。
Gitの独自フックや設定キーは追加せず、既存のpull・push・同期の設定も変更しません。
共通指示はエージェントへの作業方針であり、Git操作を強制的に禁止する仕組みではありません。

標準の読み込み先：[Codexの共通指示](https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide#using-agentsmd)、[Claude Codeのユーザールール](https://code.claude.com/docs/en/memory#user-level-rules)。

### インストール中のパスワード入力

`setup.sh` と `install-packages.sh` は、最初に管理者認証を行い、実行中は通常の `sudo` の認証キャッシュを維持します。
Homebrewには、このコマンド内ですでに `sudo` の認証を確認したことを伝え、重複するキャッシュのリセットを避けます。
認証を維持する処理は、成功・失敗のどちらでもスクリプト終了時に停止します。
macOSのアプリごとの許可画面や独自のインストーラーによる認証は別なので、必要に応じて操作してください。

---

## 🗂️ 管理している主なツール・設定

Markdownの改行は `format-markdown draft.md` でAIに任せられます。
指定ファイルを更新し、`--output formatted.md` を付ければ別ファイルへ保存します。
[使い方と準備](docs/format-markdown.md)を参照してください。

| カテゴリ           | ツール                                                                                                                                                                 |
| :----------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **シェル**         | [Zsh](https://www.zsh.org/) + [Prezto](https://github.com/sorin-ionescu/prezto)（補完・ハイライト・サジェスト）                                                        |
| **エディタ**       | [Vim](https://github.com/vim/vim)（[dein.vim](https://github.com/Shougo/dein.vim)）/ [VSCode](https://github.com/microsoft/vscode) / [Cursor](https://www.cursor.com/) |
| **パッケージ管理** | [Homebrew](https://github.com/Homebrew/brew) / [apt](https://github.com/Debian/apt)                                                                                    |
| **ターミナル**     | [iTerm2](https://github.com/gnachman/iTerm2)                                                                                                                           |
| **キーボード**     | [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) / [Hammerspoon](https://github.com/Hammerspoon/hammerspoon)                                       |
| **AI**             | [Claude Desktop](https://claude.ai/) / Cursor / MCP                                                                                                                    |
| **システム監視**   | [btop](https://github.com/aristocratos/btop)                                                                                                                           |

---

## 🏛️ 設計思想

> **「設定は、コードである。」**

| 原則                       | 説明                                                             |
| :------------------------- | :--------------------------------------------------------------- |
| **宣言的**                 | Brewfileや設定ファイルに書かれた状態が、そのまま環境の正解になる |
| **冪等**                   | 何度実行しても同じ結果になる。壊れない                           |
| **モジュラー**             | 全体を一括で実行することも、個別に実行することもできる           |
| **クロスプラットフォーム** | OSの差異はスクリプトが吸収する                                   |

---

<div align="center">

**Works on my machine. And yours too.**

</div>
