# Windows Setup

## Stratup フォルダに Autoohtkey.ahk のショートカットを配置

```posh
cd "$HOME\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
explorer.exe .
```

## Setup PowerShell

```posh
~/dotfiles/win/scripts/deploy.ps1
```

`deploy.ps1` は PowerShell プロファイルのリンクに加えて、`~/dotfiles/win/bin` に `bin/` コマンド用の `.cmd` shim を生成し、ユーザー PATH に追加します。反映には PowerShell の再起動、または `Refresh-Environment` が必要です。

## Setup scoop

```posh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
scoop import "$HOME\dotfiles\win\scoop.json"
```

## Setup windows default configuration

```posh
~/dotfiles/win/scripts/windows.ps1
```

## bin commands on Windows

多くの `bin/` コマンドは Node.js で動きます。`win/setup_win.ps1` は `OpenJS.NodeJS.LTS` をインストールします。

外部ツールが必要なコマンド:

- `git-diffn`: Git for Windows の Bash と awk/gawk
- `pdf-compress`: Ghostscript と qpdf
- `merge_pdf`: cpdf
- `extract-m3u8`: Playwright (`npm install -g playwright` と `npx playwright install chromium`)
