#!/bin/bash

set -eux

function has () {
  type "$1" > /dev/null 2>&1
}

if ! has "anyenv"; then
  git clone https://github.com/anyenv/anyenv ~/.anyenv
fi

# install anyenv update command
if ! has "anyenv update"; then
  [ ! -d "$(anyenv root)"/plugins/anyenv-update ] && git clone https://github.com/znz/anyenv-update.git "$(anyenv root)"/plugins/anyenv-update
fi

# install nodenv
if ! has "nodenv"; then
  anyenv install nodenv
fi

if ! has "node"; then
  # nodenv-default-packages
  [ ! -d "$(nodenv root)"/plugins/nodenv-default-packages ] && git clone -q https://github.com/nodenv/nodenv-default-packages.git "$(nodenv root)"/plugins/nodenv-default-packages
  [ ! -e "$(nodenv root)"/default-packages ] && cp "${DOTFILES}"/misc/default-packages "$(nodenv root)"/default-packages
  # install latest version of Node.js
  # latest=$(nodenv install --list | grep -v - | grep -v rc | grep -v nightly | tail -n 1)
  nodenv install 16.13.1
  nodenv global 16.13.1
fi

# install rbenv
if ! has "rbenv"; then
  anyenv install rbenv
fi

if ! has "ruby"; then
  # install rbenv-default-gems
  [ ! -d "$(rbenv root)"/plugins/rbenv-default-gems ] && git clone -q https://github.com/rbenv/rbenv-default-gems.git "$(rbenv root)"/plugins/rbenv-default-gems
  [ ! -e "$(rbenv root)"/default-gems ] && cp "${DOTFILES}"/misc/default-gems "$(rbenv root)"/default-gems

  # install latest version of ruby
  latest=$(rbenv install --list | grep -v - | tail -n 1)
  current=$(rbenv versions | tail -n 1 | cut -d' ' -f 2)
  if [ "${current}" != "${latest}" ]; then
    rbenv install "${latest}"
    rbenv global "${latest}"
    rbenv rehash
  fi
fi

