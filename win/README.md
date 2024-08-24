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
