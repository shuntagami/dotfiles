#!/usr/bin/env node

// Overlay display preferences on an existing connection; never copy credentials into git.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const booleanKeys = new Set([
  'UseVirtualMonitors', 'MatchScreenResolution', 'ChangeResolution',
  'UseDynamicResolutionUpdate', 'UseHIDPIResolution', 'StartInFullscreen',
]);

export function validatePolicy(policy) {
  if (!policy || typeof policy.displayName !== 'string' || !policy.displayName.trim()
      || !policy.settings || Array.isArray(policy.settings)
      || typeof policy.settings !== 'object' || !Object.keys(policy.settings).length) {
    throw new Error('Policy requires displayName and nonempty settings.');
  }
  for (const [key, value] of Object.entries(policy.settings)) {
    if (booleanKeys.has(key) && typeof value === 'boolean') continue;
    if (key === 'NumberOfVirtualMonitors' && value === 1) continue;
    throw new Error(`Unsupported display setting or value: ${key}`);
  }
}

export function mergeDisplaySettings(connection, policy) {
  validatePolicy(policy);
  if (connection.DisplayName !== policy.displayName) return null;
  // Refuse a different protocol/schema rather than modifying a similarly named connection.
  for (const key of Object.keys(policy.settings)) {
    if (!Object.hasOwn(connection, key)) throw new Error(`Connection is missing ${key}; check Jump Desktop's version.`);
  }
  return { ...connection, ...policy.settings };
}

function viewerRunning() {
  const result = spawnSync('/usr/bin/pgrep', ['-f', '/Jump Desktop.app/Contents/MacOS/Jump Desktop'], { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0 && result.status !== 1) throw new Error('Unable to check Jump Desktop process.');
  return result.status === 0;
}

function main() {
  const flags = process.argv.slice(2);
  if (flags.includes('--help')) {
    console.log('Usage: node scripts/jump-desktop-display.mjs [--check | --quit | --deploy]\n'
      + 'Default: apply while Jump Desktop is closed. --check: inspect only.\n'
      + '--quit: quit and reopen the viewer to apply (disconnects sessions).\n'
      + '--deploy: skip if the viewer is running or the connection is not registered.');
    return;
  }
  if (flags.length > 1 || flags.some(flag => !['--check', '--quit', '--deploy'].includes(flag))) {
    throw new Error('Invalid arguments; use --help.');
  }
  if (process.platform !== 'darwin') {
    if (flags.includes('--deploy')) return;
    throw new Error('This script manages the macOS Jump Desktop viewer.');
  }
  const policyPath = fileURLToPath(new URL('../misc/jump-desktop/display.json', import.meta.url));
  const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));
  validatePolicy(policy);
  const serversDir = path.join(os.homedir(), 'Documents/JumpDesktop/Viewer/Servers');
  const findTarget = () => {
    const entries = fs.existsSync(serversDir) ? fs.readdirSync(serversDir) : [];
    const matches = entries.filter(name => name.endsWith('.jump')).map(name => {
      const filename = path.join(serversDir, name);
      return { filename, connection: JSON.parse(fs.readFileSync(filename, 'utf8')) };
    }).filter(({ connection }) => connection.DisplayName === policy.displayName);
    if (matches.length > 1) throw new Error('Multiple matching connections; use a unique displayName in the policy.');
    return matches[0];
  };
  let target = findTarget();
  if (!target) {
    const message = `Connection "${policy.displayName}" is not registered in ${serversDir}. Sign in to Jump Desktop first.`;
    if (flags.includes('--deploy')) { console.log(`Skipping: ${message}`); return; }
    throw new Error(message);
  }
  const differences = connection => Object.keys(policy.settings).filter(key => connection[key] !== policy.settings[key]);
  mergeDisplaySettings(target.connection, policy); // Validate before stopping any application.
  if (flags.includes('--check')) {
    console.log(JSON.stringify({ displayName: policy.displayName,
      settings: Object.fromEntries(Object.keys(policy.settings).map(key => [key, target.connection[key]])),
      differingKeys: differences(target.connection) }, null, 2));
    if (differences(target.connection).length) process.exitCode = 1;
    return;
  }
  const wasRunning = viewerRunning();
  if (wasRunning && !flags.includes('--quit')) {
    const message = 'Jump Desktop is running. Close it and run jump-display-apply, or use jump-display-apply --quit.';
    if (flags.includes('--deploy')) { console.log(`Skipping: ${message}`); return; }
    throw new Error(message);
  }
  try {
    if (wasRunning) {
      execFileSync('/usr/bin/osascript', ['-e', 'tell application "Jump Desktop" to quit'], { timeout: 15000 });
      const deadline = Date.now() + 10000;
      while (viewerRunning() && Date.now() < deadline) {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
      }
      if (viewerRunning()) throw new Error('Jump Desktop did not quit; settings were not written.');
    }
    // The app saves on quit; read the final file again so other changes are preserved.
    target = findTarget();
    if (!target) throw new Error('Connection disappeared while quitting.');
    const merged = mergeDisplaySettings(target.connection, policy);
    const changed = differences(target.connection);
    if (!changed.length) { console.log('Jump Desktop display settings already match dotfiles.'); return; }
    if (viewerRunning()) throw new Error('Jump Desktop restarted; settings were not written.');
    const backupRoot = path.join(os.homedir(), 'Library/Application Support/dotfiles/backups/jump-desktop');
    fs.mkdirSync(backupRoot, { recursive: true, mode: 0o700 });
    const backupDir = fs.mkdtempSync(path.join(backupRoot, 'display-'));
    const backup = path.join(backupDir, path.basename(target.filename));
    fs.copyFileSync(target.filename, backup, fs.constants.COPYFILE_EXCL);
    fs.chmodSync(backup, 0o600);
    const staging = fs.mkdtempSync(path.join(serversDir, '.dotfiles-display-'));
    try {
      const temporary = path.join(staging, 'connection.jump');
      fs.writeFileSync(temporary, JSON.stringify(merged, null, 2) + '\n', { mode: 0o600 });
      fs.renameSync(temporary, target.filename);
    } finally {
      fs.rmSync(staging, { recursive: true, force: true });
    }
    if (differences(JSON.parse(fs.readFileSync(target.filename, 'utf8'))).length) throw new Error('Verification failed.');
    console.log(`Applied: ${changed.join(', ')}\nBackup: ${backup}`);
  } finally {
    if (wasRunning && !viewerRunning()) execFileSync('/usr/bin/open', ['-g', '-a', 'Jump Desktop']);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { main(); } catch (error) { console.error(`Error: ${error.message}`); process.exitCode = 1; }
}
