$ErrorActionPreference = "Stop"

$Dotfiles = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$SourceBin = Join-Path $Dotfiles "bin"
$ShimBin = Join-Path $Dotfiles "win\bin"

New-Item -ItemType Directory -Force -Path $ShimBin | Out-Null

function Get-Runner {
    param([string] $Path)

    $firstLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction SilentlyContinue
    if ($firstLine -match "node") { return "node" }
    if ($firstLine -match "bash|zsh|sh") { return "bash" }

    return $null
}

function Write-CmdShim {
    param(
        [string] $Name,
        [string] $Runner,
        [string] $ScriptPath
    )

    $shimPath = Join-Path $ShimBin "$Name.cmd"
    $scriptForCmd = $ScriptPath -replace "\\", "/"
    $content = @"
@echo off
setlocal
set "SCRIPT=$scriptForCmd"
$Runner "%SCRIPT%" %*
exit /b %ERRORLEVEL%
"@

    Set-Content -LiteralPath $shimPath -Value $content -Encoding ASCII
}

Get-ChildItem -LiteralPath $SourceBin -File |
    Where-Object { $_.Name -notlike ".*" } |
    ForEach-Object {
        $runner = Get-Runner $_.FullName
        if ($runner) {
            Write-CmdShim -Name $_.Name -Runner $runner -ScriptPath $_.FullName
        }
    }

function Add-UserPathEntry {
    param([string] $PathToAdd)

    $resolved = (Resolve-Path $PathToAdd).Path.TrimEnd("\")
    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($currentUserPath) {
        $parts = $currentUserPath -split ";" | Where-Object { $_ }
    }

    $exists = $false
    foreach ($part in $parts) {
        if ($part.TrimEnd("\") -ieq $resolved) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $newPath = if ($currentUserPath) { "$currentUserPath;$resolved" } else { $resolved }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    }

    $sessionParts = $env:Path -split ";" | Where-Object { $_ }
    if (-not ($sessionParts | Where-Object { $_.TrimEnd("\") -ieq $resolved })) {
        $env:Path = "$resolved;$env:Path"
    }
}

Add-UserPathEntry $ShimBin

Write-Host "Installed bin shims to $ShimBin"
