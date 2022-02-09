#!/bin/bash

set -eux

# Ask for the administrator password upfront
sudo -v

cd $HOME

if ! type brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! type git >/dev/null 2>&1; then
  brew install git
fi

if [ ! -d dotfiles ]; then
  git clone https://github.com/shuntagami/dotfiles.git && cd dotfiles && chmod +x ./scripts/*
fi

brew bundle install --file=$HOME/dotfiles/misc/Brewfile

$HOME/dotfiles/scripts/deploy.sh
