# ~/.zprofile — login-time setup.
# Runs after macOS /etc/zprofile's path_helper, so PATH ordering set here wins.

[[ -s ${ZDOTDIR:-$HOME}/.zprezto/runcoms/zprofile ]] && \
  source "${ZDOTDIR:-$HOME}/.zprezto/runcoms/zprofile"

if [[ $OSTYPE == darwin* ]]; then
  path=(
    ~/.antigravity/antigravity/bin(N)
    $HOMEBREW_PREFIX/opt/ruby@3.4/bin(N)
    $path
  )
fi

path=(
  $GOPATH/bin(N)
  $HOME/.local/bin(N)
  $DOTFILES/bin(N)
  $DOTFILES/bin/private(N)
  $path
)

typeset -gU path
export PATH
