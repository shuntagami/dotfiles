#!/usr/bin/env bash

set -euo pipefail

# Notification settings, the parts of them that belong in dotfiles.
#
# Three layers stand between "Slack sent a message" and a banner on screen, and
# they are owned in three different places:
#
#   1. Which SITES may notify, inside the browser. Chrome reads enterprise
#      policies from its own preference domain, so this one is ours. It is worth
#      owning because Chrome does NOT sync it: notifications are registered
#      UNSYNCABLE in Chromium's content_settings_registry, so a new machine or a
#      new profile starts over, and clicking "Allow" in the browser lands in one
#      profile's Preferences file (there are several here) and is lost when that
#      profile is reset.
#
#   2. Whether MACOS lets the app put anything on screen. Not reachable through
#      `defaults`: on macOS 26 the per-app settings live in a protected store
#      under group.com.apple.usernoted. A configuration profile is the supported
#      way in, and it addresses apps by BUNDLE ID -- which is the only way to
#      reach Chrome's second notification identity (see the profile itself).
#
#   3. What Slack notifies ABOUT (which messages, sound, schedule). Kept in the
#      Slack account and synced between devices, so not ours and not here.
#
# Runs from deploy.sh on every deploy, so everything below is idempotent and
# nothing here waits on a human: the one step that cannot be automated (approving
# a profile) is asked for only when it is actually needed.

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping macOS notification settings (not running on macOS)."
  exit 0
fi

# Resolved from THIS FILE's location rather than from $DOTFILES or ~/dotfiles.
# deploy.sh, which calls this, addresses everything as ~/dotfiles/..., and an env
# var read only here would mean the two disagree about which checkout is being
# deployed -- the caller running one copy of the script while the script reads
# another copy's profile. A path relative to the script cannot disagree with the
# script.
readonly DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROFILE_PATH="${DOTFILES_DIR}/misc/notifications.mobileconfig"
readonly PROFILE_IDENTIFIER="local.dotfiles.notifications"
readonly STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/dotfiles"
readonly PROFILE_STATE="${STATE_DIR}/notifications-profile.sha256"
readonly USERNOTED_PREFS="${HOME}/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist"

###############################################################################
# 1. Chrome: which sites may show notifications                               #
###############################################################################

# Measured, not assumed. NotificationsAllowedForUrls carries no
# `can_be_recommended` in Chrome's policy list, which reads as "a user-domain
# write will be ignored as merely recommended". Against a throwaway profile,
# with controls: Notification.permission is "granted" for a listed origin and
# "default" for two unlisted ones. It applies.
#
# The write REPLACES the array. That is the intent -- this list is the source of
# truth, so add an origin here rather than in the browser.
readonly CHROME_NOTIFICATION_URLS=(
  "https://app.slack.com"
  "https://discord.com"
)

if defaults write com.google.Chrome NotificationsAllowedForUrls -array "${CHROME_NOTIFICATION_URLS[@]}"; then
  echo "Chrome: notifications allowed for ${CHROME_NOTIFICATION_URLS[*]}"
else
  echo "Could not write Chrome's notification policy."
fi

###############################################################################
# 2. macOS: per-app notification settings, as a configuration profile         #
###############################################################################

# Apple allows this payload on macOS with neither supervision nor MDM, but
# `profiles -I` was removed in Big Sur -- so installing means opening the file
# and approving it once, and there is no way around that from a script.
#
# Which makes "only when needed" the whole game, since this runs on every
# deploy. Approval is asked for in three cases: nothing is installed, the
# settings changed, or the last thing we asked for was never approved.
#
# The third case is why the recorded state carries a TIMESTAMP as well as a
# hash. The installed payload cannot be read back without root, so the hash
# alone cannot say which version is on the machine -- and writing it at ask time
# would then make a DECLINED update look up to date until the settings moved
# again. `profiles list -verbose` reports an installationDate, so comparing it
# against the moment we asked answers what the hash cannot: cancel the dialog
# and the date stays older than the ask, and the next deploy asks again.
#
# What this still cannot verify is that the installed payload MATCHES ours: only
# that something was installed after we asked for it. Reading the payload back
# needs root, and a deploy step should not ask for it.
#
# The hash covers PayloadContent ONLY, not the whole file. Comments and
# formatting are then free: re-approving a profile whose settings did not move
# is friction with nothing behind it, and friction is what gets a deploy step
# ignored. Anything macOS actually enforces lives in that payload.
profile_installed() {
  profiles list 2>/dev/null | grep -q "${PROFILE_IDENTIFIER}"
}

# Epoch seconds of our profile's installationDate, or empty when it is absent or
# unreadable. `profiles list -verbose` groups one profile's attributes under a
# shared [N] index, so the identifier and the date are matched through it.
profile_installed_at() {
  profiles list -verbose 2>/dev/null | python3 -c '
import datetime, re, sys

wanted = sys.argv[1]
identifiers, dates = {}, {}
for line in sys.stdin:
    found = re.search(r"\[(\d+)\] attribute: (\w+): (.*)$", line.rstrip())
    if not found:
        continue
    index, key, value = found.group(1), found.group(2), found.group(3).strip()
    if key == "profileIdentifier":
        identifiers[index] = value
    elif key == "installationDate":
        dates[index] = value

for index, identifier in identifiers.items():
    if identifier != wanted or index not in dates:
        continue
    try:
        print(int(datetime.datetime.strptime(dates[index], "%Y-%m-%d %H:%M:%S %z").timestamp()))
    except ValueError:
        pass
    break
' "${PROFILE_IDENTIFIER}"
}

ask_to_install_profile() {
  local reason="$1" hash="$2"
  echo "Notification profile: ${reason}"
  if open "${PROFILE_PATH}"; then
    # Recorded only now, with the moment of the ask, and only because `open`
    # succeeded. The date comparison above is what turns this into "approved";
    # on its own it means no more than "asked for".
    mkdir -p "${STATE_DIR}"
    printf '%s %s\n' "${hash}" "$(date +%s)" > "${PROFILE_STATE}"
    echo "  Opened ${PROFILE_PATH} -- approve it in System Settings (Device Management)."
    echo "  It does not take effect until approved."
  else
    echo "  Could not open ${PROFILE_PATH}. Double-click it to install."
  fi
}

if [[ ! -f "${PROFILE_PATH}" ]]; then
  echo "Notification profile missing at ${PROFILE_PATH}; skipped."
else
  profile_hash="$(plutil -extract PayloadContent xml1 -o - "${PROFILE_PATH}" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  # "<hash> <epoch>". A state file from before the timestamp existed carries the
  # hash alone; its ask time reads as 0, which no installationDate predates, so
  # an already-approved profile is not re-asked for on the strength of an
  # upgrade.
  state="$(cat "${PROFILE_STATE}" 2>/dev/null || true)"
  asked_hash="${state%% *}"
  asked_at="${state##* }"
  [[ "${asked_at}" =~ ^[0-9]+$ ]] || asked_at=0
  installed_at="$(profile_installed_at)"

  if ! profile_installed; then
    ask_to_install_profile "not installed" "${profile_hash}"
  elif [[ "${asked_hash}" != "${profile_hash}" ]]; then
    ask_to_install_profile "its settings changed since it was installed" "${profile_hash}"
  elif [[ -n "${installed_at}" ]] && ((installed_at < asked_at)); then
    ask_to_install_profile "the last update to it was never approved" "${profile_hash}"
  else
    echo "Notification profile up to date (${PROFILE_IDENTIFIER})."
  fi
fi

###############################################################################
# 3. Notifications while the display is mirrored or shared                    #
###############################################################################

# Wanted: notifications keep arriving while mirroring (dndMirrored = false), so a
# message is not silently swallowed during a screen share.
#
# This one is READ and reported, never written, and the asymmetry is deliberate.
# It lives inside `dnd_prefs`, a nested binary plist in the group container above
# -- the same file that holds the notification settings for every app on the
# machine. cfprefsd does not own that path the way it owned com.apple.ncprefs,
# which this script used to write through, and that domain no longer exists on
# macOS 26. Writing it behind the daemon's back to flip one boolean risks every
# other app's settings in the same file; a checkbox in System Settings does not.
# So: say when it drifts, and let a human spend the five seconds.
if [[ ! -f "${USERNOTED_PREFS}" ]]; then
  echo "Mirrored-display setting: notification preferences not found; skipped."
else
  mirrored="$(python3 - "${USERNOTED_PREFS}" <<'PY' 2>/dev/null || true
import plistlib, sys
try:
    blob = plistlib.load(open(sys.argv[1], "rb")).get("dnd_prefs")
    if isinstance(blob, bytes):
        print(plistlib.loads(blob).get("dndMirrored", ""))
except Exception:
    pass
PY
  )"
  case "${mirrored}" in
    False) echo "Mirrored-display notifications: on (dndMirrored=False), as wanted." ;;
    True)  echo "Mirrored-display notifications are SUPPRESSED (dndMirrored=True)."
           echo "  Turn on System Settings > Notifications > \"Allow notifications when mirroring or sharing the display\"." ;;
    *)     echo "Mirrored-display setting: could not read dndMirrored; left alone." ;;
  esac
fi

echo "macOS notification settings complete."
