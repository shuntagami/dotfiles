#!/bin/zsh

set -eu

readonly keychain_service="Supabase MCP"
readonly keychain_account="access-token"
readonly keychain_project_account="project-ref"

save_item() {
  local account="$1" value="$2" comment="$3"
  printf '%s\n%s\n' "$value" "$value" |
    /usr/bin/security add-generic-password \
      -U \
      -a "$account" \
      -s "$keychain_service" \
      -j "$comment" \
      -w
}

echo "Create a long-lived PAT at:"
echo "https://supabase.com/dashboard/account/tokens"
echo "Leave empty to keep the PAT already in Keychain."
echo
read -r -s "token?Supabase PAT: "
echo

if [[ -n "$token" ]]; then
  if [[ ! "$token" =~ '^sbp_[0-9a-f]{40}$' ]]; then
    unset token
    echo "Invalid PAT. Expected a value beginning with sbp_." >&2
    exit 1
  fi
  save_item "$keychain_account" "$token" "Long-lived PAT for local Supabase MCP clients"
  echo "Supabase MCP PAT saved to macOS Keychain."
fi
unset token

echo
echo "Project ref is the 20-character ID in https://<ref>.supabase.co."
echo "Leave empty to keep the project ref already in Keychain."
read -r "project_ref?Supabase project ref: "

if [[ -n "$project_ref" ]]; then
  if [[ ! "$project_ref" =~ '^[a-z0-9]{20}$' ]]; then
    echo "Invalid project ref. Expected 20 lowercase letters or digits." >&2
    exit 1
  fi
  save_item "$keychain_project_account" "$project_ref" "Project ref for local Supabase MCP clients"
  echo "Supabase MCP project ref saved to macOS Keychain."
fi
