#!/bin/zsh

set -eu

token=$(/usr/bin/security find-generic-password -s "Supabase CLI" -w 2>/dev/null)
if [[ -z "$token" ]]; then
  echo "Supabase CLI PAT was not found in macOS Keychain." >&2
  exit 1
fi

export SUPABASE_ACCESS_TOKEN="$token"
unset token

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
exec npx -y @supabase/mcp-server-supabase@latest \
  --project-ref vktggjrrpqoepgsziwsj
