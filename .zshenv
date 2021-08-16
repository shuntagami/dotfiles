# Ensure that a non-login, non-interactive shell has a defined environment.
if [[ ( "$SHLVL" -eq 1 && ! -o LOGIN ) && -s "${ZDOTDIR:-$HOME}/.zprofile" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprofile"
fi

# Browser
if [[ "$OSTYPE" == darwin* ]]; then
  export BROWSER='open'
fi

# Editors
export EDITOR='vim'
export VISUAL='vim'
export PAGER='less'

# Language
if [[ -z "$LANG" ]]; then
  eval "$(locale)"
fi

# Paths
typeset -gU path

path=(
  /opt/homebrew/{bin,sbin}
  /opt/homebrew/opt/mysql@5.7/bin
  /Applications/Visual Studio Code.app/Contents/Resources/app/bin
  $path
)
