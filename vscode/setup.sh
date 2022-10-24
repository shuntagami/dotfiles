#!/bin/bash

set -eux

[[ `uname` == "Darwin" ]] && VSCODE_SETTING_DIR=$HOME/Library/Application\ Support/Code/User
[[ `uname` == "Linux" ]] && VSCODE_SETTING_DIR=$HOME/.config/Code/User

ln -sf "${DOTFILES}"/vscode/settings.json "${VSCODE_SETTING_DIR}"/settings.json
ln -sf "${DOTFILES}"/vscode/keybindings.json "${VSCODE_SETTING_DIR}"/keybindings.json
ln -sf "${DOTFILES}"/vscode/tsconfig.json "${VSCODE_SETTING_DIR}"/tsconfig.json
ln -sf "${DOTFILES}"/vscode/snippets "${VSCODE_SETTING_DIR}"/snippets

cat < $DOTFILES/vscode/extensions | while read -r line
do
  code --install-extension "$line" --force
done

cp /dev/null $DOTFILES/vscode/extensions
code --list-extensions > $DOTFILES/vscode/extensions
