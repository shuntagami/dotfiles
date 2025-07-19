#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

# Install prezto if not already installed
PREZTO_DIR="${ZDOTDIR:-$HOME}/.zprezto"
if [[ ! -d "$PREZTO_DIR" ]]; then
  log_info "Installing prezto..."
  retry 3 git clone --recursive https://github.com/sorin-ionescu/prezto.git "$PREZTO_DIR" || die "Failed to install prezto"
  log_success "Prezto installed successfully"
fi

# Link prezto configuration files
log_info "Linking prezto configuration files..."
if command -v zsh >/dev/null 2>&1; then
  zsh -c '
    setopt EXTENDED_GLOB
    for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
      ln -sf "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
    done
  '
else
  # Fallback for systems without zsh
  for rcfile in "$PREZTO_DIR"/runcoms/*; do
    [[ "$(basename "$rcfile")" != "README.md" ]] && safe_symlink "$rcfile" "${ZDOTDIR:-$HOME}/.$(basename "$rcfile")"
  done
fi

# Update prezto and submodules
log_info "Updating prezto and submodules..."
(
  cd "$PREZTO_DIR" || die "Failed to change to prezto directory"
  retry 3 git pull || log_warning "Failed to update prezto (continuing anyway)"
  git submodule sync --recursive
  git submodule update --init --recursive
) && log_success "Prezto updated successfully"

# Source dotfiles functions
source "${SCRIPT_DIR}/lib/dotfiles.sh"

# Setup configurations
setup_ssh
link_dotfiles
link_special_files
link_macos_files

# Change shell to zsh
change_shell

log_success "Dotfiles deployment completed!"
log_info "Please restart your terminal or run: exec \$SHELL -l"
