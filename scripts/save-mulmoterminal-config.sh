#!/bin/bash

set -eux

# The reverse of install-mulmoterminal-config.sh: pull the live config (as edited via
# MulmoTerminal's Settings UI, its skills, or the /api/config route) back into dotfiles so it
# can be committed. Run this after changing settings you want to keep, then `git add -p` and
# review before committing — cwdPresets/launchers/repoDirs carry this machine's local paths and
# project names, worth a look before they land in a public repo.

DOTFILES="${HOME}/dotfiles"
SRC="${HOME}/.mulmoterminal/config.json"
DEST="${DOTFILES}/mulmoterminal/config.json"

cp "${SRC}" "${DEST}"

echo "Saved ${SRC} -> ${DEST}"
