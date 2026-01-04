# ~/.zshenv  — sane defaults, minimal work in non-login shells

# 1) In non-login, non-interactive top-level shells, inherit login env once.
if [[ ("$SHLVL" -eq 1 && ! -o LOGIN) && -s "${ZDOTDIR:-$HOME}/.zprofile" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprofile"
fi

# 2) OS-specific basics
if [[ "$OSTYPE" == darwin* ]]; then
  export BROWSER='open'
elif [[ "$OSTYPE" == "linux-gnu"* ]] && [[ -n "$WSL_DISTRO_NAME" ]]; then
  export BROWSER='wslview'
fi

# 3) Your usual suspects
export DOTFILES="$HOME/dotfiles"
export EDITOR='vim'
export VISUAL='vim'
export PAGER='less'
export GOPATH="$HOME/dotfiles/pkg/go"
export AWS_DEFAULT_REGION='ap-northeast-1'
export AWS_ASSUME_ROLE_TTL='12h'
export AWS_SESSION_TOKEN_TTL='12h'
export JAVA_HOME='/opt/homebrew/opt/openjdk@19/libexec/openjdk.jdk/Contents/Home'
export OPAMROOT="$HOME/dotfiles/pkg/.opam"

# 4) Locale: respect system if unset
if [[ -z "$LANG" ]]; then
  eval "$(locale)"
fi

# --- Homebrew & Python 3.12 最優先 PATH（堅牢版） ---
typeset -g HOMEBREW_PREFIX
HOMEBREW_PREFIX="$(
  /usr/bin/env brew --prefix 2>/dev/null || echo /opt/homebrew
)"

# 既存の path を土台に使う
path=($path)

# Python 3.12 を最前列（keg-only 対策）
if [[ -d "$HOMEBREW_PREFIX/opt/python@3.12/bin" ]]; then
  path=("$HOMEBREW_PREFIX/opt/python@3.12/bin" $path)
fi

# brew の bin も前のほうへ
if [[ -d "$HOMEBREW_PREFIX/bin" ]]; then
  path=("$HOMEBREW_PREFIX/bin" $path)
fi

# あなたの既存エントリを維持
if [[ "$OSTYPE" == darwin* ]]; then
  path=(
    ~/.antigravity/antigravity/bin
    /opt/homebrew/opt/imagemagick@6/bin
    /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin
    ~/Library/Android/sdk/platform-tools
    $path
  )
elif [[ "$OSTYPE" == "linux-gnu"* ]] && [[ -n "$WSL_DISTRO_NAME" ]]; then
  path=(/your/wsl2/specific/path $path)
fi

# GOPATH/bin は前寄りキープ
path=("$GOPATH/bin" $path)

# 重複除去は配列 'path' に適用。順序は“先に入れたほうが勝ち”で固定される
typeset -gU path
export PATH
# --- ここまで ---
