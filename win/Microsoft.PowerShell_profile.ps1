$script = @(
    "$HOME\dotfiles\win\function.ps1",
    "$HOME\dotfiles\win\components.ps1",
    "$HOME\dotfiles\win\aliases.ps1",
    "$HOME\dotfiles\win\exports.ps1"
)

$script | ForEach-Object {
    if (Test-Path $_) {
        Invoke-Expression ". $_"
    }
}
