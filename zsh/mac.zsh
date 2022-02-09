## (Mac)

# homebrew
if [ -d "/opt/homebrew" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# color
autoload -U colors
colors

# copy
alias pbp="pbpaste"

#alias pb="pbcopy"
function pb() {
  if [ -t 0 ]; then
    cat $1 | pbcopy
  else
    pbcopy < /dev/stdin
  fi
}

alias chrome="open -a Google\ Chrome"
