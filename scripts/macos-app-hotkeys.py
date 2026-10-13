#!/usr/bin/env python3
"""Apply only repository-managed Aqua Voice and Clipy shortcut preferences."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile

MISC = Path(__file__).resolve().parent.parent / 'misc'


def merge_hotkeys(existing, desired):
    by_action = {item['action']: item for item in desired}
    result = [dict(item, keys=by_action[item['action']]['keys'])
              if item.get('action') in by_action else item for item in existing]
    present = {item.get('action') for item in existing}
    result.extend(item for item in desired if item['action'] not in present)
    return result


def keycombo(key, modifiers):
    # Clipy 1.4 / Magnet stores a string key as an archived object. The old
    # macos.sh used keyCode, which is absent from this version's saved format.
    return plistlib.dumps({
        '$version': 100000, '$archiver': 'NSKeyedArchiver',
        '$top': {'root': plistlib.UID(1)},
        '$objects': ['$null', {
            '$class': plistlib.UID(3), 'key': plistlib.UID(2),
            'modifiers': modifiers, 'doubledModifiers': False,
        }, key, {'$classname': 'Magnet.KeyCombo',
                 '$classes': ['Magnet.KeyCombo', 'NSObject']}],
    }, fmt=plistlib.FMT_BINARY)


def shortcut_value(data):
    try:
        archive = plistlib.loads(data)
        objects = archive['$objects']
        combo = objects[archive['$top']['root'].data]
        key = objects[combo['key'].data]
        return {'key': key, 'modifiers': combo['modifiers']}
    except (KeyError, TypeError, IndexError, AttributeError, plistlib.InvalidFileException):
        return None


def backup(app, data):
    root = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    directory = root / 'dotfiles/app-hotkeys' / app
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / (datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.plist')
    path.write_bytes(plistlib.dumps(data))
    path.chmod(0o600)
    print(f'Backup: {path}')


def aqua(mode):
    path = Path.home() / 'Library/Application Support/Aqua Voice/settings.json'
    if not path.exists():
        print('Aqua Voice settings missing: launch the app once, then run deploy again.')
        return 1
    settings = json.loads(path.read_text())
    desired = json.loads((MISC / 'aqua-voice-hotkeys.json').read_text())
    current = settings.get('hotkeys', [])
    merged = merge_hotkeys(current, desired)
    if merged == current:
        print('OK Aqua Voice shortcuts')
        return 0
    if mode != 'apply':
        print('Aqua Voice: managed shortcuts differ.')
        return int(mode == 'check')
    backup('aqua-voice', {'hotkeys': current})
    settings['hotkeys'] = merged
    # Replace atomically; keep unrelated settings and all unmanaged actions.
    fd, temporary = tempfile.mkstemp(prefix='.dotfiles-hotkeys-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as file:
            json.dump(settings, file, indent=2, ensure_ascii=False)
            file.write('\n')
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode))
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    if json.loads(path.read_text())['hotkeys'] != merged:
        raise RuntimeError('Aqua Voice settings verification failed')
    print('Saved Aqua Voice shortcuts. Restart Aqua Voice to load them.')
    return 0


def clipy(mode):
    domain = 'com.clipy-app.Clipy'
    desired = json.loads((MISC / 'clipy-hotkeys.json').read_text())
    result = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True)
    if result.returncode:
        if b'does not exist' not in result.stderr + result.stdout:
            raise RuntimeError('Could not read Clipy preferences; no changes made.')
        current = {}
    else:
        current = plistlib.loads(result.stdout)
    changes = [(key, '-data', keycombo(**value).hex())
               for key, value in desired['hotkeys'].items()
               if shortcut_value(current.get(key)) != value]
    history_key = 'kCPYPrefMaxHistorySizeKey'
    if current.get(history_key) != desired['maxHistorySize']:
        changes.append((history_key, '-int', str(desired['maxHistorySize'])))
    if not changes:
        print('OK Clipy shortcuts and history size')
        return 0
    if mode != 'apply':
        print('Clipy: ' + ', '.join(key for key, _, _ in changes) + ' differ.')
        return int(mode == 'check')
    backup('clipy', {key: current[key] for key, _, _ in changes if key in current})
    for key, kind, value in changes:
        subprocess.run(['defaults', 'write', domain, key, kind, value], check=True)
    if clipy('check'):
        raise RuntimeError('Clipy preferences verification failed')
    print('Saved Clipy settings. Restart Clipy to load them.')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', choices=['aqua-voice', 'clipy'])
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--check', action='store_true')
    group.add_argument('--dry-run', action='store_true')
    group.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if sys.platform != 'darwin':
        print('Skipping app shortcuts: requires macOS.')
        return 0
    app_name = 'Aqua Voice.app' if args.app == 'aqua-voice' else 'Clipy.app'
    if not any((root / app_name).is_dir() for root in [Path('/Applications'), Path.home() / 'Applications']):
        print(f'Skipping {app_name}: app is not installed.')
        return 0
    mode = 'check' if args.check else 'dry-run' if args.dry_run else 'apply'
    return aqua(mode) if args.app == 'aqua-voice' else clipy(mode)


if __name__ == '__main__':
    sys.exit(main())
