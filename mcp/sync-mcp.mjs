#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const home = os.homedir();
const dotfiles = path.join(home, "dotfiles");
const sourcePath = path.join(dotfiles, "mcp", "servers.json");
const cursorPath = path.join(dotfiles, "vscode", "mcp.json");
const cursorGlobalPath = path.join(home, ".cursor", "mcp.json");
const codexConfigPath = path.join(home, ".codex", "config.toml");

const source = JSON.parse(fs.readFileSync(sourcePath, "utf8"));
const servers = source.mcpServers ?? {};
const enabledServers = Object.fromEntries(
  Object.entries(servers).filter(([, config]) => config.enabled !== false),
);

function publicServerConfig(config) {
  const { codex, claude, cursor, enabled, ...rest } = config;
  return rest;
}

function writeJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(data, null, 2)}\n`);
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
      Object.entries(enabledServers).map(([name, config]) => [name, publicServerConfig(config)]),
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
  for (const line of lines) {
    if (line.match(/^\[mcp_servers(?:\.|\])/)) {
      skipping = true;
      continue;
    }
    if (skipping && line.match(/^\[/)) {
      skipping = false;
    }
    if (!skipping) kept.push(line);
  }

  const base = kept.join("\n").replace(/\n{3,}/g, "\n\n").trimEnd();
  const blocks = Object.entries(enabledServers).map(([name, config]) => codexBlock(name, config));
  fs.writeFileSync(codexConfigPath, `${base}\n\n${blocks.join("\n\n")}\n`);
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

  for (const [name, config] of Object.entries(enabledServers)) {
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

const disabledCount = Object.keys(servers).length - Object.keys(enabledServers).length;
console.log(
  `Synced ${Object.keys(enabledServers).length} enabled MCP servers to Cursor, Codex, and Claude Code (${disabledCount} disabled in source).`,
);
