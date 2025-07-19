#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

declare -A DOTFILE_MAPPINGS=(
  [".dein.toml"]=""
  [".editorconfig"]=""
  [".gemrc"]=""
  [".gitconfig"]=""
  [".gitignore_global"]=""
  [".golangci.yml"]=""
  [".my.cnf"]=""
  [".npmrc"]=""
  [".ocamlinit"]=""
  [".vimrc"]=""
  [".zpreztorc"]=""
  [".zshenv"]=""
  [".zshrc"]=""
)

declare -A SPECIAL_MAPPINGS=(
  ["misc/docker-config.json"]="$HOME/.docker/config.json"
)

declare -A MACOS_MAPPINGS=(
  ["hammerspoon"]="$HOME/.hammerspoon"
  ["misc/claude_desktop_config.json"]="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  ["misc/memo-config.toml"]="$HOME/.config/memo/config.toml"
  ["karabiner"]="$HOME/.config/karabiner"
)

link_dotfiles() {
  log_info "Linking dotfiles..."
  
  for file in "${!DOTFILE_MAPPINGS[@]}"; do
    local source_path="$DOTFILES_ROOT/$file"
    local target_path="$HOME/$file"
    
    if [[ -f "$source_path" ]]; then
      safe_symlink "$source_path" "$target_path"
    else
      log_warning "Source file not found: $source_path"
    fi
  done
}

link_special_files() {
  log_info "Linking special configuration files..."
  
  for source in "${!SPECIAL_MAPPINGS[@]}"; do
    local source_path="$DOTFILES_ROOT/$source"
    local target_path="${SPECIAL_MAPPINGS[$source]}"
    
    if [[ -f "$source_path" ]]; then
      safe_symlink "$source_path" "$target_path"
    else
      log_warning "Source file not found: $source_path"
    fi
  done
}

link_macos_files() {
  if ! is_macos; then
    log_debug "Skipping macOS-specific files (not on macOS)"
    return 0
  fi
  
  log_info "Linking macOS-specific configuration files..."
  
  for source in "${!MACOS_MAPPINGS[@]}"; do
    local source_path="$DOTFILES_ROOT/$source"
    local target_path="${MACOS_MAPPINGS[$source]}"
    
    if [[ -e "$source_path" ]]; then
      if [[ "$source" == "hammerspoon" ]]; then
        if ! grep -sq "require('keyboard')" "$HOME/.hammerspoon/init.lua" 2>/dev/null; then
          safe_symlink "$source_path" "$target_path"
        else
          log_info "Hammerspoon configuration already exists, skipping..."
        fi
      else
        safe_symlink "$source_path" "$target_path"
      fi
    else
      log_warning "Source not found: $source_path"
    fi
  done
  
  if [[ -d "$HOME/.config/karabiner" ]]; then
    log_info "Restarting Karabiner Elements..."
    launchctl kickstart -k "gui/$(id -u)/org.pqrs.karabiner.karabiner_console_user_server" 2>/dev/null || log_warning "Failed to restart Karabiner Elements"
  fi
}

setup_ssh() {
  log_info "Setting up SSH configuration..."
  
  local ssh_dir="$HOME/.ssh"
  local ssh_config="$ssh_dir/config"
  
  if [[ ! -d "$ssh_dir" ]]; then
    mkdir -p "$ssh_dir" || die "Failed to create SSH directory"
    chmod 700 "$ssh_dir" || die "Failed to set SSH directory permissions"
    log_success "Created SSH directory: $ssh_dir"
  fi
  
  if [[ ! -f "$ssh_config" ]]; then
    touch "$ssh_config" || die "Failed to create SSH config file"
    chmod 600 "$ssh_config" || die "Failed to set SSH config permissions"
    log_success "Created SSH config file: $ssh_config"
  fi
}

change_shell() {
  local zsh_path
  zsh_path="$(command -v zsh)" || die "zsh not found in PATH"
  
  if [[ "$SHELL" != "$zsh_path" ]]; then
    log_info "Changing default shell to zsh..."
    if confirm "Change default shell to zsh ($zsh_path)?"; then
      chsh -s "$zsh_path" || die "Failed to change shell"
      log_success "Default shell changed to zsh"
      log_info "Please restart your terminal or run: exec \$SHELL -l"
    else
      log_info "Shell change skipped by user"
    fi
  else
    log_info "Shell is already set to zsh"
  fi
}