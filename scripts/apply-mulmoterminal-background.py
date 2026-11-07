#!/usr/bin/env python3
"""Apply the personal background to saved directories and existing terminal worktrees."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = json.loads((ROOT / 'mulmoterminal/background.json').read_text())
SOURCE = ROOT / 'mulmoterminal' / SETTINGS['image']
REL_IMAGE = '.mulmoterminal-background/dog.JPG'
API = 'http://localhost:' + os.environ.get('MULMOTERMINAL_PORT', '34567')


def get(route, **params):
    url = API + route + ('?' + urllib.parse.urlencode(params) if params else '')
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.load(response)


def read_object(path):
    value = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(value, dict):
        raise ValueError('Expected JSON object: ' + str(path))
    return value


def write_object(path, value):
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.background-config-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def git(directory, *args):
    result = subprocess.run(['git', '-C', str(directory), *args], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return result.stdout.strip() if result.returncode == 0 else None


def main():
    assert SOURCE.is_file(), SOURCE
    try:
        config = get('/api/config')
        live = True
    except OSError:
        config = read_object(Path.home() / '.mulmoterminal/config.json')
        live = False
    directories = {Path(item['path']) for item in config.get('cwdPresets', [])}
    if shutil.which('tmux'):
        result = subprocess.run(['tmux', '-L', 'mulmoterminal', 'list-panes', '-a',
                                 '-F', '#{pane_current_path}'], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            directories.update(Path(p) for p in result.stdout.splitlines() if p.startswith('/'))
    count = 0
    for directory in sorted(directories):
        if not directory.is_dir():
            continue
        local = directory / '.mulmoterminal.local.json'
        data = read_object(local)
        detail = get('/api/dir-config-detail', cwd=str(directory)) if live else None
        existing = detail['config'].get('backgroundImage') if detail else data.get('backgroundImage')
        ours = isinstance(data.get('backgroundImage'), dict) and data['backgroundImage'].get('image') == REL_IMAGE
        if existing and not ours:
            print('Preserved existing background:', directory)
            continue
        # Personal files must not appear as untracked changes in the user's projects.
        top = git(directory, 'rev-parse', '--show-toplevel')
        if top:
            exclude = git(directory, 'rev-parse', '--path-format=absolute', '--git-path', 'info/exclude')
            if exclude:
                path = Path(exclude)
                path.parent.mkdir(parents=True, exist_ok=True)
                text = path.read_text() if path.exists() else ''
                prefix = directory.resolve().relative_to(Path(top).resolve()).as_posix()
                prefix = '' if prefix == '.' else prefix + '/'
                for name in ['.mulmoterminal.local.json', '.mulmoterminal-background/']:
                    line = '/' + prefix + name
                    if line not in text.splitlines():
                        text += '\n' + line + '\n'
                path.write_text(text)
        destination = directory / REL_IMAGE
        destination.parent.mkdir(exist_ok=True)
        if destination.exists() and not ours:
            raise RuntimeError('Unmanaged image already exists: ' + str(destination))
        if local.exists() and not ours:
            backup = Path.home() / '.cache/dotfiles/background-before'
            backup.mkdir(parents=True, exist_ok=True)
            key = hashlib.sha256(str(directory).encode()).hexdigest()
            target = backup / (key + '.json')
            if not target.exists():
                shutil.copy2(local, target)
        shutil.copy2(SOURCE, destination)
        data['backgroundImage'] = {**SETTINGS, 'image': REL_IMAGE}
        write_object(local, data)
        if live:
            applied = get('/api/dir-config-detail', cwd=str(directory))['config']['backgroundImage']
            if not applied or applied['opacity'] != SETTINGS['opacity'] or applied['fit'] != SETTINGS['fit']:
                raise RuntimeError('Background was not accepted: ' + str(directory))
            with urllib.request.urlopen(API + applied['url'], timeout=5) as response:
                if hashlib.sha256(response.read()).digest() != hashlib.sha256(SOURCE.read_bytes()).digest():
                    raise RuntimeError('Served image differs: ' + str(directory))
        count += 1
        print('Applied' + (' and verified: ' if live else ': '), directory)
    print('Background applied to', count, 'directories.')


if __name__ == '__main__':
    main()
