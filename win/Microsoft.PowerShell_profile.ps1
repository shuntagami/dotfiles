$script = @(
    "$Home\dotfiles\win\function.ps1",
    "$Home\dotfiles\win\components.ps1",
    "$Home\dotfiles\win\aliases.ps1",
    "$Home\dotfiles\win\exports.ps1"
)

$script | ForEach-Object {
    if (Test-Path $_) {
        Invoke-Expression ". $_"
    }
}
