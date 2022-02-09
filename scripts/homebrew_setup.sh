#!/bin/bash

set -eux

echo installing homebrew...
which brew >/dev/null 2>&1 || /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

echo run brew doctor...
which brew >/dev/null 2>&1 && brew doctor

echo run brew update...
which brew >/dev/null 2>&1 && brew update

echo ok. run brew upgrade...
brew upgrade

echo change authority for brew...
sudo chown -R $(whoami):admin /usr/local/*
sudo chmod -R g+w /usr/local/*

formulas=(
  anyenv
  awscli
  cask
  docker
  docker-compose
  gh
  git
  git-secrets
  hub
  imagemagick
  lua
  mas
  vim
  watch
  zsh
)

"brew tap..."
brew tap homebrew/dupes
brew tap homebrew/versions
brew tap homebrew/homebrew-php
brew tap homebrew/apache
brew tap sanemat/font

echo start brew install apps...
for formula in "${formulas[@]}"; do
  brew install $formula || brew upgrade $formula
done

casks=(
  adobe-acrobat-reader
  clipy
  docker
  github
  google-chrome
  google-drive-file-stream
  google-japanese-ime
  gyazo
  iterm2
  kindle
  slack
  utm
  virtualbox
  visual-studio-code
  zoom
)

echo start brew cask install apps...
for cask in "${casks[@]}"; do
 brew install --cask $cask
done

echo Installing Apps from the App Store...
mas install 539883307 #LINE

brew cleanup
brew cask cleanup

# anyenv updateコマンドをインストール
[ ! -d "$(anyenv root)"/plugins/anyenv-update ] && git clone https://github.com/znz/anyenv-update.git "$(anyenv root)"/plugins/anyenv-update
anyenv install tfenv
anyenv install nodenv
anyenv install rbenv

cat << END

**************************************************
Everything is ready. Enjoy your new Mac!
**************************************************

END
