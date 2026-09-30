#!/bin/bash

set -eu

# dotfiles -> ~/.mulmoterminal/config.json. A MERGE, not a copy: a missing config is seeded whole,
# and on a configured machine only the shared keys that differ are set — through the running
# server when there is one. The machine's own keys (recent directories, the work log switch,
# accounts) are left alone. See sync-mulmoterminal-config.py; pass --dry-run to see the changes first.

exec python3 "${HOME}/dotfiles/scripts/sync-mulmoterminal-config.py" apply "$@"
