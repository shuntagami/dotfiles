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

# Cursor: merge our sound hook without overwriting hooks registered by other apps.
python3 ~/dotfiles/scripts/install-cursor-notify.py

# MulmoTerminal: config.json is written by the app itself (write-temp-then-rename), so a
# symlink here would get replaced by a real file the moment it saves. Seed it only when
# missing — on an already-configured machine this must never overwrite live settings that
# have not been copied back with save-mulmoterminal-config.sh.
if [[ ! -f ~/.mulmoterminal/config.json ]]; then
  ~/dotfiles/scripts/install-mulmoterminal-config.sh
fi

# Screenpipe: manage only prompt/config files that are safe to keep in dotfiles.
# Databases, recordings, logs, outputs, and connection secrets stay under ~/.screenpipe.
if [[ -d "${HOME}/dotfiles/screenpipe/pipes" ]]; then
  mkdir -p "${HOME}/.screenpipe/pipes"
  for pipe_md in "${HOME}"/dotfiles/screenpipe/pipes/*/pipe.md(.N); do
    pipe_name="${pipe_md:h:t}"
    mkdir -p "${HOME}/.screenpipe/pipes/${pipe_name}"
    ln -sf "${pipe_md}" "${HOME}/.screenpipe/pipes/${pipe_name}/pipe.md"
    for pipe_extension in "${pipe_md:h}"/extensions/*.ts(.N); do
      mkdir -p "${HOME}/.screenpipe/pipes/${pipe_name}/.pi/extensions"
      ln -sf "${pipe_extension}" "${HOME}/.screenpipe/pipes/${pipe_name}/.pi/extensions/${pipe_extension:t}"
    done
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
  # Rebuild and reload the display-mode brightness policy on each deploy.
  # The installer skips machines where MonitorControl is not installed.
  bash "${HOME}/dotfiles/scripts/macos-monitorcontrol.sh"

  # Apply the registered Mac mini connection's display policy without interrupting sessions.
  if command -v node >/dev/null 2>&1; then
    node "${HOME}/dotfiles/scripts/jump-desktop-display.mjs" --deploy
  fi

  # No URL router here any more, and no default-browser step either.
  #
  # Finicky used to sit here: it was registered as the system handler, then sent
  # Discord links to Chrome and everything else to Dia. Both are out of use, and
  # the indirection was not free -- a browser kept alive in the background still
  # holds its global keyboard shortcuts, which is how Dia's profile switcher
  # swallowed Cmd+Shift+P while Chrome was in front.
  #
  # The default browser is not set from here because it CANNOT be, on this OS.
  # `defaultbrowser` (the Homebrew CLI the old block used) reads nothing on
  # macOS 26: every browser in its listing comes back unmarked even when
  # LaunchServices has a handler registered, and its write is silent. macOS
  # wants the request to come from the browser itself, so this is a one-time
  # click -- Chrome's own "make default" prompt, or System Settings > Desktop &
  # Dock > Default web browser. Doing it here would only look declarative.

  if [[ "${DOTFILES_PROFILE:-full}" != "minimal" ]]; then
    ln -sfn ~/dotfiles/hammerspoon ~/.hammerspoon
  fi
  mkdir -p ~/Library/Application\ Support/Claude
  ln -sf ~/dotfiles/misc/claude_desktop_config.json ~/Library/Application\ Support/Claude/claude_desktop_config.json
  mkdir -p ~/.config/memo
  ln -sf ~/dotfiles/misc/memo-config.toml ~/.config/memo/config.toml
  mkdir -p ~/Library/Application\ Support/ngrok
  ln -sf ~/dotfiles/misc/ngrok.yml ~/Library/Application\ Support/ngrok/ngrok.yml

  # git worktree を Spotlight と Time Machine の対象から外す。worktree の置き場所は
  # リポジトリが増えるたびに増える (Claude Code は <repo>/.claude/worktrees に作り、
  # 置き場所を変える設定が無い) ので、deploy のたびに探し直して当てる。
  # 何度実行しても安全 (除外済みはスキップする)。
  bash ~/dotfiles/scripts/exclude-worktrees-from-indexing.sh

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
