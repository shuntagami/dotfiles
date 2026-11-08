#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping BetterDisplay settings (not running on macOS)."
  exit 0
fi
if [[ ! -d "/Applications/BetterDisplay.app" ]]; then
  echo "Skipping BetterDisplay settings (BetterDisplay is not installed)."
  exit 0
fi

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SUPPORT_DIR="${HOME}/Library/Application Support/dotfiles"
readonly LABEL="local.dotfiles.betterdisplay-mode"
readonly PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
readonly DOMAIN="pro.betterdisplay.BetterDisplay"
# The MonitorControl setup this replaces. Its agent and app are stopped so
# the brightness and volume keys have a single owner.
readonly OLD_LABEL="local.dotfiles.monitorcontrol-mode"
readonly OLD_STATE="local.dotfiles.monitorcontrol-mode"
readonly NEW_STATE="local.dotfiles.betterdisplay-mode"
readonly BUILD_DIR="$(mktemp -d)"
betterdisplay_stop_requested=false

# Preserve the failing command's status and restore the app if setup stopped it.
cleanup() {
  local result=$?
  trap - EXIT
  rm -rf "${BUILD_DIR}" || true
  if [[ "${result}" -ne 0 && "${betterdisplay_stop_requested}" == true ]]; then
    open -g -a BetterDisplay || true
  fi
  exit "${result}"
}
trap cleanup EXIT

# Compile and validate before replacing the running helper.
swiftc -O -F /System/Library/PrivateFrameworks \
  -framework DisplayServices -framework CoreDisplay \
  "${SCRIPT_DIR}/betterdisplay-mode.swift" -o "${BUILD_DIR}/betterdisplay-mode"
"${BUILD_DIR}/betterdisplay-mode" --self-test

mkdir -p "${SUPPORT_DIR}" "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs/dotfiles"
if [[ ! -f "${SUPPORT_DIR}/betterdisplay-before.plist" ]]; then
  # Only a confirmed missing domain can skip the backup. Other read/export
  # errors must stop setup before the existing app or agent is touched.
  if defaults read "${DOMAIN}" >/dev/null 2>"${BUILD_DIR}/domain-error"; then
    defaults export "${DOMAIN}" "${BUILD_DIR}/betterdisplay-before.plist"
    mv "${BUILD_DIR}/betterdisplay-before.plist" "${SUPPORT_DIR}/betterdisplay-before.plist"
  else
    read_result=$?
    if [[ "$(<"${BUILD_DIR}/domain-error")" == *"Domain ${DOMAIN} does not exist"* ||
          "$(<"${BUILD_DIR}/domain-error")" == *"Domain '${DOMAIN}' not found."* ]]; then
      echo "BetterDisplay has no saved preferences yet; skipping backup."
    else
      cat "${BUILD_DIR}/domain-error" >&2
      exit "${read_result}"
    fi
  fi
fi

# Retire the MonitorControl helper. A laptop panel it blanked stays recorded in
# the new state, so the new helper still restores its brightness later.
launchctl bootout "gui/$(id -u)/${OLD_LABEL}" 2>/dev/null || true
rm -f "${HOME}/Library/LaunchAgents/${OLD_LABEL}.plist" "${SUPPORT_DIR}/monitorcontrol-mode"
for key in builtInBlanked builtInBrightness mode; do
  if ! defaults read "${NEW_STATE}" "${key}" >/dev/null 2>&1 &&
     value="$(defaults read "${OLD_STATE}" "${key}" 2>/dev/null)"; then
    case "${key}" in
      builtInBlanked) defaults write "${NEW_STATE}" "${key}" -bool "${value}" ;;
      builtInBrightness) defaults write "${NEW_STATE}" "${key}" -float "${value}" ;;
      *) defaults write "${NEW_STATE}" "${key}" -string "${value}" ;;
    esac
  fi
done
if pgrep -x MonitorControl >/dev/null; then
  osascript -e 'tell application "MonitorControl" to quit' || true
fi

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
install -m 755 "${BUILD_DIR}/betterdisplay-mode" "${SUPPORT_DIR}/betterdisplay-mode"

# Brightness keys adjust every display with brightness control; the helper
# keeps a mirrored laptop panel out of that set. Volume keys drive a monitor
# over DDC only while it is the default output; otherwise they go to macOS.
readonly VIDEO_KEYS="all"
readonly AUDIO_KEYS="displayWithAudioDeviceNameMatch"
keyboard_settings_current() {
  [[ "$(defaults read "${DOMAIN}" videoKeyboardControl 2>/dev/null)" == "${VIDEO_KEYS}" &&
     "$(defaults read "${DOMAIN}" audioKeyboardControl 2>/dev/null)" == "${AUDIO_KEYS}" ]]
}

# BetterDisplay reads these settings only at launch. Restart it only when they
# change, because quitting it also drops virtual screens and their mirroring.
if keyboard_settings_current; then
  echo "BetterDisplay keyboard settings are already current; not restarting it."
else
  if pgrep -x BetterDisplay >/dev/null; then
    betterdisplay_stop_requested=true
    osascript -e 'tell application "BetterDisplay" to quit'
    for _ in {1..40}; do
      if ! pgrep -x BetterDisplay >/dev/null; then break; fi
      sleep 0.1
    done
    if pgrep -x BetterDisplay >/dev/null; then
      echo "BetterDisplay did not quit; settings were not overwritten." >&2
      exit 1
    fi
  fi
  defaults write "${DOMAIN}" videoKeyboardControl -string "${VIDEO_KEYS}"
  defaults write "${DOMAIN}" audioKeyboardControl -string "${AUDIO_KEYS}"
fi

python3 - "${PLIST}" "${LABEL}" "${SUPPORT_DIR}" "${HOME}/Library/Logs/dotfiles" <<'PY'
import plistlib
import sys
from pathlib import Path

plist, label, support, logs = sys.argv[1:]
with open(plist, "wb") as file:
    plistlib.dump({
        "Label": label,
        "ProgramArguments": [str(Path(support) / "betterdisplay-mode"), "--watch"],
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
        "LimitLoadToSessionType": "Aqua",
        "StandardOutPath": str(Path(logs) / "betterdisplay-mode.log"),
        "StandardErrorPath": str(Path(logs) / "betterdisplay-mode.error.log"),
    }, file)
PY
plutil -lint "${PLIST}"
launchctl bootstrap "gui/$(id -u)" "${PLIST}"
echo "Installed automatic BetterDisplay policy: mirrored = external only; extended = all displays."
