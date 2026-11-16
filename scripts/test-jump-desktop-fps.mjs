import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const source = fileURLToPath(new URL('./jump-desktop-fps.applescript', import.meta.url));
const wrapper = fs.readFileSync(new URL('../bin/jump-fps', import.meta.url), 'utf8');

test('session selection handles multiple displays without controlling the UI',
  { skip: process.platform !== 'darwin' }, () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'jump-fps-test-'));
    try {
      const compiled = path.join(dir, 'fps.scpt');
      const compile = spawnSync('/usr/bin/osacompile', ['-o', compiled, source], { encoding: 'utf8' });
      assert.equal(compile.status, 0, compile.stderr);
      const run = expression => spawnSync('/usr/bin/osascript', ['-e',
        `set fpsScript to load script POSIX file ${JSON.stringify(compiled)}\n${expression}`,
      ], { encoding: 'utf8' });
      const choose = (names, requested = '') => run(
        `return fpsScript's chooseSession({${names.map(x => JSON.stringify(x)).join(',')}}, ${JSON.stringify(requested)})`);

      for (const names of [
        ['Studio'],
        ['Studio', 'Studio - Display 2'],
        ['Studio - Display 12', 'Studio - Display 2', 'Studio'],
        ['Studio - Display 2'], // No base title: preserve the literal name.
      ]) {
        const result = choose(names);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(result.stdout.trim(), names.length === 1 ? names[0] : 'Studio');
      }
      for (const names of [
        ['Studio', 'Studio - Display 2', 'Mini', 'Mini - Display 2'],
        ['Studio', 'Settings'],
        ['Studio', 'Studio - Display backup'],
        ['Studio', 'Studio - Display 2 extra'],
        ['Studio', 'Studio - Display '],
      ]) {
        const result = choose(names);
        assert.notEqual(result.status, 0);
        assert.match(result.stderr, /接続先を特定できません/);
        assert.match(result.stderr, /「Studio」, 「/);
      }
      const explicit = choose(['Studio', 'Studio - Display 2', 'Mini'], 'Mini');
      assert.equal(explicit.status, 0, explicit.stderr);
      assert.equal(explicit.stdout.trim(), 'Mini');
      assert.match(choose(['Studio'], 'Missing').stderr, /接続先「Missing」が見つかりません/);
      assert.match(choose([]).stderr, /接続が見つかりません/);

      const menu = run(`return fpsScript's chooseSession(fpsScript's windowNamesFrom({"Minimize", missing value, "Bring All to Front", missing value, "Jump Desktop", "Studio", "Studio - Display 2"}), "")`);
      assert.equal(menu.status, 0, menu.stderr);
      assert.equal(menu.stdout.trim(), 'Studio');
      const empty = run(`return fpsScript's chooseSession(fpsScript's windowNamesFrom({"Minimize", missing value, "Jump Desktop"}), "")`);
      assert.match(empty.stderr, /接続が見つかりません/);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

test('CLI preserves session arguments locally and through the SSH shell', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'jump-fps-cli-test-'));
  try {
    fs.mkdirSync(path.join(dir, 'bin'));
    fs.mkdirSync(path.join(dir, 'scripts'));
    fs.copyFileSync(source, path.join(dir, 'scripts/jump-desktop-fps.applescript'));
    const hostname = path.join(dir, 'hostname');
    const osascript = path.join(dir, 'osascript');
    const ssh = path.join(dir, 'ssh');
    fs.writeFileSync(osascript, `#!/usr/bin/env node
const fs = require('node:fs');
console.log(JSON.stringify({args: process.argv.slice(2), stdin: fs.readFileSync(0, 'utf8')}));
`, { mode: 0o755 });
    fs.writeFileSync(ssh, `#!/usr/bin/env node
const {spawnSync} = require('node:child_process');
const result = spawnSync('/bin/sh', ['-c', process.argv.at(-1)], {stdio: 'inherit'});
process.exit(result.status ?? 1);
`, { mode: 0o755 });
    const script = path.join(dir, 'bin/jump-fps');
    fs.writeFileSync(script, wrapper.replaceAll('/bin/hostname', hostname)
      .replaceAll('/usr/bin/osascript', osascript).replaceAll('/usr/bin/ssh', ssh));
    const session = "Studio's Mac $(false) `false` ; $USER \"quoted\"";
    for (const host of ['Shun-Tagami-MBP', 'Shun-Tagami-Mac-Studio']) {
      fs.writeFileSync(hostname, `#!/bin/sh\necho ${host}\n`, { mode: 0o755 });
      for (const args of [[], ['30'], ['stats', session], ['29.97', session]]) {
        const result = spawnSync('/bin/bash', [script, ...args], { encoding: 'utf8' });
        assert.equal(result.status, 0, result.stderr);
        const actual = JSON.parse(result.stdout);
        assert.deepEqual(actual.args.slice(1), args.length ? args : ['status']);
        if (host === 'Shun-Tagami-MBP') {
          assert.equal(actual.args[0], path.join(dir, 'scripts/jump-desktop-fps.applescript'));
        } else {
          assert.equal(actual.args[0], '-');
          assert.equal(actual.stdin, fs.readFileSync(source, 'utf8'));
        }
      }
      for (const args of [['30', ''], ['30', 'Studio', 'extra'], ['bogus']]) {
        const result = spawnSync('/bin/bash', [script, ...args], { encoding: 'utf8' });
        assert.equal(result.status, 2, result.stderr);
        assert.match(result.stderr, /Usage:/);
      }
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
