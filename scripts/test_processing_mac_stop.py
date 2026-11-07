"""Exercise source shutdown over fake SSH without touching apps or real services."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
FAKE = r'''
import json, os, subprocess, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ['PROCESSING_STOP_TEST_ROOT'])
if name == 'ssh':
    sys.exit(subprocess.call(['/bin/bash', '-s'], stdin=sys.stdin))
if name == 'cat':
    if args: print('test-token')
    else: sys.stdout.buffer.write(sys.stdin.buffer.read())
    sys.exit(0)
p = root / 'state.json'
s = json.loads(p.read_text())
s['calls'].append([name, *args])
result = 0
if name == 'launchctl':
    label = args[1].split('/', 2)[-1]
    if args[0] == 'bootout':
        if s['alreadyStopped']: result = 1
        else: s['pending'][label] = 3
    elif args[0] == 'print':
        if s['alreadyStopped']: result = 1
        elif label in s['pending']:
            if not s['stuck']:
                s['pending'][label] -= 1
                result = 1 if s['pending'][label] <= 0 else 0
elif name == 'curl':
    url = args[-1]
    if url.endswith('/drain'): print('200', end='')
    elif ':8091/' in url:
        if s['alreadyStopped'] or 'com.ele-inc.scribe-bot.slack' in s['pending']: result = 7
        else: print('{"active":0}')
    else:
        label = 'com.ele-inc.marunage-studio.runtime' if ':8080/' in url else (
            'com.ele-inc.marunage-studio.web' if ':3100/' in url else 'com.ele-inc.launch-video-gen.web')
        result = 7 if s['alreadyStopped'] or label in s['pending'] else 0
p.write_text(json.dumps(s))
sys.exit(result)
'''


class SourceShutdownTests(unittest.TestCase):
    def stop(self, module, function, *, already_stopped=False, stuck=False):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            for name in ('ssh', 'launchctl', 'curl', 'sleep', 'cat'):
                command = bin_dir / name
                command.write_text(f'#!{sys.executable}\n' + FAKE)
                command.chmod(0o755)
            state = root / 'state.json'
            state.write_text(json.dumps({'alreadyStopped': already_stopped, 'stuck': stuck, 'pending': {}, 'calls': []}))
            script = 'FROM=test-source\nsource "$1/scripts/processing-mac/lib.sh"\nsource "$1/scripts/processing-mac/$2.sh"\n"$3"'
            result = subprocess.run(['/bin/bash', '-euc', script, 'test', str(ROOT), module, function],
                                    env=dict(os.environ, PROCESSING_STOP_TEST_ROOT=str(root),
                                             PATH=str(bin_dir) + os.pathsep + os.environ['PATH']),
                                    capture_output=True, text=True, timeout=15)
            return result, json.loads(state.read_text())

    def test_waits_for_delayed_launchd_deregistration(self):
        for module, function in [('scribe', 'scribe_stop_old'), ('launch-video-gen', 'lvg_stop_old'),
                                 ('marunage-studio', 'marunage_stop_old')]:
            with self.subTest(module=module):
                result, state = self.stop(module, function)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(any(call[0] == 'sleep' for call in state['calls']))

    def test_stuck_jobs_still_fail(self):
        for module, function in [('scribe', 'scribe_stop_old'), ('launch-video-gen', 'lvg_stop_old'),
                                 ('marunage-studio', 'marunage_stop_old')]:
            with self.subTest(module=module):
                result, _ = self.stop(module, function, stuck=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('止まりません', result.stderr)

    def test_already_stopped_scribe_does_not_wait_for_missing_http_status(self):
        result, state = self.stop('scribe', 'scribe_stop_old', already_stopped=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call[0] in ('curl', 'sleep') for call in state['calls']))


if __name__ == '__main__':
    unittest.main()
