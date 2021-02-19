#!/bin/bash

set -e
DOT_DIRECTORY="${HOME}/dotfiles"

has() {
  type "$1" > /dev/null 2>&1
}

# anyenv updateコマンドをインストール
# [ ! -d "$(anyenv root)"/plugins/anyenv-update ] && git clone https://github.com/znz/anyenv-update.git "$(anyenv root)"/plugins/anyenv-update
# anyenv init
# anyenv install tfenv
# anyenv install nodenv
# anyenv install rbenv
# exec $SHELL -l

if has "nodenv"; then
  # nodenv-default-packagesの導入
  [ ! -d "$(nodenv root)"/plugins/nodenv-default-packages ] && git clone -q https://github.com/nodenv/nodenv-default-packages.git "$(nodenv root)"/plugins/nodenv-default-packages
  [ ! -e "$(nodenv root)"/default-packages ] && cp "${DOT_DIRECTORY}"/default-packages "$(nodenv root)"/default-packages
  # 最新のnodeを入れる
  latest=$(nodenv install --list | grep -v - | grep -v rc | grep -v nightly | tail -n 1)
  nodenv install "${latest}"
  nodenv global "${latest}"
fi

if has "rbenv"; then
  [ ! -d "$(rbenv root)"/plugins/rbenv-default-gems ] && git clone -q https://github.com/rbenv/rbenv-default-gems.git "$(rbenv root)"/plugins/rbenv-default-gems
  [ ! -e "$(rbenv root)"/default-gems ] && cp "${DOT_DIRECTORY}"/default-gems "$(rbenv root)"/default-gems
fi

if has "rbenv"; then
  # 最新のRubyを入れる
  latest=$(rbenv install --list | grep -v - | tail -n 1)
  current=$(rbenv versions | tail -n 1 | cut -d' ' -f 2)
  if [ "${current}" != "${latest}" ]; then
    rbenv install "${latest}"
    rbenv global "${latest}"
  fi
fi
