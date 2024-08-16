if (-not (Test-Path -Path $Profile.AllUsersCurrentHost)) {
    New-Item -ItemType SymbolicLink -Path $Profile.AllUsersCurrentHost -Target "$Home\dotfiles\win\Microsoft.PowerShell_profile.ps1"
}

if (-not (Test-Path -Path "$Home\.dein.toml")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.dein.toml" -Target "$Home\dotfiles\.dein.toml"
}

if (-not (Test-Path -Path "$Home\.editorconfig")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.editorconfig" -Target "$Home\dotfiles\.editorconfig"
}

if (-not (Test-Path -Path "$Home\.gemrc")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.gemrc" -Target "$Home\dotfiles\.gemrc"
}

if (-not (Test-Path -Path "$Home\.gitconfig")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.gitconfig" -Target "$Home\dotfiles\.gitconfig"
}

if (-not (Test-Path -Path "$Home\.gitignore_global")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.gitignore_global" -Target "$Home\dotfiles\.gitignore_global"
}

if (-not (Test-Path -Path "$Home\.golangci.yml")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.golangci.yml" -Target "$Home\dotfiles\.golangci.yml"
}

if (-not (Test-Path -Path "$Home\.my.cnf")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.my.cnf" -Target "$Home\dotfiles\.my.cnf"
}

if (-not (Test-Path -Path "$Home\.npmrc")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.npmrc" -Target "$Home\dotfiles\.npmrc"
}

if (-not (Test-Path -Path "$Home\.ocamlinit")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.ocamlinit" -Target "$Home\dotfiles\.ocamlinit"
}

if (-not (Test-Path -Path "$Home\.vimrc")) {
    New-Item -ItemType SymbolicLink -Path "$Home\.vimrc" -Target "$Home\dotfiles\.vimrc"
}

if (-not (Test-Path -Path "$Home\AppData\Roaming\Code\User\settings.json")) {
    New-Item -ItemType SymbolicLink -Path "$Home\AppData\Roaming\Code\User\settings.json" -Target "$Home\dotfiles\vscode\settings.json"
}
