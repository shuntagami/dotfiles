import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "bin/agent-browser"
loader = importlib.machinery.SourceFileLoader("agent_browser", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
browser = importlib.util.module_from_spec(spec)
loader.exec_module(browser)


class Executed(Exception):
    pass


class BrowserTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        for directory in ("Profile 2", "Profile 8"):
            (self.root / directory).mkdir()
        (self.root / "Local State").write_text(json.dumps({"profile": {
            "last_used": "Profile 2",
            "info_cache": {
                "Profile 2": {"name": "ELE", "user_name": "user@example.com"},
                "Profile 8": {"name": "Info", "user_name": "info@example.com"},
            },
        }}))

    def test_current_profile_and_explicit_info(self):
        self.assertEqual(browser.selected_profile(self.root)[0], "Profile 2")
        self.assertEqual(browser.selected_profile(self.root, "Profile 8")[1], "info@example.com")
        data = json.loads((self.root / "Local State").read_text())
        data["profile"]["last_used"] = "Profile 8"
        (self.root / "Local State").write_text(json.dumps(data))
        self.assertEqual(browser.selected_profile(self.root)[0], "Profile 8")

    def test_missing_profile_does_not_create_one(self):
        with self.assertRaises(browser.ConfigurationError):
            browser.selected_profile(self.root, "Profile 99")
        self.assertFalse((self.root / "Profile 99").exists())

    def test_launch_overrides_and_profile_paths_are_rejected(self):
        for args in (["--isolated"], ["--config=x"], ["--cdp-endpoint", "http://localhost:9222"],
                     ["--profile-dir-name", "../Default"], ["--profile-dir-name"]):
            with self.subTest(args=args), self.assertRaises(browser.ConfigurationError):
                browser.parse_options(args)

    def test_profile_env_and_arguments(self):
        with patch.dict(os.environ, {"PLAYWRIGHT_MCP_PROFILE_DIR_NAME": "Profile 8"}):
            self.assertEqual(browser.parse_options([]), ("Profile 8", []))
            self.assertEqual(browser.parse_options(["--profile-dir-name=Profile 2", "--timeout-action", "1000"]),
                             ("Profile 2", ["--timeout-action", "1000"]))

    def test_remote_command_quotes_arguments_and_does_not_forward_token(self):
        with patch.dict(os.environ, {"PLAYWRIGHT_MCP_EXTENSION_TOKEN": "secret-do-not-send"}):
            cmd = browser.ssh_command("mbp", "mcp", "Profile 8", ["--output-dir", "a' $() path"])
        self.assertNotIn("-L", cmd)
        self.assertNotIn("secret-do-not-send", str(cmd))
        words = shlex.split(cmd[-1])
        self.assertEqual(words[2:], ["mcp", "--local", "--profile-dir-name", "Profile 8",
                                     "--output-dir", "a' $() path"])
        with self.assertRaises(browser.ConfigurationError):
            browser.ssh_command("-oProxyCommand=anything", "mcp", None, [])

    def test_host_routing(self):
        with patch.object(browser.socket, "gethostname", return_value="Shun-Tagami-MBP.local"):
            self.assertTrue(browser.is_local("shun-tagami-mbp"))
            self.assertTrue(browser.is_local("local"))
            self.assertFalse(browser.is_local("macmini"))

    def test_pause_prevents_even_ssh(self):
        marker = self.root / "paused"
        marker.touch()
        with patch.object(browser, "pause_file", return_value=marker), patch.object(browser.os, "execv") as execute:
            with self.assertRaisesRegex(browser.ConfigurationError, "Paused"):
                browser.main(["mcp"])
            execute.assert_not_called()

    def test_remote_failure_has_no_local_fallback(self):
        with patch.object(browser, "pause_file", return_value=self.root / "absent"), \
             patch.object(browser, "is_local", return_value=False), \
             patch.object(browser.os, "execv", side_effect=OSError("ssh failed")), \
             patch.object(browser, "local_state") as local:
            with self.assertRaisesRegex(OSError, "ssh failed"):
                browser.main(["mcp"])
            local.assert_not_called()

    def test_automation_chrome_is_not_the_normal_browser(self):
        uid = os.getuid()
        output = f"{uid} {browser.CHROME} --user-data-dir=/agent\n"
        with patch.object(browser.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output)):
            self.assertFalse(browser.chrome_running())
        output += f"{uid} {browser.CHROME} --restart\n"
        with patch.object(browser.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, output)):
            self.assertTrue(browser.chrome_running())

    def test_extension_is_checked_in_selected_profile(self):
        folder = self.root / "Profile 2/Extensions" / browser.EXTENSION_ID / "0.4.0_0"
        folder.mkdir(parents=True)
        (folder / "manifest.json").write_text("{}")
        self.assertTrue(browser.extension_installed(self.root, "Profile 2"))
        self.assertFalse(browser.extension_installed(self.root, "Profile 8"))

    def test_local_launch_is_pinned_to_existing_profile_and_sanitizes_environment(self):
        state = dict(browser_host="mbp", profile_directory="Profile 8", account="info@example.com",
                     chrome_running=True, extension_installed=True)
        with patch.object(browser, "pause_file", return_value=self.root / "absent"), \
             patch.object(browser, "local_state", return_value=state), \
             patch.object(browser.shutil, "which", return_value="/opt/homebrew/bin/npx"), \
             patch.object(browser.os, "execvpe", side_effect=Executed) as execute, \
             patch.dict(os.environ, {"PLAYWRIGHT_MCP_CDP_ENDPOINT": "http://localhost:9222"}):
            with self.assertRaises(Executed):
                browser.main(["mcp", "--local"])
            _, args, env = execute.call_args.args
            self.assertIn("--extension", args)
            self.assertEqual(args[-2:], ["--profile-dir-name", "Profile 8"])
            self.assertNotIn("PLAYWRIGHT_MCP_CDP_ENDPOINT", env)

    def test_missing_chrome_or_extension_fails_before_npx(self):
        for running, installed in ((False, True), (True, False)):
            state = dict(browser_host="mbp", profile_directory="Profile 2", account="user@example.com",
                         chrome_running=running, extension_installed=installed)
            with patch.object(browser, "pause_file", return_value=self.root / "absent"), \
                 patch.object(browser, "local_state", return_value=state), \
                 patch.object(browser.os, "execvpe") as execute:
                with self.assertRaises(browser.ConfigurationError):
                    browser.main(["mcp", "--local"])
                execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
