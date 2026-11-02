#!/bin/bash
# Clone this repository to ~/dotfiles. It is private, so log in to GitHub first
# (`gh auth login`, choosing HTTPS and letting it authenticate Git). The anonymous
# tarball download that used to be the fallback no longer works.

set -eux

DOTFILES="${HOME}/dotfiles"

has() {
  type "$1" > /dev/null 2>&1
}

if [ ! -d "${DOTFILES}" ]; then
  echo "Downloading dotfiles..."
  if has "gh"; then
    gh repo clone shuntagami/dotfiles "${DOTFILES}"
  else
    git clone https://github.com/shuntagami/dotfiles "${DOTFILES}"
  fi
  echo $(tput setaf 2)Download dotfiles complete!. ✔︎$(tput sgr0)
fi
