#!/bin/bash
# Codex CLI notify wrapper: forward to the original notify target unchanged
# so existing integrations keep working. Chime playback disabled.
ORIGINAL_NOTIFY="/Users/shun.tagami/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"

if [ -x "$ORIGINAL_NOTIFY" ]; then
  exec "$ORIGINAL_NOTIFY" "$@"
fi
