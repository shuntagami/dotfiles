#!/usr/bin/env node

// Overlay display preferences on existing connections; never copy credentials into git.
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
  const names = policy?.displayNames;
  if (!Array.isArray(names) || !names.length
      || names.some(name => typeof name !== 'string' || !name.trim())
      || new Set(names).size !== names.length) {
    throw new Error('Policy requires displayNames: a nonempty list of unique connection names.');
  }
  if (!policy.settings || Array.isArray(policy.settings)
      || typeof policy.settings !== 'object' || !Object.keys(policy.settings).length) {
    throw new Error('Policy requires nonempty settings.');
  }
  for (const [key, value] of Object.entries(policy.settings)) {
    if (booleanKeys.has(key) && typeof value === 'boolean') continue;
    if (key === 'NumberOfVirtualMonitors' && value === 1) continue;
    throw new Error(`Unsupported display setting or value: ${key}`);
  }
}

export function mergeDisplaySettings(connection, policy) {
  validatePolicy(policy);
  if (!policy.displayNames.includes(connection.DisplayName)) return null;
  // Refuse a different protocol/schema rather than modifying a similarly named connection.
  for (const key of Object.keys(policy.settings)) {
    if (!Object.hasOwn(connection, key)) throw new Error(`Connection is missing ${key}; check Jump Desktop's version.`);
  }
  return { ...connection, ...policy.settings };
}

export function differingKeys(connection, policy) {
  return Object.keys(policy.settings).filter(key => connection[key] !== policy.settings[key]);
}

// Picks the live session to repair: the named one, or the only policy connection with a window.
export function chooseFixTarget(policy, windowNames, requested) {
  if (requested) {
    if (!policy.displayNames.includes(requested)) throw new Error(`"${requested}" is not in displayNames.`);
    return requested;
  }
  const open = policy.displayNames.filter(name => windowNames.includes(name));
  if (open.length === 1) return open[0];
  if (!open.length) throw new Error(`No session window for ${policy.displayNames.join(' or ')}. Connect first.`);
  throw new Error(`Several sessions are open (${open.join(', ')}); run with --fix <name>.`);
}

function viewerRunning() {
  const result = spawnSync('/usr/bin/pgrep', ['-f', '/Jump Desktop.app/Contents/MacOS/Jump Desktop'], { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0 && result.status !== 1) throw new Error('Unable to check Jump Desktop process.');
  return result.status === 0;
}

function viewerWindowNames() {
  if (!viewerRunning()) return [];
  const output = execFileSync('/usr/bin/osascript', ['-e',
    'tell application "System Events" to tell process "Jump Desktop" to get name of every window'],
  { encoding: 'utf8', timeout: 15000 });
  return output.trim().split(', ').filter(Boolean);
}

function main() {
  const args = process.argv.slice(2);
  const [flag, fixName] = args;
  if (args.includes('--help')) {
    console.log('Usage: node scripts/jump-desktop-display.mjs [--check | --fix [name] | --quit | --deploy]\n'
      + 'Default: apply to every registered connection in displayNames while Jump Desktop is closed.\n'
      + '--check: inspect only.\n'
      + '--fix: reapply Single Virtual Display and Fit In Window to the live session\n'
      + '       (the open one among displayNames, or the named one).\n'
      + '--quit: quit and reopen the viewer to apply (disconnects sessions; skipped when nothing differs).\n'
      + '--deploy: skip if the viewer is running or no connection is registered.');
    return;
  }
  const validArgs = args.length === 0
    || (args.length === 1 && ['--check', '--fix', '--quit', '--deploy'].includes(flag))
    || (args.length === 2 && flag === '--fix' && !fixName.startsWith('--'));
  if (!validArgs) throw new Error('Invalid arguments; use --help.');
  if (process.platform !== 'darwin') {
    if (flag === '--deploy') return;
    throw new Error('This script manages the macOS Jump Desktop viewer.');
  }
  const policyPath = fileURLToPath(new URL('../misc/jump-desktop/display.json', import.meta.url));
  const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));
  validatePolicy(policy);
  if (flag === '--fix') {
    const targetName = chooseFixTarget(policy, viewerWindowNames(), fixName);
    const script = fileURLToPath(new URL('./jump-desktop-display-fix.applescript', import.meta.url));
    const output = execFileSync('/usr/bin/osascript', [script, targetName], {
      encoding: 'utf8', timeout: 30000,
    });
    console.log(output.trim());
    return;
  }
  const serversDir = path.join(os.homedir(), 'Documents/JumpDesktop/Viewer/Servers');
  // Registered connections in displayNames order; each name must match at most one file.
  const findTargets = () => {
    const entries = fs.existsSync(serversDir) ? fs.readdirSync(serversDir) : [];
    const connections = entries.filter(name => name.endsWith('.jump')).map(name => {
      const filename = path.join(serversDir, name);
      return { filename, connection: JSON.parse(fs.readFileSync(filename, 'utf8')) };
    });
    return policy.displayNames.flatMap(displayName => {
      const matches = connections.filter(({ connection }) => connection.DisplayName === displayName);
      if (matches.length > 1) throw new Error(`Multiple connections are named "${displayName}"; rename one in Jump Desktop.`);
      return matches;
    });
  };
  let targets = findTargets();
  const registered = new Set(targets.map(({ connection }) => connection.DisplayName));
  const missing = policy.displayNames.filter(name => !registered.has(name));
  if (!targets.length) {
    const message = `No connection named ${policy.displayNames.join(' or ')} in ${serversDir}. Sign in to Jump Desktop first.`;
    if (flag === '--deploy') { console.log(`Skipping: ${message}`); return; }
    throw new Error(message);
  }
  for (const name of missing) console.log(`Skipping "${name}": not registered in Jump Desktop.`);
  for (const { connection } of targets) mergeDisplaySettings(connection, policy); // Validate before stopping any application.
  if (flag === '--check') {
    const report = targets.map(({ connection }) => ({ displayName: connection.DisplayName,
      settings: Object.fromEntries(Object.keys(policy.settings).map(key => [key, connection[key]])),
      differingKeys: differingKeys(connection, policy) }));
    console.log(JSON.stringify(report, null, 2));
    if (report.some(entry => entry.differingKeys.length)) process.exitCode = 1;
    return;
  }
  if (targets.every(({ connection }) => !differingKeys(connection, policy).length)) {
    console.log('Jump Desktop display settings already match dotfiles.');
    return;
  }
  const wasRunning = viewerRunning();
  if (wasRunning && flag !== '--quit') {
    const message = 'Jump Desktop is running. Close it and run jump-display-apply, or use jump-display-apply --quit.';
    if (flag === '--deploy') { console.log(`Skipping: ${message}`); return; }
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
    // The app saves on quit; read the final files again so other changes are preserved.
    targets = findTargets();
    const pending = targets
      .map(target => ({ ...target, changed: differingKeys(target.connection, policy),
        merged: mergeDisplaySettings(target.connection, policy) }))
      .filter(({ changed }) => changed.length);
    if (!pending.length) { console.log('Jump Desktop display settings already match dotfiles.'); return; }
    if (viewerRunning()) throw new Error('Jump Desktop restarted; settings were not written.');
    const backupRoot = path.join(os.homedir(), 'Library/Application Support/dotfiles/backups/jump-desktop');
    fs.mkdirSync(backupRoot, { recursive: true, mode: 0o700 });
    const backupDir = fs.mkdtempSync(path.join(backupRoot, 'display-'));
    for (const { filename, connection, changed, merged } of pending) {
      const backup = path.join(backupDir, path.basename(filename));
      fs.copyFileSync(filename, backup, fs.constants.COPYFILE_EXCL);
      fs.chmodSync(backup, 0o600);
      const staging = fs.mkdtempSync(path.join(serversDir, '.dotfiles-display-'));
      try {
        const temporary = path.join(staging, 'connection.jump');
        fs.writeFileSync(temporary, JSON.stringify(merged, null, 2) + '\n', { mode: 0o600 });
        fs.renameSync(temporary, filename);
      } finally {
        fs.rmSync(staging, { recursive: true, force: true });
      }
      if (differingKeys(JSON.parse(fs.readFileSync(filename, 'utf8')), policy).length) {
        throw new Error(`Verification failed for "${connection.DisplayName}".`);
      }
      console.log(`Applied to "${connection.DisplayName}": ${changed.join(', ')}\nBackup: ${backup}`);
    }
  } finally {
    if (wasRunning && !viewerRunning()) execFileSync('/usr/bin/open', ['-g', '-a', 'Jump Desktop']);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { main(); } catch (error) { console.error(`Error: ${error.message}`); process.exitCode = 1; }
}
