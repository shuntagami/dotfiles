# ~/.zshenv — environment variables for all shells

# 1) Non-login shell: source .zprofile once
if [[ ($SHLVL -eq 1 && ! -o LOGIN) && -s ${ZDOTDIR:-$HOME}/.zprofile ]]; then
  source "${ZDOTDIR:-$HOME}/.zprofile"
fi

# 2) Core environment
export DOTFILES="$HOME/dotfiles"
export EDITOR='vim'
export VISUAL='vim'
export PAGER='less'
export GOPATH="$DOTFILES/pkg/go"

# 3) AWS
export AWS_DEFAULT_REGION='ap-northeast-1'
export AWS_ASSUME_ROLE_TTL='12h'
export AWS_SESSION_TOKEN_TTL='12h'

# 4) Locale
[[ -z $LANG ]] && eval "$(locale)"

# 5) OS-specific settings
if [[ $OSTYPE == darwin* ]]; then
  export BROWSER='open'
  typeset -g HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

  path=(
    ~/.antigravity/antigravity/bin
    $HOMEBREW_PREFIX/opt/python@3.12/bin
    $HOMEBREW_PREFIX/bin
    $path
  )
elif [[ $OSTYPE == linux-gnu* && -n $WSL_DISTRO_NAME ]]; then
  export BROWSER='wslview'
fi

# 6) Common PATH additions
path=("$GOPATH/bin" $path)

# Deduplicate
typeset -gU path
export PATH
