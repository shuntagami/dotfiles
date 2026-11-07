#!/bin/bash
# Share sudo's normal credential cache during setup. Passwords are never read or
# stored by this helper, and no sudoers / system timeout settings are changed.

dotfiles_start_sudo_session() {
  sudo -v || return
  # setup.sh passes its running keeper to install-packages.sh. The child must
  # neither create a second keeper nor stop its parent's keeper on exit.
  if [[ "${DOTFILES_SUDO_KEEPALIVE_PID:-}" =~ ^[0-9]+$ ]] &&
     kill -0 "${DOTFILES_SUDO_KEEPALIVE_PID}" 2>/dev/null; then
    return 0
  fi
  local setup_pid="$$"
  (
    keepalive_sleep_pid=""
    trap 'if [[ -n "$keepalive_sleep_pid" ]]; then kill "$keepalive_sleep_pid" 2>/dev/null || true; fi; exit 0' TERM INT
    while kill -0 "$setup_pid" 2>/dev/null; do
      # Refresh without requesting input; stop if credentials were revoked.
      sudo -n -v || exit
      sleep 60 &
      keepalive_sleep_pid=$!
      wait "$keepalive_sleep_pid" || exit
      keepalive_sleep_pid=""
    done
  ) </dev/null >/dev/null 2>&1 &
  export DOTFILES_SUDO_KEEPALIVE_PID=$!
  DOTFILES_SUDO_SESSION_OWNER="$$"
}

dotfiles_stop_sudo_session() {
  if [[ "${DOTFILES_SUDO_SESSION_OWNER:-}" == "$$" &&
        -n "${DOTFILES_SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    unset DOTFILES_SUDO_KEEPALIVE_PID DOTFILES_SUDO_SESSION_OWNER
  fi
}
