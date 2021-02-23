#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VSCODE_SETTING_DIR=~/Library/Application\ Support/Code/User

ln -sf "${SCRIPT_DIR}/settings.json" "${VSCODE_SETTING_DIR}/settings.json"

ln -sf "${SCRIPT_DIR}/keybindings.json" "${VSCODE_SETTING_DIR}/keybindings.json"

cat < ./extensions | while read -r line
do
  code --install-extension "$line"
done
code --list-extensions > extensions
