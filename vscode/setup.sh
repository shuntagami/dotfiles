#!/bin/bash

set -eux

DOTFILES=$HOME/dotfiles

# 設定ディレクトリの定義
if [[ `uname` == "Darwin" ]]; then
  VSCODE_SETTING_DIR=$HOME/Library/Application\ Support/Code/User
  CURSOR_SETTING_DIR=$HOME/Library/Application\ Support/Cursor/User
elif [[ `uname` == "Linux" ]] && [[ -n "${WSL_DISTRO_NAME}" ]]; then
  VSCODE_SETTING_DIR=/mnt/c/Users/shunt/AppData/Roaming/Code/User
  CURSOR_SETTING_DIR=/mnt/c/Users/shunt/AppData/Roaming/Cursor/User
else
  VSCODE_SETTING_DIR=$HOME/.config/Code/User
  CURSOR_SETTING_DIR=$HOME/.config/Cursor/User
fi

# 設定ファイルのリスト
CONFIG_FILES=(
  "settings.json"
  "keybindings.json"
  "tsconfig.json"
)

# WSL環境での処理
if [[ `uname` == "Linux" ]] && [[ -n "${WSL_DISTRO_NAME}" ]]; then
  # 設定ファイルのコピー
  for file in "${CONFIG_FILES[@]}"; do
    cp -R "${DOTFILES}/vscode/${file}" "${VSCODE_SETTING_DIR}/"
  done

  # 拡張機能のインストール
  for line in $(cat "$DOTFILES/vscode/extensions"); do
    code --install-extension "$line" --force
  done
  cp /dev/null $DOTFILES/vscode/extensions
  code --list-extensions > $DOTFILES/vscode/extensions

# その他の環境での処理
else
  # VSCode と Cursor の両方に対して設定ファイルのシンボリックリンクを作成
  for editor_dir in "$VSCODE_SETTING_DIR" "$CURSOR_SETTING_DIR"; do
    for file in "${CONFIG_FILES[@]}"; do
      ln -sf "${DOTFILES}/vscode/${file}" "${editor_dir}/"
    done
  done
fi
