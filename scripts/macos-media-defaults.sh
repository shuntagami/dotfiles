#!/usr/bin/env bash
# Compatibility entry point: defaults now include images, PDF and CleanShot.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/macos-default-apps.sh" "$@"
