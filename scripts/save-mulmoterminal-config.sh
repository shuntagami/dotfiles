#!/bin/bash

set -eu

# The reverse of install-mulmoterminal-config.sh: bring the live config (as edited via
# MulmoTerminal's Settings UI, its skills, or the /api/config route) back into dotfiles so it
# can be committed. The machine's own keys stay as dotfiles has them, so saving from the MacBook
# and from the Mac mini does not swap one machine's recent directories for the other's.
# Review with `git diff` before committing: prRepos and repoDirs name private repositories.

exec python3 "${HOME}/dotfiles/scripts/sync-mulmoterminal-config.py" save "$@"
