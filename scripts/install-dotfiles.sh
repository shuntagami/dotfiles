#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

OS="$(uname -s)"
DOTFILES="${HOME}/dotfiles"
DOT_TARBALL="https://github.com/shuntagami/dotfiles/tarball/main"
REMOTE_URL="https://github.com/shuntagami/dotfiles"

cd $HOME

# If missing, download and extract the dotfiles repository
if [[ ! -d "${DOTFILES}" ]]; then
  log_info "Downloading dotfiles..."
  ensure_dir "${DOTFILES}"

  if has "git"; then
    retry 3 git clone "${REMOTE_URL}" "${DOTFILES}" || die "Failed to clone dotfiles repository"
  else
    local temp_file="${HOME}/dotfiles.tar.gz"
    retry 3 curl -fsSLo "${temp_file}" "${DOT_TARBALL}" || die "Failed to download dotfiles tarball"
    tar -zxf "${temp_file}" --strip-components 1 -C "${DOTFILES}" || die "Failed to extract dotfiles"
    rm -f "${temp_file}"
  fi

  log_success "Download dotfiles complete!"
fi

