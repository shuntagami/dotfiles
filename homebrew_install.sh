#!/bin/bash

echo installing homebrew...
which brew >/dev/null 2>&1 || /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

echo run brew doctor...
which brew >/dev/null 2>&1 && brew doctor

echo run brew update...
which brew >/dev/null 2>&1 && brew update

echo ok. run brew upgrade...

brew upgrade

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
  lua
  vim
  mysql
  circleci
  imagemagick
  --HEAD universal-ctags/universal-ctags/universal-ctags
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
  gyazo
  google-chrome
  google-japanese-ime
  slack
  iterm2
  clipy
  kindle
  adobe-acrobat-reader
  visual-studio-code
  docker
  sequel-pro
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

cat << END

**************************************************
Everything is ready. Enjoy your new Mac!
**************************************************

END
