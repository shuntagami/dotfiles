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

readonly MONITORCONTROL_DOMAIN="app.monitorcontrol.MonitorControl"
readonly BUILTIN_DISPLAY_BRIGHTNESS="0.15"

monitorcontrol_was_running=false
if pgrep -x MonitorControl >/dev/null 2>&1; then
  monitorcontrol_was_running=true
  osascript -e 'tell application "MonitorControl" to quit' || true

  for _ in {1..20}; do
    if ! pgrep -x MonitorControl >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

# Keep external-display brightness independent from the built-in display,
# ambient-light changes, Control Center, and System Settings.
defaults write "${MONITORCONTROL_DOMAIN}" enableBrightnessSync -bool false

# Let macOS own the standard brightness keys. They will adjust only the
# built-in display; external brightness remains available from MonitorControl.
defaults write "${MONITORCONTROL_DOMAIN}" keyboardBrightness -int 3
defaults write "${MONITORCONTROL_DOMAIN}" multiKeyboardBrightness -int 0

# Use custom volume shortcuts to avoid conflicts with macOS media keys.
defaults write "${MONITORCONTROL_DOMAIN}" keyboardVolume -int 1
# Apply volume changes to all displays instead of pointer-position targeting.
defaults write "${MONITORCONTROL_DOMAIN}" multiKeyboardVolume -int 1

# Volume Up: Cmd+Option+Up
defaults write "${MONITORCONTROL_DOMAIN}" KeyboardShortcuts_volumeUp -string '{"carbonKeyCode":126,"carbonModifiers":2304}'
# Volume Down: Cmd+Option+Down
defaults write "${MONITORCONTROL_DOMAIN}" KeyboardShortcuts_volumeDown -string '{"carbonKeyCode":125,"carbonModifiers":2304}'
# Mute: Cmd+Option+M
defaults write "${MONITORCONTROL_DOMAIN}" KeyboardShortcuts_mute -string '{"carbonKeyCode":46,"carbonModifiers":2304}'

if [[ "${monitorcontrol_was_running}" == "true" ]]; then
  open -a MonitorControl
fi

# DisplayServices changes the physical backlight of the built-in panel only.
# This avoids altering the mirrored framebuffer or the external monitor's DDC
# brightness. It is a private macOS framework, so keep this best-effort.
if ! swift -F /System/Library/PrivateFrameworks -framework DisplayServices -e "
import CoreGraphics
import Darwin

@_silgen_name(\"DisplayServicesSetBrightness\")
func setBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

var displayCount: UInt32 = 0
guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success else {
  exit(1)
}

var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
  exit(1)
}

for display in displays where CGDisplayIsBuiltin(display) != 0 {
  guard setBrightness(display, ${BUILTIN_DISPLAY_BRIGHTNESS}) == 0 else {
    exit(1)
  }
}
"; then
  echo "Could not set the built-in display brightness; MonitorControl independence is still configured."
fi

echo "Configured MonitorControl: external brightness is independent; built-in display target is 15%."
