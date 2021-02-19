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
# Homebrew
alias brew="PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin brew"
# anyenv
eval "$(anyenv init -)"
# mysql
export PATH="/usr/local/opt/mysql@5.6/bin:$PATH"
# npm-global
export PATH=$HOME/.npm-global/bin:$PATH

# 補完を有効にする
autoload -U compinit
compinit -u

# デフォルトエディタの設定
export EDITOR="vim"

# 直前と同じコマンドラインはヒストリに追加しない
setopt hist_ignore_dups

# ヒストリにhistoryコマンドを記録しない
setopt hist_no_store

# 余分なスペースを削除してヒストリに記録する
setopt hist_reduce_blanks

# 重複したヒストリは追加しない
setopt hist_ignore_all_dups

# 補完候補が複数ある時に、一覧表示
setopt auto_list

# 保管結果をできるだけ詰める
setopt list_packed

# 補完キー（Tab, Ctrl+I) を連打するだけで順に補完候補を自動で補完
setopt auto_menu

# カッコの対応などを自動的に補完
setopt auto_param_keys

# ディレクトリ名の補完で末尾の / を自動的に付加し、次の補完に備える
setopt auto_param_slash

# Ctrl+wで､直前の/までを削除する
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

# cd をしたときにlsを実行する
function chpwd() { ls }
# hubコマンドをgitで使えるようにする
function git(){hub "$@"}

# ディレクトリ名だけで､ディレクトリの移動をする
setopt auto_cd

# 2つ上、3つ上にも移動できるようにする
alias ...='cd ../..'
alias ....='cd ../../..'

# universal-ctagsをデフォルトで使う
alias ctags="`brew --prefix`/bin/ctags"

# Other Settings
has() {
  type "$1" > /dev/null 2>&1
}

# プロンプトにjobsを表示
# PROMPT=$'
# %~ : \e[3%(?.2.1)mStatus %?\%1(j. : Job%2(j.s.) %j.) \e[m
# %# '
