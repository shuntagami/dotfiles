#!/usr/bin/env bash

set -euo pipefail

export DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

has() {
  command -v "$1" >/dev/null 2>&1
}

log_info() {
  printf "\033[0;34m[INFO]\033[0m %s\n" "$*"
}

log_success() {
  printf "\033[0;32m[SUCCESS]\033[0m %s\n" "$*"
}

log_warning() {
  printf "\033[0;33m[WARNING]\033[0m %s\n" "$*"
}

log_error() {
  printf "\033[0;31m[ERROR]\033[0m %s\n" "$*" >&2
}

log_debug() {
  if [[ "${DEBUG:-0}" == "1" ]]; then
    printf "\033[0;36m[DEBUG]\033[0m %s\n" "$*"
  fi
}

die() {
  log_error "$*"
  exit 1
}

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" || die "Failed to create directory: $dir"
    log_info "Created directory: $dir"
  fi
}

safe_symlink() {
  local source="$1"
  local target="$2"
  
  [[ -e "$source" ]] || die "Source file does not exist: $source"
  
  if [[ -L "$target" ]]; then
    rm "$target" || die "Failed to remove existing symlink: $target"
  elif [[ -e "$target" ]]; then
    log_warning "Target already exists, backing up: $target"
    mv "$target" "${target}.backup.$(date +%Y%m%d_%H%M%S)" || die "Failed to backup: $target"
  fi
  
  ensure_dir "$(dirname "$target")"
  ln -sf "$source" "$target" || die "Failed to create symlink: $source -> $target"
  log_success "Linked: $source -> $target"
}

check_os() {
  case "$(uname -s)" in
    Darwin*)  echo "macos" ;;
    Linux*)   echo "linux" ;;
    CYGWIN*)  echo "cygwin" ;;
    MINGW*)   echo "mingw" ;;
    *)        echo "unknown" ;;
  esac
}

is_macos() {
  [[ "$(check_os)" == "macos" ]]
}

is_linux() {
  [[ "$(check_os)" == "linux" ]]
}

retry() {
  local retries="$1"
  shift
  local count=0
  
  until "$@"; do
    exit_code=$?
    count=$((count + 1))
    if [[ $count -lt $retries ]]; then
      log_warning "Command failed (attempt $count/$retries). Retrying in 2 seconds..."
      sleep 2
    else
      log_error "Command failed after $retries attempts"
      return $exit_code
    fi
  done
}

confirm() {
  local prompt="$1"
  local response
  
  while true; do
    read -r -p "$prompt [y/N]: " response
    case "$response" in
      [yY][eE][sS]|[yY]) return 0 ;;
      [nN][oO]|[nN]|"") return 1 ;;
      *) log_warning "Please answer yes or no." ;;
    esac
  done
}

check_prerequisites() {
  local missing_commands=()
  
  for cmd in "$@"; do
    if ! has "$cmd"; then
      missing_commands+=("$cmd")
    fi
  done
  
  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    log_error "Missing required commands: ${missing_commands[*]}"
    log_info "Please install the missing commands and try again"
    return 1
  fi
  
  return 0
}

get_absolute_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  elif [[ -f "$path" ]]; then
    (cd "$(dirname "$path")" && pwd)/$(basename "$path")
  else
    die "Path does not exist: $path"
  fi
}

cleanup_temp() {
  local temp_dir="${1:-}"
  if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
    rm -rf "$temp_dir"
    log_debug "Cleaned up temporary directory: $temp_dir"
  fi
}

backup_file() {
  local file="$1"
  local backup_dir="${2:-$HOME/.dotfiles_backup}"
  
  if [[ -e "$file" ]]; then
    ensure_dir "$backup_dir"
    local backup_path="$backup_dir/$(basename "$file").$(date +%Y%m%d_%H%M%S)"
    cp -r "$file" "$backup_path" || die "Failed to backup: $file"
    log_info "Backed up $file to $backup_path"
  fi
}