# History persistence (previously provided by Prezto's history module)
HISTFILE="${HOME}/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt extended_history     # write timestamps to history
setopt share_history        # share history across sessions
setopt hist_verify          # show expanded history before executing

# Emacs-style keybindings (was Prezto editor module default)
bindkey -e

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

# Homebrew zsh site-functions (Pure prompt etc.) — must come before compinit
if [[ -d /opt/homebrew/share/zsh/site-functions ]]; then
  fpath=(/opt/homebrew/share/zsh/site-functions $fpath)
elif [[ -d /usr/local/share/zsh/site-functions ]]; then
  fpath=(/usr/local/share/zsh/site-functions $fpath)
fi

# Docker completions
fpath=(~/.docker/completions $fpath)
autoload -Uz compinit
compinit

# Completion behavior (replaces Prezto's completion module defaults)
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'

# Pure prompt
autoload -U promptinit; promptinit
prompt pure

# zsh-autosuggestions (load before syntax-highlighting per docs)
for d in /opt/homebrew/share/zsh-autosuggestions /usr/local/share/zsh-autosuggestions; do
  [[ -f "$d/zsh-autosuggestions.zsh" ]] && source "$d/zsh-autosuggestions.zsh" && break
done

# zsh-syntax-highlighting (must be sourced last)
for d in /opt/homebrew/share/zsh-syntax-highlighting /usr/local/share/zsh-syntax-highlighting; do
  [[ -f "$d/zsh-syntax-highlighting.zsh" ]] && source "$d/zsh-syntax-highlighting.zsh" && break
done

# Added by Antigravity
export PATH="/Users/shun.tagami/.antigravity/antigravity/bin:$PATH"
