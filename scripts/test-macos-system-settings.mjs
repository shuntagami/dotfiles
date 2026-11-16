import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { createContext, parsePlist, toPlist, run } from './macos-app-settings.mjs';
import { applySettings, loadPolicy, parsePower } from './macos-system-settings.mjs';
import { queueActivation, withQueuedActivation, readPending, activate, main as activationMain } from './macos-activation.mjs';
import { maintain } from './macos-maintenance.mjs';

const configDir = fileURLToPath(new URL('../misc/', import.meta.url));
const success = (stdout = '') => ({ status: 0, stdout, stderr: '' });
function scenario(callback, options = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-system-settings-'));
  try {
    const config = path.join(home, 'config');
    fs.mkdirSync(config);
    fs.writeFileSync(path.join(config, 'macos-settings.json'), JSON.stringify({ preferences: [
      { domain: 'com.apple.finder', activation: 'Finder', values: { ShowPathbar: true, nested: { managed: true } } },
      { domain: 'NSGlobalDomain', currentHost: true, activation: 'login', values: { Keyboard: true } },
      { domain: '/Library/Preferences/test', admin: true, activation: 'login', values: { Enabled: true } },
    ], loginItems: [] }));
    fs.writeFileSync(path.join(config, 'macos-machines.json'), JSON.stringify({ laptop: {
      name: 'Example-MBP', dock: 'right',
      power: { all: { displaysleep: 15, standbydelay: 86400 }, ac: { sleep: 0 }, battery: { sleep: 5 } },
      nvram: { SystemAudioVolume: ' ' },
    }, desktop: { name: 'Example-${MODEL}', dock: 'left' } }));
    const prefs = new Map([['com.apple.finder', { unrelated: 42, nested: { local: 'keep', managed: false } }]]);
    const power = { ac: { sleep: 5, displaysleep: 10 }, battery: { sleep: 2, displaysleep: 10 } };
    const names = { ComputerName: 'Old-name', LocalHostName: 'Old-name' };
    const nvram = { SystemAudioVolume: '\x80' };
    const calls = [];
    const active = new Set(['Finder', 'Dock', 'Aqua Voice', 'Clipy', 'CleanShot X']);
    const loginPaths = new Set();
    const state = { failWrite: false, ignoreWrite: false, failRead: false, failActivate: false, desktop: false, ...options };
    const ctx = createContext({ home, platform: 'darwin', profile: 'full', configDir: config,
      stateRoot: path.join(home, 'state'), log() {}, readPlist: parsePlist,
      run(file, originalArgs, runOptions) {
        calls.push([file, originalArgs, runOptions]);
        let args = [...originalArgs];
        if (file === '/usr/bin/sudo') {
          if (args[0] === '-v') return success();
          [file, ...args] = args;
        }
        if (file === '/usr/bin/defaults') {
          const host = args[0] === '-currentHost';
          if (host) args.shift();
          const [verb, domain, key, value] = args;
          const id = `${host ? 'host:' : ''}${domain}`;
          if (verb === 'export') {
            if (state.failRead && host) return { status: 1, stdout: '', stderr: 'Permission denied' };
            return prefs.has(id) ? success(toPlist(prefs.get(id))) : { status: 1, stdout: '', stderr: 'Domain does not exist' };
          }
          if (state.failWrite) return { status: 42, stdout: '', stderr: 'write failed' };
          if (!state.ignoreWrite) prefs.set(id, { ...prefs.get(id), [key]: parsePlist(value) });
        } else if (file === '/usr/bin/pmset') {
          if (args[0] === '-g') {
            if (args[1] === 'batt') return success(state.desktop ? "Now drawing from 'AC Power'" : 'InternalBattery-0');
            if (args[1] === 'cap') return success('Capabilities for AC Power:\n displaysleep\n sleep\nCapabilities for Battery Power:\n displaysleep\n sleep\n');
            return success(Object.entries(power).map(([scope, values]) => `${scope === 'ac' ? 'AC' : 'Battery'} Power:\n${Object.entries(values).map(([k, v]) => ` ${k} ${v}`).join('\n')}`).join('\n'));
          }
          const scope = { '-c': 'ac', '-b': 'battery' }[args[0]];
          power[scope][args[1]] = Number(args[2]);
        } else if (file === '/usr/sbin/scutil') {
          if (args[0] === '--get') return success(names[args[1]]);
          names[args[1]] = args[2];
        } else if (file === '/usr/sbin/nvram') {
          if (args[0].includes('=')) { const [key, value] = args[0].split('='); nvram[key] = value; }
          else return success(`${args[0]}\t${nvram[args[0]]}\n`);
        } else if (file === '/usr/sbin/system_profiler') {
          return success(JSON.stringify({ SPHardwareDataType: [{ machine_name: 'Mac Studio' }] }));
        } else if (file === '/usr/bin/osascript') {
          if (args[1].includes('count of')) return success(loginPaths.has(args[2]) ? '1' : '0');
          if (args[1].includes('make login item')) loginPaths.add(args[2]);
          else {
            if (state.failActivate) return { status: 1, stderr: 'quit failed' };
            active.delete(args[1].match(/application "([^"]+)"/)[1]);
          }
        } else if (file === '/usr/bin/pgrep') return { status: active.has(args[1]) ? 0 : 1 };
        else if (file === '/usr/bin/killall') {
          if (state.failActivate) return { status: 1, stderr: 'kill failed' };
          active.delete(args[0]);
        } else if (file === '/usr/bin/open') active.add(args.at(-1));
        else if (file === '/bin/launchctl') return { status: 113, stderr: 'not found' };
        return success();
      },
    });
    callback({ ctx, state, prefs, power, names, calls, active, loginPaths });
  } finally { fs.rmSync(home, { recursive: true, force: true }); }
}

const mutations = calls => calls.filter(([file, args]) => file === '/usr/bin/sudo' ||
  file === '/usr/bin/defaults' && args.includes('write') || file === '/usr/bin/pmset' && args[0] !== '-g' ||
  file === '/usr/sbin/scutil' && args[0] === '--set' || file === '/usr/sbin/nvram' && args[0].includes('='));

test('apply preserves unrelated nested preferences, verifies typed values, and second deploy writes nothing', () => scenario(({ ctx, prefs, power, calls }) => {
  assert.equal(applySettings('apply', ctx), 0);
  assert.deepEqual(prefs.get('com.apple.finder'), { unrelated: 42, ShowPathbar: true, nested: { local: 'keep', managed: true } });
  assert.deepEqual(power, { ac: { sleep: 0, displaysleep: 15 }, battery: { sleep: 5, displaysleep: 15 } });
  assert.equal(prefs.get('com.apple.dock').orientation, 'right');
  assert.equal(calls.filter(([file, args]) => file === '/usr/bin/sudo' && args[0] === '-v').length, 1);
  assert.ok(!calls.some(([file]) => /killall|launchctl|\/open$/.test(file)));
  const pending = readPending(ctx);
  assert.deepEqual(Object.keys(pending).sort(), ['Dock', 'Finder', 'login']);
  const before = fs.readdirSync(path.join(ctx.stateRoot, 'macos/backups'));
  const pendingFile = path.join(ctx.stateRoot, 'macos/pending-activation.json');
  const timestamp = fs.statSync(pendingFile).mtimeMs;
  calls.length = 0;
  assert.equal(applySettings('apply', ctx), 0);
  assert.deepEqual(mutations(calls), []);
  assert.deepEqual(readPending(ctx), pending);
  assert.equal(fs.statSync(pendingFile).mtimeMs, timestamp);
  assert.deepEqual(fs.readdirSync(path.join(ctx.stateRoot, 'macos/backups')), before);
  assert.equal(applySettings('check', ctx), 0);
}));

test('check and dry-run perform no writes, sudo, backup, activation, or state creation', () => {
  for (const mode of ['check', 'dry-run']) scenario(({ ctx, calls }) => {
    assert.equal(applySettings(mode, ctx), mode === 'check' ? 1 : 0);
    assert.deepEqual(mutations(calls), []);
    assert.equal(fs.existsSync(ctx.stateRoot), false);
  });
});

test('read errors fail planning before any writes', () => scenario(({ ctx, calls }) => {
  assert.throws(() => applySettings('apply', ctx), /Could not read/);
  assert.deepEqual(mutations(calls), []);
  assert.equal(fs.existsSync(ctx.stateRoot), false);
}, { failRead: true }));

test('write failure retains backup and activation across reruns', () => scenario(({ ctx, state, prefs }) => {
  state.failWrite = true;
  assert.throws(() => applySettings('apply', ctx), /Command failed/);
  assert.ok(readPending(ctx).Finder.length);
  assert.equal(prefs.get('com.apple.finder').ShowPathbar, undefined);
  assert.equal(fs.readdirSync(path.join(ctx.stateRoot, 'macos/backups')).length, 1);
  state.failWrite = false;
  assert.equal(applySettings('apply', ctx), 0);
  assert.equal(prefs.get('com.apple.finder').ShowPathbar, true);
}));

test('a successful setter without persisted change fails verification', () => scenario(({ ctx, state }) => {
  state.ignoreWrite = true;
  assert.throws(() => applySettings('apply', ctx), /Saved value did not match/);
  assert.ok(readPending(ctx).Finder.length);
}));

test('machine policy detects desktops and supports local opt-out of name/power/NVRAM', () => scenario(({ ctx, state, calls }) => {
  state.desktop = true;
  assert.equal(loadPolicy(ctx).machine.name, 'Example-Mac-Studio');
  const file = path.join(ctx.home, '.config/dotfiles/macos-machine.json');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ name: null, power: null, nvram: null, dock: 'bottom' }));
  assert.equal(applySettings('apply', ctx), 0);
  assert.ok(!calls.some(([file, args]) => file === '/usr/sbin/scutil' && args[0] === '--set'));
}));

test('invalid activation target, duplicate group and machine power typo fail before writes', () => {
  for (const problem of ['activation', 'duplicate', 'power']) scenario(({ ctx, calls }) => {
    const filename = path.join(ctx.configDir, problem === 'power' ? 'macos-machines.json' : 'macos-settings.json');
    const config = JSON.parse(fs.readFileSync(filename));
    if (problem === 'activation') config.preferences[0].activation = 'arbitrary-command';
    if (problem === 'duplicate') config.preferences.push(config.preferences[0]);
    if (problem === 'power') config.laptop.power.ac.sleep = 'typo';
    fs.writeFileSync(filename, JSON.stringify(config));
    assert.throws(() => applySettings('apply', ctx));
    assert.deepEqual(mutations(calls), []);
  });
});

test('login item registration uses full path and remains idempotent', () => scenario(({ ctx, calls, loginPaths }) => {
  const filename = path.join(ctx.configDir, 'macos-settings.json');
  const config = JSON.parse(fs.readFileSync(filename));
  config.loginItems = [{ name: 'Test App' }];
  fs.writeFileSync(filename, JSON.stringify(config));
  fs.mkdirSync(path.join(ctx.home, 'Applications/Test App.app'), { recursive: true });
  applySettings('apply', ctx);
  assert.ok(loginPaths.has(path.join(ctx.home, 'Applications/Test App.app')));
  calls.length = 0;
  applySettings('apply', ctx);
  assert.ok(!calls.some(([file, args]) => file === '/usr/bin/osascript' && args[1].includes('make login item')));
}));

test('minimal profile does not register full-only login items', () => scenario(({ ctx, calls }) => {
  const filename = path.join(ctx.configDir, 'macos-settings.json');
  const config = JSON.parse(fs.readFileSync(filename));
  config.loginItems = [{ name: 'Test Full App', profile: 'full' }];
  fs.writeFileSync(filename, JSON.stringify(config));
  fs.mkdirSync(path.join(ctx.home, 'Applications/Test Full App.app'), { recursive: true });
  ctx.profile = 'minimal';
  applySettings('apply', ctx);
  assert.ok(!calls.some(([file]) => file === '/usr/bin/osascript'));
}));

test('activation only restarts pending apps on explicit command and retains login notice', () => scenario(({ ctx, calls }) => {
  queueActivation('Finder', ['paths'], ctx);
  queueActivation('Aqua Voice', ['hotkeys'], ctx);
  queueActivation('login', ['keyboard'], ctx);
  activationMain(['--status'], ctx);
  assert.deepEqual(calls, []);
  activate(ctx);
  assert.ok(calls.some(([file]) => file === '/usr/bin/killall'));
  assert.ok(calls.some(([file, args]) => file === '/usr/bin/open' && args.at(-1) === 'Aqua Voice'));
  assert.deepEqual(readPending(ctx), { login: ['keyboard'] });
  calls.length = 0;
  activate(ctx);
  assert.deepEqual(calls, []);
  activationMain(['--acknowledge-login'], ctx);
  assert.deepEqual(readPending(ctx), {});
}));

test('failed activation preserves pending state and retries successfully', () => scenario(({ ctx, state }) => {
  queueActivation('Finder', ['paths'], ctx);
  state.failActivate = true;
  assert.throws(() => activate(ctx), /Activation failed/);
  assert.deepEqual(readPending(ctx), { Finder: ['paths'] });
  state.failActivate = false;
  activate(ctx);
  assert.deepEqual(readPending(ctx), {});
}));

test('corrupt activation state is preserved and prevents settings writes', () => scenario(({ ctx, calls }) => {
  const file = path.join(ctx.stateRoot, 'macos/pending-activation.json');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, '{broken');
  assert.throws(() => applySettings('apply', ctx));
  assert.equal(fs.readFileSync(file, 'utf8'), '{broken');
  assert.deepEqual(mutations(calls), []);
}));

test('concurrent activation lock cannot lose pending entries', () => scenario(({ ctx }) => {
  queueActivation('Finder', ['paths'], ctx);
  const lock = path.join(ctx.stateRoot, 'macos/activation.lock');
  fs.mkdirSync(lock);
  assert.throws(() => queueActivation('Dock', ['icons'], ctx), /busy/);
  assert.deepEqual(readPending(ctx), { Finder: ['paths'] });
  fs.rmdirSync(lock);
  queueActivation('Dock', ['icons'], ctx);
  assert.deepEqual(readPending(ctx), { Finder: ['paths'], Dock: ['icons'] });
}));

test('activation cannot run between queueing and saving settings', () => scenario(({ ctx }) => {
  let saved = false;
  withQueuedActivation('Finder', ['paths'], ctx, () => {
    assert.throws(() => activate(ctx), /busy/);
    saved = true;
  });
  assert.equal(saved, true);
  assert.deepEqual(readPending(ctx), { Finder: ['paths'] });
}));

test('power parser handles each source and rejects unreadable data', () => {
  assert.deepEqual(parsePower('AC Power:\n sleep 0 (sleep prevented by app)\nBattery Power:\n sleep 5'), { ac: { sleep: 0 }, battery: { sleep: 5 } });
  assert.throws(() => parsePower('Permission denied'));
});

test('maintenance is explicit and dry-run preserves Launchpad data', () => scenario(({ ctx, calls }) => {
  maintain('spotlight', true, ctx);
  assert.deepEqual(calls, []);
  const file = path.join(ctx.home, 'Library/Application Support/Dock/test-database.db');
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, 'db');
  maintain('launchpad', true, ctx);
  assert.equal(fs.readFileSync(file, 'utf8'), 'db');
  assert.throws(() => maintain('unknown', false, ctx));
}));

test('migration has one screenshot shortcut owner and role-specific Dock location', () => {
  const config = JSON.parse(fs.readFileSync(path.join(configDir, 'macos-settings.json')));
  const roles = JSON.parse(fs.readFileSync(path.join(configDir, 'macos-machines.json')));
  assert.ok(!config.preferences.some(group => group.domain === 'com.apple.symbolichotkeys'));
  assert.ok(!config.preferences.some(group => group.domain === 'com.apple.dock' && 'orientation' in group.values));
  assert.equal(roles.laptop.dock, 'right');
  assert.equal(roles.desktop.dock, 'left');
});

test('native defaults accepts typed XML and preserves sibling keys', { skip: process.platform !== 'darwin' }, () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-native-defaults-'));
  try {
    const domain = path.join(directory, 'preferences');
    const expected = { enabled: true, list: ['日本語', 1], seconds: 0.001, animation: 0.1 };
    assert.equal(run('/usr/bin/defaults', ['write', domain, 'unrelated', '-string', 'preserve']).status, 0);
    assert.equal(run('/usr/bin/defaults', ['write', domain, 'managed', toPlist(expected)]).status, 0);
    const exported = run('/usr/bin/defaults', ['export', domain, '-']);
    assert.equal(exported.status, 0);
    assert.deepEqual(parsePlist(exported.stdout), { unrelated: 'preserve', managed: expected });
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
