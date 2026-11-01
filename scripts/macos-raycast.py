#!/usr/bin/env python3
"""Prepare a private Raycast Snippets import; never modify Raycast's database."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "raycast/snippets.local.json"


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
    args = parser.parse_args()
    if args.check:
        validate(json.loads(TARGET.read_text()))
        print("Raycast local Snippets JSON is valid (app settings/import not checked).")
        return
    if TARGET.exists() and not args.refresh_from_macos:
        validate(json.loads(TARGET.read_text()))
        print(f"Keeping existing private snippets: {TARGET}")
        return
    if sys.platform != "darwin":
        raise ValueError("Run the macOS export on a Mac")
    result = subprocess.run(["/usr/bin/defaults", "export", "-g", "-"], capture_output=True, check=True)
    items = plistlib.loads(result.stdout).get("NSUserDictionaryReplacementItems", [])
    snippets = convert(items)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    if TARGET.exists():
        backup = TARGET.with_name(TARGET.name + ".backup-" + datetime.now().strftime("%Y%m%d%H%M%S%f"))
        backup.write_bytes(TARGET.read_bytes())
        backup.chmod(0o600)
    fd, temporary = tempfile.mkstemp(dir=TARGET.parent, prefix=".snippets-", suffix=".local.json")
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(snippets, output, ensure_ascii=False, indent=2)
            output.write("\n")
        os.replace(temporary, TARGET)
    finally:
        Path(temporary).unlink(missing_ok=True)
    print(f"Prepared {len(snippets)} snippets: {TARGET}")
    print("In Raycast, run Import Snippets and select this file. See raycast/README.md.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Never print replacement contents or defaults output.
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
