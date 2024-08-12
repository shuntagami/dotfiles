#!/bin/bash

set -eux

if [[ `uname` == "Darwin" ]]; then
  VSCODE_SETTING_DIR=$HOME/Library/Application\ Support/Code/User
elif [[ `uname` == "Linux" ]] && [[ -n "${WSL_DISTRO_NAME}" ]]; then
  VSCODE_SETTING_DIR=/mnt/c/Users/shunt/AppData/Roaming/Code/User
else
  VSCODE_SETTING_DIR=$HOME/.config/Code/User
fi

if [[ `uname` == "Linux" ]] && [[ -n "${WSL_DISTRO_NAME}" ]]; then
  cp -R "${DOTFILES}"/vscode/settings.json "${VSCODE_SETTING_DIR}"/settings.json
  cp -R "${DOTFILES}"/vscode/keybindings.json "${VSCODE_SETTING_DIR}"/keybindings.json
  cp -R "${DOTFILES}"/vscode/tsconfig.json "${VSCODE_SETTING_DIR}"/tsconfig.json
  cp -R "${DOTFILES}"/vscode/snippets "${VSCODE_SETTING_DIR}"
  for line in $(cat "$DOTFILES/vscode/extensions"); do
    code --install-extension "$line" --force
  done
else
  ln -sf "${DOTFILES}"/vscode/settings.json "${VSCODE_SETTING_DIR}"/settings.json
  ln -sf "${DOTFILES}"/vscode/keybindings.json "${VSCODE_SETTING_DIR}"/keybindings.json
  ln -sf "${DOTFILES}"/vscode/tsconfig.json "${VSCODE_SETTING_DIR}"/tsconfig.json
  ln -sf "${DOTFILES}"/vscode/snippets "${VSCODE_SETTING_DIR}"
fi
