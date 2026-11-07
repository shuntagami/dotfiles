// Shared macOS plist and command helpers. No npm dependencies or shell evaluation.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Settings are saved, but an app must be launched/restarted to finish setup.
export const NEEDS_APP_ACTION = 3;

export function run(file, args = [], options = {}) {
  const result = spawnSync(file, args, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, ...options });
  if (result.error) throw result.error;
  return result;
}

const unescapeXml = text => text.replace(/&(#x[\da-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, entity) => {
  const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
  return entity.startsWith('#')
    ? String.fromCodePoint(entity[1] === 'x' ? parseInt(entity.slice(2), 16) : Number(entity.slice(1)))
    : named[entity];
});
const escapeXml = text => String(text).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[char]);

// Input is XML emitted by the system plutil/defaults tools. Preserve NSData,
// dates, large integers and archived CF$UID references that JSON cannot hold.
export function parsePlist(xml) {
  const tokens = xml.replace(/<\?[\s\S]*?\?>|<!DOCTYPE[^>]*>|<!--[\s\S]*?-->/g, '').match(/<[^>]*>|[^<]+/g) ?? [];
  let index = 0;
  const skip = () => { while (tokens[index]?.trim() === '') index++; };
  const end = tag => {
    skip();
    if (tokens[index++] !== `</${tag}>`) throw new Error(`Invalid plist: expected </${tag}>`);
  };
  const read = () => {
    skip();
    const token = tokens[index++];
    const match = token?.match(/^<(\w+)(?:\s[^>]*?)?\s*(\/?)>$/);
    if (!match) throw new Error('Invalid plist element.');
    const [, tag, closed] = match;
    if (tag === 'true' || tag === 'false') {
      if (!closed) end(tag);
      return tag === 'true';
    }
    if (tag === 'plist') { const value = read(); end(tag); return value; }
    if (tag === 'dict' || tag === 'array') {
      const value = tag === 'dict' ? {} : [];
      if (closed) return value;
      skip();
      while (tokens[index] !== `</${tag}>`) {
        if (index >= tokens.length) throw new Error('Unterminated plist container.');
        if (tag === 'array') value.push(read());
        else {
          if (!/^<key(?:\s*\/?)>/.test(tokens[index])) throw new Error('Invalid plist dictionary key.');
          const key = read();
          Object.defineProperty(value, key, { value: read(), enumerable: true, writable: true, configurable: true });
        }
        skip();
      }
      end(tag);
      return value;
    }
    let text = '';
    if (!closed) {
      while (tokens[index] && !tokens[index].startsWith('<')) text += tokens[index++];
      end(tag);
    }
    if (tag === 'string' || tag === 'key') return unescapeXml(text);
    if (tag === 'data') return Buffer.from(text.replace(/\s/g, ''), 'base64');
    if (tag === 'date') return new Date(text.trim());
    if (tag === 'integer') {
      const value = BigInt(text.trim());
      return value <= BigInt(Number.MAX_SAFE_INTEGER) && value >= BigInt(Number.MIN_SAFE_INTEGER) ? Number(value) : value;
    }
    if (tag === 'real') return Number(text.trim());
    throw new Error(`Unsupported plist type: ${tag}`);
  };
  const value = read();
  skip();
  if (index !== tokens.length) throw new Error('Unexpected trailing plist content.');
  return value;
}

export function toPlist(value) {
  const encode = item => {
    if (Buffer.isBuffer(item)) return `<data>${item.toString('base64')}</data>`;
    if (item instanceof Date) return `<date>${item.toISOString().replace(/\.\d{3}Z$/, 'Z')}</date>`;
    if (Array.isArray(item)) return `<array>${item.map(encode).join('')}</array>`;
    if (typeof item === 'boolean') return item ? '<true/>' : '<false/>';
    if (typeof item === 'bigint') return `<integer>${item}</integer>`;
    if (typeof item === 'number' && Number.isFinite(item)) {
      const tag = Number.isInteger(item) ? 'integer' : 'real';
      return `<${tag}>${item}</${tag}>`;
    }
    if (typeof item === 'string') return `<string>${escapeXml(item)}</string>`;
    if (item && typeof item === 'object') return `<dict>${Object.entries(item).map(([key, entry]) => `<key>${escapeXml(key)}</key>${encode(entry)}`).join('')}</dict>`;
    throw new Error('Unsupported plist value.');
  };
  return `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0">${encode(value)}</plist>\n`;
}

export function createContext(options = {}) {
  const home = options.home ?? os.homedir();
  const ctx = {
    home, platform: process.platform, run, log: console.log,
    configDir: fileURLToPath(new URL('../misc/', import.meta.url)),
    stateRoot: path.join(process.env.XDG_STATE_HOME ?? path.join(home, '.local/state'), 'dotfiles'),
    ...options,
  };
  ctx.readPlist ??= input => {
    const result = ctx.run('/usr/bin/plutil', ['-convert', 'xml1', '-o', '-', '-'], { input });
    if (result.status !== 0) throw new Error('Could not decode plist with plutil.');
    return parsePlist(result.stdout);
  };
  ctx.preferences ??= domain => {
    const result = ctx.run('/usr/bin/defaults', ['export', domain, '-']);
    if (result.status === 0) return ctx.readPlist(result.stdout);
    if (`${result.stderr}${result.stdout}`.includes('does not exist')) return {};
    throw new Error(`Could not read ${domain} preferences; no settings for this domain were overwritten.`);
  };
  ctx.command ??= name => {
    for (const directory of (process.env.PATH ?? '').split(path.delimiter)) {
      const filename = path.join(directory, name);
      try { fs.accessSync(filename, fs.constants.X_OK); return filename; } catch {}
    }
    return null;
  };
  ctx.applications ??= () => {
    const apps = new Map();
    for (const root of ['/Applications', path.join(home, 'Applications')]) {
      if (!fs.existsSync(root)) continue;
      const candidates = fs.readdirSync(root).flatMap(name => {
        const entry = path.join(root, name);
        if (name.endsWith('.app')) return [entry];
        if (!fs.statSync(entry).isDirectory()) return [];
        return fs.readdirSync(entry).filter(child => child.endsWith('.app')).map(child => path.join(entry, child));
      });
      for (const app of candidates) {
        const info = path.join(app, 'Contents/Info.plist');
        if (!fs.existsSync(info)) continue;
        const result = ctx.run('/usr/bin/plutil', ['-extract', 'CFBundleIdentifier', 'raw', '-o', '-', info]);
        if (result.status === 0) apps.set(result.stdout.trim().toLowerCase(), app);
      }
    }
    return apps;
  };
  ctx.handler ??= extension => {
    const result = ctx.run(ctx.command('duti'), ['-x', extension]);
    return result.status === 0 ? result.stdout.trim().split('\n').at(-1) ?? '' : '';
  };
  return ctx;
}

export function writePlist(filename, value) {
  fs.writeFileSync(filename, toPlist(value), { mode: 0o600 });
}

export function parseMode(args) {
  if (!args.length || args.length === 1 && args[0] === '--apply') return 'apply';
  if (args.length === 1 && ['--check', '--dry-run', '--help', '-h'].includes(args[0])) return args[0] === '-h' ? 'help' : args[0].slice(2);
  throw new Error('Usage: [--apply|--check|--dry-run|--help]');
}

export function isMain(url) {
  return process.argv[1] && url === pathToFileURL(path.resolve(process.argv[1])).href;
}

export function cli(main) {
  try { process.exitCode = main(); } catch (error) { console.error(`Error: ${error.message}`); process.exitCode = 1; }
}
