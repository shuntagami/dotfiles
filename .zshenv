# ~/.zshenv — environment variables for all zsh shells (kept minimal).
# The full PATH is built in ~/.zprofile, not here, so script invocations stay
# light and macOS path_helper (in /etc/zprofile) cannot reorder our PATH.

# Core environment
export DOTFILES="$HOME/dotfiles"
export EDITOR='vim'
export VISUAL='vim'
export PAGER='less'
export GOPATH="$DOTFILES/pkg/go"

# Cheap, unconditional guarantee that $DOTFILES/bin wins over Homebrew/system
# dirs (e.g. so bin/git shadows /opt/homebrew/bin/git - see git-hooks/post-checkout
# for why) in EVERY zsh shell, not just logins. .zshenv is the one rc file zsh
# always reads, login or not, nested or not; .zprofile below only reruns for a
# login shell or a SHLVL-1 non-login one, so a shell nested deeper (a tmux pane,
# a subshell some other program spawns) skips it and just inherits whatever
# PATH its parent happened to have - observed in practice to sometimes predate
# a PATH fix, even hours into an already-open session. Plain prepend, no
# globbing/stat calls, so it's safe to pay on every single shell invocation;
# any duplicate it creates is harmless and gets deduped by .zprofile's
# `typeset -gU path` for shells that do reach it.
PATH="$DOTFILES/bin:$DOTFILES/bin/private:$PATH"
export PATH

# AWS
export AWS_DEFAULT_REGION='ap-northeast-1'
export AWS_ASSUME_ROLE_TTL='12h'
export AWS_SESSION_TOKEN_TTL='12h'

# Locale (static default avoids forking /usr/bin/locale on every shell start)
export LANG=${LANG:-en_US.UTF-8}

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
