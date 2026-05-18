const { spawnSync } = require('child_process');

function run(command, args, input) {
  const result = spawnSync(command, args, {
    input,
    encoding: 'utf8',
    stdio: ['pipe', 'ignore', 'ignore'],
    windowsHide: true,
  });

  return !result.error && result.status === 0;
}

function copy(text) {
  if (process.platform === 'win32') {
    return run('clip', [], text);
  }

  if (process.platform === 'darwin') {
    return run('pbcopy', [], text);
  }

  return (
    run('wl-copy', [], text) ||
    run('xclip', ['-selection', 'clipboard'], text) ||
    run('xsel', ['--clipboard', '--input'], text)
  );
}

module.exports = { copy };
