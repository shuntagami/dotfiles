#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const home = os.homedir();
const dotfiles = path.join(home, "dotfiles");
const sourcePath = path.join(dotfiles, "mcp", "servers.json");
const cursorPath = path.join(dotfiles, "mcp", "generated", "cursor.mcp.json");
const cursorGlobalPath = path.join(home, ".cursor", "mcp.json");
const codexConfigPath = path.join(home, ".codex", "config.toml");
const geminiHome = path.join(home, ".gemini");
const antigravityConfigPath = path.join(geminiHome, "config", "mcp_config.json");
// ~/.gemini alone means nothing: Gemini CLI keeps its user settings there too.
const antigravityMarkers = [
  path.join(geminiHome, "antigravity"),
  path.join(geminiHome, "antigravity-cli"),
  path.join(geminiHome, "antigravity-ide"),
];
const antigravityIdeConfigPath = path.join(geminiHome, "antigravity", "mcp_config.json");

const source = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
const servers = source.mcpServers ?? {};
const enabledServers = Object.fromEntries(
  Object.entries(servers).filter(([, config]) => config.enabled !== false),
);

function publicServerConfig(config) {
  const { codex, claude, cursor, antigravity, clients, headersFromKeychain, enabled, ...rest } = config;
  return rest;
}

// Cursor and Codex configs live in this repository and Claude Code keeps its own
// file, so a resolved Keychain secret must never be rendered for them.
const secretSafeClients = new Set(["antigravity"]);

function serversFor(client) {
  return Object.fromEntries(
    Object.entries(enabledServers).filter(([name, config]) => {
      if (Array.isArray(config.clients) && !config.clients.includes(client)) return false;
      if (config.headersFromKeychain && !secretSafeClients.has(client)) {
        console.warn(`${client} config cannot hold secrets; skipped MCP server: ${name}`);
        return false;
      }
      return true;
    }),
  );
}

// `mode` is applied to existing files too: writeFileSync only honours it when
// it creates the file, and a config holding a token must not stay world-readable.
function writeJson(filePath, data, { mode } = {}) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`, mode ? { mode } : undefined);
  if (mode) fs.chmodSync(filePath, mode);
}

function tomlString(value) {
  return JSON.stringify(value);
}

function tomlArray(values) {
  return `[${values.map(tomlString).join(", ")}]`;
}

function codexBlock(name, config) {
  const lines = [`[mcp_servers.${name}]`];
  if (config.url) {
    lines.push(`url = ${tomlString(config.url)}`);
  } else {
    lines.push(`command = ${tomlString(config.command)}`);
    if (Array.isArray(config.args) && config.args.length > 0) {
      lines.push(`args = ${tomlArray(config.args)}`);
    }
  }
  if (config.enabled === false) {
    lines.push("enabled = false");
  }
  if (config.env && Object.keys(config.env).length > 0) {
    lines.push("");
    lines.push(`[mcp_servers.${name}.env]`);
    for (const [key, value] of Object.entries(config.env)) {
      lines.push(`${key} = ${tomlString(value)}`);
    }
  }
  if (config.codex?.tools) {
    for (const [toolName, toolConfig] of Object.entries(config.codex.tools)) {
      lines.push("");
      lines.push(`[mcp_servers.${name}.tools.${toolName}]`);
      for (const [key, value] of Object.entries(toolConfig)) {
        lines.push(`${key} = ${tomlString(value)}`);
      }
    }
  }
  return lines.join("\n");
}

function syncCursor() {
  writeJson(cursorPath, {
    mcpServers: Object.fromEntries(
      Object.entries(serversFor("cursor")).map(([name, config]) => [
        name,
        publicServerConfig(config),
      ]),
    ),
  });

  fs.mkdirSync(path.dirname(cursorGlobalPath), { recursive: true });
  try {
    const current = fs.lstatSync(cursorGlobalPath);
    if (!current.isSymbolicLink()) {
      fs.renameSync(cursorGlobalPath, `${cursorGlobalPath}.backup-${Date.now()}`);
    } else if (fs.readlinkSync(cursorGlobalPath) !== cursorPath) {
      fs.unlinkSync(cursorGlobalPath);
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  try {
    fs.lstatSync(cursorGlobalPath);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    fs.symlinkSync(cursorPath, cursorGlobalPath);
  }
}

function syncCodex() {
  fs.mkdirSync(path.dirname(codexConfigPath), { recursive: true });
  let config = fs.existsSync(codexConfigPath) ? fs.readFileSync(codexConfigPath, "utf8") : "";
  const lines = config.split("\n");
  const kept = [];
  let skipping = false;
  let insertedManagedBlocks = false;
  const managedServerNames = new Set(Object.keys(servers));
  const renderedManagedBlocks = Object.entries(serversFor("codex"))
    .map(([name, config]) => codexBlock(name, config))
    .join("\n\n");
  for (const line of lines) {
    const mcpTable = line.match(/^\[mcp_servers\.([^\.\]]+)/);
    if (mcpTable) {
      skipping = managedServerNames.has(mcpTable[1]);
      if (skipping && !insertedManagedBlocks) {
        kept.push(renderedManagedBlocks, "");
        insertedManagedBlocks = true;
      }
    } else if (line.match(/^\[/)) {
      skipping = false;
    }
    if (!skipping) kept.push(line);
  }

  const base = kept.join("\n").replace(/\n{3,}/g, "\n\n").trimEnd();
  const nextConfig = insertedManagedBlocks
    ? base
    : `${base}\n\n${renderedManagedBlocks}`;
  fs.writeFileSync(codexConfigPath, `${nextConfig}\n`);
}

function keychainSecret({ service, account }) {
  const result = spawnSync("/usr/bin/security", ["find-generic-password", "-s", service, "-a", account, "-w"], {
    encoding: "utf8",
  });
  if (result.status !== 0) return null;
  return result.stdout.trim() || null;
}

// Resolved secrets are only ever written to ~/.gemini, which is not in git.
function resolveKeychainHeaders(config) {
  const headers = {};
  for (const [name, source] of Object.entries(config.headersFromKeychain ?? {})) {
    const secret = keychainSecret(source);
    if (!secret) return null;
    headers[name] = `${source.prefix ?? ""}${secret}`;
  }
  return headers;
}

function antigravityServerConfig(config) {
  const { type, url, headers, command, args, env } = publicServerConfig(config);
  if (url) {
    const remote = { serverUrl: url };
    const keychainHeaders = resolveKeychainHeaders(config);
    if (keychainHeaders === null) return null;
    const allHeaders = { ...headers, ...keychainHeaders };
    if (Object.keys(allHeaders).length > 0) remote.headers = allHeaders;
    return remote;
  }
  const local = { command };
  if (Array.isArray(args) && args.length > 0) local.args = args;
  if (env && Object.keys(env).length > 0) local.env = env;
  return local;
}

function commandExists(name) {
  return (process.env.PATH ?? "")
    .split(path.delimiter)
    .filter(Boolean)
    .some((dir) => {
      try {
        fs.accessSync(path.join(dir, name), fs.constants.X_OK);
        return true;
      } catch {
        return false;
      }
    });
}

function syncAntigravity() {
  const installed = antigravityMarkers.some((marker) => fs.existsSync(marker)) || commandExists("agy");
  if (!installed) {
    console.warn("Antigravity not found; skipped Antigravity MCP sync");
    return;
  }

  let current = { mcpServers: {} };
  if (fs.existsSync(antigravityConfigPath)) {
    const raw = fs.readFileSync(antigravityConfigPath, "utf8").trim();
    if (raw) current = JSON.parse(raw);
  }

  const managedServerNames = new Set(Object.keys(servers));
  const unmanaged = Object.entries(current.mcpServers ?? {}).filter(
    ([name]) => !managedServerNames.has(name),
  );
  const managed = Object.entries(serversFor("antigravity"))
    .map(([name, config]) => {
      const resolved = antigravityServerConfig(config);
      if (resolved === null) {
        console.warn(`missing Keychain secret; skipped Antigravity MCP server: ${name}`);
      }
      return [name, resolved];
    })
    .filter(([, resolved]) => resolved !== null);

  writeJson(
    antigravityConfigPath,
    { ...current, mcpServers: Object.fromEntries([...unmanaged, ...managed]) },
    { mode: 0o600 },
  );

  // The IDE reads its own copy. It creates this link itself on first run, so only
  // fill in a missing one; an existing file is the app's to manage.
  if (fs.existsSync(path.dirname(antigravityIdeConfigPath)) && !fs.existsSync(antigravityIdeConfigPath)) {
    fs.symlinkSync(antigravityConfigPath, antigravityIdeConfigPath);
  }
}

function syncClaude() {
  const claude = spawnSync("claude", ["--version"], { encoding: "utf8" });
  if (claude.status !== 0) {
    console.warn("claude command not found; skipped Claude Code MCP sync");
    return;
  }

  for (const name of Object.keys(servers)) {
    spawnSync("claude", ["mcp", "remove", "--scope", "user", name], {
      encoding: "utf8",
    });
  }

  for (const [name, config] of Object.entries(serversFor("claude"))) {
    const payload = JSON.stringify(publicServerConfig(config));
    const result = spawnSync("claude", ["mcp", "add-json", "--scope", "user", name, payload], {
      encoding: "utf8",
    });
    if (result.status !== 0) {
      process.stderr.write(result.stderr || result.stdout);
      throw new Error(`failed to sync Claude Code MCP server: ${name}`);
    }
  }
}

syncCursor();
syncCodex();
syncClaude();
syncAntigravity();

const disabledCount = Object.keys(servers).length - Object.keys(enabledServers).length;
console.log(
  `Synced ${Object.keys(enabledServers).length} enabled MCP servers to Cursor, Codex, Claude Code, and Antigravity (${disabledCount} disabled in source).`,
);
