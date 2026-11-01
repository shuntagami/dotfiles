#!/usr/bin/env python3
"""Prepare a private Raycast Snippets import; never modify Raycast's database."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "raycast/snippets.local.json"
SETTINGS = ROOT / "raycast/settings.json"
CONFIRMED = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "dotfiles/raycast/confirmed.json"


def private_write(target, content):
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix=".raycast-", suffix=".local.json")
    try:
        with os.fdopen(fd, "w") as output:
            output.write(content)
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def encoded(snippets):
    return json.dumps(snippets, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def fingerprint(snippets, settings):
    return hashlib.sha256(encoded({"snippets": snippets, "settings": settings}).encode()).hexdigest()


def import_url(snippets, major):
    if major >= 2:
        return "raycast://extensions/raycast/snippets/import-snippets?context=" + quote(encoded(snippets), safe="")
    return "raycast://snippets/import?" + "&".join("snippet=" + quote(encoded(s), safe="") for s in snippets)


def installed_app():
    return next((p for p in (Path("/Applications/Raycast.app"), Path.home() / "Applications/Raycast.app") if p.is_dir()), None)


def deploy(snippets):
    settings = json.loads(SETTINGS.read_text())
    digest = fingerprint(snippets, settings)
    if CONFIRMED.exists():
        receipt = json.loads(CONFIRMED.read_text())
        if receipt.get("fingerprint") == digest:
            print("Raycast: current dictionary and settings were previously confirmed on this Mac; no import repeated.")
            return 0
    app = installed_app()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    major = int(info["CFBundleShortVersionString"].split(".")[0])
    result = subprocess.run(["/usr/bin/open", import_url(snippets, major)], capture_output=True)
    if result.returncode:
        raise ValueError("Could not open Raycast import; no import has been marked complete")
    print("Raycast import requested. This does NOT confirm that import completed.")
    print("Finish the import confirmation; allow Accessibility if requested; enable Snippet Expansion,")
    print("choose Immediately, disable Expand within Words, and enable Override System Snippets.")
    print("After verifying expansion, run: python3 ~/dotfiles/scripts/macos-raycast.py --confirm-setup")
    return 3


def validate(snippets):
    if not isinstance(snippets, list):
        raise ValueError("Snippets must be a JSON array")
    keywords = set()
    for snippet in snippets:
        if not isinstance(snippet, dict) or any(
            not isinstance(snippet.get(key), str) or not snippet[key]
            for key in ("name", "text", "keyword")
        ):
            raise ValueError("Every snippet needs nonempty name, text and keyword strings")
        if snippet["keyword"] in keywords:
            raise ValueError("Duplicate snippet keyword; resolve locally before importing")
        keywords.add(snippet["keyword"])


def convert(items):
    by_keyword = {}
    conflicts = set()
    for item in items:
        keyword, text = item.get("replace"), item.get("with")
        if item.get("on", True) in (False, 0):
            continue
        if isinstance(keyword, str) and keyword and isinstance(text, str) and text:
            # Raycast evaluates {...} placeholders. Do not silently reinterpret literals.
            if "{" in text or "}" in text:
                raise ValueError("A replacement contains braces; convert its Raycast placeholders manually")
            if keyword in by_keyword and by_keyword[keyword]["text"] != text:
                conflicts.add(keyword)
            by_keyword[keyword] = {"name": keyword, "text": text, "keyword": keyword}
    snippets = [snippet for key, snippet in by_keyword.items() if key not in conflicts]
    if conflicts:
        print(f"Skipped {len(conflicts)} conflicting duplicate keywords; resolve them in macOS before refreshing.")
    validate(snippets)
    if not snippets:
        raise ValueError("No active macOS text replacements found")
    return sorted(snippets, key=lambda snippet: snippet["keyword"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="validate the local import file only")
    modes.add_argument("--refresh-from-macos", action="store_true", help="back up and rebuild the local file")
    modes.add_argument("--deploy", action="store_true", help="use this Mac's dictionary and request import unless previously confirmed")
    modes.add_argument("--confirm-setup", action="store_true", help="record YOUR confirmation of import, settings and expansion on this Mac")
    args = parser.parse_args()
    if args.confirm_setup:
        snippets = json.loads(TARGET.read_text())
        validate(snippets)
        settings = json.loads(SETTINGS.read_text())
        private_write(CONFIRMED, json.dumps({"fingerprint": fingerprint(snippets, settings)}, indent=2) + "\n")
        print("Recorded your confirmation of this Mac's current snippets and settings (not an automatic UI check).")
        return 0
    if args.check:
        validate(json.loads(TARGET.read_text()))
        print("Raycast local Snippets JSON is valid (app settings/import not checked).")
        return
    if args.deploy and (sys.platform != "darwin" or not installed_app()):
        print("Raycast not installed on this Mac; skipping. Install with: brew install --cask raycast")
        return 0
    if TARGET.exists() and not args.refresh_from_macos and not args.deploy:
        validate(json.loads(TARGET.read_text()))
        print(f"Keeping existing private snippets: {TARGET}")
        return
    if sys.platform != "darwin":
        raise ValueError("Run the macOS export on a Mac")
    result = subprocess.run(["/usr/bin/defaults", "export", "-g", "-"], capture_output=True, check=True)
    items = plistlib.loads(result.stdout).get("NSUserDictionaryReplacementItems", [])
    if args.deploy and not any(item.get("on", True) and item.get("replace") and item.get("with") for item in items):
        print("Raycast: no active text replacements on this Mac; nothing to import.")
        return 0
    snippets = convert(items)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(snippets, ensure_ascii=False, indent=2) + "\n"
    changed = not TARGET.exists() or TARGET.read_text() != content
    if TARGET.exists() and changed:
        backup = TARGET.with_name(TARGET.name + ".backup-" + datetime.now().strftime("%Y%m%d%H%M%S%f"))
        private_write(backup, TARGET.read_text())
    if changed:
        private_write(TARGET, content)
    else:
        TARGET.chmod(0o600)
    print(f"Prepared {len(snippets)} snippets: {TARGET}")
    if args.deploy:
        return deploy(snippets)
    print("In Raycast, run Import Snippets and select this file. See raycast/README.md.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Never print replacement contents or defaults output.
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
