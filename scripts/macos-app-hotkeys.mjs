#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { createContext, toPlist, writePlist, parseMode, isMain, cli } from './macos-app-settings.mjs';

export function mergeHotkeys(existing, desired) {
  const byAction = new Map(desired.map(item => [item.action, item]));
  const present = new Set(existing.map(item => item.action));
  return [...existing.map(item => byAction.has(item.action) ? { ...item, keys: byAction.get(item.action).keys } : item),
    ...desired.filter(item => !present.has(item.action))];
}

function keycombo(value, ctx) {
  // CF$UID dictionaries become binary archive references through native plutil.
  const xml = toPlist({
    $version: 100000, $archiver: 'NSKeyedArchiver', $top: { root: { CF$UID: 1 } },
    $objects: ['$null', { $class: { CF$UID: 3 }, key: { CF$UID: 2 },
      modifiers: value.modifiers, doubledModifiers: false }, value.key,
    { $classname: 'Magnet.KeyCombo', $classes: ['Magnet.KeyCombo', 'NSObject'] }],
  });
  const result = ctx.run('/usr/bin/plutil', ['-convert', 'binary1', '-o', '-', '-'], { input: xml, encoding: null });
  if (result.status !== 0) throw new Error('Could not encode Clipy shortcut.');
  return result.stdout;
}

export function shortcutValue(data, ctx) {
  if (!Buffer.isBuffer(data)) return null;
  try {
    const archive = ctx.readPlist(data);
    const combo = archive.$objects[archive.$top.root.CF$UID];
    return { key: archive.$objects[combo.key.CF$UID], modifiers: combo.modifiers };
  } catch { return null; }
}

function backup(app, data, ctx) {
  const root = path.join(ctx.stateRoot, 'app-hotkeys', app);
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  const directory = fs.mkdtempSync(path.join(root, 'before-'));
  const filename = path.join(directory, 'settings.plist');
  writePlist(filename, data);
  ctx.log(`Backup: ${filename}`);
}

export function aqua(mode, ctx) {
  const filename = path.join(ctx.home, 'Library/Application Support/Aqua Voice/settings.json');
  if (!fs.existsSync(filename)) {
    ctx.log('Aqua Voice settings missing: launch the app once, then run deploy again.');
    return 1;
  }
  const settings = JSON.parse(fs.readFileSync(filename, 'utf8'));
  const desired = JSON.parse(fs.readFileSync(path.join(ctx.configDir, 'aqua-voice-hotkeys.json'), 'utf8'));
  const current = settings.hotkeys ?? [];
  const merged = mergeHotkeys(current, desired);
  if (isDeepStrictEqual(merged, current)) { ctx.log('OK Aqua Voice shortcuts'); return 0; }
  if (mode !== 'apply') { ctx.log('Aqua Voice: managed shortcuts differ.'); return Number(mode === 'check'); }
  backup('aqua-voice', { hotkeys: current }, ctx);
  settings.hotkeys = merged;
  const staging = fs.mkdtempSync(path.join(path.dirname(filename), '.dotfiles-hotkeys-'));
  try {
    const temporary = path.join(staging, 'settings.json');
    fs.writeFileSync(temporary, JSON.stringify(settings, null, 2) + '\n', { mode: fs.statSync(filename).mode & 0o777 });
    fs.chmodSync(temporary, fs.statSync(filename).mode & 0o777);
    fs.renameSync(temporary, filename);
  } finally { fs.rmSync(staging, { recursive: true, force: true }); }
  if (!isDeepStrictEqual(JSON.parse(fs.readFileSync(filename, 'utf8')).hotkeys, merged)) throw new Error('Aqua Voice settings verification failed.');
  ctx.log('Saved Aqua Voice shortcuts. Restart Aqua Voice to load them.');
  return 0;
}

export function clipy(mode, ctx) {
  const domain = 'com.clipy-app.Clipy';
  const desired = JSON.parse(fs.readFileSync(path.join(ctx.configDir, 'clipy-hotkeys.json'), 'utf8'));
  const current = ctx.preferences(domain);
  const changes = Object.entries(desired.hotkeys)
    .filter(([key, value]) => !isDeepStrictEqual(shortcutValue(current[key], ctx), value))
    .map(([key, value]) => ({ key, value }));
  const historyKey = 'kCPYPrefMaxHistorySizeKey';
  if (current[historyKey] !== desired.maxHistorySize) changes.push({ key: historyKey, integer: desired.maxHistorySize });
  if (!changes.length) { ctx.log('OK Clipy shortcuts and history size'); return 0; }
  if (mode !== 'apply') { ctx.log(`Clipy: ${changes.map(item => item.key).join(', ')} differ.`); return Number(mode === 'check'); }
  // Prepare archives before making any changes.
  const writes = changes.map(({ key, value, integer }) => [key, value ? '-data' : '-int', value ? keycombo(value, ctx).toString('hex') : String(integer)]);
  backup('clipy', Object.fromEntries(changes.filter(item => Object.hasOwn(current, item.key)).map(item => [item.key, current[item.key]])), ctx);
  for (const args of writes) {
    const result = ctx.run('/usr/bin/defaults', ['write', domain, ...args]);
    if (result.status !== 0) throw new Error('Could not write Clipy preferences.');
  }
  if (clipy('check', ctx)) throw new Error('Clipy preferences verification failed.');
  ctx.log('Saved Clipy settings. Restart Clipy to load them.');
  return 0;
}

export function main(args = process.argv.slice(2), ctx = createContext()) {
  const [app, ...flags] = args;
  if (!['aqua-voice', 'clipy'].includes(app)) throw new Error('Usage: macos-app-hotkeys.mjs <aqua-voice|clipy> [--apply|--check|--dry-run]');
  const mode = parseMode(flags);
  if (mode === 'help') { ctx.log('Usage: <aqua-voice|clipy> [--apply|--check|--dry-run]'); return 0; }
  if (ctx.platform !== 'darwin') { ctx.log('Skipping app shortcuts: requires macOS.'); return 0; }
  const appName = app === 'aqua-voice' ? 'Aqua Voice.app' : 'Clipy.app';
  if (!['/Applications', path.join(ctx.home, 'Applications')].some(root => fs.existsSync(path.join(root, appName)))) {
    ctx.log(`Skipping ${appName}: app is not installed.`);
    return 0;
  }
  return app === 'aqua-voice' ? aqua(mode, ctx) : clipy(mode, ctx);
}

if (isMain(import.meta.url)) cli(main);
