#!/bin/zsh
# Reconcile managed settings. Packages and legacy macOS defaults have separate entry points.
set -eu
setopt PIPE_FAIL

DOTFILES="${HOME}/dotfiles"
update_prezto=false
case "${1:-}" in
  --update-prezto) update_prezto=true ;;
  --help)
    echo "Usage: deploy.sh [--update-prezto]"
    echo "Apply managed settings; optionally update Prezto from its remote."
    exit 0 ;;
  '') ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
(( $# <= 1 )) || { echo "Too many arguments" >&2; exit 2; }

# Fail before changing settings if a required synchronizer cannot run.
for dependency in python3 node git; do
  command -v "$dependency" >/dev/null || {
    echo "Missing $dependency; run scripts/install-packages.sh first." >&2
    exit 1
  }
done

# env > saved choice > first-run prompt (full when run without a terminal).
if [[ -z "${DOTFILES_PROFILE:-}" ]]; then
  if [[ -f "${HOME}/.dotfiles-profile" ]]; then
    DOTFILES_PROFILE=$(<"${HOME}/.dotfiles-profile")
  elif [[ -t 0 ]]; then
    echo "Select a profile: 1) full (default)  2) minimal (without Karabiner/Hammerspoon)"
    read "profile_choice?Enter choice [1]: "
    case "$profile_choice" in
      2|minimal) DOTFILES_PROFILE=minimal ;;
      *) DOTFILES_PROFILE=full ;;
    esac
  else
    DOTFILES_PROFILE=full
  fi
fi
case "$DOTFILES_PROFILE" in
  full|minimal) ;;
  *) echo "Invalid DOTFILES_PROFILE: $DOTFILES_PROFILE (expected full or minimal)" >&2; exit 2 ;;
esac
export DOTFILES_PROFILE
if [[ ! -f "${HOME}/.dotfiles-profile" ]] || [[ "$(<"${HOME}/.dotfiles-profile")" != "$DOTFILES_PROFILE" ]]; then
  print -r -- "$DOTFILES_PROFILE" > "${HOME}/.dotfiles-profile"
fi

# Bootstrap Prezto when absent. Ordinary deploys do not move its desired version.
prezto_home="${ZDOTDIR:-$HOME}/.zprezto"
if [[ ! -d "$prezto_home" ]]; then
  git clone --recursive https://github.com/sorin-ionescu/prezto.git "$prezto_home"
fi
if $update_prezto; then
  git -C "$prezto_home" pull --ff-only
fi
git -C "$prezto_home" submodule sync --recursive
git -C "$prezto_home" submodule update --init --recursive

# All plain links, including real directories created by apps, use the same
# backup-and-replace policy. Correct links are left untouched.
python3 "$DOTFILES/scripts/install-user-configs.py" links
for config in prezto codex claude agent-instructions skills editors; do
  python3 "$DOTFILES/scripts/install-user-configs.py" "$config"
done
if [[ -d ~/.marunage-studio-claude ]]; then
  python3 "$DOTFILES/scripts/install-user-configs.py" agent-instructions --claude-config-dir ~/.marunage-studio-claude
fi
python3 "$DOTFILES/scripts/remove-cursor-notify.py"
bash "$DOTFILES/scripts/install-mulmoterminal-config.sh"
python3 "$DOTFILES/scripts/apply-mulmoterminal-background.py"
python3 "$DOTFILES/scripts/install-user-configs.py" screenpipe
node "$DOTFILES/mcp/sync-mcp.mjs"

# The included local identity is machine-owned. Never rewrite an existing one.
if [[ ! -f "${HOME}/.gitconfig.local" ]]; then
  if [[ -t 0 ]]; then
    read "git_user_name?Git user.name: "
    read "git_user_email?Git user.email: "
    git config --file "${HOME}/.gitconfig.local" user.name "$git_user_name"
    git config --file "${HOME}/.gitconfig.local" user.email "$git_user_email"
  else
    echo "Warning: ~/.gitconfig.local is missing; set this machine's Git identity there."
  fi
fi

if [[ "$(uname -s)" == Darwin ]]; then
  zsh "$DOTFILES/scripts/deploy-macos.sh"
fi

# Query the account database: $SHELL may be stale in the running session.
zsh_path=$(command -v zsh)
if [[ "$(uname -s)" == Darwin ]]; then
  current_shell=$(dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}')
else
  current_shell=$(getent passwd "$(id -un)" | cut -d: -f7)
fi
if [[ "$current_shell" != "$zsh_path" ]]; then
  sudo chsh -s "$zsh_path" "$(id -un)"
fi

echo "Deploy complete! Run 'exec \$SHELL -l' to reload your shell."
