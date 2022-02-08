#!/bin/bash

set -eux

if has "nodenv"; then
  # nodenv-default-packages
  [ ! -d "$(nodenv root)"/plugins/nodenv-default-packages ] && git clone -q https://github.com/nodenv/nodenv-default-packages.git "$(nodenv root)"/plugins/nodenv-default-packages
  [ ! -e "$(nodenv root)"/default-packages ] && cp "${DOTFILES}"/misc/default-packages "$(nodenv root)"/default-packages
  # install latest version of Node.js
  # latest=$(nodenv install --list | grep -v - | grep -v rc | grep -v nightly | tail -n 1)
  nodenv install 14.15.5
  nodenv global 14.15.5
fi

if has "rbenv"; then
  # rbenv-default-gems
  [ ! -d "$(rbenv root)"/plugins/rbenv-default-gems ] && git clone -q https://github.com/rbenv/rbenv-default-gems.git "$(rbenv root)"/plugins/rbenv-default-gems
  [ ! -e "$(rbenv root)"/default-gems ] && cp "${DOTFILES}"/misc/default-gems "$(rbenv root)"/default-gems
fi

if has "rbenv"; then
  # install latest version of ruby
  latest=$(rbenv install --list | grep -v - | tail -n 1)
  current=$(rbenv versions | tail -n 1 | cut -d' ' -f 2)
  if [ "${current}" != "${latest}" ]; then
    rbenv install "${latest}"
    rbenv global "${latest}"
    rbenv rehash
  fi
fi
