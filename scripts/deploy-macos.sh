#!/bin/zsh
# App settings used by deploy.sh; legacy system defaults remain in macos.sh.
set -eu
setopt PIPE_FAIL
DOTFILES="${HOME}/dotfiles"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
mkdir -p "$state_dir"

# Reconcile the display-mode brightness policy.
# The installer skips machines where BetterDisplay is not installed.
bash "${DOTFILES}/scripts/macos-betterdisplay.sh"

# App shortcuts live separately from optional system-wide macOS settings.
source "${DOTFILES}/scripts/app-settings-status.sh"
dotfiles_apply_app_settings bash "${DOTFILES}/scripts/macos-aqua-voice.sh"
dotfiles_apply_app_settings bash "${DOTFILES}/scripts/macos-clipy.sh"
# Espanso owns text expansion; retire Raycast and restore Spotlight.
dotfiles_apply_app_settings python3 "${DOTFILES}/scripts/macos-espanso.py"

# Apply the registered Mac mini connection's display policy without interrupting sessions.
node "${DOTFILES}/scripts/jump-desktop-display.mjs" --deploy

# Notifications: which sites may notify in Chrome, and whether macOS lets the
# apps show anything. Idempotent and non-interactive -- it only opens the
# configuration profile when that profile is missing or has changed.
bash "${DOTFILES}/scripts/macos-notifications.sh"

# Keep file associations and CleanShot screenshot shortcuts in sync.
dotfiles_apply_app_settings bash "${DOTFILES}/scripts/macos-default-apps.sh"

# The default browser is selected in Chrome or System Settings.

python3 "${DOTFILES}/scripts/install-user-configs.py" claude-desktop

# git worktree を Spotlight と Time Machine の対象から外す。worktree の置き場所は
# リポジトリが増えるたびに増える (Claude Code は <repo>/.claude/worktrees に作り、
# 置き場所を変える設定が無い) ので、deploy のたびに探し直して当てる。
# 何度実行しても安全 (除外済みはスキップする)。
bash "${DOTFILES}/scripts/exclude-worktrees-from-indexing.sh"

# watch-downloads-copy: auto-copy plain text files from Downloads to clipboard
# The old agent is absent on a fresh Mac, or may already be unloaded.
if [[ -f ~/Library/LaunchAgents/com.user.watch-downloads.plist ]]; then
  launchctl unload ~/Library/LaunchAgents/com.user.watch-downloads.plist 2>/dev/null || true
fi
rm -f ~/Library/LaunchAgents/com.user.watch-downloads.plist
mkdir -p ~/Library/Scripts/Folder\ Action\ Scripts
download_source="${DOTFILES}/misc/Copy Downloaded Text.scpt.applescript"
download_target="${HOME}/Library/Scripts/Folder Action Scripts/Copy Downloaded Text.scpt"
download_signature() {
  shasum -a 256 "$download_source" "$download_target" | shasum -a 256 | cut -d' ' -f1
}
if [[ ! -f "$download_target" || ! -f "$state_dir/download-folder-action.sha256" ]] || \
   [[ "$(<"$state_dir/download-folder-action.sha256")" != "$(download_signature)" ]]; then
  osacompile -o "$download_target" "$download_source"
  download_signature > "$state_dir/download-folder-action.sha256"
fi
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
    if not (exists script scriptName of fa) then
      make new script at end of scripts of fa with properties {name:scriptName, path:scriptPath, enabled:true}
    else
      set enabled of script scriptName of fa to true
    end if
  end tell
'

# iTerm2: load preferences from custom folder
iterm_preferences=$(python3 "${DOTFILES}/scripts/install-user-configs.py" iterm2)
if [[ "$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true)" != "$iterm_preferences" ]]; then
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$iterm_preferences"
fi
if [[ "$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null || true)" != 1 ]]; then
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
fi

# The location of the configuration file for karabiner-elements
# https://karabiner-elements.pqrs.org/docs/manual/misc/configuration-file-path/
if [[ "${DOTFILES_PROFILE:-full}" != "minimal" ]]; then
  python3 "${DOTFILES}/scripts/install-user-configs.py" karabiner
  karabiner_hash=$(shasum -a 256 "$DOTFILES/karabiner/karabiner.json" | cut -d' ' -f1)
  if [[ -d /Applications/Karabiner-Elements.app ]] && {
    [[ ! -f "$state_dir/karabiner.sha256" ]] ||
    [[ "$(<"$state_dir/karabiner.sha256")" != "$karabiner_hash" ]]
  }; then
    if launchctl print gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server &>/dev/null; then
      launchctl kickstart -k gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server
    elif launchctl print gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server &>/dev/null; then
      launchctl kickstart -k gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server
    else
      open -a "Karabiner-Elements"
    fi
    print -r -- "$karabiner_hash" > "$state_dir/karabiner.sha256"
  fi
fi

# Processing Mac (company services). Does nothing unless misc/processing-mac.conf names this
# Mac; then it takes over the services that are not running here yet from the previous Mac,
# after asking (docs/processing-mac.md). A failure here should not undo the rest of the deploy.
bash "${DOTFILES}/scripts/processing-mac.sh" deploy ||
  echo "処理用Macの引き継ぎは終わっていません。docs/processing-mac.md を見て、scripts/processing-mac.sh deploy を実行し直してください。"
