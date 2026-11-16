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

# Ask once, refresh the normal sudo cache, and stop the keeper even on failure.
source "${DOTFILES}/scripts/sudo-session.sh"
trap dotfiles_stop_sudo_session EXIT
dotfiles_start_sudo_session

# Phase 1: Install packages
echo "==> Installing packages..."
bash "${DOTFILES}/scripts/install-packages.sh"

# Phase 2: Deploy dotfiles and app settings (including BetterDisplay on macOS)
echo "==> Deploying dotfiles..."
zsh "${DOTFILES}/scripts/deploy.sh"

# Phase 3: first-run administrator settings (macOS only)
if [[ "$(uname)" == "Darwin" ]]; then
  echo "==> Configuring sudo Touch ID..."
  bash "${DOTFILES}/scripts/sudo-touch-id.sh"
fi

# System and editor settings are applied by deploy.sh above. App restarts and
# maintenance are explicit commands; see docs/macos-settings.md.

echo "Setup complete! Run 'exec \$SHELL -l' to reload your shell."
