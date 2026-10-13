#!/usr/bin/env python3
"""Apply explicit file associations and CleanShot shortcuts for this Mac's user."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

CONFIG = Path(__file__).resolve().parent.parent / 'misc/default-apps.json'
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def run(*args):
    return subprocess.run(args, text=True, capture_output=True)


def applications():
    found = {}
    for root in (Path('/Applications'), Path.home() / 'Applications'):
        for pattern in ('*.app', '*/*.app'):
            for app in root.glob(pattern):
                try:
                    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
                    found[info['CFBundleIdentifier'].lower()] = app
                except (OSError, KeyError, plistlib.InvalidFileException):
                    continue
    return found


def preferences(domain):
    result = run('defaults', 'export', domain, '-')
    if result.returncode == 0:
        return plistlib.loads(result.stdout.encode())
    if 'does not exist' in result.stderr + result.stdout:
        return {}
    raise RuntimeError(f'Could not read {domain} preferences; no settings for this domain were overwritten.')


def handler(duti, extension):
    result = run(duti, '-x', extension)
    return result.stdout.strip().splitlines()[-1] if result.returncode == 0 and result.stdout.strip() else ''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--apply', action='store_true', help='apply settings (default)')
    group.add_argument('--check', action='store_true', help='inspect only; exit 1 on mismatch')
    group.add_argument('--dry-run', action='store_true', help='show changes without writing')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        print('Skipping default apps: requires macOS.')
        return 0
    duti = shutil.which('duti')
    if not duti:
        print('Install duti first: brew install duti', file=sys.stderr)
        return 1
    config = json.loads(CONFIG.read_text())
    apps = applications()
    apply = not (args.check or args.dry_run)
    changes = []
    failed = False
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'dotfiles/default-apps'
    backup = state / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backed_up = False

    def save_backup():
        nonlocal backed_up
        if backed_up:
            return
        backup.mkdir(parents=True, mode=0o700)
        source = Path.home() / 'Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist'
        if source.exists():
            shutil.copy2(source, backup / source.name)
        # Only the keys managed here; never copy CleanShot's license or account.
        screenshot = config['screenshots']
        prefs = preferences(screenshot['bundleId'])
        subset = {key: prefs[key] for key in screenshot['shortcuts'] if key in prefs}
        (backup / 'cleanshot-shortcuts.plist').write_bytes(plistlib.dumps(subset))
        (backup / 'symbolic-hotkeys.plist').write_bytes(plistlib.dumps(preferences('com.apple.symbolichotkeys')))
        (backup / 'associations.json').write_text(json.dumps(changes, indent=2) + '\n')
        backed_up = True
        print(f'Backup: {backup}')

    # Resolve installed apps before writing. Acrobat Pro is preferred; Reader
    # is used on Macs with only Reader. Missing apps are reported, not installed.
    plans = []
    for association in config['fileAssociations']:
        bundle = next((b for b in association['bundleIds'] if b.lower() in apps), None)
        if not bundle:
            print(f"Missing app: {association['name']}", file=sys.stderr)
            failed = True
            continue
        for extension in association['extensions']:
            current = handler(duti, extension)
            plans.append((bundle, extension, current))
            if current.lower() != bundle.lower():
                changes.append({'extension': extension, 'before': current, 'after': bundle})

    registered = set()
    for bundle, extension, current in plans:
        if current.lower() == bundle.lower():
            print(f'OK .{extension} -> {bundle}')
            continue
        print(f"{'Set' if apply else 'Mismatch' if args.check else 'Would set'} .{extension}: {current or 'unknown'} -> {bundle}")
        if not apply:
            failed = failed or args.check
            continue
        save_backup()
        if bundle not in registered:
            result = run(LSREGISTER, '-f', str(apps[bundle.lower()]))
            if result.returncode:
                print(result.stderr, file=sys.stderr)
                failed = True
                continue
            registered.add(bundle)
        result = run(duti, '-s', bundle, '.' + extension, 'all')
        actual = handler(duti, extension)
        if result.returncode or actual.lower() != bundle.lower():
            print(f'Failed .{extension}: {result.stderr.strip()} actual={actual or "unknown"}', file=sys.stderr)
            failed = True

    screenshot = config['screenshots']
    domain = screenshot['bundleId']
    if domain.lower() not in apps:
        print('Missing CleanShot X: screenshot settings skipped.', file=sys.stderr)
        return 1
    prefs = preferences(domain)
    reload_needed = False
    for key, expected in screenshot['shortcuts'].items():
        actual = prefs.get(key)
        if isinstance(actual, bytes):
            actual = json.loads(actual)
        # CleanShot also stores True for its built-in default binding.
        if actual is True or actual == expected:
            print(f'OK CleanShot {key}')
            continue
        print(f"{'Set' if apply else 'Mismatch' if args.check else 'Would set'} CleanShot {key}")
        if apply:
            save_backup()
            data = json.dumps(expected, separators=(',', ':')).encode().hex()
            result = run('defaults', 'write', domain, key, '-data', data)
            failed = failed or result.returncode != 0
            reload_needed = True
        else:
            failed = failed or args.check
    system = preferences('com.apple.symbolichotkeys').get('AppleSymbolicHotKeys', {})
    for key in screenshot['disabledSystemShortcuts']:
        value = system.get(key, {})
        if value.get('enabled') is False or value.get('enabled') == 0:
            print(f'OK native screenshot shortcut {key}: disabled')
            continue
        print(f"{'Disable' if apply else 'Mismatch' if args.check else 'Would disable'} native screenshot shortcut {key}")
        if apply:
            save_backup()
            value['enabled'] = False
            xml = plistlib.dumps(value, fmt=plistlib.FMT_XML).decode()
            result = run('defaults', 'write', 'com.apple.symbolichotkeys', 'AppleSymbolicHotKeys', '-dict-add', key, xml)
            failed = failed or result.returncode != 0
        else:
            failed = failed or args.check
    if reload_needed:
        print('Restart CleanShot X to activate the changed shortcuts. Existing captures were not interrupted.')
        failed = True
    # Verify stored screenshot settings after writes through a read-only pass.
    if apply and not failed:
        return subprocess.run([sys.executable, str(Path(__file__).resolve()), '--check']).returncode
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
