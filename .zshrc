#
# Executes commands at the start of an interactive session.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Customize to your needs...
# brew path
export PATH="/opt/homebrew/opt/openssl@1.1/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

# vscode code command
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
# mysql
export PATH="/opt/homebrew/opt/mysql@5.7/bin:$PATH"
# anyenv
eval "$(anyenv init -)"
# java
export PATH="${JAVA_HOME}/bin:$PATH"

# use vim as default editor
export EDITOR="vim"

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

# excule ls after cd
function chpwd() { ls }

# enable command git in command hub
function git(){hub "$@"}

pr_checkout () {
  gh pr list;
  echo "Type the number of PR to checkout: " && read number;
  gh pr checkout ${number};
}

pr_diff () {
  gh pr list;
  echo "Type the number of PR to checkout: " && read number;
  gh pr diff ${number};
}

init_repo () {
  git init && git commit --allow-empty -m "empty commit" && git add -A && git status && git commit -v
  echo "Type repository name: " && read name;
  echo "Type repository description: " && read description;
  gh repo create ${name} --description ${description};
  git push origin HEAD;
}

# change directory without cd
setopt auto_cd

alias ...='cd ../..'
alias ....='cd ../../..'

# Other Settings
has() {
  type "$1" > /dev/null 2>&1
}
export PATH="$HOME/sls/node_modules/.bin/:$PATH"
