#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { createContext, toPlist, writePlist, parseMode, isMain, cli } from './macos-app-settings.mjs';

const LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';

export function manageDefaultApps(mode, ctx) {
  const duti = ctx.command('duti');
  if (!duti) throw new Error('Install duti first: brew install duti');
  const config = JSON.parse(fs.readFileSync(path.join(ctx.configDir, 'default-apps.json'), 'utf8'));
  const apps = ctx.applications();
  const apply = mode === 'apply';
  const changes = [];
  let failed = false;
  let backupDirectory;
  const saveBackup = () => {
    if (backupDirectory) return;
    const root = path.join(ctx.stateRoot, 'default-apps');
    fs.mkdirSync(root, { recursive: true, mode: 0o700 });
    backupDirectory = fs.mkdtempSync(path.join(root, 'before-'));
    const source = path.join(ctx.home, 'Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist');
    if (fs.existsSync(source)) fs.copyFileSync(source, path.join(backupDirectory, path.basename(source)));
    // Export only managed CleanShot keys, excluding license and account data.
    const prefs = ctx.preferences(config.screenshots.bundleId);
    const subset = Object.fromEntries(Object.keys(config.screenshots.shortcuts).filter(key => Object.hasOwn(prefs, key)).map(key => [key, prefs[key]]));
    writePlist(path.join(backupDirectory, 'cleanshot-shortcuts.plist'), subset);
    writePlist(path.join(backupDirectory, 'symbolic-hotkeys.plist'), ctx.preferences('com.apple.symbolichotkeys'));
    fs.writeFileSync(path.join(backupDirectory, 'associations.json'), JSON.stringify(changes, null, 2) + '\n', { mode: 0o600 });
    ctx.log(`Backup: ${backupDirectory}`);
  };
  const plans = [];
  for (const association of config.fileAssociations) {
    const bundle = association.bundleIds.find(id => apps.has(id.toLowerCase()));
    if (!bundle) { ctx.log(`Missing app: ${association.name}`); failed = true; continue; }
    for (const extension of association.extensions) {
      const current = ctx.handler(extension);
      plans.push({ bundle, extension, current });
      if (current.toLowerCase() !== bundle.toLowerCase()) changes.push({ extension, before: current, after: bundle });
    }
  }
  const registered = new Set();
  for (const { bundle, extension, current } of plans) {
    if (current.toLowerCase() === bundle.toLowerCase()) { ctx.log(`OK .${extension} -> ${bundle}`); continue; }
    ctx.log(`${apply ? 'Set' : mode === 'check' ? 'Mismatch' : 'Would set'} .${extension}: ${current || 'unknown'} -> ${bundle}`);
    if (!apply) { failed ||= mode === 'check'; continue; }
    saveBackup();
    if (!registered.has(bundle)) {
      const result = ctx.run(LSREGISTER, ['-f', apps.get(bundle.toLowerCase())]);
      if (result.status !== 0) { ctx.log(result.stderr); failed = true; continue; }
      registered.add(bundle);
    }
    const result = ctx.run(duti, ['-s', bundle, `.${extension}`, 'all']);
    const actual = ctx.handler(extension);
    if (result.status !== 0 || actual.toLowerCase() !== bundle.toLowerCase()) {
      ctx.log(`Failed .${extension}: ${(result.stderr ?? '').trim()} actual=${actual || 'unknown'}`);
      failed = true;
    }
  }
  const screenshot = config.screenshots;
  const domain = screenshot.bundleId;
  if (!apps.has(domain.toLowerCase())) { ctx.log('Missing CleanShot X: screenshot settings skipped.'); return 1; }
  const prefs = ctx.preferences(domain);
  let reloadNeeded = false;
  for (const [key, expected] of Object.entries(screenshot.shortcuts)) {
    let actual = prefs[key];
    if (Buffer.isBuffer(actual)) actual = JSON.parse(actual.toString('utf8'));
    // CleanShot also stores true for its built-in default binding.
    if (actual === true || isDeepStrictEqual(actual, expected)) { ctx.log(`OK CleanShot ${key}`); continue; }
    ctx.log(`${apply ? 'Set' : mode === 'check' ? 'Mismatch' : 'Would set'} CleanShot ${key}`);
    if (apply) {
      saveBackup();
      const data = Buffer.from(JSON.stringify(expected)).toString('hex');
      const result = ctx.run('/usr/bin/defaults', ['write', domain, key, '-data', data]);
      failed ||= result.status !== 0;
      reloadNeeded = true;
    } else failed ||= mode === 'check';
  }
  const system = ctx.preferences('com.apple.symbolichotkeys').AppleSymbolicHotKeys ?? {};
  for (const key of screenshot.disabledSystemShortcuts) {
    const value = system[key] ?? {};
    if (value.enabled === false || value.enabled === 0) { ctx.log(`OK native screenshot shortcut ${key}: disabled`); continue; }
    ctx.log(`${apply ? 'Disable' : mode === 'check' ? 'Mismatch' : 'Would disable'} native screenshot shortcut ${key}`);
    if (apply) {
      saveBackup();
      const xml = toPlist({ ...value, enabled: false });
      const result = ctx.run('/usr/bin/defaults', ['write', 'com.apple.symbolichotkeys', 'AppleSymbolicHotKeys', '-dict-add', key, xml]);
      failed ||= result.status !== 0;
    } else failed ||= mode === 'check';
  }
  if (reloadNeeded) { ctx.log('Restart CleanShot X to activate the changed shortcuts. Existing captures were not interrupted.'); failed = true; }
  return apply && !failed ? manageDefaultApps('check', ctx) : Number(failed);
}

export function main(args = process.argv.slice(2), ctx = createContext()) {
  const mode = parseMode(args);
  if (mode === 'help') { ctx.log('Usage: macos-default-apps.mjs [--apply|--check|--dry-run]'); return 0; }
  if (ctx.platform !== 'darwin') { ctx.log('Skipping default apps: requires macOS.'); return 0; }
  return manageDefaultApps(mode, ctx);
}

if (isMain(import.meta.url)) cli(main);
