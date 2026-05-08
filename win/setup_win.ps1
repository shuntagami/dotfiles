$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

winget import --accept-package-agreements (Join-Path $ScriptDir "winget.json")
winget install --exact --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
