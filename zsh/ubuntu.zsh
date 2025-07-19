#!/usr/bin/env zsh

## (Ubuntu)

# Load configuration
if [[ -f "$HOME/dotfiles/config/paths.conf" ]]; then
  source "$HOME/dotfiles/config/paths.conf"
fi

# Shortcuts (using configured paths)
alias d="cd ${alias_dot}"
alias p="cd ${alias_p}"
alias g="git"
alias bat="batcat"

alias cl1='xclip -selection clipboard -o | head -n 1 | while IFS= read -r line; do printf "%s" "$line"; done | xclip -selection clipboard'
