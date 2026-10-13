import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { aqua, clipy, shortcutValue } from './macos-app-hotkeys.mjs';
import { manageDefaultApps } from './macos-default-apps.mjs';
import { createContext, parsePlist, toPlist, run, NEEDS_APP_ACTION } from './macos-app-settings.mjs';

const configDir = fileURLToPath(new URL('../misc/', import.meta.url));

function isolated(callback) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-app-settings-'));
  try { return callback(home); } finally { fs.rmSync(home, { recursive: true, force: true }); }
}

test('Aqua apply preserves unmanaged actions, fields, settings and repeated apply makes no changes', () => isolated(home => {
  const filename = path.join(home, 'Library/Application Support/Aqua Voice/settings.json');
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, JSON.stringify({
    hotkeys: [{ action: 'activate', keys: 'Old', customField: true }, { action: 'open_note', keys: 'Custom' }],
    unrelated: { value: 'preserve' },
  }));
  fs.chmodSync(filename, 0o640);
  const ctx = createContext({ home, configDir, stateRoot: path.join(home, 'state'), log() {} });
  assert.equal(aqua('apply', ctx), 0);
  const updated = JSON.parse(fs.readFileSync(filename, 'utf8'));
  assert.deepEqual(updated.unrelated, { value: 'preserve' });
  assert.ok(updated.hotkeys.some(item => item.action === 'open_note' && item.keys === 'Custom'));
  assert.ok(updated.hotkeys.some(item => item.action === 'activate' && item.keys === 'Fn' && item.customField));
  assert.equal(fs.statSync(filename).mode & 0o777, 0o640);
  const before = fs.readFileSync(filename);
  assert.equal(aqua('apply', ctx), 0);
  assert.deepEqual(fs.readFileSync(filename), before);
  assert.equal(fs.readdirSync(path.join(home, 'state/app-hotkeys/aqua-voice')).length, 1);
}));

test('Aqua check does not write settings or create backups', () => isolated(home => {
  const filename = path.join(home, 'Library/Application Support/Aqua Voice/settings.json');
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, '{"hotkeys": [], "unrelated": 42}\n');
  const before = fs.readFileSync(filename);
  const ctx = createContext({ home, configDir, stateRoot: path.join(home, 'state'), log() {} });
  assert.equal(aqua('check', ctx), 1);
  assert.deepEqual(fs.readFileSync(filename), before);
  assert.equal(fs.existsSync(ctx.stateRoot), false);
}));

function associationScenario(mode, accept) {
  return isolated(home => {
    const directory = path.join(home, 'config');
    fs.mkdirSync(directory);
    fs.writeFileSync(path.join(directory, 'default-apps.json'), JSON.stringify({
      fileAssociations: [{ name: 'Acrobat', bundleIds: ['com.adobe.Acrobat.Pro', 'com.adobe.Reader'], extensions: ['pdf'] }],
      screenshots: { bundleId: 'pl.maketheweb.cleanshotx', shortcuts: {}, disabledSystemShortcuts: [] },
    }));
    let current = 'com.apple.Preview';
    const writes = [];
    const ctx = createContext({
      home, configDir: directory, stateRoot: path.join(home, 'state'), log() {},
      command: () => 'duti', preferences: () => ({}), handler: () => current,
      applications: () => new Map([['com.adobe.reader', '/fake/Reader.app'], ['pl.maketheweb.cleanshotx', '/fake/CleanShot X.app']]),
      run(file, args) {
        if (file === 'duti' && args[0] === '-s') {
          writes.push(args);
          if (accept) current = args[1].toLowerCase();
        }
        return { status: 0, stdout: '', stderr: '' };
      },
    });
    const result = manageDefaultApps(mode, ctx);
    return { result, writes, backedUp: fs.existsSync(ctx.stateRoot) };
  });
}

test('successful setter without actual association change fails', () => {
  const { result, writes, backedUp } = associationScenario('apply', false);
  assert.equal(result, 1);
  assert.equal(writes.length, 1);
  assert.equal(backedUp, true);
});

test('Reader fallback accepts case-insensitive bundle ID', () => {
  const { result, writes } = associationScenario('apply', true);
  assert.equal(result, 0);
  assert.equal(writes[0][1], 'com.adobe.Reader');
});

test('dry-run makes no writes or backups', () => {
  const { result, writes, backedUp } = associationScenario('dry-run', false);
  assert.equal(result, 0);
  assert.deepEqual(writes, []);
  assert.equal(backedUp, false);
});

test('preferences read error is not treated as an empty domain', () => {
  const ctx = createContext({ run: () => ({ status: 1, stdout: '', stderr: 'Permission denied' }) });
  assert.throws(() => ctx.preferences('test.domain'), /Could not read/);
});

test('plist reads native data, references, large integers and preserves XML string whitespace', () => {
  const value = parsePlist('<?xml version="1.0"?><plist version="1.0"><dict><key>text</key><string> &lt;日本語&amp;\n </string><key>data</key><data>YWJj</data><key>large</key><integer>9223372036854775807</integer><key>ref</key><dict><key>CF$UID</key><integer>2</integer></dict><key>empty</key><array/></dict></plist>');
  assert.equal(value.text, ' <日本語&\n ');
  assert.deepEqual(value.data, Buffer.from('abc'));
  assert.equal(value.large, 9223372036854775807n);
  assert.deepEqual(value.ref, { CF$UID: 2 });
  assert.deepEqual(value.empty, []);
});

test('plist rejects invalid or unsupported input', () => {
  assert.throws(() => parsePlist('<plist><array><string>unclosed</array></plist>'));
  assert.throws(() => parsePlist('<plist><unsupported/></plist>'));
});

test('native plutil preserves data, dates and UID references across binary conversion', { skip: process.platform !== 'darwin' }, () => {
  const value = { data: Buffer.from('abc'), date: new Date('2026-10-13T00:00:00Z'), large: 9223372036854775807n, ref: { CF$UID: 2 }, text: '<日本語&>' };
  const binary = run('/usr/bin/plutil', ['-convert', 'binary1', '-o', '-', '-'], { input: toPlist(value), encoding: null });
  assert.equal(binary.status, 0);
  assert.deepEqual(createContext().readPlist(binary.stdout), value);
});

test('Clipy apply produces native archives, retains unrelated preferences and is idempotent', { skip: process.platform !== 'darwin' }, () => isolated(home => {
  const prefs = { unrelated: 'preserve' };
  let writes = 0;
  const ctx = createContext({
    home, configDir, stateRoot: path.join(home, 'state'), log() {}, preferences: () => prefs,
    run(file, args, options) {
      if (file === '/usr/bin/defaults' && args[0] === 'write') {
        writes++;
        prefs[args[2]] = args[3] === '-data' ? Buffer.from(args[4], 'hex') : Number(args[4]);
        return { status: 0, stdout: '', stderr: '' };
      }
      return run(file, args, options);
    },
  });
  assert.equal(clipy('apply', ctx), 0);
  assert.equal(prefs.unrelated, 'preserve');
  assert.deepEqual(shortcutValue(prefs.kCPYHotKeyHistoryKeyCombo, ctx), { key: 'v', modifiers: 2304 });
  assert.equal(ctx.readPlist(prefs.kCPYHotKeyHistoryKeyCombo).$objects[1].key.CF$UID, 2);
  assert.equal(writes, 3);
  assert.equal(clipy('apply', ctx), 0);
  assert.equal(writes, 3);
}));

test('missing Aqua settings requests first launch without reporting a write failure', () => isolated(home => {
  const ctx = createContext({ home, log() {} });
  assert.equal(aqua('apply', ctx), NEEDS_APP_ACTION);
  assert.equal(aqua('check', ctx), 1);
}));

function screenshotScenario(options, callback) {
  return isolated(home => {
    const shot = options.changeShortcut ? {} : { capture: true };
    const system = { AppleSymbolicHotKeys: { '28': { enabled: !options.alreadyDisabled, value: { parameters: [51, 20, 1179648], type: 'standard' } } } };
    let activations = 0;
    const configDir = path.join(home, 'config');
    fs.mkdirSync(configDir);
    fs.writeFileSync(path.join(configDir, 'default-apps.json'), JSON.stringify({
      fileAssociations: [], screenshots: {
        bundleId: 'pl.maketheweb.cleanshotx', shortcuts: { capture: { carbonModifiers: 768, carbonKey: 20 } },
        disabledSystemShortcuts: ['28'],
      },
    }));
    const ctx = createContext({
      home, configDir, stateRoot: path.join(home, 'state'), log() {}, command: () => 'duti',
      applications: () => new Map([['pl.maketheweb.cleanshotx', '/fake/CleanShot X.app']]),
      preferences: domain => domain === 'com.apple.symbolichotkeys' ? system : shot,
      run(file, args) {
        if (file.endsWith('/activateSettings')) { activations++; return { status: options.activationFails ? 1 : 0 }; }
        if (file === '/usr/bin/defaults' && args[0] === 'write') {
          if (options.writeFails) return { status: 1 };
          if (args[1] === 'com.apple.symbolichotkeys') system.AppleSymbolicHotKeys[args[4]] = parsePlist(args[5]);
          else shot[args[2]] = Buffer.from(args[4], 'hex');
        }
        return { status: 0, stdout: '', stderr: '' };
      },
    });
    return callback(ctx, () => activations);
  });
}

test('saved CleanShot shortcut returns app-action status after verification', () => screenshotScenario({ changeShortcut: true, alreadyDisabled: true }, ctx => {
  assert.equal(manageDefaultApps('apply', ctx), NEEDS_APP_ACTION);
  assert.equal(manageDefaultApps('check', ctx), 0);
}));

test('CleanShot write failure is not masked by a restart requirement', () => screenshotScenario({ changeShortcut: true, alreadyDisabled: true, writeFails: true }, ctx => {
  assert.equal(manageDefaultApps('apply', ctx), 1);
}));

test('native screenshot changes activate once and matching settings do not activate again', () => screenshotScenario({}, (ctx, activations) => {
  assert.equal(manageDefaultApps('apply', ctx), 0);
  assert.equal(activations(), 1);
  assert.equal(manageDefaultApps('apply', ctx), 0);
  assert.equal(activations(), 1);
}));

test('check and dry-run never activate native settings', () => screenshotScenario({}, (ctx, activations) => {
  assert.equal(manageDefaultApps('check', ctx), 1);
  assert.equal(manageDefaultApps('dry-run', ctx), 0);
  assert.equal(activations(), 0);
}));

test('native settings activation failure is reported', () => screenshotScenario({ activationFails: true }, ctx => {
  assert.equal(manageDefaultApps('apply', ctx), 1);
}));

test('deploy continues for app-action status and stops for real failures in Bash and Zsh', { skip: process.platform !== 'darwin' }, () => {
  const helper = fileURLToPath(new URL('./app-settings-status.sh', import.meta.url));
  for (const shell of ['/bin/bash', '/bin/zsh']) {
    for (const code of [0, NEEDS_APP_ACTION, 1, 42]) {
      const result = spawnSync(shell, ['-ec', 'source "$1"\ndotfiles_apply_app_settings /bin/sh -c "exit $2"\necho continued', 'test', helper, String(code)], { encoding: 'utf8' });
      assert.equal(result.status, code === NEEDS_APP_ACTION ? 0 : code);
      assert.equal(result.stdout.includes('continued'), code === 0 || code === NEEDS_APP_ACTION);
    }
  }
});
