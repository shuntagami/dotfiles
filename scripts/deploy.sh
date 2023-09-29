#!/bin/zsh

set -eux

if [ ! -d ${HOME}/.zprezto ]; then
  git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
fi

# prezto
setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
  ln -sf "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done

# add and update submodule
cd ${HOME}/.zprezto && git pull && git submodule sync --recursive && git submodule update --init --recursive

# symlink dotfiles
ln -sf ~/dotfiles/.dein.toml ~/.dein.toml
ln -sf ~/dotfiles/.editorconfig ~/.editorconfig
ln -sf ~/dotfiles/.gemrc ~/.gemrc
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.gitignore_global ~/.gitignore_global
ln -sf ~/dotfiles/.golangci.yml ~/.golangci.yml
ln -sf ~/dotfiles/.my.cnf ~/.my.cnf
ln -sf ~/dotfiles/.npmrc ~/.npmrc
ln -sf ~/dotfiles/.ocamlinit ~/.ocamlinit
ln -sf ~/dotfiles/.vimrc ~/.vimrc
ln -sf ~/dotfiles/.zpreztorc ~/.zpreztorc
ln -sf ~/dotfiles/.zshenv ~/.zshenv
ln -sf ~/dotfiles/.zshrc ~/.zshrc

if [[ "$OSTYPE" == "darwin"* ]]; then
  if ! grep -sq "require('keyboard')" ~/.hammerspoon/init.lua; then
    ln -sf ~/dotfiles/hammerspoon ~/.hammerspoon
  fi

  # The location of the configuration file for kareabiner-elements
  # https://karabiner-elements.pqrs.org/docs/manual/misc/configuration-file-path/
  ln -s ~/dotfiles/karabiner ~/.config
  launchctl kickstart -k gui/`id -u`/org.pqrs.karabiner.karabiner_console_user_server
fi

# change shell
chsh -s $(which zsh)

exec ${SHELL} -l
