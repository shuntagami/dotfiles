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
# path
export PATH=$HOME/bin:usr/bin:/usr/local/bin:$PATH
# anyenv
eval "$(anyenv init -)"
# mysql
export PATH="/usr/local/opt/mysql@5.6/bin:$PATH"
