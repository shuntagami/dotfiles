#!/bin/bash

set -eux

# ~/.mulmoterminal/config.json cannot be symlinked like the rest of deploy.sh: MulmoTerminal
# writes it with write-temp-then-rename, and rename() replaces a symlink at that path with a
# real file instead of writing through it. So this is a ONE-WAY copy, not a live link — running
# it overwrites ~/.mulmoterminal/config.json with whatever is committed here, discarding any
# local edits made since the last time they were copied back with save-mulmoterminal-config.sh.

DOTFILES="${HOME}/dotfiles"
SRC="${DOTFILES}/mulmoterminal/config.json"
DEST="${HOME}/.mulmoterminal/config.json"

mkdir -p "${HOME}/.mulmoterminal"
cp "${SRC}" "${DEST}"

echo "Installed ${SRC} -> ${DEST}"
