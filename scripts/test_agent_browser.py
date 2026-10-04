"""Check browser routing and credentials without touching a browser or real Keychain."""
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

script = Path(__file__).resolve().parents[1] / "bin/agent-browser"
loader = importlib.machinery.SourceFileLoader("agent_browser", str(script))
spec = importlib.util.spec_from_loader(loader.name, loader)
browser = importlib.util.module_from_spec(spec)
loader.exec_module(browser)


class BrowserTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def profiles(self, directory):
        root = Path(directory)
        for name in ("Default", "Profile 2", "Profile 9"):
            (root / name).mkdir()
        (root / "Local State").write_text(json.dumps({"profile": {
            "last_used": "Default", "info_cache": {
                "Default": {"user_name": "personal@example.com"},
                "Profile 2": {"user_name": browser.DEFAULT_ACCOUNT},
                "Profile 9": {"user_name": "info@ele-inc.com"},
            },
        }}))
        return root

    def test_account_wins_over_last_used_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.profiles(directory)
            self.assertEqual(browser.selected_profile(root, account=browser.DEFAULT_ACCOUNT)[0], "Profile 2")
            self.assertEqual(browser.selected_profile(root, account="info@ele-inc.com")[0], "Profile 9")

    def test_missing_or_ambiguous_account_never_falls_back(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.profiles(directory)
            with self.assertRaises(browser.ConfigurationError):
                browser.selected_profile(root, account="missing@example.com")
            state = json.loads((root / "Local State").read_text())
            state["profile"]["info_cache"]["Default"]["user_name"] = browser.DEFAULT_ACCOUNT
            (root / "Local State").write_text(json.dumps(state))
            with self.assertRaises(browser.ConfigurationError):
                browser.selected_profile(root, account=browser.DEFAULT_ACCOUNT)

    def test_default_target_is_macbook_even_when_agent_runs_elsewhere(self):
        with patch.object(browser, "is_local", return_value=False), \
             patch.object(browser.os, "execv", side_effect=SystemExit(0)) as execute:
            with self.assertRaises(SystemExit):
                browser.main(["mcp"])
        command = execute.call_args.args[1]
        self.assertIn("shun-tagami-mbp", command)
        self.assertIn("--account shun.tagami@ele-inc.com", command[-1])

    def test_ssh_has_only_profile_selector_and_never_caller_token(self):
        os.environ["PLAYWRIGHT_MCP_EXTENSION_TOKEN"] = "caller-token-must-not-travel"
        command = browser.ssh_command("shun-tagami-mbp", "mcp", None, browser.DEFAULT_ACCOUNT, [])
        self.assertNotIn("caller-token-must-not-travel", " ".join(command))
        self.assertNotIn("PLAYWRIGHT_MCP_EXTENSION_TOKEN", " ".join(command))
        with self.assertRaises(browser.ConfigurationError):
            browser.ssh_command("mbp;touch /tmp/oops", "mcp", None, None, [])

    def test_profile_and_account_cannot_be_mixed(self):
        self.assertEqual(browser.parse_options([])[:2], (None, browser.DEFAULT_ACCOUNT))
        self.assertEqual(browser.parse_options(["--profile-dir-name", "Profile 2"])[:2], ("Profile 2", None))
        with self.assertRaises(browser.ConfigurationError):
            browser.parse_options(["--profile-dir-name", "Profile 2", "--account", "info@ele-inc.com"])
        with self.assertRaises(browser.ConfigurationError):
            browser.parse_options(["--profile-dir-name", "../other"])
        with self.assertRaises(browser.ConfigurationError):
            browser.parse_options(["--user-data-dir", "/tmp/other-chrome"])

    def test_missing_keychain_token_does_not_start_browser_or_mcp(self):
        state = {"browser_host": "MacBook", "profile_directory": "Profile 2",
                 "account": browser.DEFAULT_ACCOUNT, "extension_installed": True,
                 "automatic_connection": False}
        with patch.object(browser, "local_state", return_value=state), \
             patch.object(browser, "pause_file") as paused, \
             patch.object(browser, "ensure_chrome_running") as start, \
             patch.object(browser, "run_mcp") as execute:
            paused.return_value.exists.return_value = False
            with self.assertRaisesRegex(browser.ConfigurationError, "setup-auth"):
                browser.main(["mcp", "--local"])
            start.assert_not_called()
            execute.assert_not_called()

    def test_keychain_errors_do_not_reveal_secret_or_error_output(self):
        with patch.object(browser.subprocess, "run", return_value=subprocess.CompletedProcess([], 44, "", "")):
            self.assertIsNone(browser.keychain_token("Profile 2"))
        with patch.object(browser.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "secret-value", "secret-error")):
            with self.assertRaises(browser.ConfigurationError) as error:
                browser.keychain_token("Profile 2")
            self.assertNotIn("secret", str(error.exception))

    def test_setup_sends_secret_on_stdin_not_argv_or_output(self):
        token = "example_token_1234567890"
        with patch.object(browser.sys, "stdin", io.StringIO(token)), \
             patch.object(browser.sys, "stderr", io.StringIO()) as output, \
             patch.object(browser.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
            browser.setup_auth("Profile 2")
            self.assertNotIn(token, " ".join(run.call_args.args[0]))
            self.assertEqual(run.call_args.kwargs["input"], token + "\n" + token + "\n")
            self.assertNotIn(token, output.getvalue())

    def test_ssh_keychain_read_uses_login_session_service(self):
        with patch.object(browser, "security_read_token", return_value=subprocess.CompletedProcess([], 36, "", "User interaction is not allowed")), \
             patch.object(browser, "keychain_request", return_value={"token": "example_token_1234567890"}) as request:
            self.assertEqual(browser.keychain_token("Profile 2"), "example_token_1234567890")
            request.assert_called_once_with("read", "Profile 2")

    def test_ssh_keychain_setup_uses_login_session_and_requires_confirmation(self):
        with patch.object(browser.sys, "stdin", io.StringIO("example_token_1234567890")), \
             patch.object(browser, "security_store_token", return_value=subprocess.CompletedProcess([], 36, "", "")), \
             patch.object(browser, "keychain_request", return_value={"stored": False}):
            with self.assertRaises(browser.ConfigurationError):
                browser.setup_auth("Profile 2")

    def test_keychain_service_rejects_another_user(self):
        def different_user(fd, uid, gid):
            uid._obj.value = os.getuid() + 1
            return 0
        with patch.object(browser.ctypes, "CDLL") as library, patch.object(browser.socket, "socket") as connection:
            library.return_value.getpeereid.side_effect = different_user
            self.assertFalse(browser.trusted_peer(connection.return_value))

    def test_normal_chrome_launch_has_no_separate_data_directory(self):
        with patch.object(browser, "chrome_running", side_effect=[False, True]), \
             patch.object(browser.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
            browser.ensure_chrome_running("Profile 2")
            self.assertEqual(run.call_args.args[0], ["/usr/bin/open", "-a", "Google Chrome", "--args", "--profile-directory=Profile 2"])

    def test_mcp_uses_selected_keychain_item_not_inherited_token(self):
        state = {"browser_host": "MacBook", "profile_directory": "Profile 2",
                 "account": browser.DEFAULT_ACCOUNT, "extension_installed": True,
                 "automatic_connection": True}
        os.environ["PLAYWRIGHT_MCP_EXTENSION_TOKEN"] = "wrong_profile_token"
        os.environ["PLAYWRIGHT_MCP_CDP_ENDPOINT"] = "http://wrong-machine:9222"
        with patch.object(browser, "local_state", return_value=state), \
             patch.object(browser, "pause_file") as paused, \
             patch.object(browser, "ensure_chrome_running"), \
             patch.object(browser, "keychain_token", return_value="selected_profile_token"), \
             patch.object(browser.shutil, "which", return_value="/opt/homebrew/bin/npx"), \
             patch.object(browser.sys, "stderr", io.StringIO()) as output, \
             patch.object(browser, "run_mcp", return_value=0) as execute:
            paused.return_value.exists.return_value = False
            self.assertEqual(browser.main(["mcp", "--local"]), 0)
            environment = execute.call_args.args[1]
            self.assertEqual(environment["PLAYWRIGHT_MCP_EXTENSION_TOKEN"], "selected_profile_token")
            self.assertNotIn("PLAYWRIGHT_MCP_CDP_ENDPOINT", environment)
            self.assertNotIn("selected_profile_token", output.getvalue())

    def test_redaction_preserves_json_when_secret_appears_in_connect_url(self):
        secret = b"example_token_1234567890"
        message = json.dumps({"result": {"text": "connect.html?token=" + secret.decode()}}).encode() + b"\n"
        output = io.BytesIO()
        browser.forward_redacted(io.BytesIO(message), output, secret)
        self.assertNotIn(secret, output.getvalue())
        self.assertEqual(json.loads(output.getvalue())["result"]["text"], "connect.html?token=***")

    def test_mcp_proxy_forwards_requests_and_redacts_both_output_streams(self):
        token = "example_token_1234567890"
        program = "import os,sys,json; data=json.loads(sys.stdin.readline()); print(json.dumps({'id':data['id'],'token':os.environ['PLAYWRIGHT_MCP_EXTENSION_TOKEN']})); print(os.environ['PLAYWRIGHT_MCP_EXTENSION_TOKEN'],file=sys.stderr)"
        incoming = io.TextIOWrapper(io.BytesIO(b'{"id":7}\n'))
        outgoing = io.TextIOWrapper(io.BytesIO())
        diagnostics = io.TextIOWrapper(io.BytesIO())
        with patch.object(browser.sys, "stdin", incoming), \
             patch.object(browser.sys, "stdout", outgoing), \
             patch.object(browser.sys, "stderr", diagnostics):
            result = browser.run_mcp([sys.executable, "-c", program], {"PLAYWRIGHT_MCP_EXTENSION_TOKEN": token})
        self.assertEqual(result, 0)
        self.assertEqual(json.loads(outgoing.buffer.getvalue()), {"id": 7, "token": "***"})
        self.assertEqual(diagnostics.buffer.getvalue(), b"***\n")


if __name__ == "__main__":
    unittest.main()
