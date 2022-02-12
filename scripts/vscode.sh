#!/bin/bash

set -eux

[[ `uname` == "Darwin" ]] && VSCODE_SETTING_DIR=$HOME/Library/Application\ Support/Code/User
[[ `uname` == "Linux" ]] && VSCODE_SETTING_DIR=$HOME/.config/Code/User

ln -sf "${DOTFILES}"/misc/settings.json "${VSCODE_SETTING_DIR}"/settings.json
ln -sf "${DOTFILES}"/misc/keybindings.json "${VSCODE_SETTING_DIR}"/keybindings.json
ln -sf "${DOTFILES}"/misc/tsconfig.json "${VSCODE_SETTING_DIR}"/tsconfig.json

cat < $DOTFILES/misc/extensions | while read -r line
do
  code --install-extension "$line"
done

cp /dev/null $DOTFILES/misc/extensions
code --list-extensions > $DOTFILES/misc/extensions
