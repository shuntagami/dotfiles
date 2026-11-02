#!/usr/bin/env python3
"""Generate private Espanso matches from this Mac and install tracked configuration."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
CONFIG = Path.home() / "Library/Application Support/espanso"
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "dotfiles/espanso"


def convert(items, prefix):
    if not isinstance(prefix, str) or any(c.isspace() for c in prefix):
        raise ValueError("keywordPrefix must be a string without whitespace")
    replacements, conflicts = {}, set()
    for item in items:
        key, text = item.get("replace"), item.get("with")
        if item.get("on", True) in (False, 0):
            continue
        if not isinstance(key, str) or not key or not isinstance(text, str) or not text:
            continue
        if key in replacements and replacements[key] != text:
            conflicts.add(key)
        replacements[key] = text
    matches = []
    for key, text in sorted(replacements.items()):
        if key in conflicts:
            continue
        if prefix and prefix + key in replacements:
            raise ValueError("A generated trigger conflicts with a native replacement")
        # Avoid interpreting native literal text as an Espanso variable/cursor command.
        if "{{" in text or "}}" in text or "$|$" in text:
            raise ValueError("A replacement contains Espanso syntax; convert it manually")
        if any(c.isspace() or ord(c) < 32 for c in key):
            raise ValueError("A dictionary trigger contains whitespace or control characters")
        match = {"trigger": prefix + key, "replace": text}
        if not prefix:
            # Prevent short suffixes such as gm from matching inside lgm/elegm.
            match["left_word"] = True
        matches.append(match)
    return matches, len(conflicts)


def private_write(target, content):
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix=".dotfiles-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def backup(target):
    if not target.exists() and not target.is_symlink():
        return
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination = STATE / (target.name + "." + datetime.now().strftime("%Y%m%d%H%M%S%f") + ".backup")
    private_write(destination, target.read_text())


def install_config(source, target):
    if target.is_symlink() and target.resolve() == source.resolve():
        return
    backup(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".dotfiles-link")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(source)
    os.replace(temporary, target)


def run(arguments, *, timeout=30):
    try:
        return subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ValueError("Setup command timed out; retry setup") from None


def disable_system_replacements():
    """Turn off native substitution, retaining the dictionary as generation input."""
    managed = {
        "NSGlobalDomain": ["NSAutomaticTextReplacementEnabled", "WebAutomaticTextReplacementEnabled"],
        "com.google.Chrome": ["WebAutomaticTextReplacementEnabled"],
    }
    domains = run(["/usr/bin/defaults", "domains"])
    if domains.returncode:
        raise ValueError("Could not list preference domains")
    existing_domains = {item.strip() for item in domains.stdout.strip().split(",")}
    previous = {}
    for domain, keys in managed.items():
        if domain != "NSGlobalDomain" and domain not in existing_domains:
            preferences = {}
        else:
            exported = run(["/usr/bin/defaults", "export", domain, "-"])
            if exported.returncode:
                raise ValueError("Could not read native text replacement preferences")
            preferences = plistlib.loads(exported.stdout.encode())
        previous[domain] = {key: preferences.get(key) for key in keys}
    original = STATE / "native-text-replacement-preferences.json"
    if not original.exists():
        private_write(original, json.dumps(previous, indent=2) + "\n")
    for domain, keys in managed.items():
        for key in keys:
            if run(["/usr/bin/defaults", "write", domain, key, "-bool", "false"]).returncode:
                raise ValueError("Could not disable native text replacement")
            checked = run(["/usr/bin/defaults", "read", domain, key])
            if checked.returncode or checked.stdout.strip() != "0":
                raise ValueError("Native text replacement preference did not stay disabled")
    print("macOS and Chrome text replacement preferences saved as off; dictionary data retained.")


def restore_spotlight():
    """Return Command+Space to Spotlight without changing other symbolic keys."""
    domain = "com.apple.symbolichotkeys"
    exported = run(["/usr/bin/defaults", "export", domain, "-"])
    if exported.returncode:
        raise ValueError("Could not read Spotlight shortcut preferences")
    keys = plistlib.loads(exported.stdout.encode()).get("AppleSymbolicHotKeys", {})
    original = STATE / "spotlight-shortcut.json"
    if not original.exists():
        private_write(original, json.dumps({"64": keys.get("64")}, indent=2) + "\n")
    desired = {"enabled": True, "value": {"parameters": [32, 49, 1048576], "type": "standard"}}
    if keys.get("64") != desired:
        value = plistlib.dumps(desired).decode()
        if run(["/usr/bin/defaults", "write", domain, "AppleSymbolicHotKeys", "-dict-add", "64", value]).returncode:
            raise ValueError("Could not restore Spotlight shortcut")
        activation = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        if Path(activation).exists() and run([activation, "-u"]).returncode:
            raise ValueError("Spotlight shortcut saved; log out and back in to activate it")
    checked = run(["/usr/bin/defaults", "export", domain, "-"])
    if checked.returncode or plistlib.loads(checked.stdout.encode()).get("AppleSymbolicHotKeys", {}).get("64") != desired:
        raise ValueError("Spotlight shortcut verification failed")
    print("Spotlight shortcut: Command+Space.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--prepare-only", action="store_true", help="write configuration without starting apps")
    args = parser.parse_args()
    if sys.platform != "darwin":
        print("Espanso setup is only supported on macOS.")
        return 0
    result = run(["/usr/bin/defaults", "export", "-g", "-"])
    if result.returncode:
        raise ValueError("Could not read this Mac's text replacements")
    items = plistlib.loads(result.stdout.encode()).get("NSUserDictionaryReplacementItems", [])
    settings = json.loads((ROOT / "espanso/settings.json").read_text())
    prefix = settings["keywordPrefix"]
    matches, conflicts = convert(items, prefix)
    print(f"Espanso: {len(matches)} matches; {conflicts} conflicting native keywords excluded.")
    if args.dry_run:
        return 0
    if not matches:
        print("No matches generated; existing configuration was left untouched.")
        return 3
    # JSON is valid YAML, and avoids hand-escaping private replacement strings.
    payload = json.dumps({"matches": matches}, ensure_ascii=False, indent=2) + "\n"
    target = CONFIG / "match/dotfiles-macos.yml"
    if not target.exists() or target.read_text() != payload:
        backup(target)
        private_write(target, payload)
    else:
        target.chmod(0o600)
    install_config(ROOT / "espanso/config/default.yml", CONFIG / "config/default.yml")
    print("Espanso configuration prepared (private matches stay on this Mac).")
    if args.prepare_only:
        return 0
    binary = shutil.which("espanso")
    if not binary:
        print("Install Espanso with brew install --cask espanso, then rerun setup.")
        return 3
    if any(p.exists() for p in [Path("/Applications/Raycast.app"), Path.home() / "Applications/Raycast.app"]):
        brew = shutil.which("brew")
        if not brew or run([brew, "uninstall", "--cask", "raycast"], timeout=120).returncode:
            print("Remove Raycast with brew uninstall --cask raycast, then rerun setup.")
            return 3
        print("Raycast uninstalled; its saved data was not purged.")
    if settings.get("restoreSpotlight", False):
        restore_spotlight()
    if settings.get("disableSystemTextReplacement", False):
        disable_system_replacements()
        after = run(["/usr/bin/defaults", "export", "-g", "-"])
        if after.returncode or plistlib.loads(after.stdout.encode()).get("NSUserDictionaryReplacementItems", []) != items:
            raise ValueError("Native dictionary data changed during setup; inspect locally before continuing")
    # Parse configuration before registering or starting the background service.
    result = run([binary, "match", "list"])
    if result.returncode:
        raise ValueError("Espanso rejected the configuration; run espanso log locally to inspect")
    if run([binary, "service", "check"]).returncode:
        if run([binary, "service", "register"]).returncode:
            raise ValueError("Could not register Espanso login service")
    # Espanso 2.4.1's service start fails with launchctl exit 3 on macOS 27.
    # Enable and bootstrap the registered user agent through the modern API.
    service = f"gui/{os.getuid()}/com.federicoterzi.espanso"
    domain = f"gui/{os.getuid()}"
    agent = Path.home() / "Library/LaunchAgents/com.federicoterzi.espanso.plist"
    if run(["/bin/launchctl", "enable", service]).returncode:
        raise ValueError("Could not enable Espanso login service")
    status = run([binary, "service", "status"])
    if status.returncode or "not running" in status.stdout.lower():
        loaded = run(["/bin/launchctl", "print", service]).returncode == 0
        arguments = ["kickstart", "-k", service] if loaded else ["bootstrap", domain, str(agent)]
        if run(["/bin/launchctl", *arguments]).returncode:
            raise ValueError("launchctl could not start Espanso; inspect its Login Items entry")
        for _ in range(20):
            status = run([binary, "service", "status"])
            if status.returncode == 0 and "not running" not in status.stdout.lower():
                break
            time.sleep(0.25)
        else:
            print("Espanso is not running. Finish its first-launch Accessibility approval and rerun setup.")
            return 3
    print("Espanso service is running. Accessibility approval must be completed on this Mac.")
    print(f"Verify {prefix}lgm in both a normal input and xterm, including cursor position and repeated expansions.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError) as error:
        print(f"Espanso setup: {error}", file=sys.stderr)
        sys.exit(1)
