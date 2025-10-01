#!/usr/bin/env zsh

## (Mac)

# Load configuration
if [[ -f "$HOME/dotfiles/config/dotfiles.conf" ]]; then
  source "$HOME/dotfiles/config/dotfiles.conf"
fi

if [[ -f "$HOME/dotfiles/config/paths.conf" ]]; then
  source "$HOME/dotfiles/config/paths.conf"
fi

# Shortcuts (using configured paths)
alias d="cd ${alias_dot}"
alias dls="cd ${alias_downloads}"
alias dt="cd ${alias_d}"
alias p="cd ${alias_p}"
alias 88labs="cd ${alias_p}/88labs"
alias g="git"
alias icloud="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"
alias python="python3"
# alias code="cursor"

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
alias copyfile='pbcopy <'

function pb() {
  if [ -t 0 ]; then
    cat $1 | pbcopy
  else
    pbcopy </dev/stdin
  fi
}

# IP addresses
alias ip="dig +short myip.opendns.com @resolver1.opendns.com"
alias localip="ipconfig getifaddr en0"
alias ips="ifconfig -a | grep -o 'inet6\? \(addr:\)\?\s\?\(\(\([0-9]\+\.\)\{3\}[0-9]\+\)\|[a-fA-F0-9:]\+\)' | awk '{ sub(/inet6? (addr:)? ?/, \"\"); print }'"

# Get macOS Software Updates
alias os.update='sudo softwareupdate -i -a'

function say() {
  osascript -e "say \"$1\""
}

# Disable Spotlight
alias spotlight.off="sudo mdutil -a -i off"
# Enable Spotlight
alias spotlight.on="sudo mdutil -a -i on"

# Update locate command
alias db.update="sudo /usr/libexec/locate.updatedb"

# VPN
alias vpn.connect="networksetup -connectpppoeservice '${VPN_SERVICE_NAME}'"
alias vpn.disconnect="networksetup -disconnectpppoeservice '${VPN_SERVICE_NAME}'"

# Wifi
alias wifi.on="networksetup -setairportpower en0 on"
alias wifi.off="networksetup -setairportpower en0 off"
alias wifi.home="networksetup -setairportnetwork en0 '${WIFI_NETWORK_HOME}'"
alias wifi.office="networksetup -setairportnetwork en0 '${WIFI_NETWORK_OFFICE}'"

# aws-vault
function avl() {
  local profile="$1"
  if [ -z "$profile" ]; then
    echo "Usage: avl <profile>"
    return 1
  fi
  local url=$(aws-vault login "$profile" --stdout)
  if [ $? -eq 0 ]; then
    open -na "Google Chrome" --args --incognito --user-data-dir="${alias_library}/Application Support/Google/Chrome/aws-vault/$profile" "$url"
  fi
}

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

# Check typo between HEAD and default branch
alias typocheck="git diff HEAD..$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@') --name-only | xargs -I {} typos {}"

# For Kindle, Extracts and copies the first line of clipboard content without a trailing newline
alias cl1='pbpaste | head -n 1 | while IFS= read -r line; do printf "%s" "$line"; done | pbcopy'

update-brew-env() {
  MODE=$1 # 引数: from-brewfile or from-system

  export HOMEBREW_CASK_OPTS="${HOMEBREW_CASK_OPTS}"
  cd "${alias_dot}/misc"
  brew update

  if [[ "$MODE" == "from-brewfile" ]]; then
    brew bundle cleanup --force --file="${alias_dot}/misc/Brewfile"
    brew bundle install --file="${alias_dot}/misc/Brewfile"
  elif [[ "$MODE" == "from-system" ]]; then
    brew bundle dump --force --file="${alias_dot}/misc/Brewfile"
  else
    echo "Usage: update-brew-env [from-brewfile|from-system]"
    return 1
  fi

  brew cleanup
  # npm install -g npm
  # npm update -g
  # sudo gem update --system
  # sudo gem update
  # sudo gem cleanup
}

alias update-from-brewfile='update-brew-env from-brewfile'
alias update-from-system='update-brew-env from-system'

alias h1down='sed -i "" -E -e "s/^# (.*)$/\\1/" -e "s/^#(#+) /\\1 /"'
alias h1up='sed -i "" -E "s/^(#+ .*)/#\\1/"'
alias nobold='sed -i "" -E '\''s/\*\*([^*]+)\*\*/\1/g'\'''
noboldh() {
  sed -i "" -E '/^[[:space:]]*#/ s/\*\*([^*]+)\*\*/\1/g' "$@"
}
alias trims='perl -i -CSAD -pe '\''s/[\h\p{Z}\x{00A0}\x{2000}-\x{200B}\x{202F}\x{205F}\x{2060}\x{3000}\x{FEFF}]+$//'\'''
