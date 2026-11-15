#!/usr/bin/env python3
import os
from pathlib import Path
import runpy
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

MODULE = runpy.run_path(str(Path(__file__).resolve().parent.parent / "bin/clipboard-image-sync"))
write_private = MODULE["atomic_write_private"]
send_binary = MODULE["send_binary"]


class InstallerTests(unittest.TestCase):
    def test_replacement_keeps_all_keys_and_private_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "authorized_keys"
            target.write_text("existing-key\n")
            write_private(target, "existing-key\nbridge-key\n")
            self.assertEqual(target.read_text(), "existing-key\nbridge-key\n")
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_failed_flush_preserves_existing_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "authorized_keys"
            target.write_text("existing-key\n")
            with patch.object(os, "fsync", side_effect=OSError("disk full")):
                with self.assertRaises(OSError):
                    write_private(target, "replacement\n")
            self.assertEqual(target.read_text(), "existing-key\n")
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_upload_handles_spaces_quotes_and_shell_characters(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "source"
            binary.write_bytes(b"\x00\xffcompiled executable\n")
            destination = Path(directory) / "Application Support ' $(not-executed)"
            real_run = subprocess.run

            def local_ssh(args, **kwargs):
                self.assertEqual(args[:4], ["ssh", "-o", "BatchMode=yes", "sender"])
                return real_run(["/bin/sh", "-c", args[4]], **kwargs)

            with patch.object(subprocess, "run", side_effect=local_ssh):
                send_binary("sender", binary, str(destination))
            self.assertEqual(destination.read_bytes(), binary.read_bytes())
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
