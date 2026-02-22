#!/bin/bash

set -eux

DOTFILES=$HOME/dotfiles

# 環境判定関数
is_darwin() {
  [[ $(uname) == "Darwin" ]]
}

is_wsl() {
  [[ $(uname) == "Linux" ]] && [[ -n "${WSL_DISTRO_NAME}" ]]
}

is_linux() {
  [[ $(uname) == "Linux" ]] && [[ -z "${WSL_DISTRO_NAME}" ]]
}

# 設定ディレクトリの取得
get_setting_dirs() {
  if is_darwin; then
    VSCODE_SETTING_DIR="$HOME/Library/Application Support/Code/User"
    CURSOR_SETTING_DIR="$HOME/Library/Application Support/Cursor/User"
  elif is_wsl; then
    VSCODE_SETTING_DIR="/mnt/c/Users/shunt/AppData/Roaming/Code/User"
    CURSOR_SETTING_DIR="/mnt/c/Users/shunt/AppData/Roaming/Cursor/User"
  else
    VSCODE_SETTING_DIR="$HOME/.config/Code/User"
    CURSOR_SETTING_DIR="$HOME/.config/Cursor/User"
  fi
}

# 確認プロンプト関数
confirm_replace() {
  local file_path=$1
  # Auto-approve when called from setup.sh
  if [[ "${DOTFILES_AUTO:-}" == "1" ]]; then
    return 0
  fi
  echo "Warning: ${file_path} already exists and is not a symlink."
  read -p "Do you want to replace it with a symlink? (y/N): " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

# シンボリックリンク作成関数（既存ファイルがある場合は確認）
create_symlink_safe() {
  local target=$1
  local link_path=$2

  if [[ -e "$link_path" ]] && [[ ! -L "$link_path" ]]; then
    if confirm_replace "$link_path"; then
      rm "$link_path"
      ln -sf "$target" "$link_path"
    else
      echo "Skipping symlink creation for ${link_path}."
      return 1
    fi
  else
    ln -sf "$target" "$link_path"
  fi
}

# 設定ファイルのコピー（WSL環境用）
copy_config_files() {
  local target_dir=$1
  shift
  local files=("$@")

  for file in "${files[@]}"; do
    cp -R "${DOTFILES}/vscode/${file}" "${target_dir}/"
  done
}

# 設定ファイルのシンボリックリンク作成
create_config_symlinks() {
  local vscode_dir=$1
  local cursor_dir=$2
  shift 2
  local files=("$@")

  for editor_dir in "$vscode_dir" "$cursor_dir"; do
    for file in "${files[@]}"; do
      ln -sf "${DOTFILES}/vscode/${file}" "${editor_dir}/"
    done
  done
}

# メイン処理
main() {
  # 設定ディレクトリの取得
  get_setting_dirs

  # 設定ファイルのリスト
  local config_files=(
    "settings.json"
    "keybindings.json"
    "tsconfig.json"
  )

  # WSL環境での処理
  if is_wsl; then
    copy_config_files "$VSCODE_SETTING_DIR" "${config_files[@]}"
  else
    # その他の環境での処理
    create_config_symlinks "$VSCODE_SETTING_DIR" "$CURSOR_SETTING_DIR" "${config_files[@]}"

    # Cursor の mcp.json のシンボリックリンク作成（macOS/Linux環境のみ）
    if is_darwin || is_linux; then
      local cursor_mcp_dir="$HOME/.cursor"
      local cursor_mcp_file="${cursor_mcp_dir}/mcp.json"

      mkdir -p "$cursor_mcp_dir"
      create_symlink_safe "${DOTFILES}/vscode/mcp.json" "$cursor_mcp_file"
    fi
  fi
}

main
