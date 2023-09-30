#!/bin/zsh

## (Mac)

# Shortcuts
alias d="cd ~/dotfiles"
alias dls="cd ~/Downloads"
alias dt="cd ~/Desktop"
alias p="cd ~/projects"
alias 88labs="cd ~/projects/88labs"
alias g="git"
alias icloud="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"

# homebrew
if [ -d "/opt/homebrew" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# color
autoload -U colors
colors

# Airport CLI alias
alias airport='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport'

alias chrome="open -a Google\ Chrome"

# Recursively delete `.DS_Store` files
alias rm-ds-store="find . -name '.DS_Store' -type f -delete"

alias emptytrash="osascript -e 'tell application \"Finder\" to empty trash'"

# Flush Directory Service cache
alias flush="dscacheutil -flushcache && killall -HUP mDNSResponder"

# copy
alias pbp="pbpaste"

function pb() {
  if [ -t 0 ]; then
    cat $1 | pbcopy
  else
    pbcopy < /dev/stdin
  fi
}

# IP addresses
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"
alias localip="ipconfig getifaddr en0"
alias ips="ifconfig -a | grep -o 'inet6\? \(addr:\)\?\s\?\(\(\([0-9]\+\.\)\{3\}[0-9]\+\)\|[a-fA-F0-9:]\+\)' | awk '{ sub(/inet6? (addr:)? ?/, \"\"); print }'"

# Get macOS Software Updates
alias os.update='sudo softwareupdate -i -a'

function say() {
  osascript -e "say \"{$1}\""
}

# Disable Spotlight
alias spotlight.off="sudo mdutil -a -i off"
# Enable Spotlight
alias spotlight.on="sudo mdutil -a -i on"

# Update installed Ruby gems, Homebrew, npm, and their installed packages
alias update='cd ~/dotfiles/misc; brew update; brew bundle install --file=$HOME/dotfiles/misc/Brewfile; rm -rf Brewfile; brew bundle dump; brew cleanup; npm install npm -g; npm update -g; sudo gem update --system; sudo gem update; sudo gem cleanup; 1'

# Update locate command
alias db.update="sudo /usr/libexec/locate.updatedb"

# VPN
alias vpn.connect="networksetup -connectpppoeservice 'ANDPAD-VPN (L2TP)'"
alias vpn.disconnect="networksetup -disconnectpppoeservice 'ANDPAD-VPN (L2TP)'"

# Wifi
alias wifi.on="networksetup -setairportpower en0 on"
alias wifi.off="networksetup -setairportpower en0 off"
alias wifi.hotspot="networksetup -setairportnetwork en0 pixel"
alias wifi.starbucks="networksetup -setairportnetwork en0 at_STARBUCKS_Wi2"

# aws-vault
alias avl='(){ open -na "Google Chrome" --args --incognito --user-data-dir=$HOME/Library/Application\ Support/Google/Chrome/aws-vault/$@ $(aws-vault login $@ --stdout) }'

# Display Manager
## Mirror
alias mirror.on='~/dotfiles/scripts/display_manager.py mirror enable ext0 main'
alias mirror.off='~/dotfiles/scripts/display_manager.py mirror disable'

## Res
alias res.max='~/dotfiles/scripts/display_manager.py res highest main'
alias res.default='~/dotfiles/scripts/display_manager.py res default all'
alias res.31='~/dotfiles/scripts/display_manager.py res 3360 1890'
alias res.27='~/dotfiles/scripts/display_manager.py res 3008 1692'
alias res.qhd='~/dotfiles/scripts/display_manager.py res 2560 1440'
alias res.fhd='~/dotfiles/scripts/display_manager.py res 1920 1080'
