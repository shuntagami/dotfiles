# Helpers shared by scripts/processing-mac.sh and its service modules. Sourced, not run.
#
# FROM is the previous processing Mac (an SSH destination). FROM=. means "this Mac" and is
# only accepted together with --dry-run, to rehearse the whole flow without touching anything.

DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
FROM="${FROM:-}"
GUI="gui/$(id -u)"
AGENTS_DIR="$HOME/Library/LaunchAgents"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

say() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() {
  printf '\n[processing-mac] %s\n' "$*" >&2
  exit 1
}

# Run a shell command on this Mac, or only print it with --dry-run.
run() {
  printf '    $ %s\n' "$1"
  [ "$DRY_RUN" = 1 ] || bash -c "set -euo pipefail; $1"
}

# Run a shell snippet (stdin) on the previous Mac, or only print it with --dry-run.
on_old() {
  local script
  script="$(cat)"
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s\n' "$script" | sed "s/^/    [旧Mac] /"
    return 0
  fi
  ssh "${SSH_OPTS[@]}" "$FROM" bash -s <<<"$script"
}

# Read-only command on the previous Mac. Runs even with --dry-run.
ask_old() {
  if [ "$FROM" = . ]; then
    bash -c "cd \"\$HOME\"; $1"
  else
    ssh "${SSH_OPTS[@]}" "$FROM" "$1"
  fi
}

# Copy from the previous Mac, keeping modes, times and symlinks.
# pull <path relative to the old Mac's home> <local destination> [extra rsync options...]
pull() {
  local src="$1" dest="$2"
  shift 2
  local rsync=rsync progress=()
  # Homebrew's rsync can show overall progress; macOS's openrsync can only show it per file.
  if [ -x /opt/homebrew/bin/rsync ]; then
    rsync=/opt/homebrew/bin/rsync
    progress=(--info=progress2)
  fi
  run "$rsync -a --partial ${progress[*]-} $* -e 'ssh ${SSH_OPTS[*]}' '$FROM:$src' '$dest'"
}

agent_loaded() { launchctl print "$GUI/$1" >/dev/null 2>&1; }

confirm() {
  [ "$ASSUME_YES" = 1 ] && return 0
  [ "$DRY_RUN" = 1 ] && {
    note "（確認: $1）"
    return 0
  }
  local answer
  read -r -p "$1 [y/N] " answer </dev/tty
  [ "$answer" = y ] || [ "$answer" = Y ]
}

# wait_for <seconds> <what> <command...>: poll every 10 seconds until the command succeeds.
wait_for() {
  local limit="$1" what="$2" waited=0
  shift 2
  [ "$DRY_RUN" = 1 ] && {
    note "（待つ: ${what}）"
    return 0
  }
  until "$@"; do
    [ "$waited" -ge "$limit" ] && return 1
    [ $((waited % 60)) -eq 0 ] && note "$what を待っています…"
    sleep 10
    waited=$((waited + 10))
  done
}

# Major version comparison for "x.y.z" strings: version_at_least <have> <need>.
version_at_least() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}
