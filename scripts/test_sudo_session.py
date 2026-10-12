"""Run sudo caching and package setup against fake commands; never invoke real sudo."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
FAKE_COMMAND = r'''
import json, os
from pathlib import Path
import subprocess, sys
name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ['DOTFILES_TEST_USER_ROOT'])
state = root / 'sudo-cached'
with (root / 'commands.jsonl').open('a') as log:
    log.write(json.dumps([name, args]) + '\n')
if name == 'uname':
    print('Darwin')
elif name == 'sudo':
    if args == ['-v']:
        if os.environ.get('FAIL_SUDO'):
            sys.exit(17)
        if not state.exists():
            with (root / 'prompts').open('a') as log:
                log.write('authentication\n')
        state.touch()
    elif not state.exists():
        sys.exit(1)
elif name == 'brew':
    if args == ['shellenv']:
        sys.exit(0)
    if args and args[0] == 'bundle':
        if os.environ.get('HOMEBREW_SUDO_CHECKED') != '1':
            state.unlink(missing_ok=True)
            sys.exit(19)
        if not state.exists():
            sys.exit(20)
        (root / 'keeper-pid').write_text(os.environ['DOTFILES_SUDO_KEEPALIVE_PID'])
        (root / 'brewfile-path').write_text(args[2].split('=', 1)[1])
        for _ in range(3):
            subprocess.run([str(Path(sys.argv[0]).with_name('sudo')), '-n', 'installer'], check=True)
        sys.exit(int(os.environ.get('FAIL_BREW', '0')))
'''


class SudoSessionTest(unittest.TestCase):
    def prepare(self, root):
        fake_bin = root / 'bin'
        fake_bin.mkdir()
        for name in ['sudo', 'uname', 'brew']:
            target = fake_bin / name
            target.write_text('#!' + sys.executable + '\n' + FAKE_COMMAND)
            target.chmod(0o755)
        scripts = root / 'dotfiles/scripts'
        scripts.mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/sudo-session.sh', scripts)
        misc = root / 'dotfiles/misc'
        misc.mkdir()
        (misc / 'Brewfile').write_text('cask "google-chrome"\ncask "karabiner-elements" # full-only\n')
        env = dict(os.environ, DOTFILES_TEST_USER_ROOT=str(root), DOTFILES_PROFILE='minimal',
                   PATH=str(fake_bin) + os.pathsep + os.environ['PATH'])
        env.pop('DOTFILES_SUDO_KEEPALIVE_PID', None)
        env.pop('DOTFILES_SUDO_SESSION_OWNER', None)
        return scripts, env

    def assert_keeper_stopped(self, root):
        pid = int((root / 'keeper-pid').read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def run_packages(self, root, failure=''):
        scripts, env = self.prepare(root)
        # Redirect only the disposable script's explicit paths. HOME and the
        # real installed Homebrew stay untouched.
        text = (ROOT / 'scripts/install-packages.sh').read_text()
        text = text.replace('${HOME}', '${DOTFILES_TEST_USER_ROOT}')
        text = text.replace('$HOME/', '$DOTFILES_TEST_USER_ROOT/')
        text = text.replace('/opt/homebrew/bin/brew', str(root / 'bin/brew'))
        script = scripts / 'install-packages.sh'
        script.write_text(text)
        if failure == 'sudo':
            env['FAIL_SUDO'] = '1'
        elif failure:
            env['FAIL_BREW'] = failure
        return subprocess.run(['/bin/bash', str(script)], env=env, capture_output=True,
                              text=True, timeout=10)

    def test_standalone_packages_authenticate_once_and_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_packages(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / 'prompts').read_text().splitlines(), ['authentication'])
            self.assert_keeper_stopped(root)
            self.assertFalse(Path((root / 'brewfile-path').read_text()).exists())

    def test_failed_install_stops_keeper_and_preserves_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_packages(root, '42')
            self.assertEqual(result.returncode, 42, result.stderr)
            self.assert_keeper_stopped(root)
            self.assertFalse(Path((root / 'brewfile-path').read_text()).exists())

    def test_failed_authentication_never_starts_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_packages(root, 'sudo')
            self.assertEqual(result.returncode, 17, result.stderr)
            self.assertFalse((root / 'keeper-pid').exists())
            self.assertFalse((root / 'brewfile-path').exists())

    def test_nested_child_does_not_stop_parent_keeper(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts, env = self.prepare(root)
            parent = scripts / 'parent.sh'
            parent.write_text('''#!/bin/bash
set -euo pipefail
source "$DOTFILES_TEST_USER_ROOT/dotfiles/scripts/sudo-session.sh"
trap dotfiles_stop_sudo_session EXIT
dotfiles_start_sudo_session
printf '%s' "$DOTFILES_SUDO_KEEPALIVE_PID" > "$DOTFILES_TEST_USER_ROOT/keeper-pid"
/bin/bash -c 'source "$DOTFILES_TEST_USER_ROOT/dotfiles/scripts/sudo-session.sh"; dotfiles_start_sudo_session; dotfiles_stop_sudo_session'
kill -0 "$DOTFILES_SUDO_KEEPALIVE_PID"
''')
            result = subprocess.run(['/bin/bash', str(parent)], env=env, capture_output=True,
                                    text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / 'prompts').read_text().splitlines(), ['authentication'])
            self.assert_keeper_stopped(root)


if __name__ == '__main__':
    unittest.main()
