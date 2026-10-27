#!/usr/bin/env python3
"""有効化したリポジトリで、既定worktreeに残る変更のコピーをpush前に読み取り専用で確認する。"""
import os
from pathlib import Path
import subprocess
import sys

# フックの環境変数が、別worktreeへのgitコマンドにも現在のindexを使わせるのを防ぐ。
ENV = {k: v for k, v in os.environ.items() if k not in {
    'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_PREFIX',
    'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES',
}}
ENV['GIT_LITERAL_PATHSPECS'] = '1'


def git(cwd, *args, optional=False, data=None):
    result = subprocess.run(['git', '-C', str(cwd), *args], env=ENV, input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        if optional:
            return None
        raise RuntimeError(result.stderr.decode(errors='replace').strip())
    return result.stdout


def paths(raw):
    return {os.fsdecode(x) for x in raw.split(b'\0') if x}


def default_ref(root, remote):
    named = git(root, 'symbolic-ref', '-q', f'refs/remotes/{remote}/HEAD', optional=True)
    if named:
        return named.decode().strip()
    for branch in ('main', 'master'):
        ref = f'refs/remotes/{remote}/{branch}'
        if git(root, 'rev-parse', '--verify', ref, optional=True):
            return ref
    return None


def working_blob(root, name):
    file = root / name
    if file.is_symlink():
        return git(root, 'hash-object', '--stdin', data=os.fsencode(os.readlink(file))).strip()
    if file.is_file():
        return git(root, 'hash-object', '--path', name, '--', str(file)).strip()
    return None


def check(remote, updates):
    cwd = Path.cwd()
    enabled = git(cwd, 'config', '--bool', '--get', 'workflow.checkDuplicateEdits', optional=True)
    if enabled != b'true\n':
        return 0
    current = git(cwd, 'rev-parse', '--show-toplevel', optional=True)
    if not current:
        return 0
    records = git(cwd, 'worktree', 'list', '--porcelain', '-z').split(b'\0')
    roots = [Path(os.fsdecode(x[9:])) for x in records if x.startswith(b'worktree ')]
    if not roots or roots[0].resolve() == Path(os.fsdecode(current.strip())).resolve():
        return 0  # 同じworktree内でブランチを切り替える運用は対象外。
    root = roots[0]
    target = default_ref(root, remote)
    if not target:
        return 0
    branch = git(root, 'symbolic-ref', '--short', '-q', 'HEAD', optional=True)
    prefix = f'refs/remotes/{remote}/'
    if not branch or branch.decode().strip() != target.removeprefix(prefix):
        return 0
    staged = paths(git(root, 'diff', '--cached', '--name-only', '-z'))
    dirty = staged | paths(git(root, 'diff', '--name-only', '-z'))
    dirty |= paths(git(root, 'ls-files', '--others', '--exclude-standard', '-z'))
    duplicates = set()
    for line in updates:
        local_ref, oid, remote_ref, _ = line.split()
        if set(oid) == {'0'} or not remote_ref.startswith('refs/heads/'):
            continue
        base = git(root, 'merge-base', target, oid, optional=True)
        if not base:
            continue
        changed = paths(git(root, 'diff', '--name-only', '--no-renames', '-z', base.decode().strip(), oid))
        for name in dirty & changed:
            if (root / name).is_dir() and not (root / name).is_symlink():
                continue
            expected = git(root, 'rev-parse', '--verify', f'{oid}:{name}', optional=True)
            expected = expected.strip() if expected else None
            index = git(root, 'rev-parse', '--verify', f':{name}', optional=True) if name in staged else None
            if working_blob(root, name) == expected or (index and index.strip() == expected):
                duplicates.add(name)
    if not duplicates:
        return 0
    print(f'[pre-push] 既定のworktreeに、pushする内容と重複した未保存変更が残っています: {root}', file=sys.stderr)
    for name in sorted(duplicates):
        print(f'  {name}', file=sys.stderr)
    print('push対象のcommitと同じ内容です。バックアップを残し、上記の変更だけを確認・整理してからpushしてください。'
          '無関係な作業は残してください。このチェックはファイルを変更していません。', file=sys.stderr)
    return 1


if __name__ == '__main__':
    try:
        sys.exit(check(sys.argv[1], sys.stdin.read().splitlines()))
    except (OSError, RuntimeError, ValueError, IndexError) as error:
        print(f'[pre-push] 変更の重複を確認できませんでした: {error}', file=sys.stderr)
        sys.exit(1)
