#!/bin/zsh

set -eux

if [ ! -d ${HOME}/.zprezto ]; then
  git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
fi

# prezto
setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^(README.md|zpreztorc|zshenv|zshrc)(.N); do
  ln -sf "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done

# add and update submodule
git -C ${HOME}/.zprezto pull && git -C ${HOME}/.zprezto submodule sync --recursive && git -C ${HOME}/.zprezto submodule update --init --recursive

# symlink dotfiles
ln -sf ~/dotfiles/.dein.toml ~/.dein.toml
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.gitignore_global ~/.gitignore_global
ln -sf ~/dotfiles/.vimrc ~/.vimrc
ln -sf ~/dotfiles/.zpreztorc ~/.zpreztorc
ln -sf ~/dotfiles/.zshenv ~/.zshenv
ln -sf ~/dotfiles/.zshrc ~/.zshrc
mkdir -p ~/.docker
ln -sf ~/dotfiles/misc/docker-config.json ~/.docker/config.json

# ssh config
if [ ! -d ${HOME}/.ssh ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/config && chmod 600 ~/.ssh/config
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  ln -sfn ~/dotfiles/hammerspoon ~/.hammerspoon
  mkdir -p ~/Library/Application\ Support/Claude
  ln -sf ~/dotfiles/misc/claude_desktop_config.json ~/Library/Application\ Support/Claude/claude_desktop_config.json
  mkdir -p ~/.config/memo
  ln -sf ~/dotfiles/misc/memo-config.toml ~/.config/memo/config.toml

  # The location of the configuration file for karabiner-elements
  # https://karabiner-elements.pqrs.org/docs/manual/misc/configuration-file-path/
  ln -sfn ~/dotfiles/karabiner ~/.config/karabiner
  launchctl kickstart -k gui/`id -u`/org.pqrs.karabiner.karabiner_console_user_server
fi

# change shell
sudo chsh -s $(which zsh) $USER

echo "Deploy complete! Run 'exec \$SHELL -l' to reload your shell."
