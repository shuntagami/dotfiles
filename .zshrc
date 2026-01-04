# Source Prezto
[[ -s ${ZDOTDIR:-$HOME}/.zprezto/init.zsh ]] && source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"

# Exclude trivial commands from history
zshaddhistory() {
  local line="${1%%$'\n'}"
  [[ ! "$line" =~ "^(cd|jj?|lazygit|la|ll|ls|rmdir|trash)($| )" ]]
}

# Shell options
setopt auto_cd              # cd without typing cd
setopt hist_ignore_dups     # ignore consecutive duplicates
setopt hist_no_store        # don't store history command
setopt hist_reduce_blanks   # remove extra blanks
setopt hist_ignore_all_dups # remove older duplicates
setopt auto_list            # show completion candidates
setopt list_packed          # compact completion list
setopt auto_menu            # tab to cycle completions
setopt auto_param_keys      # auto-complete brackets
setopt auto_param_slash     # auto-append slash to dirs

# Word boundaries for Ctrl+w
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

# OS-specific config
[[ $OSTYPE == darwin* ]] && source $DOTFILES/zsh/mac.zsh
[[ $OSTYPE == linux-gnu* ]] && source $DOTFILES/zsh/ubuntu.zsh
[[ $(uname -r) == *microsoft-standard-WSL2* ]] && source $DOTFILES/zsh/wsl.zsh

# Additional configs
for f in common docker-aliases extra functions http-status-codes; do
  [[ -f $DOTFILES/zsh/$f.zsh ]] && source $DOTFILES/zsh/$f.zsh
done

# PATH additions
[[ -d $DOTFILES/bin ]] && addToPath $DOTFILES/bin
[[ -d $DOTFILES/bin/private ]] && addToPath $DOTFILES/bin/private

# anyenv
if [[ -d $DOTFILES/pkg/.anyenv ]]; then
  export ANYENV_ROOT="$DOTFILES/pkg/.anyenv"
  addToPath $ANYENV_ROOT/bin
  (( $+commands[anyenv] )) && eval "$(anyenv init - zsh)"
fi

# Docker completions
fpath=(~/.docker/completions $fpath)
autoload -Uz compinit
compinit
