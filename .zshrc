# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Load the shell dotfiles, and then some:
# * ~/.path can be used to extend `$PATH`.
# * ~/.extra can be used for other settings you don’t want to commit.
for file in ~/.{aliases,docker-aliases,functions,extra}; do
	[ -r "$file" ] && [ -f "$file" ] && source "$file";
done;
unset file;

# anyenv
if [ -e "$HOME/.anyenv" ]
then
  if command -v anyenv 1>/dev/null 2>&1
  then
      eval "$(anyenv init -)"
  fi
fi

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

