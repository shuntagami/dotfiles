#!/usr/bin/env node
// Explicit maintenance commands. Never called by deploy or setup.
import fs from 'node:fs';
import path from 'node:path';
import { createContext, isMain, cli } from './macos-app-settings.mjs';

export function maintain(operation, dryRun, ctx) {
  const commands = {
    spotlight: ['/usr/bin/sudo', ['/usr/bin/mdutil', '-E', '/']],
    launchservices: ['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
      ['-kill', '-r', '-domain', 'local', '-domain', 'system', '-domain', 'user']],
  };
  if (operation === 'launchpad') {
    const directory = path.join(ctx.home, 'Library/Application Support/Dock');
    const files = fs.existsSync(directory) ? fs.readdirSync(directory)
      .filter(name => /^.+-.+\.db$/.test(name)).map(name => path.join(directory, name)) : [];
    for (const file of files) {
      ctx.log(`Remove Launchpad database: ${file}`);
      if (!dryRun) fs.unlinkSync(file);
    }
    if (!dryRun && files.length) ctx.log('Launchpad database removed. Restart Dock when convenient.');
    return 0;
  }
  const command = commands[operation];
  if (!command) throw new Error('Usage: macos-maintenance.mjs <spotlight|launchservices|launchpad> [--dry-run]');
  ctx.log(`${command[0]} ${command[1].join(' ')}`);
  if (!dryRun) {
    const result = ctx.run(...command, { stdio: 'inherit' });
    if (result.status !== 0) throw new Error(`${operation} maintenance failed.`);
  }
  return 0;
}

export function main(args = process.argv.slice(2), ctx = createContext()) {
  if (args.length < 1 || args.length > 2 || args.length === 2 && args[1] !== '--dry-run') throw new Error('Choose a maintenance operation and optional --dry-run.');
  if (ctx.platform !== 'darwin') { ctx.log('Skipping maintenance: requires macOS.'); return 0; }
  return maintain(args[0], args[1] === '--dry-run', ctx);
}

if (isMain(import.meta.url)) cli(main);
