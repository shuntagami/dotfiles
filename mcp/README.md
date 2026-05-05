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

- Cursor: `~/dotfiles/vscode/mcp.json` and `~/.cursor/mcp.json`
- Codex: `~/.codex/config.toml`
- Claude Code: user-scope MCP entries in `~/.claude.json`

Secrets are not stored in dotfiles. Local secret files live under `~/.config/mcp`.

For Slack:

```sh
mkdir -p ~/.config/mcp
cp ~/dotfiles/mcp/slack.env.example ~/.config/mcp/slack.env
chmod 600 ~/.config/mcp/slack.env
```
