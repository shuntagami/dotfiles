#!/bin/bash
# Compatibility entry point; deploy.sh applies these settings on every run.
set -euo pipefail
DOTFILES="${HOME}/dotfiles"
exec python3 "${DOTFILES}/scripts/install-user-configs.py" editors
