#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

cd "${DOTFILES_ROOT}"

case "$(check_os)" in
  "linux")
    log_info "Installing packages for Linux..."
    check_prerequisites curl wget || die "Missing required tools"
    
    source "${DOTFILES_ROOT}/scripts/apt-get" && run-apt
    source "${DOTFILES_ROOT}/scripts/anyenv" && install-anyenv
    source "${DOTFILES_ROOT}/scripts/gh" && install-gh
    source "${DOTFILES_ROOT}/scripts/btop" && install-btop
    ;;
  
  "macos")
    log_info "Installing packages for macOS..."
    
    if ! has "brew"; then
      log_info "Installing Homebrew..."
      retry 3 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Failed to install Homebrew"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    
    if has "brew"; then
      export HOMEBREW_CASK_OPTS="--no-quarantine"
      local brewfile="${DOTFILES_ROOT}/misc/Brewfile"
      [[ -f "$brewfile" ]] || die "Brewfile not found: $brewfile"
      
      log_info "Installing packages from Brewfile..."
      retry 3 brew bundle install --file="$brewfile" || die "Failed to install packages from Brewfile"
      eval "$(/opt/homebrew/bin/brew shellenv)"
      source "${DOTFILES_ROOT}/scripts/anyenv" && install-anyenv
    fi
    ;;
  
  *)
    die "Unsupported operating system: $(uname -s)"
    ;;
esac

log_success "Package installation completed!"
