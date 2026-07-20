#!/bin/zsh

# Keep the long-lived Supabase CLI PAT in Keychain and only expose it to apps
# through the per-user launchd environment. The token is never stored here.
token=$(/usr/bin/security find-generic-password -s "Supabase CLI" -w 2>/dev/null)

if [[ -z "$token" ]]; then
  exit 1
fi

/bin/launchctl setenv SUPABASE_ACCESS_TOKEN "$token"
