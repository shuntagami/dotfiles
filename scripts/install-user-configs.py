#!/usr/bin/env python3
"""Resolve repository settings to the installing user's home, without editing sources."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
# Existing app-written settings use these homes. Treat them as template prefixes,
# never as directories to read on the destination machine.
SOURCE_HOME = Path('/Users/shun.tagami')
SOURCE_HOMES = (str(SOURCE_HOME), '/Users/shuntagami')
CONFIGS = {
    'codex': ('codex/config.toml', '.codex/config.toml'),
    'claude': ('claude/settings.json', '.claude/settings.json'),
    'claude-desktop': ('misc/claude_desktop_config.json',
                       'Library/Application Support/Claude/claude_desktop_config.json'),
}


def relocate_string(value, home):
    # Codex notification arguments and trusted-services env vars contain JSON
    # inside a TOML string. Decode first so escaped slashes and quoted homes work.
    if value.startswith(('{', '[')):
        try:
            nested = json.loads(value)
        except ValueError:
            pass
        else:
            updated = relocate(nested, home)
            if updated != nested:
                return json.dumps(updated, ensure_ascii=False, separators=(',', ':'))
    for prefix in SOURCE_HOMES:
        value = re.sub(re.escape(prefix) + r'(?=$|/|:)', lambda _: str(home), value)
    return value.replace('${HOME}', str(home))


def relocate(value, home, location=()):
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            if key == 'command' and ('hooks' in location or 'statusLine' in location):
                # These commands are shell strings; MCP commands are executable
                # paths and must not get shell quoting.
                tokens = shlex.split(item)
                updated = [relocate_string(token, home) for token in tokens]
                result[key] = shlex.join(updated) if tokens != updated else item
            else:
                result[relocate_string(key, home)] = relocate(item, home, (*location, key))
        return result
    if isinstance(value, list):
        return [relocate(item, home, location) for item in value]
    if isinstance(value, str):
        return relocate_string(value, home)
    return value


def render(source, home):
    if source.suffix == '.json':
        return (json.dumps(relocate(json.loads(source.read_text()), home),
                           ensure_ascii=False, indent=2) + '\n').encode()
    if source.suffix == '.plist':
        return plistlib.dumps(relocate(plistlib.loads(source.read_bytes()), home), sort_keys=False)
    # Replace individual TOML string values/keys, preserving comments and tables.
    # These templates use single-line basic and literal strings. Re-encoding as
    # basic strings handles spaces, quotes, and embedded JSON without dependencies.
    def string(match):
        token = match.group()
        value = json.loads(token) if token.startswith('"') else token[1:-1]
        updated = relocate_string(value, home)
        return json.dumps(updated, ensure_ascii=False) if updated != value else token
    return re.sub(r'"(?:\\.|[^"\\\n])*"|\'[^\'\n]*\'', string, source.read_text()).encode()


def write_if_changed(target, content):
    if target.exists() and target.read_bytes() == content:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix='.' + target.name)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def link(target, source):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink() and target.resolve() == source.resolve():
        return
    if target.is_symlink():
        target.unlink()
    elif target.exists():
        target.rename(target.with_name(target.name + '.bak.' + str(time.time_ns())))
    target.symlink_to(source)


def install(name, home, root=ROOT, claude_config_dir=None):
    if name == 'agent-instructions':
        # 本文はGit管理下に置き、標準の共通指示の置き場所にはリンクだけを作る。
        instructions = [
            ('codex/AGENTS.md', home / '.codex/AGENTS.md'),
            ('docs/git-workflow.md', home / '.claude/rules/git-workflow.md'),
        ]
        if claude_config_dir is not None:
            instructions.append(('docs/git-workflow.md', Path(claude_config_dir) / 'rules/git-workflow.md'))
        for source, _ in instructions:
            if not (root / source).is_file():
                raise FileNotFoundError(root / source)
        for source, target in instructions:
            link(target, root / source)
        return root
    generated = home / '.local/share/dotfiles/generated'
    if name == 'iterm2':
        source = root / 'misc/com.googlecode.iterm2.plist'
        write_if_changed(generated / source.name, render(source, home))
        return generated
    source_name, target_name = CONFIGS[name]
    source = root / source_name
    # Keep the author's existing app -> repository update flow. Other users get
    # resolved local files, so editing their configs cannot rewrite the templates.
    if home == SOURCE_HOME:
        resolved = source
    else:
        resolved = generated / source_name
        write_if_changed(resolved, render(source, home))
    link(home / target_name, resolved)
    return resolved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', choices=[*CONFIGS, 'iterm2', 'agent-instructions'])
    parser.add_argument('--claude-config-dir', type=Path,
                        help='別のCLAUDE_CONFIG_DIRにも共通ルールを配置する（agent-instructionsのみ）')
    args = parser.parse_args()
    if args.claude_config_dir is not None and args.config != 'agent-instructions':
        parser.error('--claude-config-dir は agent-instructions と組み合わせてください')
    profile = args.claude_config_dir.expanduser().resolve() if args.claude_config_dir is not None else None
    print(install(args.config, Path.home(), claude_config_dir=profile))


if __name__ == '__main__':
    main()
