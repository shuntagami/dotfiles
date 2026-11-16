#!/usr/bin/env bash
# Compatibility entry point. Persistent settings are also applied by deploy.sh.
# Restarts and maintenance now have explicit commands; see docs/macos-settings.md.
set -euo pipefail
exec zsh "${HOME}/dotfiles/scripts/deploy-macos.sh" "$@"
