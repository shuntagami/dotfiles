#!/bin/bash

set -eux

has() {
  type "$1" > /dev/null 2>&1
}

cd $HOME/dotfiles

if [[ `uname` == "Linux" ]]; then
  source $HOME/dotfiles/scripts/apt-get
  run_apt
elif [[ `uname` == "Darwin" ]]; then
  if ! has "brew"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  if has "brew"; then
    brew bundle install --file=$HOME/dotfiles/misc/Brewfile
  fi
fi

