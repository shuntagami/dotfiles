import copy
import importlib.util
from pathlib import Path
import unittest
import tempfile

spec = importlib.util.spec_from_file_location("raycast_setup", Path(__file__).with_name("macos-raycast-setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class AutomatedSetupTests(unittest.TestCase):
    def setUp(self):
        self.settings = {"openAtLogin": True, "replaceSpotlight": True, "snippets": {
            "enabled": True, "expandWithinWords": False, "expansionMode": "Immediately",
            "responseTime": "Default", "completionSound": "None"}}
        self.links = [{"name": "mt", "link": "http://localhost:34567/terminals"},
                      {"name": "slack", "link": "https://example.com/slack"}]
        self.snippets = [{"name": ";gm", "keyword": ";gm", "text": "private@example.com"}]
        self.calls = []
        self.saved = []
        self.journal = {}

    def ui(self, *args):
        self.calls.append(args)
        if args == ("import", "Snippet"):
            return "verified import Snippet|1|0"
        return "present" if args[0] == "quicklink-present" else "verified"

    def save(self, value):
        self.saved.append(copy.deepcopy(value))

    def launch(self, kind, value):
        self.calls.append(("launch", kind, value))

    def apply(self, ui=None):
        setup.apply(self.settings, self.links, {"preferExistingTabs": True}, self.snippets,
                    ui or self.ui, self.journal, self.save, self.launch)

    def test_override_is_disabled_before_other_expansion_changes(self):
        self.apply()
        self.assertLess(self.calls.index(("toggle", "Override System Snippets", 0)),
                        self.calls.index(("choose", "Expansion Mode", "Immediately")))
        self.assertIn("configuration", self.saved[-1])

    def test_failed_setting_rolls_back_expansion_and_does_not_complete(self):
        def ui(*args):
            self.calls.append(args)
            if args[:2] == ("choose", "Expansion Mode"):
                raise setup.NeedsUserAction("UI changed")
            return "verified"
        with self.assertRaises(setup.NeedsUserAction):
            self.apply(ui)
        self.assertIn(("toggle", "Enable Snippet Expansion", 0), self.calls)
        self.assertEqual(self.saved, [])

    def test_failed_spotlight_change_restores_previous_binding(self):
        def ui(*args):
            if args[0] == "spotlight":
                raise setup.NeedsUserAction("cannot apply")
            return self.ui(*args)
        with self.assertRaises(setup.NeedsUserAction):
            self.apply(ui)
        self.assertIn(("launch", "spotlight-restore", None), self.calls)
        self.assertEqual(self.saved, [])

    def test_import_failure_never_records_import_or_completion(self):
        def ui(*args):
            if args == ("import", "Snippet"):
                raise setup.NeedsUserAction("not imported")
            return self.ui(*args)
        with self.assertRaises(setup.NeedsUserAction):
            self.apply(ui)
        self.assertEqual(self.journal, {})
        self.assertEqual(self.saved, [])

    def test_retry_skips_confirmed_import_but_reapplies_settings(self):
        self.journal["snippets"] = setup.digest(self.snippets)
        self.apply()
        self.assertNotIn(("import", "Snippet"), self.calls)
        self.assertIn(("toggle", "Override System Snippets", 0), self.calls)

    def test_only_missing_quicklinks_are_imported(self):
        def ui(*args):
            if args == ("quicklink-present", "slack"):
                return "missing"
            return self.ui(*args)
        self.apply(ui)
        self.assertIn(("launch", "quicklinks", [self.links[1]]), self.calls)

    def test_alias_failure_does_not_claim_full_setup(self):
        def ui(*args):
            if args == ("alias", "slack", "slack"):
                raise setup.NeedsUserAction("not applied")
            return self.ui(*args)
        with self.assertRaises(setup.NeedsUserAction):
            self.apply(ui)
        self.assertNotIn("configuration", self.journal)
        self.assertTrue(all("configuration" not in value for value in self.saved))

    def test_permission_wait_still_finishes_imports_and_links(self):
        def ui(*args):
            if args == ("expansion-access",):
                self.calls.append(args)
                return "required"
            return self.ui(*args)
        with self.assertRaisesRegex(setup.NeedsUserAction, "Imports and Quicklinks"):
            self.apply(ui)
        self.assertIn(("import", "Snippet"), self.calls)
        self.assertIn(("alias", "slack", "slack"), self.calls)
        self.assertIn(("request-access",), self.calls)
        self.assertNotIn(("toggle", "Enable Snippet Expansion", 1), self.calls)
        self.assertTrue(self.journal["requiresAccessibility"])
        self.assertNotIn("configuration", self.journal)

    def test_changed_existing_snippet_is_not_silently_skipped(self):
        self.journal["snippetEntries"] = {";gm": "old-content-hash"}
        with self.assertRaisesRegex(setup.NeedsUserAction, "cannot overwrite"):
            self.apply()
        self.assertNotIn("snippets", self.journal)
        self.assertFalse(any(c[0:2] == ("launch", "snippets") for c in self.calls))

    def test_unknown_duplicate_does_not_become_verified_import(self):
        def ui(*args):
            if args == ("import", "Snippet"):
                return "verified import Snippet|0|1"
            return self.ui(*args)
        with self.assertRaisesRegex(setup.NeedsUserAction, "unverified existing"):
            self.apply(ui)
        self.assertNotIn("snippets", self.journal)

    def test_old_completion_is_cleared_before_reapplying(self):
        self.journal["configuration"] = "previously-applied"
        def ui(*args):
            raise setup.NeedsUserAction("UI not available")
        with self.assertRaises(setup.NeedsUserAction):
            self.apply(ui)
        self.assertNotIn("configuration", self.saved[0])

    def test_concurrent_setup_is_rejected_and_lock_releases(self):
        with tempfile.TemporaryDirectory() as directory:
            filename = Path(directory) / "setup.lock"
            with setup.setup_lock(filename):
                with self.assertRaisesRegex(setup.NeedsUserAction, "Another Raycast"):
                    with setup.setup_lock(filename):
                        self.fail("A second setup must not acquire the lock")
            with setup.setup_lock(filename):
                self.assertEqual(filename.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
