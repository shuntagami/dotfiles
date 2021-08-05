#!/bin/bash

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
  git
  git-secrets
  awscli
  anyenv
  docker
  docker-compose
  cask
  mas
  hub
  jmeter
  lua
  vim
  postgresql
  circleci
  imagemagick
  watch
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
  dropbox
  evernote
  github
  gyazo
  google-chrome
  google-drive-file-stream
  google-japanese-ime
  slack
  the-unarchiver
  iterm2
  clipy
  kindle
  adobe-acrobat-reader
  visual-studio-code
  docker
  sequel-pro
  utm
  virtualbox
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
exec $SHELL -l

cat << END

**************************************************
Everything is ready. Enjoy your new Mac!
**************************************************

END
