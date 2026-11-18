#!/usr/bin/env python3
"""Resolve repository settings to the installing user's home, without editing sources."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import sys
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

# Plain file/directory links share one replacement policy. App-written JSON/TOML
# above still goes through render(); do not put machine state or secrets here.
LINKS = {
    **{name: name for name in ('.dein.toml', '.gitconfig', '.gitignore_global', '.vimrc')},
    'misc/docker-config.json': '.docker/config.json',
    'claude/keybindings.json': '.claude/keybindings.json',
    'misc/ssh/config': '.ssh/config',
}
MAC_LINKS = {'misc/memo-config.toml': '.config/memo/config.toml'}
SHELL_FILES = ('.zpreztorc', '.zprofile', '.zshenv', '.zshrc')
EDITOR_FILES = ('settings.json', 'keybindings.json', 'tsconfig.json', 'snippets')


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
    if not source.exists():
        raise FileNotFoundError(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink() and target.resolve() == source.resolve():
        return
    if target.is_symlink():
        target.unlink()
    elif target.exists():
        target.rename(target.with_name(target.name + '.bak.' + str(time.time_ns())))
    target.symlink_to(source)


def install_links(home, root=ROOT, profile='full', platform=sys.platform, zdotdir=None):
    links = dict(LINKS)
    if platform == 'darwin':
        links.update(MAC_LINKS)
        if profile == 'full':
            links['hammerspoon'] = '.hammerspoon'
        # ngrok.yml is intentionally untracked. A clean clone must not produce
        # a dangling link, nor replace this machine's private ngrok config.
        ngrok_source = root / 'misc/ngrok.yml'
        ngrok_target = home / 'Library/Application Support/ngrok/ngrok.yml'
        if ngrok_source.is_file():
            links['misc/ngrok.yml'] = 'Library/Application Support/ngrok/ngrok.yml'
        elif ngrok_target.is_symlink() and ngrok_target.resolve() == ngrok_source.resolve():
            ngrok_target.unlink()
    for source, target in links.items():
        link(home / target, root / source)
    for name in SHELL_FILES:
        link((zdotdir or home) / name, root / name)
    ssh = home / '.ssh'
    ssh.chmod(0o700)
    # chmod through a symlink would modify the tracked source. Only local files
    # need permissions here; git stores the shared config without secrets.
    local = ssh / 'config.local'
    if not local.exists():
        local.touch(mode=0o600)


def install_skills(home, root=ROOT):
    for agent in ('claude', 'codex'):
        destination = home / f'.{agent}/skills'
        # Normalize a whole-directory link before descending, preserving every
        # existing child through its own link. Never mutate the source directory
        # and do not lose access to unrelated or plugin-managed skills.
        if destination.is_symlink():
            previous = destination.resolve()
            children = list(previous.iterdir()) if previous.is_dir() else []
            destination.unlink()
            destination.mkdir(parents=True)
            for child in children:
                (destination / child.name).symlink_to(child)
        destination.mkdir(parents=True, exist_ok=True)
        managed_roots = (root / agent / 'skills', root / 'agents/skills')
        resolved_roots = {folder.resolve() for folder in managed_roots}
        wanted = {}
        for folder in managed_roots:
            for skill in sorted(folder.glob('*')):
                if skill.is_dir():
                    if skill.name in wanted:
                        raise ValueError(f'Duplicate {agent} skill: {skill.name}')
                    wanted[skill.name] = skill
        for name, source in wanted.items():
            link(destination / name, source)
        # Remove only obsolete links directly into our own skill folders. Local
        # skills and plugin-managed links remain owned by their installers.
        for target in destination.iterdir():
            if target.is_symlink() and target.name not in wanted:
                if target.resolve().parent in resolved_roots:
                    target.unlink()


def install_editors(home, root=ROOT, platform=sys.platform):
    # WSL deploy configures the Linux editors. Windows editors are configured by
    # win/scripts/deploy.ps1, rather than guessing a Windows account name.
    base = home / ('Library/Application Support' if platform == 'darwin' else '.config')
    for editor in ('Code', 'Cursor'):
        for name in EDITOR_FILES:
            link(base / editor / 'User' / name, root / 'vscode' / name)


def install_prezto(zdotdir):
    for source in sorted((zdotdir / '.zprezto/runcoms').iterdir()):
        if source.is_file() and source.name not in ('README.md', 'zpreztorc', 'zshenv', 'zshrc', 'zprofile'):
            link(zdotdir / ('.' + source.name), source)


def install_screenpipe(home, root=ROOT):
    for source in sorted((root / 'screenpipe/pipes').glob('*/pipe.md')):
        target = home / '.screenpipe/pipes' / source.parent.name
        link(target / 'pipe.md', source)
        for extension in sorted((source.parent / 'extensions').glob('*.ts')):
            link(target / '.pi/extensions' / extension.name, extension)


def install(name, home, root=ROOT, claude_config_dir=None):
    if name == 'karabiner':
        source = root / 'karabiner'
        if not (source / 'karabiner.json').is_file():
            raise FileNotFoundError(source / 'karabiner.json')
        # Karabiner may create this directory before the first deploy. Preserve
        # it before linking; ln -sfn alone would create a nested link inside it.
        link(home / '.config/karabiner', source)
        return source
    if name == 'agent-instructions':
        # 本文はGit管理下に置き、標準の共通指示の置き場所にはリンクだけを作る。
        instructions = [
            ('codex/AGENTS.md', home / '.codex/AGENTS.md'),
        ]
        claude_rules = ('git-workflow.md', 'personal-procedures.md')
        instructions.extend(
            (f'docs/{rule}', home / '.claude/rules' / rule) for rule in claude_rules
        )
        if claude_config_dir is not None:
            instructions.extend(
                (f'docs/{rule}', Path(claude_config_dir) / 'rules' / rule) for rule in claude_rules
            )
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
    parser.add_argument('config', choices=[*CONFIGS, 'iterm2', 'agent-instructions', 'karabiner',
                                         'links', 'skills', 'editors', 'prezto', 'screenpipe'])
    parser.add_argument('--profile', choices=['full', 'minimal'], default=os.environ.get('DOTFILES_PROFILE', 'full'))
    parser.add_argument('--claude-config-dir', type=Path,
                        help='別のCLAUDE_CONFIG_DIRにも共通ルールを配置する（agent-instructionsのみ）')
    args = parser.parse_args()
    if args.claude_config_dir is not None and args.config != 'agent-instructions':
        parser.error('--claude-config-dir は agent-instructions と組み合わせてください')
    claude_config_dir = args.claude_config_dir.expanduser().resolve() if args.claude_config_dir is not None else None
    if args.config == 'links':
        install_links(Path.home(), profile=args.profile,
                      zdotdir=Path(os.environ.get('ZDOTDIR') or str(Path.home())))
        return
    if args.config == 'skills':
        install_skills(Path.home())
        return
    if args.config == 'editors':
        install_editors(Path.home())
        return
    if args.config == 'prezto':
        install_prezto(Path(os.environ.get('ZDOTDIR') or str(Path.home())))
        return
    if args.config == 'screenpipe':
        install_screenpipe(Path.home())
        return
    print(install(args.config, Path.home(), claude_config_dir=claude_config_dir))


if __name__ == '__main__':
    main()
