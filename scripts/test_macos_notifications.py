"""Notification deploy never opens UI; profile installation is an explicit action."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
FAKE = r'''
import os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
with (Path(os.environ['NOTIFICATION_TEST_ROOT']) / 'commands.log').open('a') as stream:
    stream.write(name + ' ' + ' '.join(sys.argv[1:]) + '\n')
if name == 'uname':
    print('Darwin')
elif name == 'profiles' and os.environ.get('PROFILE_INSTALLED'):
    print('[1] attribute: profileIdentifier: local.dotfiles.notifications')
    if '-verbose' in sys.argv:
        print('[1] attribute: installationDate: 2000-01-01 00:00:00 +0000')
'''


@unittest.skipUnless(sys.platform == 'darwin', 'native plutil/shasum required')
class NotificationDeployTest(unittest.TestCase):
    def test_repeated_deploy_does_not_open_missing_pending_or_changed_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / 'home'
            home.mkdir()
            repo = root / 'repo'
            (repo / 'scripts').mkdir(parents=True)
            (repo / 'misc').mkdir()
            source = ROOT / 'scripts/macos-notifications.sh'
            script = repo / 'scripts' / source.name
            # Redirect only the script's output paths; never alter real HOME.
            script.write_text(source.read_text().replace('${HOME}', '${NOTIFICATION_TEST_HOME}'))
            shutil.copyfile(ROOT / 'misc/notifications.mobileconfig', repo / 'misc/notifications.mobileconfig')
            fake_bin = root / 'bin'
            fake_bin.mkdir()
            for name in ('uname', 'defaults', 'profiles', 'open'):
                file = fake_bin / name
                file.write_text(f'#!{sys.executable}\n' + FAKE)
                file.chmod(0o755)
            env = dict(os.environ, NOTIFICATION_TEST_ROOT=str(root), NOTIFICATION_TEST_HOME=str(home),
                       XDG_STATE_HOME=str(home / 'state'), PATH=str(fake_bin) + ':' + os.environ['PATH'])
            state = home / 'state/dotfiles/notifications-profile.sha256'
            def run(*args):
                result = subprocess.run(['/bin/bash', str(script), *args], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                return result.stdout
            for _ in range(2):
                self.assertIn('Pending approval', run())
            self.assertFalse(state.exists())
            self.assertFalse(any(line.startswith('open ') for line in (root / 'commands.log').read_text().splitlines()))
            run('--install-profile')
            self.assertTrue(state.exists())
            snapshot = state.read_bytes()
            self.assertEqual(sum(line.startswith('open ') for line in (root / 'commands.log').read_text().splitlines()), 1)
            run()
            env['PROFILE_INSTALLED'] = '1'
            state.write_text('old-hash 1\n')
            run()
            self.assertEqual(state.read_text(), 'old-hash 1\n')
            self.assertEqual(sum(line.startswith('open ') for line in (root / 'commands.log').read_text().splitlines()), 1)
            self.assertNotEqual(snapshot, state.read_bytes())


if __name__ == '__main__':
    unittest.main()
