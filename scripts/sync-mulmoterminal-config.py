#!/usr/bin/env python3
"""Keep ~/.mulmoterminal/config.json and dotfiles' copy in step across machines.

  apply  dotfiles -> live. Seeds a missing config whole; on a configured machine it sets only
         the shared keys that differ, leaving the machine's own keys (LOCAL_KEYS) alone.
  save   live -> dotfiles. Copies the shared keys back; the LOCAL_KEYS in dotfiles are kept.

The file cannot simply be symlinked: MulmoTerminal writes it with write-temp-then-rename, which
replaces a symlink with a real file. And copying it whole in either direction carries one
machine's recent directories onto the other. So the two directions merge instead.

While the server runs, apply goes through POST /api/config, the app's own write path: it takes
effect without a restart for most keys and cannot race the app's own writes. A top-level key
sent there replaces that key whole, which is what "dotfiles decides this key" means.
"""
import argparse
import json
import os
from pathlib import Path
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
DOTFILES_CONFIG = ROOT / 'mulmoterminal' / 'config.json'
LIVE_CONFIG = Path.home() / '.mulmoterminal' / 'config.json'
API = 'http://localhost:' + os.environ.get('MULMOTERMINAL_PORT', '34567') + '/api/config'

# Keys dotfiles does not carry between machines, for one of two reasons.
# Per machine: cwdPresets is the launcher's list of recent directories; worklogEnabled starts a
# token-spending scheduled summary, wanted on one machine, not both; accounts and repoDirs point
# at directories on this disk.
# Private: this repository is PUBLIC, and prRepos / gitlabHosts name work repositories and hosts.
# Copy those between machines by hand (POST /api/config), never through a commit.
LOCAL_KEYS = {'cwdPresets', 'worklogEnabled', 'accounts', 'repoDirs', 'prRepos', 'gitlabHosts'}

# Read at server start rather than on the next tab reload.
RESTART_KEYS = {'prRepos', 'gitlabHosts', 'fontFamily', 'providers', 'sessionReapIntervalHours',
                'feedRefreshEnabled', 'calendarSyncEnabled'}


def read_object(path):
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise SystemExit(f'expected a JSON object: {path}')
    return value


def write_object(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name + '.')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def request(method, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(API, data=data, method=method, headers={'Content-Type': 'application/json'})
    # The API is on this machine; a proxy in the environment must not intercept it.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=5) as response:
        return json.load(response)


def shared(config):
    return {key: value for key, value in config.items() if key not in LOCAL_KEYS}


def apply(dry_run):
    wanted = read_object(DOTFILES_CONFIG)
    try:
        live, running = request('GET'), True
    except OSError:
        running = False
        if not LIVE_CONFIG.exists():
            print(f'{LIVE_CONFIG} is missing: seeding it whole from dotfiles')
            if not dry_run:
                write_object(LIVE_CONFIG, wanted)
            return
        live = read_object(LIVE_CONFIG)

    changes = {key: value for key, value in shared(wanted).items() if live.get(key) != value}
    if not changes:
        print('MulmoTerminal config: nothing to apply')
        return
    print('MulmoTerminal config: ' + ('would set ' if dry_run else 'setting ') + ', '.join(sorted(changes)))
    if dry_run:
        return

    if running:
        request('POST', changes)
        after = request('GET')
        # A value the server's validation dropped comes back different; say so rather than
        # reporting a setting that is not in force.
        dropped = sorted(key for key, value in changes.items() if after.get(key) != value)
        if dropped:
            raise SystemExit('MulmoTerminal did not keep: ' + ', '.join(dropped))
        restart = sorted(RESTART_KEYS & changes.keys())
        print('Applied through the running server. Reload the browser tab'
              + (f'; restart the server for {", ".join(restart)}' if restart else '') + '.')
    else:
        write_object(LIVE_CONFIG, {**read_object(LIVE_CONFIG), **changes})
        print(f'Wrote {LIVE_CONFIG}; it is read when MulmoTerminal next starts.')


def save(dry_run):
    live = read_object(LIVE_CONFIG)
    saved = read_object(DOTFILES_CONFIG) if DOTFILES_CONFIG.exists() else {}
    # In the live file's key order, so a save does not reshuffle the committed file.
    merged = {}
    for key, value in live.items():
        if key not in LOCAL_KEYS:
            merged[key] = value
        elif key in saved:
            merged[key] = saved[key]
    merged.update({key: saved[key] for key in LOCAL_KEYS if key in saved and key not in merged})
    changed = sorted(key for key in merged.keys() | saved.keys() if merged.get(key) != saved.get(key))
    print('dotfiles copy: ' + (('would update ' if dry_run else 'updating ') + ', '.join(changed) if changed else 'already up to date'))
    if changed and not dry_run:
        write_object(DOTFILES_CONFIG, merged)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('direction', choices=['apply', 'save'])
    parser.add_argument('--dry-run', action='store_true', help='report what would change, change nothing')
    args = parser.parse_args()
    (apply if args.direction == 'apply' else save)(args.dry_run)


if __name__ == '__main__':
    main()
