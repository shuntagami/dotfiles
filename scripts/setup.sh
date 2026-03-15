#!/bin/bash

set -euo pipefail

DOTFILES="${HOME}/dotfiles"

echo "Starting dotfiles setup..."

# Profile selection: "full" (default) or "minimal" (non-engineer)
# Can be set via environment variable: DOTFILES_PROFILE=minimal ./setup.sh
# The choice is saved to ~/.dotfiles-profile so individual scripts can read it.
PROFILE_FILE="${HOME}/.dotfiles-profile"

if [[ -z "${DOTFILES_PROFILE:-}" ]]; then
  echo ""
  echo "Select a profile:"
  echo "  1) full    - All settings (default)"
  echo "  2) minimal - Without Vim extension, Karabiner, Hammerspoon"
  echo ""
  read -p "Enter choice [1]: " profile_choice
  case "${profile_choice}" in
    2|minimal) export DOTFILES_PROFILE="minimal" ;;
    *)         export DOTFILES_PROFILE="full" ;;
  esac
fi

echo "${DOTFILES_PROFILE}" > "${PROFILE_FILE}"
echo "==> Using profile: ${DOTFILES_PROFILE} (saved to ${PROFILE_FILE})"

# Ask for the administrator password upfront (once)
sudo -v
# Keep-alive: update existing sudo time stamp until setup has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Phase 1: Install packages
echo "==> Installing packages..."
bash "${DOTFILES}/scripts/install-packages.sh"

# Phase 2: Deploy dotfiles (symlinks)
echo "==> Deploying dotfiles..."
zsh "${DOTFILES}/scripts/deploy.sh"

# Phase 3: macOS / editor settings (macOS only)
# if [[ "$(uname)" == "Darwin" ]]; then
  # echo "==> Configuring macOS defaults..."
  # bash "${DOTFILES}/scripts/macos.sh"

  # echo "==> Setting up VSCode/Cursor..."
  # DOTFILES_AUTO=1 bash "${DOTFILES}/vscode/setup.sh"
# fi

echo "Setup complete! Run 'exec \$SHELL -l' to reload your shell."
