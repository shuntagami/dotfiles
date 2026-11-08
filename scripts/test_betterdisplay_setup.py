"""Run installer failure paths against fake commands and an isolated support directory."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


FAKE_COMMAND = r'''
import os
from pathlib import Path
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["BETTERDISPLAY_TEST_ROOT"])
with (root / "commands.log").open("a") as log:
    log.write(name + " " + " ".join(args) + "\n")
stage = name
if name in ("defaults", "launchctl"):
    stage += " " + args[0]
if stage == "defaults read" and os.environ.get("FAIL_STAGE") == "missing domain":
    print("Domain " + args[1] + " does not exist", file=sys.stderr)
    sys.exit(1)
if stage == "defaults read" and os.environ.get("FAIL_STAGE") == "missing domain modern":
    print("Error: Domain '" + args[1] + "' not found.", file=sys.stderr)
    sys.exit(1)
if stage == os.environ.get("FAIL_STAGE"):
    sys.exit(42)
if stage == "defaults read" and os.environ.get("KEYS_CURRENT") and len(args) == 3:
    print({"videoKeyboardControl": "all",
           "audioKeyboardControl": "displayWithAudioDeviceNameMatch"}.get(args[2], ""))
if name == "swiftc":
    binary = Path(args[args.index("-o") + 1])
    binary.write_text("#!/bin/sh\nexit 0\n")
    binary.chmod(0o755)
elif name == "pgrep":
    sys.exit(0 if (root / ("running-" + args[-1])).exists() else 1)
elif name == "osascript":
    app = args[-1].split('"')[1]
    (root / ("running-" + app)).unlink(missing_ok=True)
elif name == "open":
    (root / ("running-" + args[-1])).touch()
elif name == "defaults" and args[0] == "export":
    Path(args[-1]).write_text("backup")
elif name == "python3":
    sys.exit(subprocess.call([sys.executable, *args]))
'''


@unittest.skipUnless(sys.platform == "darwin" and Path("/Applications/BetterDisplay.app").is_dir(),
                     "Installer requires macOS with BetterDisplay installed")
class InstallerRecoveryTests(unittest.TestCase):
    """Exercise the real installer flow without touching apps, preferences, or launchd."""

    def run_installer(self, failure, monitorcontrol_running=False, keys_current=False):
        """Stub external commands and redirect only the test copy's support paths."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "running-BetterDisplay").touch()
            if monitorcontrol_running:
                (root / "running-MonitorControl").touch()
            fake_bin = root / "bin"
            fake_bin.mkdir()
            for name in ("swiftc", "pgrep", "osascript", "open", "defaults", "python3", "plutil", "launchctl"):
                command = fake_bin / name
                command.write_text(f"#!{sys.executable}\n" + FAKE_COMMAND)
                command.chmod(0o755)
            source = Path(__file__).with_name("macos-betterdisplay.sh").read_text()
            # Do not change HOME: redirect the installer's explicit output paths
            # in this disposable copy, keeping the real user's shell untouched.
            script = root / "setup.sh"
            script.write_text(source.replace("${HOME}", "${BETTERDISPLAY_TEST_ROOT}"))
            env = dict(os.environ, BETTERDISPLAY_TEST_ROOT=str(root), FAIL_STAGE=failure,
                       KEYS_CURRENT="1" if keys_current else "",
                       PATH=str(fake_bin) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, text=True)
            log = (root / "commands.log").read_text().splitlines()
            backup = root / "Library/Application Support/dotfiles/betterdisplay-before.plist"
            running = {app: (root / ("running-" + app)).exists() for app in ("BetterDisplay", "MonitorControl")}
            return result, log, running, backup.exists()

    def test_failures_after_quit_reopen_app(self):
        """Each post-quit failure must preserve exit status and reopen BetterDisplay."""
        for failure in ("defaults write", "python3", "plutil", "launchctl bootstrap"):
            with self.subTest(failure=failure):
                result, log, running, _ = self.run_installer(failure)
                self.assertEqual(result.returncode, 42, result.stderr)
                self.assertEqual(log.count("open -g -a BetterDisplay"), 1)
                self.assertTrue(running["BetterDisplay"])

    def test_compile_failure_leaves_app_running(self):
        """Failure before teardown must not stop or reopen the existing app."""
        result, log, running, _ = self.run_installer("swiftc")
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertFalse(any(line.startswith(("osascript ", "open ")) for line in log))
        self.assertTrue(running["BetterDisplay"])

    def test_success_leaves_launch_to_agent(self):
        """A successful installer delegates startup to the registered LaunchAgent."""
        result, log, _, backup = self.run_installer("")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(line.startswith("launchctl bootstrap ") for line in log))
        self.assertNotIn("open -g -a BetterDisplay", log)
        self.assertIn("defaults write pro.betterdisplay.BetterDisplay videoKeyboardControl -string all", log)
        self.assertTrue(backup)

    def test_current_settings_keep_app_running(self):
        """A redeploy with unchanged keyboard settings must not quit BetterDisplay."""
        for failure in ("", "defaults write"):
            with self.subTest(failure=failure):
                result, log, running, _ = self.run_installer(failure, keys_current=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(running["BetterDisplay"])
                self.assertFalse(any("BetterDisplay" in line for line in log if line.startswith(("osascript ", "open "))))
                self.assertFalse(any(line.startswith("defaults write pro.betterdisplay") for line in log))

    def test_retires_monitorcontrol(self):
        """The old helper is unloaded and MonitorControl stops owning the keys."""
        result, log, running, _ = self.run_installer("", monitorcontrol_running=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(line.startswith("launchctl bootout ") and "monitorcontrol-mode" in line for line in log))
        self.assertFalse(running["MonitorControl"])

    def test_missing_preferences_skip_backup(self):
        """An app with no preferences domain can be installed without an empty backup."""
        for failure in ("missing domain", "missing domain modern"):
            with self.subTest(failure=failure):
                result, log, _, backup = self.run_installer(failure)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(backup)
                self.assertTrue(any(line.startswith("launchctl bootstrap ") for line in log))

    def test_backup_errors_abort_before_teardown(self):
        """Unexpected preference read/export errors preserve the running apps and agents."""
        for failure in ("defaults read", "defaults export"):
            with self.subTest(failure=failure):
                result, log, running, backup = self.run_installer(failure, monitorcontrol_running=True)
                self.assertEqual(result.returncode, 42, result.stderr)
                self.assertFalse(backup)
                self.assertTrue(running["BetterDisplay"])
                self.assertTrue(running["MonitorControl"])
                self.assertFalse(any(line.startswith(("osascript ", "launchctl ", "open ")) for line in log))


if __name__ == "__main__":
    unittest.main()
