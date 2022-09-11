# Ensure that a non-login, non-interactive shell has a defined environment.
if [[ ( "$SHLVL" -eq 1 && ! -o LOGIN ) && -s "${ZDOTDIR:-$HOME}/.zprofile" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprofile"
fi

if [[ "$OSTYPE" == darwin* ]]; then
  export BROWSER='open'
fi

export DOTFILES=$HOME/dotfiles
export EDITOR='vim'
export GOPATH=$HOME/dotfiles/pkg/go
export PAGER='less'
export VISUAL='vim'

# Language
if [[ -z "$LANG" ]]; then
  eval "$(locale)"
fi

# direnv
if command -v direnv 1>/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

# Paths
path=(
  /Applications/Visual Studio Code.app/Contents/Resources/app/bin
  $GOPATH/bin
  $path
)

typeset -gU PATH
