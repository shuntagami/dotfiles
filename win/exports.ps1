# Make vim the default editor
Set-Environment "EDITOR" "vim"
Set-Environment "GIT_EDITOR" $Env:EDITOR

# Add .dotnet/tools to the PATH environment variable
$dotnetToolsPath = "$HOME\.dotnet\tools"
if ($Env:Path -notlike "*$dotnetToolsPath*") {
   $Env:Path = "$Env:Path;$dotnetToolsPath"
}

# Optionally, save the new PATH permanently for the user
[System.Environment]::SetEnvironmentVariable("Path", $Env:Path, [System.EnvironmentVariableTarget]::User)

# Disable the Progress Bar
$ProgressPreference='SilentlyContinue'
