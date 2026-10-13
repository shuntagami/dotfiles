# Shared Bash/Zsh handling for an app's first-launch/restart requirement.
# Exit 3 means a user action remains; real configuration failures still stop deploy.
dotfiles_apply_app_settings() {
  if "$@"; then
    return 0
  else
    local app_settings_result=$?
    if [[ "${app_settings_result}" -eq 3 ]]; then
      echo "Warning: app launch/restart required; continuing dotfiles deployment."
      return 0
    fi
    return "${app_settings_result}"
  fi
}
