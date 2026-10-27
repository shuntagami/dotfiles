"""Check deployment and MCP sync under another home without touching real settings."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('user_configs', ROOT / 'scripts/install-user-configs.py')
configs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configs)


class UserConfigPathsTest(unittest.TestCase):
    def test_agent_instructions_link_to_tracked_sources_and_preserve_existing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / '別の利用者'
            old = home / '.codex/AGENTS.md'
            old.parent.mkdir(parents=True)
            old.write_text('既存の共通指示\n')
            other_rule = home / '.claude/rules/other.md'
            other_rule.parent.mkdir(parents=True)
            other_rule.write_text('別のルール\n')
            expected = {
                '.codex/AGENTS.md': 'codex/AGENTS.md',
                '.claude/rules/git-workflow.md': 'docs/git-workflow.md',
            }
            configs.install('agent-instructions', home)
            for target, source in expected.items():
                self.assertTrue((home / target).is_symlink())
                self.assertEqual((home / target).resolve(), (ROOT / source).resolve())
            backups = list(old.parent.glob('AGENTS.md.bak.*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), '既存の共通指示\n')
            configs.install('agent-instructions', home)
            self.assertEqual(len(list(old.parent.glob('AGENTS.md.bak.*'))), 1)
            self.assertEqual(other_rule.read_text(), '別のルール\n')
            self.assertFalse((home / '.gitconfig').exists())

    def test_separate_claude_profile_uses_the_same_tracked_rule(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / '利用者'
            profile = home / '.studio-claude'
            existing = profile / 'rules/local.md'
            existing.parent.mkdir(parents=True)
            existing.write_text('アプリの既存ルール\n')
            configs.install('agent-instructions', home, claude_config_dir=profile)
            target = profile / 'rules/git-workflow.md'
            self.assertEqual(target.resolve(), (ROOT / 'docs/git-workflow.md').resolve())
            self.assertEqual((home / '.claude/rules/git-workflow.md').resolve(), target.resolve())
            self.assertEqual(existing.read_text(), 'アプリの既存ルール\n')

    def test_deploy_for_another_user_preserves_sources_and_existing_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / 'Hirata Mac'
            target = home / '.claude/settings.json'
            target.parent.mkdir(parents=True)
            target.write_text('{"previous": true}\n')
            before = {name: (ROOT / source).read_bytes()
                      for name, (source, _) in configs.CONFIGS.items()}
            for name, (source, relative_target) in configs.CONFIGS.items():
                resolved = configs.install(name, home)
                installed = home / relative_target
                self.assertTrue(installed.is_symlink())
                self.assertEqual(installed.resolve(), resolved.resolve())
                content = installed.read_text()
                self.assertNotIn('/Users/shun.tagami', content)
                self.assertNotIn('\\/Users\\/shun.tagami', content)
                first = installed.read_bytes()
                configs.install(name, home)
                self.assertEqual(installed.read_bytes(), first)
                self.assertEqual((ROOT / source).read_bytes(), before[name])
            backups = list(target.parent.glob('settings.json.bak.*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(json.loads(backups[0].read_text()), {'previous': True})
            claude = json.loads(target.read_text())
            self.assertEqual(shlex.split(claude['statusLine']['command'])[0],
                             str(home / 'dotfiles/claude/statusline.sh'))
            for hook in claude['hooks']['Stop']:
                for action in hook['hooks']:
                    self.assertEqual(shlex.split(action['command'])[1],
                                     str(home / 'dotfiles/scripts/agent-notify.py'))

    def test_nested_json_toml_keys_and_shell_quoting(self):
        home = Path('/Users/Hirata "CEO" Mac')
        text = '''[projects."/Users/shun.tagami/dotfiles"]
trust_level = "trusted"
notify = ["/Users/shun.tagami/bin/notify", "[\\"\\\\/Users\\\\/shun.tagami\\\\/dotfiles\\\\/notify.sh\\"]"]
services = '{"browser":"/Users/shun.tagami/.codex/browser.mjs"}'
'''
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'config.toml'
            source.write_text(text)
            rendered = configs.render(source, home).decode()
        # TOML basic strings use the same escapes as JSON for these values.
        key_token = rendered.splitlines()[0][len('[projects.'):-1]
        self.assertEqual(json.loads(key_token), str(home / 'dotfiles'))
        notification = json.loads(rendered.splitlines()[2].split(' = ', 1)[1])
        self.assertEqual(notification[0], str(home / 'bin/notify'))
        self.assertEqual(json.loads(notification[1]), [str(home / 'dotfiles/notify.sh')])
        services = json.loads(rendered.splitlines()[3].split(' = ', 1)[1])
        self.assertEqual(json.loads(services)['browser'], str(home / '.codex/browser.mjs'))
        hook = configs.relocate({'hooks': {'Stop': [{'command':
            'python3 /Users/shun.tagami/dotfiles/scripts/agent-notify.py claude'}]}}, home)
        self.assertEqual(shlex.split(hook['hooks']['Stop'][0]['command']),
                         ['python3', str(home / 'dotfiles/scripts/agent-notify.py'), 'claude'])

    def test_iterm_working_directory_uses_current_home(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / 'hirata'
            folder = configs.install('iterm2', home)
            settings = plistlib.loads((folder / 'com.googlecode.iterm2.plist').read_bytes())
            self.assertTrue(settings['New Bookmarks'])
            for profile in settings['New Bookmarks']:
                if profile.get('Working Directory') == '/Users/shuntagami':
                    self.fail('iTerm still uses the previous home')
            self.assertIn(str(home), [p.get('Working Directory') for p in settings['New Bookmarks']])

    def test_author_keeps_repository_update_flow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'codex/config.toml'
            source.parent.mkdir()
            source.write_text('model = "example"\n')
            original = configs.SOURCE_HOME
            try:
                configs.SOURCE_HOME = root / 'author'
                installed = configs.install('codex', configs.SOURCE_HOME, root)
                self.assertEqual(installed, source)
                self.assertEqual((configs.SOURCE_HOME / '.codex/config.toml').resolve(), source.resolve())
            finally:
                configs.SOURCE_HOME = original

    @unittest.skipUnless(shutil.which('node'), 'Node.js is required for MCP integration')
    def test_mcp_sync_resolves_all_clients_without_changing_canonical_source(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory) / 'Hirata Mac'
            dotfiles = home / 'dotfiles'
            mcp = dotfiles / 'mcp'
            mcp.mkdir(parents=True)
            source = ROOT / 'mcp/servers.json'
            (mcp / source.name).write_bytes(source.read_bytes())
            fake_bin = home / 'bin'
            fake_bin.mkdir()
            claude = fake_bin / 'claude'
            claude.write_text('#!/bin/sh\nexit 1\n')
            claude.chmod(0o755)
            # Redirect the disposable script's explicit home lookup. Do not
            # change HOME or call clients / Keychain on the actual machine.
            script = mcp / 'sync-test.mjs'
            script.write_text((ROOT / 'mcp/sync-mcp.mjs').read_text().replace(
                'const home = os.homedir();', 'const home = process.env.DOTFILES_TEST_HOME;'))
            result = subprocess.run([shutil.which('node'), str(script)], capture_output=True,
                                    text=True, env=dict(os.environ,
                                        DOTFILES_TEST_HOME=str(home), PATH=str(fake_bin) + ':/usr/bin:/bin'))
            self.assertEqual(result.returncode, 0, result.stderr)
            cursor = json.loads((home / '.cursor/mcp.json').read_text())
            self.assertEqual(cursor['mcpServers']['playwright']['command'],
                             str(dotfiles / 'bin/playwright-mcp'))
            self.assertEqual(cursor['mcpServers']['supabase']['command'],
                             str(dotfiles / 'mcp/run-supabase-mcp.sh'))
            self.assertNotIn('${HOME}', (home / '.codex/config.toml').read_text())
            self.assertIn(str(dotfiles / 'bin/playwright-mcp'), (home / '.codex/config.toml').read_text())
            self.assertEqual((mcp / source.name).read_bytes(), source.read_bytes())


if __name__ == '__main__':
    unittest.main()
