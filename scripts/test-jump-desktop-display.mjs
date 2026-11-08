import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { chooseFixTarget, differingKeys, mergeDisplaySettings, validatePolicy } from './jump-desktop-display.mjs';

const script = fileURLToPath(new URL('./jump-desktop-display.mjs', import.meta.url));
const policy = JSON.parse(fs.readFileSync(new URL('../misc/jump-desktop/display.json', import.meta.url), 'utf8'));
const viewerRunning = spawnSync('/usr/bin/pgrep', ['-f', '/Jump Desktop.app/Contents/MacOS/Jump Desktop']).status === 0;

// A saved connection with every managed key off, plus fields that must survive.
function connection(name) {
  return { DisplayName: name, ServerId: `secret-${name}`,
    ...Object.fromEntries(Object.keys(policy.settings).map(key => [key, key === 'NumberOfVirtualMonitors' ? 0 : false])) };
}

function isolated(names, callback) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-jump-display-'));
  const servers = path.join(home, 'Documents/JumpDesktop/Viewer/Servers');
  fs.mkdirSync(servers, { recursive: true });
  names.forEach((name, index) => fs.writeFileSync(path.join(servers, `${index}.jump`), JSON.stringify(connection(name))));
  const run = (...args) => spawnSync(process.execPath, [script, ...args], { env: { ...process.env, HOME: home }, encoding: 'utf8' });
  const read = index => JSON.parse(fs.readFileSync(path.join(servers, `${index}.jump`), 'utf8'));
  try { return callback({ run, read }); } finally { fs.rmSync(home, { recursive: true, force: true }); }
}

test('policy lists the Mac Studio and Mac mini connections', () => {
  validatePolicy(policy);
  assert.deepEqual(policy.displayNames, ['Shun-Tagami-Mac-Studio', 'Shun-Tagami-Mac-mini']);
});

test('policy validation rejects missing, empty and duplicate names', () => {
  for (const displayNames of [undefined, [], [''], ['A', 'A']]) {
    assert.throws(() => validatePolicy({ displayNames, settings: policy.settings }), /displayNames/);
  }
  assert.throws(() => validatePolicy({ displayNames: ['A'], settings: { Unknown: true } }), /Unsupported/);
});

test('merge applies to listed connections only and keeps other fields', () => {
  const merged = mergeDisplaySettings(connection('Shun-Tagami-Mac-mini'), policy);
  assert.equal(merged.ServerId, 'secret-Shun-Tagami-Mac-mini');
  assert.deepEqual(differingKeys(merged, policy), []);
  assert.equal(mergeDisplaySettings(connection('Other'), policy), null);
  const { UseHIDPIResolution, ...older } = connection('Shun-Tagami-Mac-mini');
  assert.throws(() => mergeDisplaySettings(older, policy), /missing UseHIDPIResolution/);
});

test('fix targets the only open session, or the named one', () => {
  assert.equal(chooseFixTarget(policy, ['Shun-Tagami-Mac-Studio', 'Jump Desktop'], undefined), 'Shun-Tagami-Mac-Studio');
  assert.equal(chooseFixTarget(policy, ['Shun-Tagami-Mac-Studio', 'Shun-Tagami-Mac-mini'], 'Shun-Tagami-Mac-mini'), 'Shun-Tagami-Mac-mini');
  assert.throws(() => chooseFixTarget(policy, [], undefined), /No session window/);
  assert.throws(() => chooseFixTarget(policy, policy.displayNames, undefined), /--fix <name>/);
  assert.throws(() => chooseFixTarget(policy, [], 'Other'), /not in displayNames/);
});

test('deploy without any registered connection is skipped', () => isolated(['Other'], ({ run, read }) => {
  const result = run('--deploy');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^Skipping: No connection named/);
  assert.equal(read(0).UseVirtualMonitors, false);
}));

test('apply updates every registered connection, skips missing ones, then reports no change',
  { skip: viewerRunning && 'Jump Desktop viewer is running' }, () => isolated(['Shun-Tagami-Mac-Studio', 'Other'], ({ run, read }) => {
    const check = run('--check');
    assert.equal(check.status, 1);
    assert.match(check.stdout, /Skipping "Shun-Tagami-Mac-mini"/);
    const applied = run();
    assert.equal(applied.status, 0, applied.stderr);
    assert.match(applied.stdout, /Applied to "Shun-Tagami-Mac-Studio"/);
    assert.deepEqual(differingKeys(read(0), policy), []);
    assert.equal(read(0).ServerId, 'secret-Shun-Tagami-Mac-Studio');
    assert.equal(read(1).UseVirtualMonitors, false);
    const again = run();
    assert.equal(again.status, 0, again.stderr);
    assert.match(again.stdout, /already match/);
    assert.equal(run('--check').status, 0);
  }));

test('duplicate connection names are refused before writing', () => isolated(['Shun-Tagami-Mac-mini', 'Shun-Tagami-Mac-mini'], ({ run, read }) => {
  const result = run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Multiple connections are named "Shun-Tagami-Mac-mini"/);
  assert.equal(read(0).UseVirtualMonitors, false);
}));
