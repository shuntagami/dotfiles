#!/bin/zsh

set -eux

# Load profile: env var > ~/.dotfiles-profile > interactive prompt
if [[ -z "${DOTFILES_PROFILE:-}" ]]; then
  if [[ -f "${HOME}/.dotfiles-profile" ]]; then
    DOTFILES_PROFILE=$(cat "${HOME}/.dotfiles-profile")
  else
    echo ""
    echo "Select a profile:"
    echo "  1) full    - All settings (default)"
    echo "  2) minimal - Without Vim extension, Karabiner, Hammerspoon"
    echo ""
    read "profile_choice?Enter choice [1]: "
    case "${profile_choice}" in
      2|minimal) DOTFILES_PROFILE="minimal" ;;
      *)         DOTFILES_PROFILE="full" ;;
    esac
    echo "${DOTFILES_PROFILE}" > "${HOME}/.dotfiles-profile"
  fi
fi
export DOTFILES_PROFILE

if [ ! -d ${HOME}/.zprezto ]; then
  git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
fi

# prezto
setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^(README.md|zpreztorc|zshenv|zshrc|zprofile)(.N); do
  ln -sf "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done

# add and update submodule
git -C ${HOME}/.zprezto pull && git -C ${HOME}/.zprezto submodule sync --recursive && git -C ${HOME}/.zprezto submodule update --init --recursive

# symlink dotfiles
ln -sf ~/dotfiles/.dein.toml ~/.dein.toml
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.gitignore_global ~/.gitignore_global
ln -sf ~/dotfiles/.vimrc ~/.vimrc
ln -sf ~/dotfiles/.zpreztorc ~/.zpreztorc
ln -sf ~/dotfiles/.zprofile ~/.zprofile
ln -sf ~/dotfiles/.zshenv ~/.zshenv
ln -sf ~/dotfiles/.zshrc ~/.zshrc
mkdir -p ~/.docker
ln -sf ~/dotfiles/misc/docker-config.json ~/.docker/config.json
mkdir -p ~/.local/state/crossnote
ln -sf ~/dotfiles/misc/crossnote/parser.js ~/.local/state/crossnote/parser.js
ln -sf ~/dotfiles/misc/crossnote/style.less ~/.local/state/crossnote/style.less
mkdir -p ~/.config/mcp
if [[ -f ~/.config/mcp/slack.env && ! -L ~/.config/mcp/slack.env && ! -f ~/dotfiles/mcp/slack.env ]]; then
  mv ~/.config/mcp/slack.env ~/dotfiles/mcp/slack.env
fi
ln -sf ~/dotfiles/mcp/slack.env ~/.config/mcp/slack.env
if [[ -f ~/dotfiles/mcp/slack.env ]]; then
  chmod 600 ~/dotfiles/mcp/slack.env
fi

# MCP: sync canonical dotfiles config to Cursor, Codex, and Claude Code.
if command -v node >/dev/null 2>&1; then
  ~/dotfiles/mcp/sync-mcp.mjs
else
  echo "Skipping MCP sync: node is not installed."
fi

# Per-machine git identity (~/.gitconfig.local is included from ~/.gitconfig)
if [[ ! -f "${HOME}/.gitconfig.local" ]]; then
  echo ""
  echo "Setting up per-machine git identity (~/.gitconfig.local)"
  set +u
  read "git_user_name?  Git user.name: "
  read "git_user_email?  Git user.email: "
  set -u
  {
    echo "[user]"
    echo "	name = ${git_user_name}"
    echo "	email = ${git_user_email}"
  } > "${HOME}/.gitconfig.local"
fi

# ssh config
if [ ! -d ${HOME}/.ssh ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/config && chmod 600 ~/.ssh/config
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  if [[ "${DOTFILES_PROFILE:-full}" != "minimal" ]]; then
    ln -sfn ~/dotfiles/hammerspoon ~/.hammerspoon
  fi
  mkdir -p ~/Library/Application\ Support/Claude
  ln -sf ~/dotfiles/misc/claude_desktop_config.json ~/Library/Application\ Support/Claude/claude_desktop_config.json
  mkdir -p ~/.config/memo
  ln -sf ~/dotfiles/misc/memo-config.toml ~/.config/memo/config.toml
  mkdir -p ~/Library/Application\ Support/ngrok
  ln -sf ~/dotfiles/misc/ngrok.yml ~/Library/Application\ Support/ngrok/ngrok.yml

  # watch-downloads-copy: auto-copy plain text files from Downloads to clipboard
  chmod +x ~/dotfiles/bin/watch-downloads-copy
  launchctl unload ~/Library/LaunchAgents/com.user.watch-downloads.plist 2>/dev/null
  rm -f ~/Library/LaunchAgents/com.user.watch-downloads.plist
  mkdir -p ~/Library/Scripts/Folder\ Action\ Scripts
  osacompile -o ~/Library/Scripts/Folder\ Action\ Scripts/Copy\ Downloaded\ Text.scpt \
    ~/dotfiles/misc/Copy\ Downloaded\ Text.scpt.applescript
  # Enable Folder Actions and attach script to Downloads
  osascript -e 'tell application "System Events" to set folder actions enabled to true'
  osascript -e '
    tell application "System Events"
      set downloadsPath to (POSIX path of (path to downloads folder))
      set scriptName to "Copy Downloaded Text.scpt"
      set scriptPath to ((path to home folder as text) & "Library:Scripts:Folder Action Scripts:" & scriptName)

      if not (exists folder action downloadsPath) then
        make new folder action at end of folder actions with properties {name:downloadsPath, path:downloadsPath, enabled:true}
      end if

      set fa to folder action downloadsPath
      set enabled of fa to true
      if exists script scriptName of fa then delete script scriptName of fa
      make new script at end of scripts of fa with properties {name:scriptName, path:scriptPath, enabled:true}
    end tell
  '

  # iTerm2: load preferences from custom folder
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/dotfiles/misc"
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true

  # The location of the configuration file for karabiner-elements
  # https://karabiner-elements.pqrs.org/docs/manual/misc/configuration-file-path/
  if [[ "${DOTFILES_PROFILE:-full}" != "minimal" ]]; then
    ln -sfn ~/dotfiles/karabiner ~/.config/karabiner
    if launchctl print gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server &>/dev/null; then
      launchctl kickstart -k gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server
    else
      open -a "Karabiner-Elements"
    fi
  fi
fi

# change shell
sudo chsh -s $(which zsh) $(id -un)

echo "Deploy complete! Run 'exec \$SHELL -l' to reload your shell."
