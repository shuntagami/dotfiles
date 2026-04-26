# Login-shell environment (previously provided by Prezto's runcoms/zprofile).
# Most env (EDITOR, PATH, HOMEBREW_PREFIX) is set in ~/dotfiles/.zshenv.
# This file only keeps what was uniquely useful from the Prezto default.

# Ensure path arrays don't contain duplicates.
typeset -gU cdpath fpath mailpath path

# Default less options.
# -X disables screen clearing on exit (also disables mousewheel scroll). Remove
# -X if mouse-wheel scrolling is preferred over keeping content on screen.
[[ -z "$LESS" ]] && export LESS='-g -i -M -R -S -w -X -z-4'

# less input preprocessor (handles archives, binary files, etc.).
if [[ -z "$LESSOPEN" ]] && (( $#commands[(i)lesspipe(|.sh)] )); then
  export LESSOPEN="| /usr/bin/env $commands[(i)lesspipe(|.sh)] %s 2>&-"
fi
