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
export OPAMROOT=$HOME/dotfiles/pkg/.opam

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
  $GOPATH/bin
  $path
)

if [[ "$OSTYPE" == darwin* ]]; then
  path=(
    /opt/homebrew/opt/gnu-getopt/bin
    /opt/homebrew/opt/imagemagick@6/bin
    /Applications/Visual Studio Code.app/Contents/Resources/app/bin
    ~/Library/Android/sdk/platform-tools
    $path
  )
elif [[ "$OSTYPE" == "linux-gnu"* ]] && [[ ! -z "$WSL_DISTRO_NAME" ]]; then
  # Add WSL2 specific paths here
  path=(
    /your/wsl2/specific/path
    $path
  )
fi

typeset -gU PATH
export PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"
