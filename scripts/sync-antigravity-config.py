#!/usr/bin/env python3
"""Merge shared Antigravity CLI settings while keeping machine-local trust lists."""
import argparse
from importlib.util import module_from_spec, spec_from_file_location
import json
import os
from pathlib import Path
import tempfile


_paths_spec = spec_from_file_location('user_configs', Path(__file__).with_name('install-user-configs.py'))
_paths = module_from_spec(_paths_spec)
_paths_spec.loader.exec_module(_paths)

ROOT = Path(__file__).resolve().parent.parent
DOTFILES_CONFIG = ROOT / 'antigravity' / 'settings.json'

# Machine-local workspace paths (this repository is public).
LOCAL_KEYS = frozenset({'trustedWorkspaces'})
LIVE_MODE = 0o600
SOURCE_MODE = 0o644


def live_config_path(home=None, env=None):
    """Resolve the active Antigravity CLI settings.json path."""
    if home is not None:
        return Path(home) / '.gemini' / 'antigravity-cli' / 'settings.json'
    active_env = os.environ if env is None else env
    antigravity_home = active_env.get('ANTIGRAVITY_HOME')
    if antigravity_home:
        return Path(antigravity_home).expanduser() / 'settings.json'
    return Path.home() / '.gemini' / 'antigravity-cli' / 'settings.json'


def read_object(path):
    """Read a JSON file and ensure its top-level value is a JSON object."""
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise SystemExit(f'expected a JSON object: {path}')
    return value


def write_object(path, value, mode):
    """Atomically write a JSON object file with explicit permissions."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name + '.')
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def shared(config):
    """Return only non-local keys safe to synchronize across machines."""
    return {key: value for key, value in config.items() if key not in LOCAL_KEYS}


def apply(dry_run=False, home=None, dotfiles_config=DOTFILES_CONFIG, live_config=None):
    """Apply shared keys from dotfiles to the live Antigravity settings.json."""
    target_home = Path.home() if home is None else Path(home)
    live_path = live_config_path(home=home) if live_config is None else Path(live_config)
    wanted = shared(_paths.relocate(read_object(dotfiles_config), target_home))

    if not live_path.exists():
        print(f'Antigravity config: {live_path} is missing; ' + ('would seed' if dry_run else 'seeding') + ' from dotfiles')
        if not dry_run:
            write_object(live_path, wanted, LIVE_MODE)
        return sorted(wanted)

    live = read_object(live_path)
    changes = {key: value for key, value in wanted.items() if live.get(key) != value}
    if not changes and not live_path.is_symlink():
        print('Antigravity config: nothing to apply')
        return []

    if changes:
        print('Antigravity config: ' + ('would set ' if dry_run else 'setting ') + ', '.join(sorted(changes)))
    else:
        print('Antigravity config: ' + ('would replace symlink with regular file at ' if dry_run else 'replacing symlink with regular file at ') + str(live_path))

    if not dry_run:
        write_object(live_path, {**live, **changes}, LIVE_MODE)
    return sorted(changes)


def save(dry_run=False, dotfiles_config=DOTFILES_CONFIG, live_config=None):
    """Save shared keys from live Antigravity settings.json back into dotfiles."""
    live_path = live_config_path() if live_config is None else Path(live_config)
    live = read_object(live_path)
    saved = read_object(dotfiles_config) if dotfiles_config.exists() else {}

    merged = {}
    for key, value in live.items():
        if key not in LOCAL_KEYS:
            merged[key] = value
        elif key in saved:
            merged[key] = saved[key]
    merged.update({key: saved[key] for key in LOCAL_KEYS if key in saved and key not in merged})

    changed = sorted(key for key in merged.keys() | saved.keys() if merged.get(key) != saved.get(key))
    print('Antigravity dotfiles copy: ' + (('would update ' if dry_run else 'updating ') + ', '.join(changed) if changed else 'already up to date'))
    if changed and not dry_run:
        write_object(dotfiles_config, merged, SOURCE_MODE)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('direction', choices=['apply', 'save'])
    parser.add_argument('--dry-run', action='store_true', help='report what would change, change nothing')
    args = parser.parse_args()
    if args.direction == 'apply':
        apply(dry_run=args.dry_run)
    else:
        save(dry_run=args.dry_run)


if __name__ == '__main__':
    main()
