$script = @("$Home\dotfiles\win\components\git.ps1")
foreach ($s in $script) {
  if (Test-Path $s) {
    . $s
  }
}
