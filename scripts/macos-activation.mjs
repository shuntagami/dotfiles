#!/usr/bin/env node
// Settings writes queue activation before mutation; only --apply restarts apps.
import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { createContext, isMain, cli } from './macos-app-settings.mjs';

const targets = new Set(['Dock', 'Finder', 'Activity Monitor', 'Aqua Voice', 'Clipy', 'CleanShot X', 'Karabiner-Elements', 'login']);
const stateFile = ctx => path.join(ctx.stateRoot, 'macos/pending-activation.json');
export function validateTarget(target) {
  if (!targets.has(target)) throw new Error(`Unknown activation target: ${target}`);
}

function withLock(ctx, callback) {
  const directory = path.dirname(stateFile(ctx));
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const lock = path.join(directory, 'activation.lock');
  try { fs.mkdirSync(lock, { mode: 0o700 }); }
  catch (error) {
    if (error.code === 'EEXIST') throw new Error(`Activation state is busy. Retry after the other deploy/activation finishes. If it crashed, inspect and remove ${lock}.`);
    throw error;
  }
  try { return callback(); } finally { fs.rmdirSync(lock); }
}

export function readPending(ctx) {
  const file = stateFile(ctx);
  const pending = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
  if (!pending || Array.isArray(pending) || typeof pending !== 'object' ||
      Object.entries(pending).some(([target, reasons]) => !targets.has(target) ||
        !Array.isArray(reasons) || reasons.some(reason => typeof reason !== 'string'))) {
    throw new Error('Invalid pending activation state; preserved for inspection.');
  }
  return pending;
}

function savePending(pending, ctx) {
  const file = stateFile(ctx);
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temporary, JSON.stringify(pending, null, 2) + '\n', { mode: 0o600 });
    fs.renameSync(temporary, file);
  } finally { fs.rmSync(temporary, { force: true }); }
}

// No commands are accepted from the state file; targets resolve through this module.
export function queueActivation(target, reasons, ctx) {
  return withQueuedActivation(target, reasons, ctx, () => {});
}

// Hold the same lock through both queueing and the write, so an explicit
// activation cannot clear the entry before the new settings have been saved.
export function withQueuedActivation(target, reasons, ctx, mutate) {
  validateTarget(target);
  if (!Array.isArray(reasons) || !reasons.length || reasons.some(reason => typeof reason !== 'string')) throw new Error('Invalid activation reasons.');
  return withLock(ctx, () => {
    const pending = readPending(ctx);
    const next = [...new Set([...(pending[target] ?? []), ...reasons])].sort();
    if (!isDeepStrictEqual(pending[target], next)) savePending({ ...pending, [target]: next }, ctx);
    return mutate();
  });
}

export function reportPending(ctx) {
  const pending = readPending(ctx);
  for (const [target, reasons] of Object.entries(pending)) ctx.log(`Pending ${target}: ${reasons.join(', ')}`);
  if (Object.keys(pending).length) ctx.log('Activate when convenient: node ~/dotfiles/scripts/macos-activation.mjs --apply');
  return pending;
}

function checked(ctx, file, args) {
  const result = ctx.run(file, args);
  if (result.status !== 0) throw new Error(`Activation failed: ${file} ${args.join(' ')}`);
}

function activatePending(ctx) {
  const pending = readPending(ctx);
  for (const target of Object.keys(pending)) {
    if (target === 'login') {
      ctx.log('Log out/in or restart this Mac to load pending session settings.'); continue;
    } else if (target === 'Karabiner-Elements') {
      const domain = `gui/${process.getuid()}`;
      for (const name of ['Karabiner-Console-User-Server', 'karabiner_console_user_server']) {
        const service = `${domain}/org.pqrs.service.agent.${name}`;
        const result = ctx.run('/bin/launchctl', ['print', service]);
        if (result.status === 0) { checked(ctx, '/bin/launchctl', ['kickstart', '-k', service]); break; }
        if (![113, 3].includes(result.status)) throw new Error('Could not inspect Karabiner service; activation remains pending.');
      }
    } else {
      const running = ctx.run('/usr/bin/pgrep', ['-x', target]);
      if (running.status !== 1) {
        if (running.status !== 0) throw new Error(`Could not inspect ${target}; activation remains pending.`);
        if (['Dock', 'Finder', 'Activity Monitor'].includes(target)) {
          checked(ctx, '/usr/bin/killall', [target]);
        } else {
          checked(ctx, '/usr/bin/osascript', ['-e', `tell application "${target}" to quit`]);
          // A successful Apple event does not prove the process finished quitting.
          for (let attempt = 0; attempt < 50; attempt++) {
            const result = ctx.run('/usr/bin/pgrep', ['-x', target]);
            if (result.status === 1) break;
            if (result.status !== 0 || attempt === 49) throw new Error(`${target} did not quit; activation remains pending.`);
            checked(ctx, '/bin/sleep', ['0.1']);
          }
          checked(ctx, '/usr/bin/open', ['-g', '-a', target]);
        }
      }
    }
    // A stopped app loads the saved settings on next launch. Keep entries for
    // later targets if any command fails; commit progress after each success.
    delete pending[target];
    savePending(pending, ctx);
    ctx.log(`Activated ${target}`);
  }
  reportPending(ctx);
}

export function activate(ctx) {
  if (!Object.keys(readPending(ctx)).length) return;
  withLock(ctx, () => activatePending(ctx));
}

export function main(args = process.argv.slice(2), ctx = createContext()) {
  if (ctx.platform !== 'darwin') { ctx.log('Skipping activation: requires macOS.'); return 0; }
  if (!args.length || args.length === 1 && args[0] === '--status') { reportPending(ctx); return 0; }
  if (args[0] === '--queue' && args.length >= 3) { queueActivation(args[1], args.slice(2), ctx); return 0; }
  if (args.length === 1 && args[0] === '--acknowledge-login') {
    withLock(ctx, () => {
      const pending = readPending(ctx);
      if ('login' in pending) { delete pending.login; savePending(pending, ctx); }
    });
    reportPending(ctx);
    return 0;
  }
  if (args.length === 1 && args[0] === '--apply') { activate(ctx); return 0; }
  throw new Error('Usage: macos-activation.mjs [--status|--apply|--acknowledge-login]');
}

if (isMain(import.meta.url)) cli(main);
