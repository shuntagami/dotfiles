#!/bin/zsh

## (Mac)

# Shortcuts
alias d="cd ~/dotfiles"
alias dls="cd ~/Downloads"
alias dt="cd ~/Desktop"
alias p="cd ~/projects"
alias g="git"
alias icloud="cd ~/Library/Mobile\ Documents/com~apple~CloudDocs"
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

uncode() {
  pbpaste \
  | sed 's/^```.*$//g' \
  | sed 's/^    //g' \
  | sed 's/^`//g; s/`$//g' \
  | pbcopy
}

mdclean() {
  pbpaste \
  | sed '/^---$/d' \
  | sed '/^___$/d' \
  | sed '/^\*\*\*$/d' \
  | pbcopy
}

mdclean_all() {
  pbpaste \
  | sed 's/^```.*$//g' \
  | sed 's/^    //g' \
  | sed 's/^`//g; s/`$//g' \
  | sed '/^---$/d' \
  | sed '/^___$/d' \
  | sed '/^\*\*\*$/d' \
  | pbcopy
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
alias vpn.connect="networksetup -connectpppoeservice 'ANDPAD-VPN (L2TP)'"
alias vpn.disconnect="networksetup -disconnectpppoeservice 'ANDPAD-VPN (L2TP)'"

# Wifi
alias wifi.on="networksetup -setairportpower en0 on"
alias wifi.off="networksetup -setairportpower en0 off"
alias wifi.hotspot="networksetup -setairportnetwork en0 pixel"
alias wifi.starbucks="networksetup -setairportnetwork en0 at_STARBUCKS_Wi2"

# aws-vault
function avl() {
  local profile="$1"
  if [ -z "$profile" ]; then
    echo "Usage: avl <profile>"
    return 1
  fi
  local url=$(aws-vault login "$profile" --stdout)
  if [ $? -eq 0 ]; then
    open -na "Google Chrome" --args --incognito --user-data-dir="$HOME/Library/Application Support/Google/Chrome/aws-vault/$profile" "$url"
  fi
}

# Display Manager
## Mirror
alias mirror.on='~/dotfiles/scripts/display_manager mirror enable ext0 main'
alias mirror.off='~/dotfiles/scripts/display_manager mirror disable'

## Res
alias res.max='~/dotfiles/scripts/display_manager res highest main'
alias res.default='~/dotfiles/scripts/display_manager res default all'
alias res.40='~/dotfiles/scripts/display_manager res 3840 1620'
alias res.31='~/dotfiles/scripts/display_manager res 3360 1890'
alias res.27='~/dotfiles/scripts/display_manager res 3008 1692'
alias res.qhd='~/dotfiles/scripts/display_manager res 2560 1440'
alias res.fhd='~/dotfiles/scripts/display_manager res 1920 1080'

# Check typo between HEAD and default branch
alias typocheck="git diff HEAD..$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@') --name-only | xargs -I {} typos {}"

# For Kindle, Extracts and copies the first line of clipboard content without a trailing newline
alias cl1='pbpaste | head -n 1 | while IFS= read -r line; do printf "%s" "$line"; done | pbcopy'

# Cursor 拡張機能の同期（Brewfile の vscode 行を参照）
_sync_cursor_extensions() {
  local mode=$1
  local brewfile=$HOME/dotfiles/misc/Brewfile

  if [[ "$mode" == "from-brewfile" ]]; then
    # Brewfile を正として Cursor に適用
    echo "Syncing Cursor extensions from Brewfile..."

    # Brewfile にある拡張機能をインストール
    grep "^vscode " "$brewfile" | sed 's/vscode "\(.*\)"/\1/' | while read ext; do
      cursor --install-extension "$ext" --force 2>/dev/null
    done

    # Brewfile にない拡張機能を削除
    cursor --list-extensions 2>/dev/null | while read ext; do
      if ! grep -q "vscode \"$ext\"" "$brewfile"; then
        echo "Uninstalling from Cursor: $ext"
        cursor --uninstall-extension "$ext" 2>/dev/null
      fi
    done
  elif [[ "$mode" == "from-system" ]]; then
    # VSCode の状態を Cursor にも反映
    echo "Syncing Cursor extensions from VSCode..."
    code --list-extensions | while read ext; do
      cursor --install-extension "$ext" --force 2>/dev/null
    done

    # VSCode にない拡張機能を Cursor から削除
    cursor --list-extensions 2>/dev/null | while read ext; do
      if ! code --list-extensions | grep -qx "$ext"; then
        echo "Uninstalling from Cursor: $ext"
        cursor --uninstall-extension "$ext" 2>/dev/null
      fi
    done
  fi
}

update-brew-env() {
  MODE=$1 # 引数: from-brewfile or from-system

  export HOMEBREW_CASK_OPTS="--no-quarantine"
  cd ~/dotfiles/misc
  brew update

  if [[ "$MODE" == "from-brewfile" ]]; then
    # Brewfile を正として同期（不要なものを削除 → インストール → lock 更新）
    brew bundle cleanup --force --file=$HOME/dotfiles/misc/Brewfile
    brew bundle install --file=$HOME/dotfiles/misc/Brewfile
    # Cursor も同期
    _sync_cursor_extensions from-brewfile
  elif [[ "$MODE" == "from-system" ]]; then
    # システムを正として同期（Brewfile 更新 → lock 更新）
    brew bundle dump --force --file=$HOME/dotfiles/misc/Brewfile
    brew bundle install --file=$HOME/dotfiles/misc/Brewfile
    # Cursor も同期
    _sync_cursor_extensions from-system
  else
    echo "Usage: update-brew-env [from-brewfile|from-system]"
    return 1
  fi

  brew cleanup

  # npm グローバルパッケージの更新（メジャーバージョン含む）
  npm install -g npm
  npm ls -g --depth=0 --json 2>/dev/null | jq -r '.dependencies | keys[]' | xargs -I {} npm install -g {}@latest
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
