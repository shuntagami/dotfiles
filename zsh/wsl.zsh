#!/usr/bin/env zsh

## (WSL)

# Load configuration
if [[ -f "$HOME/dotfiles/config/paths.conf" ]]; then
  source "$HOME/dotfiles/config/paths.conf"
fi

# open is aliased to xdg-open in WSL
alias xdg-open="explorer.exe"

# WSL-specific paths (customize WSL_USER_NAME in config)
WSL_USER_NAME="${WSL_USER_NAME:-shunt}"
alias dls="cd /mnt/c/Users/${WSL_USER_NAME}/Downloads"
alias dt="cd /mnt/c/Users/${WSL_USER_NAME}/Desktop"

# Alternative: auto-detect username (uncomment if Windows and WSL usernames match)
# alias dls='cd /mnt/c/Users/$(whoami)/Downloads'
# alias dt='cd /mnt/c/Users/$(whoami)/Desktop'
