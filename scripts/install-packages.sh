#!/bin/bash

set -eux

# Load profile: env var > ~/.dotfiles-profile > interactive prompt
if [[ -z "${DOTFILES_PROFILE:-}" ]]; then
  if [[ -f "${HOME}/.dotfiles-profile" ]]; then
    DOTFILES_PROFILE=$(cat "${HOME}/.dotfiles-profile")
  else
    echo ""
    echo "Select a profile:"
    echo "  1) full    - All settings (default)"
    echo "  2) minimal - Without Vim extension, Karabiner, Hammerspoon"
    echo ""
    read -p "Enter choice [1]: " profile_choice
    case "${profile_choice}" in
      2|minimal) DOTFILES_PROFILE="minimal" ;;
      *)         DOTFILES_PROFILE="full" ;;
    esac
    echo "${DOTFILES_PROFILE}" > "${HOME}/.dotfiles-profile"
  fi
fi
export DOTFILES_PROFILE

has() {
  type "$1" > /dev/null 2>&1
}

cd $HOME/dotfiles

if [[ `uname` == "Linux" ]]; then
  source $HOME/dotfiles/scripts/apt-get && run-apt
  source $HOME/dotfiles/scripts/anyenv && install-anyenv
  source $HOME/dotfiles/scripts/gh && install-gh
  source $HOME/dotfiles/scripts/btop && install-btop
elif [[ `uname` == "Darwin" ]]; then
  if ! has "brew"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if has "brew"; then
    export HOMEBREW_CASK_OPTS="--no-quarantine"
    brewfile="$HOME/dotfiles/misc/Brewfile"
    if [[ "${DOTFILES_PROFILE:-full}" == "minimal" ]]; then
      tmp_brewfile=$(mktemp)
      grep -v -E '^cask "hammerspoon"|^cask "karabiner-elements"|^vscode "vscodevim\.vim"' "$brewfile" > "$tmp_brewfile"
      brewfile="$tmp_brewfile"
    fi
    brew bundle install --file="$brewfile"
    eval "$(/opt/homebrew/bin/brew shellenv)"
    source $HOME/dotfiles/scripts/anyenv && install-anyenv
  fi
fi
