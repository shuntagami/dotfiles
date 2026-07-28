#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping macOS notification settings (not running on macOS)."
  exit 0
fi

readonly NOTIFICATION_PREFS_DOMAIN="com.apple.ncprefs"
readonly SETTINGS_URL="x-apple.systempreferences:com.apple.Notifications-Settings.extension"
readonly TARGET_APPS=("Discord" "Slack")

tmp_dir="$(mktemp -d /tmp/dotfiles-macos-notifications.XXXXXX)"
trap 'rm -rf "${tmp_dir}"' EXIT

###############################################################################
# Allow notifications while mirroring or sharing the display                 #
###############################################################################

# dnd_prefs is itself a binary plist stored as data inside com.apple.ncprefs.
# Preserve every existing field and only disable the mirrored-display DND rule.
if defaults export "${NOTIFICATION_PREFS_DOMAIN}" "${tmp_dir}/ncprefs.plist" >/dev/null 2>&1; then
  if ! python3 - "${tmp_dir}/ncprefs.plist" <<'PY'
import plistlib
import subprocess
import sys

with open(sys.argv[1], "rb") as file:
    outer_preferences = plistlib.load(file)

dnd_preferences_data = outer_preferences.get("dnd_prefs")
if not isinstance(dnd_preferences_data, bytes):
    print("Skipping mirrored-display preference: dnd_prefs is not initialized yet.")
    raise SystemExit(0)

dnd_preferences = plistlib.loads(dnd_preferences_data)
dnd_preferences["dndMirrored"] = False
updated_data = plistlib.dumps(dnd_preferences, fmt=plistlib.FMT_BINARY)

subprocess.run(
    [
        "defaults",
        "write",
        "com.apple.ncprefs",
        "dnd_prefs",
        "-data",
        updated_data.hex(),
    ],
    check=True,
)
PY
  then
    echo "Could not persist the mirrored-display notification preference."
  fi
else
  echo "Skipping mirrored-display preference: ${NOTIFICATION_PREFS_DOMAIN} is unavailable."
fi

###############################################################################
# Enable desktop notifications for selected applications                     #
###############################################################################

# Per-application notification destinations are stored in a privacy-protected
# macOS database. System Settings is the supported local interface, so use
# accessibility automation rather than replacing that database.
if [[ "$(osascript -e 'tell application "System Events" to UI elements enabled' 2>/dev/null || true)" != "true" ]]; then
  echo "Could not configure app notifications: Accessibility access is disabled."
  echo "Grant your terminal Accessibility access, then rerun:"
  echo "  bash ~/dotfiles/scripts/macos-notifications.sh"
  exit 0
fi

settings_was_running=false
if pgrep -x "System Settings" >/dev/null 2>&1; then
  settings_was_running=true
fi

if ! open "${SETTINGS_URL}"; then
  echo "Could not open System Settings to configure per-application notifications."
  echo "The mirrored-display preference was still saved and will apply after login/restart."
  exit 0
fi

if ! automation_result="$(
  osascript - "${TARGET_APPS[@]}" <<'APPLESCRIPT'
on run targetApps
  tell application "System Settings" to activate

  tell application "System Events"
    tell process "System Settings"
      set frontmost to true

      -- Wait for the Notifications pane to finish loading.
      repeat with attempt from 1 to 40
        if exists front window then
          try
            set notificationScrollArea to UI element 1 of UI element 1 of UI element 4 of UI element 1 of group 1 of front window
            set mirrorPopup to UI element 9 of UI element 4 of notificationScrollArea
            if role of mirrorPopup is "AXPopUpButton" then exit repeat
          end try

          -- A previous run may have left an application detail page open.
          try
            set backButton to UI element 1 of UI element 1 of UI element 1 of toolbar 1 of front window
            if enabled of backButton then click backButton
          end try
        end if
        delay 0.25
      end repeat

      try
        set notificationScrollArea to UI element 1 of UI element 1 of UI element 4 of UI element 1 of group 1 of front window
        set mirrorPopup to UI element 9 of UI element 4 of notificationScrollArea
        if role of mirrorPopup is not "AXPopUpButton" then error "Unexpected Notifications pane structure."
      on error
        error "Could not locate the macOS Notifications pane."
      end try

      -- The popup contains "Notifications Off" followed by "Allow
      -- Notifications". Select the second item so this also works when the
      -- current value is already enabled or the UI language changes.
      click mirrorPopup
      delay 0.2
      if (count of menu items of menu 1 of mirrorPopup) < 2 then
        key code 53
        error "Unexpected mirrored-display notification menu."
      end if
      click menu item 2 of menu 1 of mirrorPopup
      delay 0.5

      set configuredApps to {}
      set missingApps to targetApps

      set notificationScrollArea to UI element 1 of UI element 1 of UI element 4 of UI element 1 of group 1 of front window
      set appList to UI element 6 of notificationScrollArea
      set appCount to count of UI elements of appList

      repeat with appIndex from 1 to appCount
        if (count of missingApps) is 0 then exit repeat

        -- Reacquire references after every navigation; SwiftUI invalidates
        -- AXUIElement references when returning from an application page.
        set notificationScrollArea to UI element 1 of UI element 1 of UI element 4 of UI element 1 of group 1 of front window
        set appList to UI element 6 of notificationScrollArea
        click UI element appIndex of appList
        delay 0.35

        set appName to name of front window
        if appName is in missingApps then
          try
            set appScrollArea to UI element 1 of UI element 1 of UI element 4 of UI element 1 of group 1 of front window

            -- Allow notifications.
            set allowNotifications to UI element 3 of UI element 1 of appScrollArea
            if value of allowNotifications is 0 then click allowNotifications

            -- Desktop banner, Notification Center, and Lock Screen.
            repeat with destinationIndex from 1 to 3
              set destinationCheckbox to UI element destinationIndex of UI element 2 of appScrollArea
              if value of destinationCheckbox is 0 then click destinationCheckbox
            end repeat

            -- Badge and sound.
            set badgeCheckbox to UI element 2 of UI element 3 of appScrollArea
            if value of badgeCheckbox is 0 then click badgeCheckbox
            set soundCheckbox to UI element 4 of UI element 3 of appScrollArea
            if value of soundCheckbox is 0 then click soundCheckbox

            delay 0.2
            if value of allowNotifications is not 1 then error "Allow notifications is still disabled."
            repeat with destinationIndex from 1 to 3
              if value of UI element destinationIndex of UI element 2 of appScrollArea is not 1 then error "A notification destination is still disabled."
            end repeat
            if value of badgeCheckbox is not 1 then error "Badge notifications are still disabled."
            if value of soundCheckbox is not 1 then error "Notification sound is still disabled."

            set end of configuredApps to appName
            set remainingApps to {}
            repeat with targetApp in missingApps
              if (targetApp as text) is not appName then set end of remainingApps to (targetApp as text)
            end repeat
            set missingApps to remainingApps
          on error errorMessage
            error "Could not configure " & appName & ": " & errorMessage
          end try
        end if

        set backButton to UI element 1 of UI element 1 of UI element 1 of toolbar 1 of front window
        click backButton
        delay 0.35
      end repeat

      set AppleScript's text item delimiters to ", "
      set configuredText to configuredApps as text
      set missingText to missingApps as text
      set AppleScript's text item delimiters to ""

      return "configured=" & configuredText & linefeed & "missing=" & missingText
    end tell
  end tell
end run
APPLESCRIPT
)"; then
  echo "Could not automate per-application notification settings."
  echo "Open System Settings > Notifications and enable Desktop notifications for Discord and Slack."
  echo "The mirrored-display preference was still saved and will apply after login/restart."
  exit 0
fi

configured_apps="$(printf '%s\n' "${automation_result}" | sed -n 's/^configured=//p')"
missing_apps="$(printf '%s\n' "${automation_result}" | sed -n 's/^missing=//p')"

if [[ -n "${configured_apps}" ]]; then
  echo "Configured macOS notifications: ${configured_apps}"
fi
if [[ -n "${missing_apps}" ]]; then
  echo "Notification settings were not registered yet for: ${missing_apps}"
  echo "Open those apps once, then rerun this script."
fi

if [[ "${settings_was_running}" == "false" ]]; then
  osascript -e 'tell application "System Settings" to quit' >/dev/null 2>&1 || true
fi

echo "macOS notification settings complete."
