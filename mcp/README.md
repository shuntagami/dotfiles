# MCP configuration

`servers.json` is the canonical MCP server list for local AI clients.
Set `"enabled": false` on a server to keep it in the canonical list without
loading it into Cursor, Codex, Claude Code, or Antigravity.
Add `"clients": ["antigravity"]` to load a server into some clients only; a
server without that key goes to all of them.

Run:

```sh
~/dotfiles/mcp/sync-mcp.mjs
```

`~/dotfiles/scripts/deploy.sh` also runs this sync automatically when Node.js
is available.

This syncs the canonical list to:

- Cursor: `~/dotfiles/mcp/generated/cursor.mcp.json` and `~/.cursor/mcp.json`
- Codex: `~/.codex/config.toml`
- Claude Code: user-scope MCP entries in `~/.claude.json`
- Antigravity (`agy`): `~/.gemini/config/mcp_config.json`

Antigravity uses its own schema: stdio servers keep `command` / `args` / `env`,
and remote servers use `serverUrl` (plus `headers`) instead of `url`. The sync
rewrites entries it owns and leaves any server added directly with
`agy mcp add` in place.

`~/.gemini` on its own does not mean Antigravity is installed — Gemini CLI keeps
its user settings there too — so the sync looks for `agy` on `PATH` or one of
`~/.gemini/antigravity{,-cli,-ide}`, and otherwise skips with a warning. The same
file backs both the `agy` CLI and the Antigravity IDE, which reads it through
`~/.gemini/antigravity/mcp_config.json`. The IDE creates that link itself on
first run; the sync only fills in a missing one and never replaces an existing
file there.

Secrets are not committed. Prefer each service's official OAuth connector or
tool-specific local config over storing tokens for MCP servers in dotfiles.

Supabase uses the local stdio MCP server with a long-lived PAT stored in a
dedicated `Supabase MCP` item in macOS Keychain. Configure or rotate it with:

```sh
~/dotfiles/mcp/setup-supabase-mcp-auth.sh
```

`run-supabase-mcp.sh` reads the PAT when the MCP server starts and exposes it
only to that child process, so clients do not need to inherit a global
`SUPABASE_ACCESS_TOKEN` environment variable. The dedicated Keychain item keeps
the secret out of dotfiles and avoids browser OAuth session expiry.

Slack is split by client, because only some of them have an official
integration.

Codex and Claude Code use their own plugins and are excluded from this entry via
`"clients": ["antigravity"]`:

- Codex enables `slack@openai-curated` in `~/dotfiles/codex/config.toml`
- Claude Code enables `slack@claude-plugins-official` in
  `~/dotfiles/claude/settings.json`

Antigravity has no such plugin, so it talks to Slack's hosted MCP server at
`https://mcp.slack.com/mcp` directly. That server only accepts a **user** token
(`xoxp-`); a bot token is rejected with `invalid_token_type`, and it offers no
dynamic client registration, so Antigravity cannot run the OAuth flow itself.
The token therefore comes from a dedicated Slack app:

- app: `Antigravity MCP` (`A0C304H1WE9`) in the ELE workspace
- all 30 user scopes the hosted server supports, read and write, each marked
  required so a reinstall actually requests it; no bot scopes at all
- `Features > Agents > Slack Model Context Protocol (MCP) Server` must be
  toggled on, or the server answers `App is not enabled for Slack MCP server
  access`
- that yields 27 tools, including `slack_send_message`, list/canvas edits and
  file uploads

Because this is a user token, there is no bot and nothing is invited to any
channel: Antigravity sees exactly what the user sees, and anything it writes is
posted as the user. Scopes come from the list that
`https://mcp.slack.com/.well-known/oauth-authorization-server` advertises, so
that endpoint is the source of truth when Slack adds more.

Configure or rotate the token with:

```sh
~/dotfiles/mcp/setup-slack-mcp-auth.sh
```

`headersFromKeychain` in `servers.json` names the Keychain item instead of the
secret, and the sync resolves it at write time.

Only Antigravity's config can hold a resolved secret, and the sync enforces
that: Cursor's and Codex's configs are files in this repository and Claude Code
keeps its own, so a server carrying `headersFromKeychain` is skipped for them
with a warning rather than written out. `~/.gemini/config/mcp_config.json` is
not in git and is written — and re-chmodded on every sync — as `0600`, because
`writeFileSync` only applies a mode when it creates the file. If the Keychain
item is missing, that server is skipped with a warning rather than written
without auth.
