#!/bin/zsh

set -eu

readonly keychain_service="Slack MCP"
readonly keychain_account="user-token"

echo "Slack's hosted MCP server authenticates with a USER token (xoxp-)."
echo "Install the 'Antigravity MCP' app and copy its User OAuth Token from:"
echo "https://api.slack.com/apps/A0C304H1WE9/oauth"
echo
read -r -s "token?Slack user token: "
echo

if [[ ! "$token" =~ '^xoxp-[0-9A-Za-z-]+$' ]]; then
  unset token
  echo "Invalid token. Expected a value beginning with xoxp-." >&2
  exit 1
fi

printf '%s\n%s\n' "$token" "$token" |
  /usr/bin/security add-generic-password \
    -U \
    -a "$keychain_account" \
    -s "$keychain_service" \
    -j "User token for Slack's hosted MCP server (read-only scopes)" \
    -w

unset token
echo "Slack MCP user token saved to macOS Keychain."
