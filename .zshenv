# ~/.zshenv — environment variables for all zsh shells (kept minimal).
# PATH is built in ~/.zprofile, not here, so script invocations stay light
# and macOS path_helper (in /etc/zprofile) cannot reorder our PATH.

# Core environment
export DOTFILES="$HOME/dotfiles"
export EDITOR='vim'
export VISUAL='vim'
export PAGER='less'
export GOPATH="$DOTFILES/pkg/go"

# AWS
export AWS_DEFAULT_REGION='ap-northeast-1'
export AWS_ASSUME_ROLE_TTL='12h'
export AWS_SESSION_TOKEN_TTL='12h'

# Locale
[[ -z $LANG ]] && eval "$(locale)"

# OS-specific env (PATH lives in .zprofile)
if [[ $OSTYPE == darwin* ]]; then
  export BROWSER='open'
  typeset -g HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
elif [[ $OSTYPE == linux-gnu* && -n $WSL_DISTRO_NAME ]]; then
  export BROWSER='wslview'
fi

# Non-login shells (e.g. `exec zsh`) skip /etc/zprofile and ~/.zprofile,
# so source ~/.zprofile manually to keep PATH consistent across both modes.
# Guarded by SHLVL to avoid re-sourcing in nested shells.
if [[ ($SHLVL -eq 1 && ! -o LOGIN) && -s ${ZDOTDIR:-$HOME}/.zprofile ]]; then
  source "${ZDOTDIR:-$HOME}/.zprofile"
fi
