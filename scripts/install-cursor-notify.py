#!/usr/bin/env python3
"""Merge the dotfiles completion hook into Cursor's shared user hooks file."""

import json
import os
from pathlib import Path
import shlex
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def install(home, script=ROOT / "scripts/agent-notify.py"):
    target = home / ".cursor/hooks.json"
    config = json.loads(target.read_text()) if target.exists() else {"version": 1, "hooks": {}}
    if not isinstance(config, dict) or config.get("version", 1) != 1:
        raise ValueError("Unsupported Cursor hooks config; left unchanged")
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("Invalid Cursor hooks object; left unchanged")
    entries = hooks.setdefault("stop", [])
    if not isinstance(entries, list):
        raise ValueError("Invalid Cursor stop hooks; left unchanged")
    command = "python3 " + shlex.quote(str(script)) + " cursor"
    if any(isinstance(entry, dict) and entry.get("command") == command for entry in entries):
        return False
    entries.append({"command": command})
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".hooks-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(config, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)
    return True


if __name__ == "__main__":
    changed = install(Path.home())
    print("Cursor completion sound hook " + ("installed." if changed else "already installed."))
