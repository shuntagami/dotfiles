import importlib.util
import json
from pathlib import Path
import plistlib
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

spec = importlib.util.spec_from_file_location("macos_raycast", Path(__file__).with_name("macos-raycast.py"))
raycast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(raycast)


class RaycastSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.settings = self.root / "settings.json"
        self.settings.write_text('{"snippets":{"expansionMode":"Immediately"}}')
        self.receipt = self.root / "confirmed.json"
        self.app = self.root / "Raycast.app"
        (self.app / "Contents").mkdir(parents=True)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "2.10.1.0"}))
        self.snippets = [{"name": "gm", "keyword": "gm", "text": "sample+tag@example.com"}]
        self.target = self.root / "snippets.local.json"
        for name, value in (("SETTINGS", self.settings), ("CONFIRMED", self.receipt), ("TARGET", self.target)):
            p = patch.object(raycast, name, value)
            p.start()
            self.addCleanup(p.stop)
        p = patch("builtins.print")
        p.start()
        self.addCleanup(p.stop)

    def test_deeplink_preserves_unicode_and_special_characters(self):
        snippets = [{"name": "住所", "keyword": "addr", "text": "a&b+日本\n#?"}]
        for version in (1, 2):
            query = parse_qs(urlsplit(raycast.import_url(snippets, version)).query)
            restored = json.loads(query["context" if version == 2 else "snippet"][0])
            self.assertEqual(restored, snippets if version == 2 else snippets[0])

    def test_successful_open_is_pending_not_import_confirmation(self):
        with patch.object(raycast, "installed_app", return_value=self.app), patch.object(raycast.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertEqual(raycast.deploy(self.snippets), 3)
            self.assertFalse(self.receipt.exists())

    def test_confirmed_content_does_not_repeat_import(self):
        digest = raycast.fingerprint(self.snippets, json.loads(self.settings.read_text()))
        self.receipt.write_text(json.dumps({"fingerprint": digest}))
        with patch.object(raycast.subprocess, "run") as run:
            self.assertEqual(raycast.deploy(self.snippets), 0)
            run.assert_not_called()

    def test_changed_content_requires_new_confirmation(self):
        self.receipt.write_text('{"fingerprint":"old"}')
        with patch.object(raycast, "installed_app", return_value=self.app), patch.object(raycast.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertEqual(raycast.deploy(self.snippets), 3)
            self.assertEqual(json.loads(self.receipt.read_text())["fingerprint"], "old")

    def test_open_failure_does_not_leak_url_or_mark_complete(self):
        with patch.object(raycast, "installed_app", return_value=self.app), patch.object(raycast.subprocess, "run") as run:
            run.return_value.returncode = 1
            with self.assertRaises(ValueError) as error:
                raycast.deploy(self.snippets)
            self.assertNotIn("example.com", str(error.exception))
            self.assertFalse(self.receipt.exists())

    def test_conflicting_keywords_are_not_silently_chosen(self):
        items = [{"replace": "dup", "with": "a"}, {"replace": "dup", "with": "b"},
                 {"replace": "gm", "with": "ok"}, {"replace": "gm", "with": "ok"},
                 {"replace": "off", "with": "disabled", "on": 0}]
        self.assertEqual(raycast.convert(items), [{"name": "gm", "keyword": "gm", "text": "ok"}])

    def test_private_writes_remain_private_on_replace(self):
        target = self.root / "private.json"
        target.write_text("old")
        target.chmod(0o644)
        raycast.private_write(target, "new")
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(target.read_text(), "new")

    def test_deploy_refreshes_from_this_mac_and_backs_up_local_edits(self):
        self.target.write_text('[{"name":"custom","keyword":"custom","text":"local"}]')
        original = self.target.read_text()
        prefs = plistlib.dumps({"NSUserDictionaryReplacementItems": [{"replace": "gm", "with": "from-this-mac"}]})
        with patch.object(raycast.sys, "platform", "darwin"), patch.object(raycast.sys, "argv", ["setup", "--deploy"]), \
             patch.object(raycast, "installed_app", return_value=self.app), \
             patch.object(raycast.subprocess, "run", return_value=SimpleNamespace(stdout=prefs)), \
             patch.object(raycast, "deploy", return_value=3):
            self.assertEqual(raycast.main(), 3)
            backups = list(self.root.glob("*.backup-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), original)
            self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(self.target.read_text())[0]["text"], "from-this-mac")
            before = self.target.stat().st_mtime_ns
            self.assertEqual(raycast.main(), 3)
            self.assertEqual(len(list(self.root.glob("*.backup-*"))), 1)
            self.assertEqual(self.target.stat().st_mtime_ns, before)

    def test_deploy_skips_empty_dictionary_without_removing_local_data(self):
        self.target.write_text("[]")
        with patch.object(raycast.sys, "platform", "darwin"), patch.object(raycast.sys, "argv", ["setup", "--deploy"]), \
             patch.object(raycast, "installed_app", return_value=self.app), \
             patch.object(raycast.subprocess, "run", return_value=SimpleNamespace(stdout=plistlib.dumps({}))), \
             patch.object(raycast, "deploy") as deploy:
            self.assertEqual(raycast.main(), 0)
            deploy.assert_not_called()
            self.assertEqual(self.target.read_text(), "[]")


if __name__ == "__main__":
    unittest.main()
