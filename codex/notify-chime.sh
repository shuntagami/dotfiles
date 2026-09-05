#!/bin/bash
# Codex CLI notify wrapper: verify completion before playing, then forward to the
# original notify target unchanged so existing integrations keep working.
ORIGINAL_NOTIFY="/Users/shun.tagami/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
python3 "$SCRIPT_DIR/../scripts/agent-notify.py" codex "$@" >/dev/null 2>&1 &

if [ -x "$ORIGINAL_NOTIFY" ]; then
  exec "$ORIGINAL_NOTIFY" "$@"
fi
