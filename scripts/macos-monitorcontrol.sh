#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping MonitorControl settings (not running on macOS)."
  exit 0
fi
if [[ ! -d "/Applications/MonitorControl.app" ]]; then
  echo "Skipping MonitorControl settings (MonitorControl is not installed)."
  exit 0
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SUPPORT_DIR="${HOME}/Library/Application Support/dotfiles"
readonly LABEL="local.dotfiles.monitorcontrol-mode"
readonly PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
readonly DOMAIN="app.monitorcontrol.MonitorControl"
readonly BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

# Compile and validate before replacing the running helper.
swiftc -O -F /System/Library/PrivateFrameworks \
  -framework DisplayServices -framework CoreDisplay \
  "${SCRIPT_DIR}/monitorcontrol-mode.swift" -o "${BUILD_DIR}/monitorcontrol-mode"
"${BUILD_DIR}/monitorcontrol-mode" --self-test

mkdir -p "${SUPPORT_DIR}" "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs/dotfiles"
if [[ ! -f "${SUPPORT_DIR}/monitorcontrol-before.plist" ]]; then
  defaults export "${DOMAIN}" "${SUPPORT_DIR}/monitorcontrol-before.plist"
fi
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
install -m 755 "${BUILD_DIR}/monitorcontrol-mode" "${SUPPORT_DIR}/monitorcontrol-mode"

# Keep the existing custom volume shortcuts. Brightness is managed dynamically.
if pgrep -x MonitorControl >/dev/null; then
  osascript -e 'tell application "MonitorControl" to quit'
  for _ in {1..40}; do
    if ! pgrep -x MonitorControl >/dev/null; then break; fi
    sleep 0.1
  done
  if pgrep -x MonitorControl >/dev/null; then
    echo "MonitorControl did not quit; settings were not overwritten." >&2
    exit 1
  fi
fi
defaults write "${DOMAIN}" keyboardVolume -int 1
defaults write "${DOMAIN}" multiKeyboardVolume -int 1
defaults write "${DOMAIN}" KeyboardShortcuts_volumeUp -string '{"carbonKeyCode":126,"carbonModifiers":2304}'
defaults write "${DOMAIN}" KeyboardShortcuts_volumeDown -string '{"carbonKeyCode":125,"carbonModifiers":2304}'
defaults write "${DOMAIN}" KeyboardShortcuts_mute -string '{"carbonKeyCode":46,"carbonModifiers":2304}'

python3 - "${PLIST}" "${LABEL}" "${SUPPORT_DIR}" "${HOME}/Library/Logs/dotfiles" <<'PY'
import plistlib
import sys
from pathlib import Path

plist, label, support, logs = sys.argv[1:]
with open(plist, "wb") as file:
    plistlib.dump({
        "Label": label,
        "ProgramArguments": [str(Path(support) / "monitorcontrol-mode"), "--watch"],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
        "LimitLoadToSessionType": "Aqua",
        "StandardOutPath": str(Path(logs) / "monitorcontrol-mode.log"),
        "StandardErrorPath": str(Path(logs) / "monitorcontrol-mode.error.log"),
    }, file)
PY
plutil -lint "${PLIST}"
launchctl bootstrap "gui/$(id -u)" "${PLIST}"
echo "Installed automatic MonitorControl policy: mirrored = external only; extended = synchronized."
