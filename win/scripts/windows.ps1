# Run with PowerShell as administrator
function Set-RegistryItemProperty {
    param (
        [string]$Path,
        [string]$Name,
        [object]$Value
    )

    if (!(Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value
}

# unpin all items from taskbar
Remove-Item "C:\Users\$env:USERNAME\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\*" -Force

# Advanced settings for taskbar
Set-RegistryItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 # hide widgets
Set-RegistryItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 # hide task view
Set-RegistryItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 # hide search box

# settings for wallpaper
$wallpaperBlack = "C:\Users\$env:USERNAME\dotfiles\static\wallpaper-black.jpg"
Set-RegistryItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name "LockScreenImagePath" -Value $wallpaperBlack
Set-RegistryItemProperty -Path "HKCU:Control Panel\Desktop" -Name WallPaper -Value $wallpaperBlack
Remove-Variable -Name wallpaperBlack
