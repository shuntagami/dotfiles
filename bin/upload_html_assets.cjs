const fs = require('node:fs');
const path = require('node:path');

function decodeEntities(value) {
  return value.replace(/&(?:amp|quot|apos|lt|gt|#\d+|#x[\da-f]+);/gi, (entity) => {
    const named = { '&amp;': '&', '&quot;': '"', '&apos;': "'", '&lt;': '<', '&gt;': '>' };
    if (named[entity.toLowerCase()]) return named[entity.toLowerCase()];
    const hex = entity.toLowerCase().startsWith('&#x');
    const code = parseInt(entity.slice(hex ? 3 : 2, -1), hex ? 16 : 10);
    return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : '\ufffd';
  });
}

function cssReferences(css) {
  const clean = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const refs = [];
  const pattern = /url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)]*))\s*\)|@import\s+(?:"([^"]*)"|'([^']*)')/gi;
  for (const match of clean.matchAll(pattern)) refs.push(match.slice(1).find((s) => s !== undefined));
  return refs;
}

function srcsetReferences(value) {
  const refs = [];
  let remaining = value;
  // URLの後の幅・密度指定を飛ばす。data URL内のカンマは区切りにしない。
  while (remaining.length) {
    remaining = remaining.replace(/^[\s,]+/, '');
    if (!remaining) break;
    const url = /^(?:data:\S+|[^\s,]+)/i.exec(remaining)?.[0];
    if (!url) break;
    refs.push(url.replace(/,+$/, ''));
    remaining = remaining.slice(url.length);
    if (!url.endsWith(',')) remaining = remaining.replace(/^[^,]*/, '');
  }
  return refs;
}

function htmlReferences(html) {
  const refs = [];
  // コメントやscript本文に書かれたHTML例は依存ファイルとして扱わない。
  const tokens = /<!--[\s\S]*?-->|<(script|style)\b((?:"[^"]*"|'[^']*'|[^'">])*)>([\s\S]*?)<\/\1\s*>|<([a-z][\w:-]*)\b((?:"[^"]*"|'[^']*'|[^'">])*)>/gi;
  for (const match of html.matchAll(tokens)) {
    if (match[0].startsWith('<!--')) continue;
    const tag = (match[1] || match[4]).toLowerCase();
    const attributes = match[2] ?? match[5];
    const attrs = new Map();
    const pattern = /([^\s=<>/'"]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g;
    for (const attribute of attributes.matchAll(pattern)) {
      attrs.set(attribute[1].toLowerCase(), decodeEntities(attribute[2] ?? attribute[3] ?? attribute[4]));
    }
    if (tag === 'base' && attrs.has('href')) {
      throw new Error('<base href> is not supported. Use paths relative to the HTML file.');
    }
    for (const attribute of ['src', 'href', 'poster']) {
      if (attrs.has(attribute)) refs.push(attrs.get(attribute));
    }
    if (tag === 'object' && attrs.has('data')) refs.push(attrs.get('data'));
    if (attrs.has('srcset')) refs.push(...srcsetReferences(attrs.get('srcset')));
    if (attrs.has('style')) refs.push(...cssReferences(attrs.get('style')));
    if (tag === 'style') refs.push(...cssReferences(match[3]));
  }
  return refs;
}

function isWithin(root, file) {
  const relative = path.relative(root, file);
  return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

/** HTMLと静的に参照されているファイルだけを、相対パスを保って公開用に集める。 */
function stageHtml(filePath, destination) {
  const entry = fs.realpathSync(filePath);
  const root = path.dirname(entry);
  const copied = new Map();
  const pending = [{ source: entry, target: 'index.html' }];

  while (pending.length) {
    const { source, target } = pending.shift();
    const real = fs.realpathSync(source);
    if (!isWithin(root, real)) throw new Error(`Referenced file is outside the HTML directory: ${source}`);
    if (!fs.statSync(real).isFile()) throw new Error(`Referenced path is not a file: ${source}`);
    if (copied.has(target)) {
      if (copied.get(target) !== real) throw new Error(`Conflicting published path: ${target}`);
      continue;
    }
    copied.set(target, real);
    const output = path.join(destination, target);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.copyFileSync(real, output);

    const extension = path.extname(source).toLowerCase();
    if (!['.html', '.htm', '.css'].includes(extension)) continue;
    const content = fs.readFileSync(real, 'utf8');
    const references = extension === '.css' ? cssReferences(content) : htmlReferences(content);
    for (const reference of references) {
      const value = reference.trim();
      if (!value || /^(?:[a-z][\w+.-]*:|\/\/|#|\?)/i.test(value)) continue;
      const urlPath = value.split(/[?#]/, 1)[0];
      const decoded = decodeURIComponent(urlPath);
      if (decoded.includes('\\') || decoded.includes('\0')) throw new Error(`Invalid asset path: ${value}`);
      const asset = decoded.startsWith('/')
        ? path.resolve(root, `.${decoded}`)
        : path.resolve(path.dirname(source), decoded);
      if (!isWithin(root, asset)) throw new Error(`Referenced file is outside the HTML directory: ${value}`);
      let resolved = asset;
      if (fs.existsSync(resolved) && fs.statSync(resolved).isDirectory()) resolved = path.join(resolved, 'index.html');
      if (!fs.existsSync(resolved)) throw new Error(`Missing referenced file: ${value} (from ${path.relative(root, source)})`);
      pending.push({ source: resolved, target: path.relative(root, resolved) });
    }
  }
  return [...copied.keys()];
}

module.exports = { stageHtml };
