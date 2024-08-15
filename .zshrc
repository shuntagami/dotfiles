# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

zshaddhistory() {
    local line="${1%%$'\n'}"
    [[ ! "$line" =~ "^(cd|jj?|lazygit|la|ll|ls|rmdir|trash)($| )" ]]
}

# change directory without cd
setopt auto_cd

# ignore just before command in history
setopt hist_ignore_dups

# ignore history in command history
setopt hist_no_store

# remove blanks in command history
setopt hist_reduce_blanks

# prevent duplicatiton in command history
setopt hist_ignore_all_dups

# show all candidates
setopt auto_list

# tighten candidates
setopt list_packed

# easy complemention just tap(Tab or Ctrl+I)
setopt auto_menu

# complement (), {},[]
setopt auto_param_keys

# add / automatically in command cd
setopt auto_param_slash

# delete until / by Ctrl+w
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

# include
[[ $(uname) == "Darwin" && -f $DOTFILES/zsh/mac.zsh ]] && source $DOTFILES/zsh/mac.zsh
[[ $(uname) == "Linux"  && -f $DOTFILES/zsh/ubuntu.zsh ]] && source $DOTFILES/zsh/ubuntu.zsh
[[ $(uname -r) == *"microsoft-standard-WSL2"* && -f $DOTFILES/zsh/wsl.zsh ]] && source $DOTFILES/zsh/wsl.zsh

[[ -f $DOTFILES/zsh/common.zsh ]] && source $DOTFILES/zsh/common.zsh
[[ -f $DOTFILES/zsh/docker-aliases.zsh ]] && source $DOTFILES/zsh/docker-aliases.zsh
[[ -f $DOTFILES/zsh/extra.zsh ]] && source $DOTFILES/zsh/extra.zsh
[[ -f $DOTFILES/zsh/functions.zsh ]] && source $DOTFILES/zsh/functions.zsh
[[ -f $DOTFILES/zsh/http-status-codes.zsh ]] && source $DOTFILES/zsh/http-status-codes.zsh

# core utils
[[ -d "$DOTFILES/bin" ]] && addToPath $DOTFILES/bin
[[ -d "$DOTFILES/bin/private" ]] && addToPath $DOTFILES/bin/private

# anyenv
if [ -e "$DOTFILES/pkg/.anyenv" ]; then
  export ANYENV_ROOT="$DOTFILES/pkg/.anyenv"
  addToPath $ANYENV_ROOT/bin
  if command -v anyenv 1>/dev/null 2>&1; then
    eval "$(anyenv init - zsh)"
  fi
fi

# opam configuration
[[ ! -r $DOTFILES/pkg/.opam/opam-init/init.zsh ]] || source $DOTFILES/pkg/.opam/opam-init/init.zsh  > /dev/null 2>&1
export PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"
