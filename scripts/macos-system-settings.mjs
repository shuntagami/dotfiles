#!/usr/bin/env node
// Declarative system preferences and machine policy. No app restarts or maintenance.
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { createContext, parseMode, toPlist, writePlist, isMain, cli } from './macos-app-settings.mjs';
import { withQueuedActivation, readPending, reportPending, validateTarget } from './macos-activation.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const merge = (current, desired) => object(desired)
  ? Object.fromEntries(Object.entries({ ...(object(current) ? current : {}), ...desired })
    .map(([key, value]) => [key, Object.hasOwn(desired, key) ? merge(current?.[key], value) : value]))
  : desired;
const resolve = (value, variables) => typeof value === 'string'
  ? value.replace(/\$\{(HOME|MODEL)\}/g, (_, key) => variables[key])
  : Array.isArray(value) ? value.map(item => resolve(item, variables))
  : object(value) ? Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolve(item, variables)])) : value;

function readJson(file) { return JSON.parse(fs.readFileSync(file, 'utf8')); }
function command(ctx, file, args, options) {
  const result = ctx.run(file, args, options);
  if (result.status !== 0) throw new Error(`Command failed: ${file} ${args.join(' ')}`);
  return result.stdout ?? '';
}

export function preferences(group, ctx) {
  const args = [...group.currentHost ? ['-currentHost'] : [], 'export', group.domain, '-'];
  const result = ctx.run('/usr/bin/defaults', args);
  if (result.status === 0) return ctx.readPlist(result.stdout);
  if (/does not exist|not found/i.test(`${result.stdout}${result.stderr}`)) return {};
  throw new Error(`Could not read ${group.domain}; no settings were changed.`);
}

export function parsePower(text, capabilities = false) {
  const scopes = { 'AC Power': 'ac', 'Battery Power': 'battery', 'UPS Power': 'ups' };
  const result = {};
  let scope;
  for (const line of text.split('\n')) {
    const heading = line.trim().replace(/^Capabilities for /, '').replace(/:$/, '');
    if (heading in scopes) { scope = scopes[heading]; result[scope] = {}; continue; }
    if (!scope) continue;
    const match = line.trim().match(capabilities ? /^(\w+)$/ : /^(\w+)\s+(\d+)\b/);
    if (match) result[scope][match[1]] = capabilities ? true : Number(match[2]);
  }
  if (!Object.keys(result).length) throw new Error('Could not parse pmset power sources.');
  return result;
}

export function loadPolicy(ctx) {
  const settings = readJson(path.join(ctx.configDir, 'macos-settings.json'));
  const battery = command(ctx, '/usr/bin/pmset', ['-g', 'batt']).includes('InternalBattery');
  const role = battery ? 'laptop' : 'desktop';
  const roles = readJson(path.join(ctx.configDir, 'macos-machines.json'));
  if (!object(roles[role])) throw new Error(`Missing machine policy: ${role}`);
  const localFile = path.join(ctx.home, '.config/dotfiles/macos-machine.json');
  const local = fs.existsSync(localFile) ? readJson(localFile) : {};
  const known = new Set(['name', 'dock', 'power', 'nvram']);
  if (!object(local) || Object.keys(local).some(key => !known.has(key))) throw new Error('Unknown machine override key.');
  const machine = { ...roles[role], ...local };
  // Read the model only when the selected policy needs it.
  let model = '';
  if (JSON.stringify(machine).includes('${MODEL}')) {
    const hardware = JSON.parse(command(ctx, '/usr/sbin/system_profiler', ['SPHardwareDataType', '-json']));
    const name = hardware.SPHardwareDataType?.[0]?.machine_name;
    if (!name) throw new Error('Could not determine Mac model; no settings were changed.');
    model = name.replace(/[^A-Za-z0-9-]+/g, '-');
  }
  const policy = resolve({ ...settings, machine }, { HOME: ctx.home, MODEL: model });
  if (!Array.isArray(policy.preferences) || !Array.isArray(policy.loginItems)) throw new Error('Invalid macOS settings policy.');
  const profileFile = path.join(ctx.home, '.dotfiles-profile');
  policy.profile = ctx.profile ?? process.env.DOTFILES_PROFILE ??
    (fs.existsSync(profileFile) ? fs.readFileSync(profileFile, 'utf8').trim() : 'full');
  if (!['full', 'minimal'].includes(policy.profile)) throw new Error('Invalid dotfiles profile.');
  if (policy.visibleVolumes !== undefined && typeof policy.visibleVolumes !== 'boolean') throw new Error('Invalid /Volumes visibility policy.');
  if (policy.machine.nvram != null && !object(policy.machine.nvram)) throw new Error('Invalid NVRAM policy.');
  for (const item of policy.loginItems) {
    if (!object(item) || typeof item.name !== 'string' || !/^[A-Za-z0-9 -]+$/.test(item.name) ||
        item.profile && !['full', 'minimal'].includes(item.profile)) throw new Error('Invalid login app policy.');
  }
  if (policy.machine.power != null && (!object(policy.machine.power) ||
      Object.entries(policy.machine.power).some(([scope, values]) => !['all', 'ac', 'battery', 'ups'].includes(scope) ||
        !object(values) || Object.entries(values).some(([key, value]) => !/^\w+$/.test(key) || !Number.isInteger(value) || value < 0)))) {
    throw new Error('Invalid machine power policy.');
  }
  const seen = new Set();
  for (const group of policy.preferences) {
    if (!group.domain || typeof group.domain !== 'string' || !object(group.values)) throw new Error('Invalid preference group.');
    const id = `${Boolean(group.currentHost)}:${group.domain}`;
    if (seen.has(id)) throw new Error(`Duplicate preference group: ${group.domain}`);
    seen.add(id);
    if (group.domain.startsWith('/Library/') && !group.admin) throw new Error(`System preferences require admin: ${group.domain}`);
    if (group.activation) validateTarget(group.activation);
    // Encode all values before any writes; unsupported values fail during planning.
    toPlist(group.values);
  }
  if (policy.machine.dock != null) {
    if (!['left', 'right', 'bottom'].includes(policy.machine.dock)) throw new Error('Invalid Dock orientation.');
    if (policy.preferences.some(group => group.domain === 'com.apple.dock' && 'orientation' in group.values)) throw new Error('Dock orientation is owned by machine policy.');
    policy.preferences.push({ domain: 'com.apple.dock', activation: 'Dock', values: { orientation: policy.machine.dock } });
  }
  return policy;
}

export function planSettings(policy, ctx) {
  const plan = [];
  for (const group of policy.preferences) {
    const current = preferences(group, ctx);
    for (const [key, managed] of Object.entries(group.values)) {
      const expected = merge(current[key], managed);
      if (isDeepStrictEqual(current[key], expected)) continue;
      plan.push({ description: `${group.domain}.${key}`, before: current[key], expected,
        admin: Boolean(group.admin), activation: group.activation,
        file: '/usr/bin/defaults', args: [...group.currentHost ? ['-currentHost'] : [], 'write', group.domain, key, toPlist(expected)],
        verify: () => isDeepStrictEqual(preferences(group, ctx)[key], expected) });
    }
  }
  if (policy.machine.power) {
    const power = parsePower(command(ctx, '/usr/bin/pmset', ['-g', 'custom']));
    const capabilities = parsePower(command(ctx, '/usr/bin/pmset', ['-g', 'cap']), true);
    const flags = { ac: '-c', battery: '-b', ups: '-u' };
    for (const [scope, current] of Object.entries(power)) {
      const desired = { ...policy.machine.power.all, ...policy.machine.power[scope] };
      for (const [key, expected] of Object.entries(desired)) {
        // Keys like standbydelay/lidwake are not exposed on every Mac.
        if (!(key in current) && !capabilities[scope]?.[key]) {
          ctx.log(`Unsupported ${scope} power setting: ${key}; skipped.`); continue;
        }
        if (!/^\w+$/.test(key) || !Number.isInteger(expected) || expected < 0) throw new Error(`Invalid power setting: ${key}`);
        if (current[key] === expected) continue;
        plan.push({ description: `power.${scope}.${key}`, before: current[key], expected, admin: true,
          file: '/usr/bin/pmset', args: [flags[scope], key, String(expected)],
          verify: () => parsePower(command(ctx, '/usr/bin/pmset', ['-g', 'custom']))[scope]?.[key] === expected });
      }
    }
  }
  if (policy.machine.name != null) {
    if (!/^[A-Za-z0-9][A-Za-z0-9-]{0,62}$/.test(policy.machine.name)) throw new Error('Invalid Mac name.');
    for (const key of ['ComputerName', 'LocalHostName']) {
      const result = ctx.run('/usr/sbin/scutil', ['--get', key]);
      if (result.status !== 0 && !`${result.stdout}${result.stderr}`.includes('not set')) throw new Error(`Could not read ${key}.`);
      const before = result.status === 0 ? result.stdout.trim() : null;
      if (before === policy.machine.name) continue;
      plan.push({ description: key, before, expected: policy.machine.name, admin: true,
        file: '/usr/sbin/scutil', args: ['--set', key, policy.machine.name],
        verify: () => command(ctx, '/usr/sbin/scutil', ['--get', key]).trim() === policy.machine.name });
    }
  }
  for (const [key, expected] of Object.entries(policy.machine.nvram ?? {})) {
    if (!/^\w+$/.test(key) || typeof expected !== 'string') throw new Error('Invalid NVRAM policy.');
    const read = () => {
      const result = ctx.run('/usr/sbin/nvram', [key]);
      if (result.status !== 0) {
        if (/data was not found/i.test(result.stderr)) return null;
        throw new Error(`Could not read NVRAM ${key}.`);
      }
      return result.stdout.replace(new RegExp(`^${key}\\t`), '').replace(/\n$/, '').replace(/%([0-9a-f]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
    };
    const before = read();
    if (before !== expected) plan.push({ description: `nvram.${key}`, before, expected, admin: true,
      file: '/usr/sbin/nvram', args: [`${key}=${expected}`], verify: () => read() === expected });
  }
  if (policy.visibleVolumes) {
    const read = () => {
      const flags = command(ctx, '/usr/bin/stat', ['-f', '%f', '/Volumes']).trim();
      if (!/^\d+$/.test(flags)) throw new Error('Could not read /Volumes visibility.');
      return Number(flags) & 0x8000;
    };
    if (read()) plan.push({ description: '/Volumes.hidden', before: true, expected: false, admin: true,
      file: '/usr/bin/chflags', args: ['nohidden', '/Volumes'], verify: () => !read() });
  }
  return plan;
}

function planLoginItems(policy, ctx) {
  const plan = [];
  const profile = policy.profile;
  for (const { name } of policy.loginItems.filter(item => !item.profile || item.profile === profile)) {
    const appPath = ['/Applications', path.join(ctx.home, 'Applications')].map(root => path.join(root, `${name}.app`)).find(file => fs.existsSync(file));
    if (!appPath) continue;
    // argv keeps home paths out of AppleScript source. Check the full path.
    const inspect = 'on run argv\ntell application "System Events" to return count of (login items whose path is item 1 of argv)\nend run';
    const read = () => {
      const count = Number(command(ctx, '/usr/bin/osascript', ['-e', inspect, appPath]).trim());
      if (!Number.isInteger(count) || count < 0) throw new Error('Could not read login items.');
      return count;
    };
    if (read()) continue;
    const script = 'on run argv\ntell application "System Events" to make login item at end with properties {path:item 1 of argv, hidden:false}\nend run';
    plan.push({ description: `loginItem.${name}`, before: 0, expected: 1, admin: false,
      file: '/usr/bin/osascript', args: ['-e', script, appPath], verify: () => read() > 0 });
  }
  return plan;
}

export function applySettings(mode, ctx) {
  const policy = loadPolicy(ctx);
  // Finish reading/validating the plan before the first backup or setting write.
  const plan = [...planSettings(policy, ctx), ...planLoginItems(policy, ctx)];
  if (mode === 'apply') readPending(ctx);
  for (const entry of plan) ctx.log(`${entry.admin ? 'Admin ' : ''}${entry.description}: ${JSON.stringify(entry.before)} -> ${JSON.stringify(entry.expected)}`);
  if (mode !== 'apply') return Number(mode === 'check' && plan.length > 0);
  if (plan.length) {
    if (plan.some(entry => entry.admin)) command(ctx, '/usr/bin/sudo', ['-v'], { stdio: 'inherit' });
    const root = path.join(ctx.stateRoot, 'macos/backups');
    fs.mkdirSync(root, { recursive: true, mode: 0o700 });
    const backup = fs.mkdtempSync(path.join(root, 'before-'));
    writePlist(path.join(backup, 'settings.plist'), Object.fromEntries(plan.map(entry => [entry.description,
      entry.before === undefined ? { absent: true } : { value: entry.before }])));
    ctx.log(`Backup: ${backup}`);
    for (const entry of plan) {
      const mutate = () => {
        command(ctx, entry.admin ? '/usr/bin/sudo' : entry.file, entry.admin ? [entry.file, ...entry.args] : entry.args);
        if (!entry.verify()) throw new Error(`Saved value did not match: ${entry.description}`);
      };
      if (entry.activation) withQueuedActivation(entry.activation, [entry.description], ctx, mutate);
      else mutate();
    }
  }
  reportPending(ctx);
  return 0;
}

export function main(args = process.argv.slice(2), ctx = createContext()) {
  const mode = parseMode(args);
  if (mode === 'help') { ctx.log('Usage: macos-system-settings.mjs [--apply|--check|--dry-run]'); return 0; }
  if (ctx.platform !== 'darwin') { ctx.log('Skipping system settings: requires macOS.'); return 0; }
  return applySettings(mode, ctx);
}

if (isMain(import.meta.url)) cli(main);
