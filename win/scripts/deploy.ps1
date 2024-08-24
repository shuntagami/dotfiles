if (-not (Test-Path -Path $Profile.AllUsersCurrentHost)) {
    New-Item -ItemType SymbolicLink -Path $Profile.AllUsersCurrentHost -Target "$HOME\dotfiles\win\Microsoft.PowerShell_profile.ps1"
}

if (-not (Test-Path -Path "$HOME\.dein.toml")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.dein.toml" -Target "$HOME\dotfiles\.dein.toml"
}

if (-not (Test-Path -Path "$HOME\.editorconfig")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.editorconfig" -Target "$HOME\dotfiles\.editorconfig"
}

if (-not (Test-Path -Path "$HOME\.gemrc")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.gemrc" -Target "$HOME\dotfiles\.gemrc"
}

if (-not (Test-Path -Path "$HOME\.gitconfig")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.gitconfig" -Target "$HOME\dotfiles\.gitconfig"
}

if (-not (Test-Path -Path "$HOME\.gitignore_global")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.gitignore_global" -Target "$HOME\dotfiles\.gitignore_global"
}

if (-not (Test-Path -Path "$HOME\.golangci.yml")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.golangci.yml" -Target "$HOME\dotfiles\.golangci.yml"
}

if (-not (Test-Path -Path "$HOME\.my.cnf")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.my.cnf" -Target "$HOME\dotfiles\.my.cnf"
}

if (-not (Test-Path -Path "$HOME\.npmrc")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.npmrc" -Target "$HOME\dotfiles\.npmrc"
}

if (-not (Test-Path -Path "$HOME\.ocamlinit")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.ocamlinit" -Target "$HOME\dotfiles\.ocamlinit"
}

if (-not (Test-Path -Path "$HOME\.vimrc")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\.vimrc" -Target "$HOME\dotfiles\.vimrc"
}

if (-not (Test-Path -Path "$HOME\AppData\Roaming\Code\User\settings.json")) {
    New-Item -ItemType SymbolicLink -Path "$HOME\AppData\Roaming\Code\User\settings.json" -Target "$HOME\dotfiles\vscode\settings.json"
}
