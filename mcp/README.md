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

Secrets are not committed. Local secret files live in `~/dotfiles/mcp` and are
symlinked into `~/.config/mcp`.

For Slack:

```sh
cp ~/dotfiles/mcp/slack.env.example ~/dotfiles/mcp/slack.env
chmod 600 ~/dotfiles/mcp/slack.env
~/dotfiles/scripts/deploy.sh
```
