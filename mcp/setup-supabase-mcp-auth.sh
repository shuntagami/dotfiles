#!/bin/zsh

set -eu

readonly keychain_service="Supabase MCP"
readonly keychain_account="access-token"

echo "Create a long-lived PAT at:"
echo "https://supabase.com/dashboard/account/tokens"
echo
read -r -s "token?Supabase PAT: "
echo

if [[ ! "$token" =~ '^sbp_[0-9a-f]{40}$' ]]; then
  unset token
  echo "Invalid PAT. Expected a value beginning with sbp_." >&2
  exit 1
fi

printf '%s\n%s\n' "$token" "$token" |
  /usr/bin/security add-generic-password \
    -U \
    -a "$keychain_account" \
    -s "$keychain_service" \
    -j "Long-lived PAT for local Supabase MCP clients" \
    -w

unset token
echo "Supabase MCP PAT saved to macOS Keychain."
