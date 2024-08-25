if (((Get-Command git -ErrorAction SilentlyContinue) -ne $null) -and ((Get-Module -ListAvailable posh-git -ErrorAction SilentlyContinue) -ne $null)) {
  Import-Module posh-git
}

if ((Get-Module -ListAvailable PSWindowsUpdate -ErrorAction SilentlyContinue) -ne $null) {
  Import-Module PSWindowsUpdate
}
