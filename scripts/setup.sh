#!/bin/bash

set -eu

DOTFILES="${HOME}/dotfiles"

echo "Starting dotfiles setup..."

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
if [[ "$(uname)" == "Darwin" ]]; then
  echo "==> Configuring macOS defaults..."
  bash "${DOTFILES}/scripts/macos.sh"

  echo "==> Setting up VSCode/Cursor..."
  DOTFILES_AUTO=1 bash "${DOTFILES}/vscode/setup.sh"
fi

echo "Setup complete! Run 'exec \$SHELL -l' to reload your shell."
