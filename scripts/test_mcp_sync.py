"""Run MCP synchronization against fake Claude state without calling installed clients."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

FAKE_CLAUDE = r'''
import json, os, sys
from pathlib import Path
home = Path(os.environ['DOTFILES_TEST_HOME'])
if sys.argv[1:] == ['--version']:
    print('test Claude')
    sys.exit(0)
with (home / 'claude-calls.jsonl').open('a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\n')
file = Path(os.environ.get('CLAUDE_CONFIG_DIR') or str(home)) / '.claude.json'
config = json.loads(file.read_text())
servers = config.setdefault('mcpServers', {})
name = sys.argv[5]
if sys.argv[2] == 'remove':
    del servers[name]
else:
    entry = json.loads(sys.argv[6])
    if entry['type'] == 'stdio':
        entry.setdefault('args', [])
    servers[name] = entry
file.write_text(json.dumps(config))
'''


@unittest.skipUnless(shutil.which('node'), 'Node.js required')
class McpSyncTest(unittest.TestCase):
    def test_repeat_is_unchanged_and_drift_updates_only_managed_entries(self):
        self.exercise_sync()

    def test_custom_claude_profile_compares_the_cli_target(self):
        self.exercise_sync(custom_profile=True)

    def test_dangling_absolute_link_recreates_referent_and_parent(self):
        self.exercise_sync(missing_referent=True)

    def test_dangling_relative_link_recreates_referent_and_parent(self):
        self.exercise_sync(missing_referent=True, relative_link=True)

    def exercise_sync(self, custom_profile=False, missing_referent=False, relative_link=False):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            mcp = home / 'dotfiles/mcp'
            mcp.mkdir(parents=True)
            source = {'mcpServers': {
                'stdio': {'type': 'stdio', 'command': '${HOME}/tool'},
                'remote': {'type': 'http', 'url': 'https://example.com/mcp'},
                'disabled': {'type': 'stdio', 'command': 'disabled', 'enabled': False},
            }}
            canonical = mcp / 'servers.json'
            canonical.write_text(json.dumps(source))
            script = mcp / 'sync.mjs'
            script.write_text((ROOT / 'mcp/sync-mcp.mjs').read_text().replace(
                'const home = os.homedir();', 'const home = process.env.DOTFILES_TEST_HOME;'))
            cli = home / 'bin/claude'
            cli.parent.mkdir()
            cli.write_text(f'#!{sys.executable}\n' + FAKE_CLAUDE)
            cli.chmod(0o755)
            config_dir = home / 'custom-claude' if custom_profile else home
            config_dir.mkdir(exist_ok=True)
            state = config_dir / '.claude.json'
            state.write_text(json.dumps({'localFlag': True, 'mcpServers': {
                'local': {'type': 'stdio', 'command': 'keep'},
                'disabled': {'type': 'stdio', 'command': 'remove'},
            }}))
            env = dict(os.environ, DOTFILES_TEST_HOME=str(home), PATH=str(cli.parent) + ':/usr/bin:/bin')
            env.pop('CLAUDE_CONFIG_DIR', None)
            if custom_profile:
                env['CLAUDE_CONFIG_DIR'] = str(config_dir)
            codex_source = home / 'dotfiles/codex/config.toml'
            if not missing_referent:
                codex_source.parent.mkdir()
                codex_source.write_text('[features]\ncustom = true\n')
                codex_source.chmod(0o640)
            codex_target = home / '.codex/config.toml'
            codex_target.parent.mkdir()
            codex_target.symlink_to('../dotfiles/codex/config.toml' if relative_link else codex_source)
            def sync():
                result = subprocess.run([shutil.which('node'), str(script)], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            sync()
            self.assertTrue(codex_target.is_symlink())
            self.assertEqual(codex_target.resolve(), codex_source.resolve())
            self.assertEqual(codex_source.stat().st_mode & 0o777, 0o600 if missing_referent else 0o640)
            if not missing_referent:
                self.assertIn('custom = true', codex_source.read_text())
            installed = json.loads(state.read_text())
            self.assertTrue(installed['localFlag'])
            self.assertEqual(installed['mcpServers']['local']['command'], 'keep')
            self.assertNotIn('disabled', installed['mcpServers'])
            self.assertEqual(installed['mcpServers']['stdio']['command'], str(home / 'tool'))
            paths = [state, mcp / 'generated/cursor.mcp.json', home / '.codex/config.toml']
            snapshot = {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in paths}
            calls = home / 'claude-calls.jsonl'
            calls.write_text('')
            sync()
            self.assertEqual(calls.read_text(), '')
            self.assertEqual(snapshot, {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in paths})
            source['mcpServers']['stdio']['command'] = '${HOME}/updated'
            canonical.write_text(json.dumps(source))
            sync()
            operations = [json.loads(line) for line in calls.read_text().splitlines()]
            self.assertEqual([op[1] for op in operations], ['remove', 'add-json'])
            self.assertTrue(all(op[4] == 'stdio' for op in operations))
            self.assertEqual(json.loads(state.read_text())['mcpServers']['stdio']['command'], str(home / 'updated'))
            self.assertEqual(json.loads(canonical.read_text()), source)


if __name__ == '__main__':
    unittest.main()
