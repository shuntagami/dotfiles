# Basic commands
function which($name) { Get-Command $name -ErrorAction SilentlyContinue | Select-Object Definition }
function touch($file) { "" | Out-File $file -Encoding ASCII }

# Common Editing needs
function Edit-Hosts { Invoke-Expression "sudo $(if($env:EDITOR -ne $null)  {$env:EDITOR } else { 'notepad' }) $env:windir\system32\drivers\etc\hosts" }
function Edit-Profile { Invoke-Expression "$(if($env:EDITOR -ne $null)  {$env:EDITOR } else { 'notepad' }) $profile" }

# Sudo
function sudo() {
    if ($args.Length -eq 1) {
        start-process $args[0] -verb "runAs"
    }
    if ($args.Length -gt 1) {
        start-process $args[0] -ArgumentList $args[1..$args.Length] -verb "runAs"
    }
}

# Update Windows Store apps. This doesn't get all, but gets most.
function Update-WindowsStore() {
    Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | Invoke-CimMethod -MethodName UpdateScanMethod
}

# System Update - Update RubyGems, NPM, and their installed packages
function System-Update() {
    Install-WindowsUpdate -IgnoreUserInput -IgnoreReboot -AcceptAll
    winget upgrade --all
    scoop update --all
    Update-Module
    Update-Help -Force -ErrorAction SilentlyContinue
    Update-Help -Force
    if ((which gem)) {
        gem update --system
        gem update
    }
    if ((which npm)) {
        npm install npm -g
        npm update -g
    }
}

# Reload the Shell
function Reload-Powershell {
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = "-nologo";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

# Download a file into a temporary folder
function curlex($url) {
    $uri = new-object system.uri $url
    $filename = $name = $uri.segments | Select-Object -Last 1
    $path = join-path $env:Temp $filename
    if( test-path $path ) { rm -force $path }

    (new-object net.webclient).DownloadFile($url, $path)

    return new-object io.fileinfo $path
}

# Empty the Recycle Bin on all drives
function Empty-RecycleBin {
    $RecBin = (New-Object -ComObject Shell.Application).Namespace(0xA)
    $RecBin.Items() | %{Remove-Item $_.Path -Recurse -Confirm:$false}
}

# Sound Volume
function Get-SoundVolume {
  <#
  .SYNOPSIS
  Get audio output volume.

  .DESCRIPTION
  The Get-SoundVolume cmdlet gets the current master volume of the default audio output device. The returned value is an integer between 0 and 100.

  .LINK
  Set-SoundVolume

  .LINK
  Set-SoundMute

  .LINK
  Set-SoundUnmute

  .LINK
  https://github.com/jayharris/dotfiles-windows/
  #>
  [math]::Round([Audio]::Volume * 100)
}
function Set-SoundVolume([Parameter(mandatory=$true)][Int32] $Volume) {
  <#
  .SYNOPSIS
  Set audio output volume.

  .DESCRIPTION
  The Set-SoundVolume cmdlet sets the current master volume of the default audio output device to a value between 0 and 100.

  .PARAMETER Volume
  An integer between 0 and 100.

  .EXAMPLE
  Set-SoundVolume 65
  Sets the master volume to 65%.

  .EXAMPLE
  Set-SoundVolume -Volume 100
  Sets the master volume to a maximum 100%.

  .LINK
  Get-SoundVolume

  .LINK
  Set-SoundMute

  .LINK
  Set-SoundUnmute

  .LINK
  https://github.com/jayharris/dotfiles-windows/
  #>
  [Audio]::Volume = ($Volume / 100)
}
function Set-SoundMute {
  <#
  .SYNOPSIS
  Mote audio output.

  .DESCRIPTION
  The Set-SoundMute cmdlet mutes the default audio output device.

  .LINK
  Get-SoundVolume

  .LINK
  Set-SoundVolume

  .LINK
  Set-SoundUnmute

  .LINK
  https://github.com/jayharris/dotfiles-windows/
  #>
   [Audio]::Mute = $true
}
function Set-SoundUnmute {
  <#
  .SYNOPSIS
  Unmote audio output.

  .DESCRIPTION
  The Set-SoundUnmute cmdlet unmutes the default audio output device.

  .LINK
  Get-SoundVolume

  .LINK
  Set-SoundVolume

  .LINK
  Set-SoundMute

  .LINK
  https://github.com/jayharris/dotfiles-windows/
  #>
   [Audio]::Mute = $false
}


### File System functions
### ----------------------------
# Create a new directory and enter it
function CreateAndSet-Directory([String] $path) { New-Item $path -ItemType Directory -ErrorAction SilentlyContinue; Set-Location $path}

# Determine size of a file or total size of a directory
function Get-DiskUsage([string] $path=(Get-Location).Path) {
    Convert-ToDiskSize `
        ( `
            Get-ChildItem .\ -recurse -ErrorAction SilentlyContinue `
            | Measure-Object -property length -sum -ErrorAction SilentlyContinue
        ).Sum `
        1
}

# Cleanup all disks (Based on Registry Settings in `windows.ps1`)
function Clean-Disks {
    Start-Process "$(Join-Path $env:WinDir 'system32\cleanmgr.exe')" -ArgumentList "/sagerun:6174" -Verb "runAs"
}

### Environment functions
### ----------------------------

# Reload the $env object from the registry
function Refresh-Environment {
    $locations = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
                 'HKCU:\Environment'

    $locations | ForEach-Object {
        $k = Get-Item $_
        $k.GetValueNames() | ForEach-Object {
            $name  = $_
            $value = $k.GetValue($_)
            Set-Item -Path Env:\$name -Value $value
        }
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Set a permanent Environment variable, and reload it into $env
function Set-Environment([String] $variable, [String] $value) {
    Set-ItemProperty "HKCU:\Environment" $variable $value
    # Manually setting Registry entry. SetEnvironmentVariable is too slow because of blocking HWND_BROADCAST
    #[System.Environment]::SetEnvironmentVariable("$variable", "$value","User")
    Invoke-Expression "`$env:${variable} = `"$value`""
}

# Add a folder to $env:Path
function Prepend-EnvPath([String]$path) { $env:PATH = $env:PATH + ";$path" }
function Prepend-EnvPathIfExists([String]$path) { if (Test-Path $path) { Prepend-EnvPath $path } }
function Append-EnvPath([String]$path) { $env:PATH = $env:PATH + ";$path" }
function Append-EnvPathIfExists([String]$path) { if (Test-Path $path) { Append-EnvPath $path } }


### Utilities
### ----------------------------

# Convert a number to a disk size (12.4K or 5M)
function Convert-ToDiskSize {
    param ( $bytes, $precision='0' )
    foreach ($size in ("B","K","M","G","T")) {
        if (($bytes -lt 1000) -or ($size -eq "T")){
            $bytes = ($bytes).tostring("F0" + "$precision")
            return "${bytes}${size}"
        }
        else { $bytes /= 1KB }
    }
}

# Start IIS Express Server with an optional path and port
function Start-IISExpress {
    [CmdletBinding()]
    param (
        [String] $path = (Get-Location).Path,
        [Int32]  $port = 3000
    )

    if ((Test-Path "${env:ProgramFiles}\IIS Express\iisexpress.exe") -or (Test-Path "${env:ProgramFiles(x86)}\IIS Express\iisexpress.exe")) {
        $iisExpress = Resolve-Path "${env:ProgramFiles}\IIS Express\iisexpress.exe" -ErrorAction SilentlyContinue
        if ($iisExpress -eq $null) { $iisExpress = Get-Item "${env:ProgramFiles(x86)}\IIS Express\iisexpress.exe" }

        & $iisExpress @("/path:${path}") /port:$port
    } else { Write-Warning "Unable to find iisexpress.exe"}
}

function Extract {
    param (
        [string]$file
    )

    Write-Host "Extracting $file ..."

    if (Test-Path $file -PathType Leaf) {
        switch -Wildcard ($file) {
            "*.tar.bz2" { tar -xjf $file }
            "*.tar.gz"  { tar -xzf $file }
            "*.bz2"     { bunzip2 $file }
            "*.rar"     { & "C:\Program Files\WinRAR\rar.exe" x $file }
            "*.gz"      { gunzip $file }
            "*.tar"     { tar -xf $file }
            "*.tbz2"    { tar -xjf $file }
            "*.tgz"     { tar -xzf $file }
            "*.zip"     { Expand-Archive -Path $file -DestinationPath (Join-Path (Get-Location) ([System.IO.Path]::GetFileNameWithoutExtension($file))) }
            "*.Z"       { uncompress $file }
            "*.7z"      { & "C:\Program Files\7-Zip\7z.exe" x $file }
            default     { Write-Host "'$file' cannot be extracted via Extract()" }
        }
    } else {
        Write-Host "'$file' is not a valid file"
    }
}

function Copy-FirstLine {
    $clipboardContent = Get-Clipboard
    $firstLine = $clipboardContent -split "`n" | Select-Object -First 1
    Set-Clipboard -Value $firstLine
}
