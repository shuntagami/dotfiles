# Core dotfiles environment
Set-Environment "DOTFILES" "$HOME\dotfiles"

# Make vim the default editor
Set-Environment "EDITOR" "vim"
Set-Environment "GIT_EDITOR" $Env:EDITOR

function Add-SessionPathIfExists([String]$path) {
   if ((Test-Path $path) -and -not (($Env:Path -split ";") | Where-Object { $_.TrimEnd("\") -ieq $path.TrimEnd("\") })) {
      $Env:Path = "$path;$Env:Path"
   }
}

Add-SessionPathIfExists "$HOME\dotfiles\win\bin"

# Add .dotnet/tools to the PATH environment variable
$dotnetToolsPath = "$HOME\.dotnet\tools"
if ($Env:Path -notlike "*$dotnetToolsPath*") {
   $Env:Path = "$Env:Path;$dotnetToolsPath"
}

# Optionally, save the new PATH permanently for the user
[System.Environment]::SetEnvironmentVariable("Path", $Env:Path, [System.EnvironmentVariableTarget]::User)

# Disable the Progress Bar
$ProgressPreference='SilentlyContinue'
