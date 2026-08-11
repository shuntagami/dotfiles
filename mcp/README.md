# MCP configuration

`servers.json` is the canonical MCP server list for local AI clients.
Set `"enabled": false` on a server to keep it in the canonical list without
loading it into Cursor, Codex, or Claude Code.

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

Slack is not configured as a local MCP server. Codex uses the official
`slack@openai-curated` plugin instead, enabled in `~/dotfiles/codex/config.toml`,
so it can authenticate through the connected Slack app integration rather than a
local bot-token MCP wrapper.

Claude Code uses official Slack integration paths too:

- `~/dotfiles/claude/settings.json` enables `slack@claude-plugins-official`
- the plugin bundles Slack's hosted MCP server at `https://mcp.slack.com/mcp`
- a connected `claude.ai Slack` MCP can also be used when authenticated
