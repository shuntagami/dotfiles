import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("installer", Path(__file__).with_name("install-cursor-notify.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallCursorNotifyTest(unittest.TestCase):
    def test_preserves_other_hooks_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            target = home / ".cursor/hooks.json"
            target.parent.mkdir()
            old = {"version": 1, "custom": True, "hooks": {
                "stop": [{"command": "node /tmp/cursor-hook.mjs stop 34567"}],
                "beforeSubmitPrompt": [{"command": "echo existing"}],
            }}
            target.write_text(json.dumps(old))
            self.assertTrue(installer.install(home))
            installed = json.loads(target.read_text())
            self.assertEqual(installed['hooks']['stop'][0], old['hooks']['stop'][0])
            self.assertEqual(installed['hooks']['beforeSubmitPrompt'], old['hooks']['beforeSubmitPrompt'])
            self.assertTrue(installed['custom'])
            self.assertEqual(len(installed['hooks']['stop']), 2)
            before = target.read_bytes()
            self.assertFalse(installer.install(home))
            self.assertEqual(target.read_bytes(), before)

    def test_fresh_install(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self.assertTrue(installer.install(home))
            data = json.loads((home / '.cursor/hooks.json').read_text())
            self.assertEqual(data['version'], 1)
            self.assertEqual(len(data['hooks']['stop']), 1)

    def test_invalid_config_is_not_overwritten(self):
        for value in ('not json', '[]', '{"version": 2}', '{"hooks": []}', '{"hooks": {"stop": {}}}'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                target = home / '.cursor/hooks.json'
                target.parent.mkdir()
                target.write_text(value)
                with self.assertRaises(ValueError):
                    installer.install(home)
                self.assertEqual(target.read_text(), value)
