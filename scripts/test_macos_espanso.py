import importlib.util
import json
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
