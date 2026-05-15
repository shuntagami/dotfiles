#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Skipping sudo Touch ID setup: this is not macOS."
  exit 0
fi

sudo -v

sudo_file="/etc/pam.d/sudo"
sudo_local="/etc/pam.d/sudo_local"
sudo_local_template="/etc/pam.d/sudo_local.template"
block_begin="# dotfiles: begin sudo Touch ID"
block_end="# dotfiles: end sudo Touch ID"
brew_prefix=""
reattach_module=""
auth_block=""
existing_config="$(mktemp)"
new_config="$(mktemp)"

trap 'rm -f "${existing_config}" "${new_config}"' EXIT

if command -v brew >/dev/null 2>&1; then
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
fi

if [[ -n "${brew_prefix}" ]]; then
  reattach_module="${brew_prefix}/lib/pam/pam_reattach.so"
fi

auth_block="${block_begin}"$'\n'
if [[ -n "${reattach_module}" && -f "${reattach_module}" ]]; then
  auth_block+="auth       optional       ${reattach_module} ignore_ssh"$'\n'
else
  echo "Skipping pam_reattach: install pam-reattach to make Touch ID work inside tmux/screen."
fi
auth_block+="auth       sufficient     pam_tid.so"$'\n'
auth_block+="${block_end}"

if [[ -f "${sudo_local}" ]]; then
  awk -v block_begin="${block_begin}" -v block_end="${block_end}" '
    $0 == block_begin { skip = 1; next }
    $0 == block_end { skip = 0; next }
    skip { next }
    /^[[:space:]]*#?[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so([[:space:]]+.*)?$/ { next }
    /pam_reattach\.so/ { next }
    { print }
  ' "${sudo_local}" > "${existing_config}"
elif [[ -f "${sudo_local_template}" ]]; then
  awk '
    /^[[:space:]]*#?[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so([[:space:]]+.*)?$/ { next }
    { print }
  ' "${sudo_local_template}" > "${existing_config}"
else
  echo "# sudo_local: local config file which survives system update and is included for sudo" > "${existing_config}"
fi

awk -v auth_block="${auth_block}" '
  {
    if (!inserted && $0 !~ /^[[:space:]]*(#.*)?$/) {
      print auth_block
      print ""
      inserted = 1
    }
    print
    if ($0 !~ /^[[:space:]]*$/) {
      saw_nonempty = 1
    }
  }
  END {
    if (!inserted) {
      if (saw_nonempty) {
        print ""
      }
      print auth_block
    }
  }
' "${existing_config}" > "${new_config}"

sudo install -m 644 -o root -g wheel "${new_config}" "${sudo_local}"

if ! grep -Eq '^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local' "${sudo_file}"; then
  echo "Warning: ${sudo_file} does not include sudo_local, so this macOS version may need manual PAM setup."
fi

echo "Configured Touch ID for sudo in ${sudo_local}."
