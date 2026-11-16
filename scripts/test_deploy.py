"""Exercise real deploy entry points in a disposable home with OS commands stubbed."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
ZSH = shutil.which('zsh')
FAKE_COMMAND = r'''
import json, os, sys
from pathlib import Path
name, args = Path(sys.argv[0]).name, sys.argv[1:]
home = Path(os.environ['HOME'])
with (home / 'commands.jsonl').open('a') as log:
    log.write(json.dumps([name, *args]) + '\n')
if name == 'uname':
    print(os.environ['TEST_OS'])
elif name == 'getent':
    print('test:x:501:20::' + str(home) + ':' + os.environ['TEST_ZSH'])
elif name == 'dscl':
    print('UserShell: ' + os.environ['TEST_ZSH'])
elif name == 'defaults':
    state = home / 'defaults.json'
    data = json.loads(state.read_text()) if state.exists() else {}
    key = '/'.join(args[1:3])
    if args[0] == 'write':
        data[key] = '1' if args[-1] == 'true' else args[-1]
        state.write_text(json.dumps(data))
    elif key in data:
        print(data[key])
    else:
        sys.exit(1)
elif name == 'osacompile':
    Path(args[args.index('-o') + 1]).write_text('compiled')
elif name == 'node':
    if args and args[0].endswith('/macos-system-settings.mjs'):
        sys.exit(int(os.environ.get('SYSTEM_SETUP_RESULT', '0')))
    sys.exit(int(os.environ.get('FAIL_NODE', '0')))
elif name == 'sudo':
    sys.exit('Unexpected sudo in an already configured account')
'''


@unittest.skipUnless(ZSH, 'zsh required')
class DeployTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / 'Test Mac'
        self.repo = self.home / 'dotfiles'
        scripts = self.repo / 'scripts'
        scripts.mkdir(parents=True)
        for name in ('deploy.sh', 'deploy-macos.sh', 'macos.sh', 'install-user-configs.py', 'sync-antigravity-config.py', 'app-settings-status.sh'):
            shutil.copyfile(ROOT / 'scripts' / name, scripts / name)
        (self.repo / 'antigravity').mkdir()
        shutil.copyfile(ROOT / 'antigravity/settings.json', self.repo / 'antigravity/settings.json')
        for name in ('remove-cursor-notify.py', 'apply-mulmoterminal-background.py', 'macos-espanso.py'):
            (scripts / name).write_text('pass\n')
        for name in ('install-mulmoterminal-config.sh', 'macos-betterdisplay.sh',
                     'macos-aqua-voice.sh', 'macos-clipy.sh', 'macos-notifications.sh',
                     'macos-default-apps.sh', 'exclude-worktrees-from-indexing.sh', 'processing-mac.sh'):
            (scripts / name).write_text('exit 0\n')
        for name in ('.dein.toml', '.gitconfig', '.gitignore_global', '.vimrc',
                     '.zpreztorc', '.zprofile', '.zshenv', '.zshrc',
                     'misc/ssh/config', 'misc/memo-config.toml', 'docs/git-workflow.md',
                     'codex/AGENTS.md', 'codex/config.toml', 'hammerspoon/init.lua',
                     'misc/Copy Downloaded Text.scpt.applescript', 'vscode/settings.json',
                     'vscode/keybindings.json', 'vscode/tsconfig.json', 'vscode/snippets/example.json',
                     'screenpipe/pipes/example/pipe.md', 'screenpipe/pipes/example/extensions/example.ts',
                     'claude/skills/private/SKILL.md', 'codex/skills/specific/SKILL.md',
                     'agents/skills/shared/SKILL.md'):
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('# fixture\n')
        for name in ('claude/settings.json', 'claude/keybindings.json', 'misc/docker-config.json',
                     'misc/claude_desktop_config.json'):
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}\n')
        shutil.copyfile(ROOT / 'misc/com.googlecode.iterm2.plist', self.repo / 'misc/com.googlecode.iterm2.plist')
        shutil.copytree(ROOT / 'karabiner', self.repo / 'karabiner')
        (self.home / '.zprezto/runcoms').mkdir(parents=True)
        (self.home / '.zprezto/runcoms/zlogin').write_text('# fixture\n')
        (self.home / '.gitconfig.local').write_text('[user]\nname = Test\nemail = test@example.com\n')
        fake_bin = self.home / 'fake-bin'
        fake_bin.mkdir()
        for name in ('git', 'sudo', 'node', 'uname', 'getent', 'dscl', 'defaults',
                     'launchctl', 'open', 'osascript', 'osacompile'):
            path = fake_bin / name
            path.write_text(f'#!{sys.executable}\n' + FAKE_COMMAND)
            path.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), DOTFILES_PROFILE='full',
                        TEST_ZSH=ZSH, TEST_OS='Linux',
                        PATH=str(fake_bin) + os.pathsep + os.environ['PATH'])
        for key in ('ZDOTDIR', 'XDG_STATE_HOME', 'ANTIGRAVITY_HOME'):
            self.env.pop(key, None)

    def run_deploy(self, *args):
        result = subprocess.run([ZSH, '-f', str(self.repo / 'scripts/deploy.sh'), *args],
                                env=self.env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        return result

    def commands(self):
        return [json.loads(line) for line in (self.home / 'commands.jsonl').read_text().splitlines()]

    def test_two_deploys_keep_links_and_backups_stable_without_pull_or_sudo(self):
        old = self.home / '.hammerspoon'
        old.mkdir()
        (old / 'local.lua').write_text('preserve')
        agy_settings = self.home / '.gemini/antigravity-cli/settings.json'
        agy_settings.parent.mkdir(parents=True)
        agy_settings.write_text(json.dumps({'trustedWorkspaces': ['/tmp/local-project']}) + '\n')
        first = self.run_deploy()
        self.assertEqual(first.returncode, 0, first.stderr)
        agy_mtime = agy_settings.lstat().st_mtime_ns
        links = [p for p in self.home.rglob('*') if p.is_symlink()]
        snapshot = {str(p): (str(p.readlink()), p.lstat().st_mtime_ns) for p in links}
        backups = list(self.home.rglob('*.bak.*'))
        second = self.run_deploy()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(snapshot, {str(p): (str(p.readlink()), p.lstat().st_mtime_ns) for p in links})
        self.assertEqual(list(self.home.rglob('*.bak.*')), backups)
        self.assertEqual(agy_settings.lstat().st_mtime_ns, agy_mtime)
        self.assertEqual(json.loads(agy_settings.read_text()), {
            'trustedWorkspaces': ['/tmp/local-project'],
            'altScreenMode': 'always',
            'model': 'Gemini 4 Hydrogen (XHigh)',
        })
        self.assertTrue((self.home / '.claude/skills/shared').is_symlink())
        self.assertTrue((self.home / '.codex/skills/shared').is_symlink())
        editor_prefix = 'Library/Application Support' if sys.platform == 'darwin' else '.config'
        self.assertTrue((self.home / editor_prefix / 'Cursor/User/snippets').is_symlink())
        self.assertTrue((self.home / '.screenpipe/pipes/example/.pi/extensions/example.ts').is_symlink())
        self.assertFalse(any('pull' in command or command[0] == 'sudo' for command in self.commands()))
        self.assertIn(['git', '-C', str(self.home / '.zprezto'), 'submodule', 'update', '--init', '--recursive'], self.commands())

    def test_prezto_update_is_explicit(self):
        result = self.run_deploy('--update-prezto')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(['git', '-C', str(self.home / '.zprezto'), 'pull', '--ff-only'], self.commands())

    def test_bad_profile_fails_before_writes(self):
        self.env['DOTFILES_PROFILE'] = 'typo'
        result = self.run_deploy()
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse((self.home / '.docker').exists())
        self.assertFalse((self.home / '.dotfiles-profile').exists())

    def test_missing_node_fails_before_any_settings_are_installed(self):
        isolated_bin = self.home / 'without-node'
        isolated_bin.mkdir()
        for name in ('python3', 'git'):
            (isolated_bin / name).symlink_to(shutil.which(name))
        self.env['PATH'] = str(isolated_bin)
        result = self.run_deploy()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('Missing node', result.stderr)
        self.assertFalse((self.home / '.docker').exists())

    def test_sync_failure_is_not_reported_as_success(self):
        self.env['FAIL_NODE'] = '42'
        result = self.run_deploy()
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertNotIn('Deploy complete', result.stdout)

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS installer paths')
    def test_permission_action_does_not_block_other_mac_settings(self):
        self.env['TEST_OS'] = 'Darwin'
        self.env['SYSTEM_SETUP_RESULT'] = '3'
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Deploy complete', result.stdout)
        self.assertTrue(any('jump-desktop-display.mjs' in ' '.join(c) for c in self.commands()))

    def test_legacy_macos_entry_rejects_unknown_flags_before_mutation(self):
        result = subprocess.run(['/bin/bash', str(self.repo / 'scripts/macos.sh'), '--dry-run'],
                                env=self.env, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse((self.home / 'commands.jsonl').exists())

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS installer paths')
    def test_mac_redeploy_does_not_recompile_or_restart_unchanged_settings(self):
        self.env['TEST_OS'] = 'Darwin'
        first = self.run_deploy()
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.home / 'commands.jsonl').write_text('')
        second = self.run_deploy()
        self.assertEqual(second.returncode, 0, second.stderr)
        commands = self.commands()
        self.assertFalse(any(c[0] in ('osacompile', 'sudo', 'open') for c in commands))
        self.assertFalse(any(c[:2] == ['launchctl', 'kickstart'] for c in commands))
        self.assertFalse(any(c[:2] == ['defaults', 'write'] for c in commands))
        self.assertFalse(any('macos.sh' in ' '.join(c) for c in commands))
        self.assertIn(['node', str(self.repo / 'scripts/macos-system-settings.mjs')], commands)
        self.assertFalse(any('macos-maintenance' in ' '.join(c) for c in commands))
        self.assertFalse(any('macos-activation' in ' '.join(c) and '--apply' in c for c in commands))
        # Repair drift in the compiled artifact, even with a valid receipt.
        (self.home / 'Library/Scripts/Folder Action Scripts/Copy Downloaded Text.scpt').write_text('drift')
        (self.home / 'commands.jsonl').write_text('')
        third = self.run_deploy()
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertTrue(any(c[0] == 'osacompile' for c in self.commands()))


if __name__ == '__main__':
    unittest.main()
