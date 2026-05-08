$ErrorActionPreference = "Stop"

$Dotfiles = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

function New-DotfileLink {
    param(
        [string] $Path,
        [string] $Target
    )

    if (-not (Test-Path -LiteralPath $Target)) {
        Write-Warning "Skipping missing target: $Target"
        return
    }

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (Test-Path -LiteralPath $Path) {
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null
    } catch {
        Write-Warning "Could not create symlink for $Path. Copying the target instead."
        Copy-Item -LiteralPath $Target -Destination $Path -Recurse -Force
    }
}

New-DotfileLink -Path $Profile.CurrentUserAllHosts -Target (Join-Path $Dotfiles "win\Microsoft.PowerShell_profile.ps1")

$links = @(
    @{ Path = "$HOME\.dein.toml"; Target = Join-Path $Dotfiles ".dein.toml" },
    @{ Path = "$HOME\.editorconfig"; Target = Join-Path $Dotfiles ".editorconfig" },
    @{ Path = "$HOME\.gitconfig"; Target = Join-Path $Dotfiles ".gitconfig" },
    @{ Path = "$HOME\.gitignore_global"; Target = Join-Path $Dotfiles ".gitignore_global" },
    @{ Path = "$HOME\.golangci.yml"; Target = Join-Path $Dotfiles ".golangci.yml" },
    @{ Path = "$HOME\.my.cnf"; Target = Join-Path $Dotfiles ".my.cnf" },
    @{ Path = "$HOME\.npmrc"; Target = Join-Path $Dotfiles ".npmrc" },
    @{ Path = "$HOME\.ocamlinit"; Target = Join-Path $Dotfiles ".ocamlinit" },
    @{ Path = "$HOME\.vimrc"; Target = Join-Path $Dotfiles ".vimrc" },
    @{ Path = "$HOME\AppData\Roaming\Code\User\settings.json"; Target = Join-Path $Dotfiles "vscode\settings.json" }
)

foreach ($link in $links) {
    New-DotfileLink -Path $link.Path -Target $link.Target
}

& (Join-Path $PSScriptRoot "install-bin-shims.ps1")

Write-Host "Windows deploy complete. Restart PowerShell or run 'Refresh-Environment' to reload PATH."
