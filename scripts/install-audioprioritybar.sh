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

if [[ -d "${APP}" && -f "${MARKER}" && "$(<"${MARKER}")" == "${VERSION}" ]]; then
  echo "AudioPriorityBar ${VERSION} is already installed."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl -fsSL -o "${work}/AudioPriorityBar.zip" "${URL}"
echo "${SHA256}  ${work}/AudioPriorityBar.zip" | shasum -a 256 -c -
ditto -x -k "${work}/AudioPriorityBar.zip" "${work}"
xattr -dr com.apple.quarantine "${work}/AudioPriorityBar.app" 2>/dev/null || true

was_running=false
if pgrep -x AudioPriorityBar >/dev/null; then
  was_running=true
  pkill -x AudioPriorityBar || true
fi
rm -rf "${APP}"
ditto "${work}/AudioPriorityBar.app" "${APP}"
mkdir -p "$(dirname "${MARKER}")"
echo "${VERSION}" > "${MARKER}"
echo "Installed AudioPriorityBar ${VERSION}."

if [[ "${was_running}" == true ]]; then
  open -g -a "${APP}"
fi
