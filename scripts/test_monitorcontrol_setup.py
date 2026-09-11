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
root = Path(os.environ["MONITORCONTROL_TEST_ROOT"])
with (root / "commands.log").open("a") as log:
    log.write(name + " " + " ".join(args) + "\n")
stage = name
if name in ("defaults", "launchctl"):
    stage += " " + args[0]
if stage == os.environ.get("FAIL_STAGE"):
    sys.exit(42)
if name == "swiftc":
    binary = Path(args[args.index("-o") + 1])
    binary.write_text("#!/bin/sh\nexit 0\n")
    binary.chmod(0o755)
elif name == "pgrep":
    sys.exit(0 if (root / "app-running").exists() else 1)
elif name == "osascript":
    (root / "app-running").unlink(missing_ok=True)
elif name == "open":
    (root / "app-running").touch()
elif name == "defaults" and args[0] == "export":
    Path(args[-1]).write_text("backup")
elif name == "python3":
    sys.exit(subprocess.call([sys.executable, *args]))
'''


@unittest.skipUnless(sys.platform == "darwin" and Path("/Applications/MonitorControl.app").is_dir(),
                     "Installer requires macOS with MonitorControl installed")
class InstallerRecoveryTests(unittest.TestCase):
    """Exercise the real installer flow without touching apps, preferences, or launchd."""

    def run_installer(self, failure):
        """Stub external commands and redirect only the test copy's support paths."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "app-running").touch()
            fake_bin = root / "bin"
            fake_bin.mkdir()
            for name in ("swiftc", "pgrep", "osascript", "open", "defaults", "python3", "plutil", "launchctl"):
                command = fake_bin / name
                command.write_text(f"#!{sys.executable}\n" + FAKE_COMMAND)
                command.chmod(0o755)
            source = Path(__file__).with_name("macos-monitorcontrol.sh").read_text()
            # Do not change HOME: redirect the installer's explicit output paths
            # in this disposable copy, keeping the real user's shell untouched.
            script = root / "setup.sh"
            script.write_text(source.replace("${HOME}", "${MONITORCONTROL_TEST_ROOT}"))
            env = dict(os.environ, MONITORCONTROL_TEST_ROOT=str(root), FAIL_STAGE=failure,
                       PATH=str(fake_bin) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, text=True)
            log = (root / "commands.log").read_text().splitlines()
            return result, log, (root / "app-running").exists()

    def test_failures_after_quit_reopen_app(self):
        """Each post-quit failure must preserve exit status and reopen MonitorControl."""
        for failure in ("defaults write", "python3", "plutil", "launchctl bootstrap"):
            with self.subTest(failure=failure):
                result, log, running = self.run_installer(failure)
                self.assertEqual(result.returncode, 42, result.stderr)
                self.assertEqual(log.count("open -g -a MonitorControl"), 1)
                self.assertTrue(running)

    def test_compile_failure_leaves_app_running(self):
        """Failure before teardown must not stop or reopen the existing app."""
        result, log, running = self.run_installer("swiftc")
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertFalse(any(line.startswith(("osascript ", "open ")) for line in log))
        self.assertTrue(running)

    def test_success_leaves_launch_to_agent(self):
        """A successful installer delegates startup to the registered LaunchAgent."""
        result, log, _ = self.run_installer("")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(line.startswith("launchctl bootstrap ") for line in log))
        self.assertNotIn("open -g -a MonitorControl", log)


if __name__ == "__main__":
    unittest.main()
