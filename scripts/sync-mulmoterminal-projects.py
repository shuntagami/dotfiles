#!/usr/bin/env python3
"""Restore Git-backed personal project defaults without editing tracked project files."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
REL_IMAGE = '.mulmoterminal-background/dog.JPG'


def read(path):
    value = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(value, dict):
        raise ValueError(f'Expected object: {path}')
    return value


def git(path, *args):
    result = subprocess.run(['git', '-C', str(path), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def tracked(directory, path):
    return git(directory, 'ls-files', '--error-unmatch', str(path)) is not None


def ignore(directory, paths):
    top = git(directory, 'rev-parse', '--show-toplevel')
    exclude = git(directory, 'rev-parse', '--path-format=absolute', '--git-path', 'info/exclude')
    if not top or not exclude:
        return
    file = Path(exclude)
    text = file.read_text() if file.exists() else ''
    for path in paths:
        line = '/' + path.resolve().relative_to(Path(top).resolve()).as_posix()
        if line not in text.splitlines():
            text += '\n' + line + '\n'
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(text)


def apply(directory, profile, image, settings, dry_run=False):
    shared = directory / '.mulmoterminal.json'
    local = directory / '.mulmoterminal.local.json'
    base = read(directory / 'repo.json')
    # repo.json can supply native appearance; preserve it instead of overriding it.
    effective = dict(base.get('extensions', {}).get('mulmoterminal', {}))
    if base.get('color'):
        effective.update({k: base['color'] for k in profile if k.endswith('Color')})
    effective.update(read(shared))
    effective.update(read(local))
    desired = {**profile, 'backgroundImage': {**settings, 'image': REL_IMAGE}}
    missing = {k: v for k, v in desired.items() if k not in effective}
    target = None
    if missing:
        target = next((p for p in [shared, local] if not tracked(directory, p)), None)
        if target is None:
            raise RuntimeError(f'{directory}: both config files are tracked; add missing defaults through a project PR')
    background = effective.get('backgroundImage', desired['backgroundImage'])
    image_path = background.get('image') if isinstance(background, dict) else background
    destination = directory / REL_IMAGE
    copy_image = image_path == REL_IMAGE
    if copy_image and destination.exists() and destination.read_bytes() != image.read_bytes():
        raise RuntimeError(f'Preserving different existing image: {destination}')
    if dry_run:
        return {'directory': str(directory), 'add_keys': list(missing), 'copy_image': copy_image and not destination.exists()}
    # Validate all conflicts before any writes; existing values always take precedence.
    if copy_image and not destination.exists():
        ignore(directory, [destination.parent])
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(image.read_bytes())
    if target:
        ignore(directory, [target])
        data = read(target)
        data.update(missing)
        target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    return {'directory': str(directory), 'add_keys': list(missing), 'background': copy_image}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--profiles', type=Path, default=Path.home() / 'ele-workspace/config/mulmoterminal-projects.json')
    args = parser.parse_args()
    profiles = read(args.profiles)
    settings = read(ROOT / 'mulmoterminal/background.json')
    image = ROOT / 'mulmoterminal' / settings['image']
    home = Path.home()
    for relative, profile in profiles.items():
        path = home / relative
        if Path(relative).is_absolute() or '..' in Path(relative).parts:
            raise ValueError(f'Unsafe project path: {relative}')
        if not path.is_dir():
            print(f'Skipped missing directory: {relative}')
            continue
        print(json.dumps(apply(path, profile, image, settings, args.dry_run), ensure_ascii=False))


if __name__ == '__main__':
    main()
