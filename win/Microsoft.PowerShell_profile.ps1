$script = @("$Home\dotfiles\win\aliases.ps1", "$Home\dotfiles\win\function.ps1")
foreach ($s in $script) {
  if (Test-Path $s) {
    . $s
  }
}
