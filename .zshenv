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
export AWS_DEFAULT_REGION='ap-northeast-1'
export AWS_ASSUME_ROLE_TTL=12h
export AWS_SESSION_TOKEN_TTL=12h
export JAVA_HOME='/opt/homebrew/opt/openjdk@19/libexec/openjdk.jdk/Contents/Home'

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
  ~/Library/Android/sdk/platform-tools
  $GOPATH/bin
  $path
)

typeset -gU PATH
