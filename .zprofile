# ~/.zprofile — login-time setup
# Runs after macOS /etc/zprofile's path_helper, so PATH ordering set here wins.

# Inherit prezto defaults (base path, less options, editors, etc.)
[[ -s ${ZDOTDIR:-$HOME}/.zprezto/runcoms/zprofile ]] && \
  source "${ZDOTDIR:-$HOME}/.zprezto/runcoms/zprofile"

# Project-specific PATH (prepended → highest priority)
if [[ $OSTYPE == darwin* ]]; then
  path=(
    ~/.antigravity/antigravity/bin
    $HOMEBREW_PREFIX/opt/ruby/bin
    $HOMEBREW_PREFIX/bin
    $path
  )
fi

path=(
  $GOPATH/bin
  $DOTFILES/bin(N)
  $DOTFILES/bin/private(N)
  $path
)

typeset -gU path
export PATH
