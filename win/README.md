# Windows Setup

## Stratup フォルダに Autoohtkey.ahk のショートカットを配置

```
cd ~/AppData/Roaming/Microsoft/Windows/ && cd Start\ Menu/Programs/Startup/
```

で移動し、ショートカットを配置する

## Setup PowerShell

```posh
New-Item -ItemType SymbolicLink -Path $Profile.AllUsersCurrentHost -Target "$Home\dotfiles\win\Microsoft.PowerShell_profile.ps1"
```

相対パス`~/dotfiles`の書き方だと`.: Could not find a part of the path 'C:\Program Files\PowerShell\7\Microsoft.PowerShell_profile.ps1'.`のエラー発生した

## Setup scoop

```posh
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```
