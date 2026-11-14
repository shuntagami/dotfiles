#!/bin/zsh

set -eu

readonly keychain_service="Supabase MCP"
readonly keychain_account="access-token"
readonly keychain_project_account="project-ref"

token=$(
  /usr/bin/security find-generic-password \
    -s "$keychain_service" \
    -a "$keychain_account" \
    -w 2>/dev/null
)

if [[ ! "$token" =~ '^sbp_[0-9a-f]{40}$' ]]; then
  echo "A valid Supabase PAT was not found in macOS Keychain." >&2
  echo "Run ~/dotfiles/mcp/setup-supabase-mcp-auth.sh to configure it." >&2
  exit 1
fi

project_ref=$(
  /usr/bin/security find-generic-password \
    -s "$keychain_service" \
    -a "$keychain_project_account" \
    -w 2>/dev/null
) || project_ref=""

if [[ ! "$project_ref" =~ '^[a-z0-9]{20}$' ]]; then
  echo "A valid Supabase project ref was not found in macOS Keychain." >&2
  echo "Run ~/dotfiles/mcp/setup-supabase-mcp-auth.sh to configure it." >&2
  exit 1
fi

export SUPABASE_ACCESS_TOKEN="$token"
unset token

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
exec npx -y @supabase/mcp-server-supabase@latest \
  --project-ref "$project_ref"
