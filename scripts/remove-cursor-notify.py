#!/usr/bin/env python3
"""Remove the retired dotfiles Cursor sound hook; preserve app-managed hooks."""

import json
import os
from pathlib import Path
import shlex
import tempfile


ROOT = Path(__file__).resolve().parent.parent


def remove(home, script=ROOT / "scripts/agent-notify.py"):
    target = home / ".cursor/hooks.json"
    if not target.exists():
        return False
    config = json.loads(target.read_text())
    if not isinstance(config, dict) or config.get("version", 1) != 1:
        raise ValueError("Unsupported Cursor hooks config; left unchanged")
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("Invalid Cursor hooks object; left unchanged")
    if not hooks and set(config) <= {"version", "hooks"}:
        target.unlink()
        return True
    entries = hooks.get("stop", [])
    if not isinstance(entries, list):
        raise ValueError("Invalid Cursor stop hooks; left unchanged")
    command = "python3 " + shlex.quote(str(script)) + " cursor"
    kept = [entry for entry in entries if not (isinstance(entry, dict) and entry.get("command") == command)]
    if len(kept) == len(entries):
        return False
    if kept:
        hooks["stop"] = kept
    else:
        hooks.pop("stop", None)
    if not hooks and set(config) <= {"version", "hooks"}:
        target.unlink()
        return True
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
    changed = remove(Path.home())
    print("Legacy Cursor sound hook " + ("removed." if changed else "not present."))
