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
if [[ -e ~/.finicky.js && ! -L ~/.finicky.js ]]; then
  mv ~/.finicky.js ~/.finicky.js.bak.$(date +%Y%m%d%H%M%S)
fi
ln -sf ~/dotfiles/.finicky.js ~/.finicky.js
mkdir -p ~/.docker
ln -sf ~/dotfiles/misc/docker-config.json ~/.docker/config.json
mkdir -p ~/.local/state/crossnote
ln -sf ~/dotfiles/misc/crossnote/parser.js ~/.local/state/crossnote/parser.js
ln -sf ~/dotfiles/misc/crossnote/style.less ~/.local/state/crossnote/style.less

# Codex: config.toml includes standard Codex settings such as installed plugins.
mkdir -p ~/.codex
if [[ -e ~/.codex/config.toml && ! -L ~/.codex/config.toml ]]; then
  mv ~/.codex/config.toml ~/.codex/config.toml.bak.$(date +%Y%m%d%H%M%S)
fi
ln -sf ~/dotfiles/codex/config.toml ~/.codex/config.toml

# Codex skills: symlink each repository-managed skill directory.
mkdir -p ~/.codex/skills
for skill_dir in "${HOME}"/dotfiles/codex/skills/*(/N); do
  skill_target=~/.codex/skills/"${skill_dir:t}"
  if [[ -e "${skill_target}" && ! -L "${skill_target}" ]]; then
    echo "Skipping Codex skill ${skill_dir:t}: ${skill_target} exists and is not a symlink."
    continue
  fi
  ln -sfn "${skill_dir}" "${skill_target}"
done

# Claude Code: settings.json includes standard Claude Code settings such as enabled plugins.
mkdir -p ~/.claude
if [[ -e ~/.claude/settings.json && ! -L ~/.claude/settings.json ]]; then
  mv ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d%H%M%S)
fi
ln -sf ~/dotfiles/claude/settings.json ~/.claude/settings.json

# Claude Code skills: symlink each skill directory. RIFE binary for vfr-sync-rife
# is not in git; fetch it once with claude/skills/vfr-sync-rife/scripts/install_rife.sh
mkdir -p ~/.claude/skills
for skill_dir in "${HOME}"/dotfiles/claude/skills/*(/N); do
  ln -sfn "${skill_dir}" ~/.claude/skills/"${skill_dir:t}"
done

# Screenpipe: manage only prompt/config files that are safe to keep in dotfiles.
# Databases, recordings, logs, outputs, and connection secrets stay under ~/.screenpipe.
if [[ -d "${HOME}/dotfiles/screenpipe/pipes" ]]; then
  mkdir -p "${HOME}/.screenpipe/pipes"
  for pipe_md in "${HOME}"/dotfiles/screenpipe/pipes/*/pipe.md(.N); do
    pipe_name="${pipe_md:h:t}"
    mkdir -p "${HOME}/.screenpipe/pipes/${pipe_name}"
    ln -sf "${pipe_md}" "${HOME}/.screenpipe/pipes/${pipe_name}/pipe.md"
  done
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
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# Back up a pre-existing real config so it can be merged into config.local by hand.
if [[ -e ~/.ssh/config && ! -L ~/.ssh/config ]]; then
  mv ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S)
fi
ln -sf ~/dotfiles/misc/ssh/config ~/.ssh/config
chmod 600 ~/dotfiles/misc/ssh/config
# Per-machine / sensitive host entries (Include'd by the tracked config, not tracked)
if [[ ! -f ~/.ssh/config.local ]]; then
  touch ~/.ssh/config.local && chmod 600 ~/.ssh/config.local
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  # Finicky is the system URL router: Discord links go to Chrome and all other
  # links fall through to Dia according to ~/.finicky.js.
  if command -v defaultbrowser >/dev/null 2>&1 && [[ -d /Applications/Finicky.app ]]; then
    open -g -a Finicky
    defaultbrowser finicky
  fi

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
