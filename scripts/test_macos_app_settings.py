"""Verify settings preservation and false-success detection without changing this Mac."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hotkeys = load('macos-app-hotkeys')
defaults = load('macos-default-apps')


class AquaSettingsTests(unittest.TestCase):
    def test_apply_preserves_custom_actions_and_unrelated_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = root / 'Library/Application Support/Aqua Voice/settings.json'
            settings.parent.mkdir(parents=True)
            settings.write_text(json.dumps({
                'hotkeys': [{'action': 'activate', 'keys': 'Old', 'customField': True},
                            {'action': 'open_note', 'keys': 'Custom'}],
                'unrelated': {'value': 'preserve'},
            }))
            with patch.object(hotkeys.Path, 'home', return_value=root), patch.object(hotkeys, 'backup'), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(hotkeys.aqua('apply'), 0)
                updated = json.loads(settings.read_text())
                self.assertEqual(updated['unrelated'], {'value': 'preserve'})
                self.assertIn({'action': 'open_note', 'keys': 'Custom'}, updated['hotkeys'])
                self.assertIn({'action': 'activate', 'keys': 'Fn', 'customField': True}, updated['hotkeys'])
                before = settings.read_bytes()
                self.assertEqual(hotkeys.aqua('apply'), 0)
                self.assertEqual(settings.read_bytes(), before)

    def test_check_does_not_write_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            settings = root / 'Library/Application Support/Aqua Voice/settings.json'
            settings.parent.mkdir(parents=True)
            settings.write_text('{"hotkeys": [], "unrelated": 42}\n')
            before = settings.read_bytes()
            with patch.object(hotkeys.Path, 'home', return_value=root), patch.object(hotkeys, 'backup') as backup, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(hotkeys.aqua('check'), 1)
                backup.assert_not_called()
            self.assertEqual(settings.read_bytes(), before)


class FileAssociationTests(unittest.TestCase):
    def exercise(self, option, accept):
        with tempfile.TemporaryDirectory() as directory, contextlib.ExitStack() as stack:
            root = Path(directory)
            config = root / 'default-apps.json'
            config.write_text(json.dumps({
                'fileAssociations': [{'name': 'Acrobat',
                                      'bundleIds': ['com.adobe.Acrobat.Pro', 'com.adobe.Reader'],
                                      'extensions': ['pdf']}],
                'screenshots': {'bundleId': 'pl.maketheweb.cleanshotx',
                                'shortcuts': {}, 'disabledSystemShortcuts': []},
            }))
            current = ['com.apple.Preview']
            writes = []

            def run(*args):
                if args[0] == 'duti' and args[1] == '-s':
                    writes.append(args)
                    if accept:
                        current[0] = args[2].lower()
                return subprocess.CompletedProcess(args, 0, '', '')

            stack.enter_context(patch.object(defaults, 'CONFIG', config))
            stack.enter_context(patch.object(defaults.sys, 'platform', 'darwin'))
            stack.enter_context(patch.object(defaults.sys, 'argv', ['script', option]))
            stack.enter_context(patch.object(defaults.shutil, 'which', return_value='duti'))
            stack.enter_context(patch.object(defaults, 'applications', return_value={
                'com.adobe.reader': root / 'Reader.app',
                'pl.maketheweb.cleanshotx': root / 'CleanShot X.app',
            }))
            stack.enter_context(patch.object(defaults, 'handler', side_effect=lambda *_: current[0]))
            stack.enter_context(patch.object(defaults, 'preferences', return_value={}))
            stack.enter_context(patch.object(defaults, 'run', side_effect=run))
            stack.enter_context(patch.object(defaults.Path, 'home', return_value=root))
            stack.enter_context(patch.dict(defaults.os.environ, {'XDG_STATE_HOME': str(root / 'state')}))
            stack.enter_context(patch.object(defaults.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
            result = defaults.main()
            return result, writes, (root / 'state').exists()

    def test_successful_setter_without_actual_change_fails(self):
        result, writes, backed_up = self.exercise('--apply', accept=False)
        self.assertEqual(result, 1)
        self.assertEqual(len(writes), 1)
        self.assertTrue(backed_up)

    def test_reader_fallback_accepts_case_insensitive_bundle_id(self):
        result, writes, _ = self.exercise('--apply', accept=True)
        self.assertEqual(result, 0)
        self.assertEqual(writes[0][2], 'com.adobe.Reader')

    def test_dry_run_makes_no_writes_or_backups(self):
        result, writes, backed_up = self.exercise('--dry-run', accept=False)
        self.assertEqual(result, 0)
        self.assertEqual(writes, [])
        self.assertFalse(backed_up)

    def test_preferences_read_error_is_not_treated_as_empty(self):
        with patch.object(defaults, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'Permission denied')):
            with self.assertRaises(RuntimeError):
                defaults.preferences('test.domain')


if __name__ == '__main__':
    unittest.main()
