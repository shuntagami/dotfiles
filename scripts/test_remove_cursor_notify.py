import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("installer", Path(__file__).with_name("remove-cursor-notify.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class RemoveCursorNotifyTest(unittest.TestCase):
    def test_preserves_other_hooks_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            target = home / ".cursor/hooks.json"
            target.parent.mkdir()
            old = {"version": 1, "custom": True, "hooks": {
                "stop": [{"command": "node /tmp/cursor-hook.mjs stop 34567"}],
                "beforeSubmitPrompt": [{"command": "echo existing"}],
            }}
            old["hooks"]["stop"].append({"command": "python3 " + str(installer.ROOT / "scripts/agent-notify.py") + " cursor"})
            target.write_text(json.dumps(old))
            self.assertTrue(installer.remove(home))
            installed = json.loads(target.read_text())
            self.assertEqual(installed['hooks']['stop'][0], old['hooks']['stop'][0])
            self.assertEqual(installed['hooks']['beforeSubmitPrompt'], old['hooks']['beforeSubmitPrompt'])
            self.assertTrue(installed['custom'])
            self.assertEqual(len(installed['hooks']['stop']), 1)
            before = target.read_bytes()
            self.assertFalse(installer.remove(home))
            self.assertEqual(target.read_bytes(), before)

    def test_missing_config_is_not_created(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            self.assertFalse(installer.remove(home))
            self.assertFalse((home / '.cursor/hooks.json').exists())

    def test_only_legacy_hook_removes_file_for_mulmoterminal_to_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            target = home / '.cursor/hooks.json'
            target.parent.mkdir()
            command = 'python3 ' + str(installer.ROOT / 'scripts/agent-notify.py') + ' cursor'
            target.write_text(json.dumps({'version': 1, 'hooks': {'stop': [{'command': command}]}}))
            self.assertTrue(installer.remove(home))
            self.assertFalse(target.exists())
            self.assertFalse(installer.remove(home))

    def test_invalid_config_is_not_overwritten(self):
        for value in ('not json', '[]', '{"version": 2}', '{"hooks": []}', '{"hooks": {"stop": {}}}'):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                target = home / '.cursor/hooks.json'
                target.parent.mkdir()
                target.write_text(value)
                with self.assertRaises(ValueError):
                    installer.remove(home)
                self.assertEqual(target.read_text(), value)
