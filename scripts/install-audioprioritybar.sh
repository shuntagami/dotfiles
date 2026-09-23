#!/usr/bin/env bash
# Install AudioPriorityBar (no Homebrew cask) from a pinned GitHub release.
# The release is ad-hoc signed and not notarized, so the archive is verified by
# SHA-256 before it replaces anything in /Applications.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping AudioPriorityBar (not running on macOS)."
  exit 0
fi

readonly VERSION="v1.2.1"
readonly SHA256="f29f23d8cfcb90765aa5716983254d8aa6ac3c725de87b3aed8614eef0873bc0"
readonly URL="https://github.com/tobi/AudioPriorityBar/releases/download/${VERSION}/AudioPriorityBar.zip"
readonly APP="/Applications/AudioPriorityBar.app"
# The bundle always reports 1.0, so track the installed release separately.
readonly MARKER="${HOME}/Library/Application Support/dotfiles/audioprioritybar.version"

# Register here rather than in macos.sh, which setup.sh does not run.
register_login_item() {
  local items
  items="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)" || return 0
  if [[ ", ${items}, " != *", AudioPriorityBar, "* ]]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${APP}\", hidden:false}" >/dev/null 2>&1 || true
  fi
}

if [[ -d "${APP}" && -f "${MARKER}" && "$(<"${MARKER}")" == "${VERSION}" ]]; then
  echo "AudioPriorityBar ${VERSION} is already installed."
  register_login_item
  exit 0
fi

work="$(mktemp -d)"
stage=""
trap 'rm -rf "${work}" ${stage:+"${stage}"}' EXIT

curl -fsSL -o "${work}/AudioPriorityBar.zip" "${URL}"
echo "${SHA256}  ${work}/AudioPriorityBar.zip" | shasum -a 256 -c -
ditto -x -k "${work}/AudioPriorityBar.zip" "${work}"
xattr -dr com.apple.quarantine "${work}/AudioPriorityBar.app" 2>/dev/null || true

# Stage on the same volume so the swap is a rename and the old app survives a
# failed copy.
stage="$(mktemp -d "/Applications/.AudioPriorityBar.XXXXXX")"
ditto "${work}/AudioPriorityBar.app" "${stage}/AudioPriorityBar.app"

was_running=false
if pgrep -x AudioPriorityBar >/dev/null; then
  was_running=true
  pkill -x AudioPriorityBar || true
fi
if [[ -e "${APP}" ]]; then
  mv "${APP}" "${stage}/previous.app"
fi
if ! mv "${stage}/AudioPriorityBar.app" "${APP}"; then
  if [[ -e "${stage}/previous.app" ]] && ! mv "${stage}/previous.app" "${APP}"; then
    echo "Could not restore the previous app; it is kept at ${stage}/previous.app" >&2
    stage=""
  fi
  if [[ "${was_running}" == true ]]; then
    open -g -a "${APP}" || true
  fi
  exit 1
fi
mkdir -p "$(dirname "${MARKER}")"
echo "${VERSION}" > "${MARKER}"
echo "Installed AudioPriorityBar ${VERSION}."
register_login_item

if [[ "${was_running}" == true ]]; then
  open -g -a "${APP}"
fi
