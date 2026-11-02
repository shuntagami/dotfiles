#!/usr/bin/env python3
"""Apply dotfiles' Raycast v2 setup through its UI, without modifying its DB."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("raycast_data", ROOT / "scripts/macos-raycast.py")
data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)
UI_SOURCE = ROOT / "scripts/raycast-ui.applescript"
INPUT_SOURCE = ROOT / "scripts/raycast-input.swift"
QUICKLINKS = ROOT / "raycast/quicklinks.json"
QUICKLINK_SETTINGS = ROOT / "raycast/quicklinks-settings.json"
STATE = data.CONFIRMED.parent
JOURNAL = STATE / "automated-setup.json"


class NeedsUserAction(Exception):
    """An OS permission, unsupported UI, or conflicting user edit needs attention."""


@contextmanager
def setup_lock(filename=None):
    """Keep simultaneous terminal sessions from controlling the same UI."""
    import fcntl
    filename = filename or STATE / "setup.lock"
    filename.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(filename, os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, "r+") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise NeedsUserAction("Another Raycast setup is running; retry after it finishes") from None
        try:
            yield
        finally:
            fcntl.flock(stream, fcntl.LOCK_UN)


def run(command, *, timeout=40, input=None, env=None):
    """Run a fixed command without a shell; never include argv in errors."""
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, input=input, env=env)
    except subprocess.TimeoutExpired:
        raise NeedsUserAction("Raycast setup timed out; no completion was recorded") from None
    if result.returncode:
        # UI adapter arguments contain only setting labels, never snippet text.
        detail = result.stderr.strip()[:500] if command[0] == "/usr/bin/osascript" or command[-1] == "--check" else ""
        raise NeedsUserAction("Raycast setup command failed. " + detail)
    return result.stdout.strip()


def digest(value):
    """Hash desired import data without keeping personal text in the journal."""
    return hashlib.sha256(data.encoded(value).encode()).hexdigest()


def compile_ui():
    """Cache a compiled copy of the tracked UI adapter for this user."""
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    signature = hashlib.sha256(UI_SOURCE.read_bytes()).hexdigest()[:16]
    target = STATE / ("ui-" + signature + ".scpt")
    if not target.exists():
        with tempfile.TemporaryDirectory(dir=STATE, prefix="compile-") as temporary:
            staging = Path(temporary) / "ui.scpt"
            run(["/usr/bin/osacompile", "-o", str(staging), str(UI_SOURCE)])
            staging.chmod(0o600)
            os.replace(staging, target)
    return target


def compile_input():
    """Build the tiny native click helper from tracked source, without downloads."""
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    signature = hashlib.sha256(INPUT_SOURCE.read_bytes()).hexdigest()[:16]
    target = STATE / ("input-" + signature)
    if not target.exists():
        with tempfile.TemporaryDirectory(dir=STATE, prefix="compile-") as temporary:
            staging = Path(temporary) / "input"
            run(["/usr/bin/swiftc", "-O", str(INPUT_SOURCE), "-o", str(staging)], timeout=120)
            staging.chmod(0o700)
            os.replace(staging, target)
    run([str(target), "--check"])
    return target


def prepare_snippets(settings):
    """Read THIS Mac's dictionary and retain a private backup of changed JSON."""
    raw = run(["/usr/bin/defaults", "export", "-g", "-"])
    items = plistlib.loads(raw.encode()).get("NSUserDictionaryReplacementItems", [])
    if not any(x.get("on", True) and x.get("replace") and x.get("with") for x in items):
        return []
    snippets = data.convert(items, settings["snippets"].get("keywordPrefix", ""))
    content = json.dumps(snippets, ensure_ascii=False, indent=2) + "\n"
    if not data.TARGET.exists() or data.TARGET.read_text() != content:
        if data.TARGET.exists():
            backup = data.TARGET.with_name(data.TARGET.name + ".backup-" + datetime.now().strftime("%Y%m%d%H%M%S%f"))
            data.private_write(backup, data.TARGET.read_text())
        data.private_write(data.TARGET, content)
    return snippets


def apply(settings, links, link_settings, snippets, ui, journal, save, launch, legacy_confirmed=False):
    """Apply controls and imports; checkpoint only after verified UI success."""
    if "configuration" in journal:
        journal.pop("configuration")
        save(journal)
    ui("restart" if journal.get("requiresAccessibility") else "start")
    ui("section", "General")
    ui("toggle", "Open at Login", int(settings["openAtLogin"]))
    if settings.get("replaceSpotlight"):
        try:
            launch("spotlight-prepare", None)
            ui("spotlight")
            launch("spotlight-verify", None)
        except BaseException:
            launch("spotlight-restore", None)
            raise
    ui("section", "Snippets")
    enabled = settings["snippets"]["enabled"]
    permission_pending = enabled and ui("expansion-access") == "required"
    if permission_pending:
        journal["requiresAccessibility"] = True
        save(journal)
    else:
        ui("toggle", "Enable Snippet Expansion", int(enabled))
    if enabled and not permission_pending:
        try:
            ui("toggle", "Override System Snippets", 0)
            ui("toggle", "Expand within Words", int(settings["snippets"]["expandWithinWords"]))
            ui("choose", "Expansion Mode", settings["snippets"]["expansionMode"])
            ui("choose", "Response Time", settings["snippets"]["responseTime"])
            ui("choose", "Completion Sound", settings["snippets"]["completionSound"])
        except BaseException:
            # Never leave the expansion engine enabled after a partial UI failure.
            try:
                ui("section", "Snippets")
                ui("toggle", "Enable Snippet Expansion", 0)
            except Exception:
                pass
            raise
    if snippets and journal.get("snippets") != digest(snippets):
        known = journal.get("snippetEntries", {})
        if not legacy_confirmed and any(s["keyword"] in known and known[s["keyword"]] != digest(s) for s in snippets):
            raise NeedsUserAction("Existing snippet contents changed; Raycast imports cannot overwrite them. Update those entries before confirming setup")
        additions = [s for s in snippets if s["keyword"] not in known]
        if additions:
            launch("snippets", additions)
            result = ui("import", "Snippet")
            try:
                _, added, skipped = result.rsplit("|", 2)
                verified_additions = int(added) == len(additions) and int(skipped) == 0
            except (ValueError, AttributeError):
                verified_additions = False
            if not verified_additions and not legacy_confirmed:
                raise NeedsUserAction("Raycast skipped unverified existing keywords; no import completion was recorded")
        journal["snippetEntries"] = {**known, **{s["keyword"]: digest(s) for s in snippets}}
        journal["snippets"] = digest(snippets)
        save(journal)
    ui("section", "Quicklinks")
    missing = [link for link in links if ui("quicklink-present", link["name"]) == "missing"]
    if missing:
        import_path = launch("quicklinks", missing)
        ui("import-file", import_path)
        ui("section", "Quicklinks")
    ui("toggle", "Prefer Existing Tabs", int(link_settings["preferExistingTabs"]))
    for link in links:
        ui("alias", link["name"], link["name"])
    for link in links:
        ui("quicklink", link["name"], link["link"], link.get("openWith", "default"))
    if permission_pending:
        ui("request-access")
        raise NeedsUserAction("Imports and Quicklinks are configured; approve Raycast Accessibility in macOS, then rerun")
    journal.pop("requiresAccessibility", None)
    journal["configuration"] = digest({"settings": settings, "quicklinks": links, "quicklinkSettings": link_settings})
    save(journal)


def main():
    """Configure the current Mac; OS approval failures remain visibly incomplete."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true", help="reapply the UI after manual app-setting changes")
    args = parser.parse_args()
    app = data.installed_app()
    if sys.platform != "darwin" or not app:
        print("Raycast not installed; skipping (install via Brewfile).")
        return 0
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if int(info["CFBundleShortVersionString"].split(".")[0]) != 2:
        raise NeedsUserAction("Automatic setup supports Raycast v2; no settings were changed")
    settings = json.loads(data.SETTINGS.read_text())
    if settings["hotkey"] != "Command+Space" or settings["snippets"]["overrideSystemSnippets"]:
        raise ValueError("This adapter requires Command+Space and Override System Snippets=false")
    links = json.loads(QUICKLINKS.read_text())
    link_settings = json.loads(QUICKLINK_SETTINGS.read_text())
    if args.dry_run:
        print("Would apply Raycast settings, import this Mac's prefixed dictionary, and configure Quicklinks/aliases.")
        return 0
    snippets = prepare_snippets(settings)
    journal = json.loads(JOURNAL.read_text()) if JOURNAL.exists() else {}
    manifest = digest({"settings": settings, "links": links, "linkSettings": link_settings,
                       "snippets": snippets, "raycastVersion": info["CFBundleShortVersionString"],
                       "adapter": UI_SOURCE.read_text(), "input": INPUT_SOURCE.read_text(),
                       "setup": Path(__file__).read_text()})
    if not args.force and journal.get("appliedManifest") == manifest:
        print("Raycast setup unchanged since the last verified application; UI skipped. Use --force after manual app changes.")
        return 0
    compiled = compile_ui()
    input_helper = compile_input()
    journal.pop("appliedManifest", None)
    data.private_write(JOURNAL, json.dumps(journal, indent=2) + "\n")
    def ui(*arguments):
        result = run(["/usr/bin/osascript", str(compiled), *map(str, arguments)], timeout=90,
                     env={**os.environ, "RAYCAST_SETUP_INPUT_HELPER": str(input_helper)})
        print("Raycast:", result, flush=True)
        return result
    original_spotlight = None
    temporary_imports = []
    def launch(kind, payload):
        """Use fixed OS commands and private files; do not log import payloads."""
        nonlocal original_spotlight
        if kind.startswith("spotlight-"):
            prefs = plistlib.loads(run(["/usr/bin/defaults", "export", "com.apple.symbolichotkeys", "-"]).encode())
            shortcuts = prefs.get("AppleSymbolicHotKeys", {})
            if kind == "spotlight-verify":
                if shortcuts.get("64", {}).get("enabled", True):
                    raise NeedsUserAction("Spotlight replacement was not verified")
                return
            if kind == "spotlight-prepare":
                original_spotlight = shortcuts.get("64", {"enabled": True, "value": {"type": "standard", "parameters": [32, 49, 1048576]}})
                desired = {"enabled": True, "value": {"type": "standard", "parameters": [32, 49, 1048576]}}
            else:
                if original_spotlight is None:
                    return
                desired = original_spotlight
            xml = plistlib.dumps(desired).decode()
            run(["/usr/bin/defaults", "write", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys", "-dict-add", "64", xml])
            run(["/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings", "-u"])
            return
        if kind == "snippets":
            url = data.import_url(payload, 2)
        else:
            fd, name = tempfile.mkstemp(dir=STATE, prefix="quicklinks-", suffix=".json")
            with os.fdopen(fd, "w") as output:
                json.dump(payload, output, ensure_ascii=False)
            temporary_imports.append(Path(name))
            return name
        run(["/usr/bin/open", url])
    def save(value):
        """Persist only verification hashes and state, never replacement text."""
        data.private_write(JOURNAL, json.dumps(value, indent=2) + "\n")
    legacy_confirmed = False
    if data.CONFIRMED.exists():
        legacy_confirmed = json.loads(data.CONFIRMED.read_text()).get("fingerprint") == data.fingerprint(snippets, settings)
    try:
        apply(settings, links, link_settings, snippets, ui, journal, save, launch, legacy_confirmed)
    finally:
        for temporary in temporary_imports:
            temporary.unlink(missing_ok=True)
    journal["appliedManifest"] = manifest
    save(journal)
    print("Raycast settings, imports and aliases were applied and checked through the UI.")
    return 0


if __name__ == "__main__":
    try:
        if sys.platform == "darwin":
            with setup_lock():
                sys.exit(main())
        else:
            sys.exit(main())
    except NeedsUserAction as error:
        print("Raycast setup incomplete:", error, file=sys.stderr)
        print("Resolve the stated blocker and rerun; verified import checkpoints are retained.", file=sys.stderr)
        sys.exit(3)
    except (ValueError, OSError) as error:
        print("Raycast setup error:", error, file=sys.stderr)
        sys.exit(1)
