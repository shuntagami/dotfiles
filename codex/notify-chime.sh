#!/bin/bash
# Codex CLI notify wrapper: play a terminal chime, then forward to the
# original notify target unchanged so existing integrations keep working.
ORIGINAL_NOTIFY="/Users/shun.tagami/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
CHIME_SOUND="/Users/shun.tagami/dotfiles/static/dog-bark.wav"

afplay "$CHIME_SOUND" >/dev/null 2>&1 &

if [ -x "$ORIGINAL_NOTIFY" ]; then
  exec "$ORIGINAL_NOTIFY" "$@"
fi
