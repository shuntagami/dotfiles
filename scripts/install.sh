#!/bin/bash

set -eux

OS="$(uname -s)"
DOTFILES="${HOME}/dotfiles"
DOT_TARBALL="https://github.com/shuntagami/dotfiles/tarball/main"
REMOTE_URL="https://github.com/shuntagami/dotfiles"

has() {
  type "$1" > /dev/null 2>&1
}

cd $HOME

# If missing, download and extract the dotfiles repository
if [ ! -d ${DOTFILES} ]; then
  echo "Downloading dotfiles..."
  mkdir ${DOTFILES}

  if has "git"; then
    git clone "${REMOTE_URL}"
  else
    curl -fsSLo ${HOME}/dotfiles.tar.gz ${DOT_TARBALL}
    tar -zxf ${HOME}/dotfiles.tar.gz --strip-components 1 -C ${DOTFILES}
    rm -f ${HOME}/dotfiles.tar.gz
  fi

  echo $(tput setaf 2)Download dotfiles complete!. ✔︎$(tput sgr0)
fi

