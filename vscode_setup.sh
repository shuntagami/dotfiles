#!/bin/bash

set -e
DOT_DIRECTORY="${HOME}/dotfiles"
VSCODE_SETTING_DIR=~/Library/Application\ Support/Code/User

ln -sf "${DOT_DIRECTORY}"/settings.json "${VSCODE_SETTING_DIR}"/settings.json
ln -sf "${DOT_DIRECTORY}"/keybindings.json "${VSCODE_SETTING_DIR}"/keybindings.json

cat < ./extensions | while read -r line
do
  code --install-extension "$line"
done
code --list-extensions > extensions
