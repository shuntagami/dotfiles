import importlib.util
import json
import plistlib
from types import SimpleNamespace
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('espanso_setup', Path(__file__).with_name('macos-espanso.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class EspansoTests(unittest.TestCase):
    def test_native_dictionary_conversion_and_conflicts(self):
        matches, conflicts = setup.convert([
            {'replace': 'gm', 'with': 'one@example.com'},
            {'replace': 'gm', 'with': 'one@example.com'},
            {'replace': 'off', 'with': 'ignored', 'on': False},
            {'replace': 'bad', 'with': 'a'}, {'replace': 'bad', 'with': 'b'},
        ], ';')
        self.assertEqual(matches, [{'trigger': ';gm', 'replace': 'one@example.com'}])
        self.assertEqual(conflicts, 1)

    def test_special_text_survives_serialization(self):
        text = '日本語 "quoted"\\path\nnext\tline'
        matches, _ = setup.convert([{'replace': 'test', 'with': text}], ';')
        self.assertEqual(json.loads(json.dumps(matches))[0]['replace'], text)

    def test_native_prefixed_conflict_is_rejected(self):
        with self.assertRaises(ValueError):
            setup.convert([{'replace': 'gm', 'with': 'a'}, {'replace': ';gm', 'with': 'b'}], ';')

    def test_dynamic_text_is_not_interpreted(self):
        for text in ['{{date}}', '$|$cursor']:
            with self.assertRaises(ValueError):
                setup.convert([{'replace': 'gm', 'with': text}], ';')

    def test_uncreated_chrome_domain_is_backed_up_as_unset(self):
        calls = []
        def fake_run(args, **kwargs):
            calls.append(args)
            if args[1] == 'domains':
                return SimpleNamespace(returncode=0, stdout='com.apple.TextEdit')
            if args[1] == 'export':
                self.assertEqual(args[2], 'NSGlobalDomain')
                return SimpleNamespace(returncode=0, stdout=plistlib.dumps({}).decode())
            return SimpleNamespace(returncode=0, stdout='0')
        with tempfile.TemporaryDirectory() as folder, patch.object(setup, 'STATE', Path(folder)), patch.object(setup, 'run', fake_run):
            setup.disable_system_replacements()
            saved = json.loads((Path(folder) / 'native-text-replacement-preferences.json').read_text())
        self.assertIsNone(saved['com.google.Chrome']['WebAutomaticTextReplacementEnabled'])
        self.assertTrue(any(args[1:3] == ['write', 'com.google.Chrome'] for args in calls))

    def test_existing_domain_read_error_is_not_treated_as_missing(self):
        calls = []
        def fake_run(args, **kwargs):
            calls.append(args)
            if args[1] == 'domains':
                return SimpleNamespace(returncode=0, stdout='com.google.Chrome')
            if args[2] == 'NSGlobalDomain':
                return SimpleNamespace(returncode=0, stdout=plistlib.dumps({}).decode())
            return SimpleNamespace(returncode=1, stdout='')
        with tempfile.TemporaryDirectory() as folder, patch.object(setup, 'STATE', Path(folder)), patch.object(setup, 'run', fake_run):
            with self.assertRaises(ValueError):
                setup.disable_system_replacements()
        self.assertFalse(any(args[1] == 'write' for args in calls))

    def test_private_replacement_never_becomes_world_readable(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'matches.yml'
            target.write_text('old')
            target.chmod(0o644)
            setup.private_write(target, 'new')
            self.assertEqual(target.read_text(), 'new')
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_existing_configuration_is_backed_up_before_linking(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, target = root / 'tracked.yml', root / 'default.yml'
            source.write_text('backend: clipboard')
            target.write_text('custom: true')
            with patch.object(setup, 'STATE', root / 'backups'):
                setup.install_config(source, target)
                setup.install_config(source, target)
            backups = list((root / 'backups').iterdir())
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), 'custom: true')
            self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
            self.assertEqual(target.resolve(), source.resolve())


if __name__ == '__main__':
    unittest.main()
