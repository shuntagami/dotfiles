const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { stageHtml } = require('../bin/upload_html_assets.cjs');

function fixture(t, files) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'test-upload-html-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const source = path.join(temp, 'source');
  const output = path.join(temp, 'output');
  fs.mkdirSync(source);
  for (const [name, content] of Object.entries(files)) {
    const file = path.join(source, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content);
  }
  return { temp, source, output, entry: path.join(source, 'report.html') };
}

test('音声とダウンロード先を同梱し、参照されていない秘密値は含めない', (t) => {
  const f = fixture(t, {
    'report.html': '<audio src="audio/test.mp3" controls></audio><a href="audio/test.wav">保存</a>',
    'audio/test.mp3': Buffer.from([0, 255, 12, 9]),
    'audio/test.wav': 'wave',
    '.env': 'SECRET=not-for-upload',
    'unrelated.json': 'private',
  });
  assert.deepEqual(stageHtml(f.entry, f.output).sort(), ['audio/test.mp3', 'audio/test.wav', 'index.html']);
  assert.deepEqual(fs.readFileSync(path.join(f.output, 'audio/test.mp3')), Buffer.from([0, 255, 12, 9]));
  assert.equal(fs.existsSync(path.join(f.output, '.env')), false);
});

test('HTML/CSSの入れ子・循環参照・ルート相対・文字エスケープを解決する', (t) => {
  const f = fixture(t, {
    'report.html': '<link href="css/main.css?v=1"><a href="pages/">次へ</a><audio src="音声%20A&amp;B.mp3#t=1"></audio>',
    'css/main.css': '@import "theme.css"; body {background:url(../images/a.png)}',
    'css/theme.css': '@import url(main.css); @font-face {src:url(/fonts/a.woff2)}',
    'images/a.png': 'image',
    'fonts/a.woff2': 'font',
    'pages/index.html': '<a href="/report.html">戻る</a>',
    '音声 A&B.mp3': 'audio',
  });
  assert.deepEqual(stageHtml(f.entry, f.output).sort(), [
    'css/main.css', 'css/theme.css', 'fonts/a.woff2', 'images/a.png', 'index.html',
    'pages/index.html', 'report.html', '音声 A&B.mp3',
  ].sort());
});

test('source・poster・srcset・inline CSS・scriptのsrcを含める', (t) => {
  const f = fixture(t, {
    'report.html': `<video poster="poster.jpg"><source src='clip.mp4'></video>
      <img srcset="small.png 1x, large.png 2x"><img srcset="data:image/png;base64,AA== 1x, large.png 2x">
      <div style="background:url(bg.png)"></div>
      <style>body {background:url('inline.png')}</style><script src="app.js"></script>`,
    'poster.jpg': 'x', 'clip.mp4': 'x', 'small.png': 'x', 'large.png': 'x',
    'bg.png': 'x', 'inline.png': 'x', 'app.js': 'x',
  });
  assert.equal(stageHtml(f.entry, f.output).length, 8);
});

test('外部URL・埋め込み・アンカー・コメント・JS本文をファイルとして扱わない', (t) => {
  const f = fixture(t, {
    'report.html': `<audio src="https://example.com/a.mp3"></audio><img src="//example.com/a.png">
      <a href="#here">本文</a><a href="mailto:x@example.com">連絡</a><a href="?q=1">検索</a>
      <img src="data:image/png;base64,AA=="><!-- <img src="missing.png"> -->
      <script>const example = '<audio src="not-a-file.mp3">';</script>`,
  });
  assert.deepEqual(stageHtml(f.entry, f.output), ['index.html']);
});

test('不足する音声を見逃さずエラーにする', (t) => {
  const f = fixture(t, { 'report.html': '<audio src="missing.mp3"></audio>' });
  assert.throws(() => stageHtml(f.entry, f.output), /Missing referenced file: missing.mp3/);
});

test('親ディレクトリとsymlink経由の外部ファイルを公開しない', (t) => {
  const f = fixture(t, { 'report.html': '<a href="../private.txt">秘密</a>' });
  fs.writeFileSync(path.join(f.temp, 'private.txt'), 'secret');
  assert.throws(() => stageHtml(f.entry, f.output), /outside the HTML directory/);
  fs.writeFileSync(f.entry, '<a href="linked.txt">秘密</a>');
  fs.symlinkSync(path.join(f.temp, 'private.txt'), path.join(f.source, 'linked.txt'));
  assert.throws(() => stageHtml(f.entry, f.output), /outside the HTML directory/);
});

test('公開先index.htmlの衝突とbase hrefを見逃さない', (t) => {
  const f = fixture(t, { 'report.html': '<a href="index.html">別ページ</a>', 'index.html': 'another page' });
  assert.throws(() => stageHtml(f.entry, f.output), /Conflicting published path/);
  fs.writeFileSync(f.entry, '<base href="https://example.com/"><audio src="a.mp3">');
  assert.throws(() => stageHtml(f.entry, f.output), /base href/);
});

test('CLIが音声入りの一時フォルダをNetlifyに渡し、終了後に片付ける', (t) => {
  const f = fixture(t, { 'report.html': '<audio src="a.mp3"></audio>', 'a.mp3': 'actual audio' });
  const fakeBin = path.join(f.temp, 'bin');
  fs.mkdirSync(fakeBin);
  const capture = path.join(f.temp, 'capture.json');
  fs.writeFileSync(path.join(fakeBin, 'netlify'), `#!${process.execPath}
const fs=require('node:fs');const path=require('node:path');const args=process.argv.slice(2);
const dir=args[args.indexOf('--dir')+1];
fs.writeFileSync(process.env.UPLOAD_TEST_CAPTURE,JSON.stringify({args,dir,files:fs.readdirSync(dir),audio:fs.readFileSync(path.join(dir,'a.mp3'),'utf8')}));
console.log(JSON.stringify({url:'https://example.netlify.app'}));`, { mode: 0o755 });
  const env = { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`, UPLOAD_TEST_CAPTURE: capture };
  const command = path.resolve(__dirname, '../bin/upload_html');
  const result = spawnSync(process.execPath, [command, '--site', 'test-site', f.entry], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'https://example.netlify.app');
  const sent = JSON.parse(fs.readFileSync(capture, 'utf8'));
  assert.deepEqual(sent.files.sort(), ['a.mp3', 'index.html']);
  assert.equal(sent.audio, 'actual audio');
  assert.ok(sent.args.includes('--prod'));
  assert.equal(sent.args[sent.args.indexOf('--site') + 1], 'test-site');
  assert.equal(fs.existsSync(sent.dir), false);

  fs.unlinkSync(capture);
  fs.unlinkSync(path.join(f.source, 'a.mp3'));
  const missing = spawnSync(process.execPath, [command, '--site', 'test-site', f.entry], { env, encoding: 'utf8' });
  assert.equal(missing.status, 1);
  assert.match(missing.stderr, /Missing referenced file/);
  assert.equal(fs.existsSync(capture), false, '不足時はNetlifyを呼ばない');
});
