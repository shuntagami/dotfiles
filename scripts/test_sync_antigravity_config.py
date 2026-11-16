"""Verify Antigravity CLI settings sync preserves local workspace trust and permissions."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('sync_antigravity', ROOT / 'scripts/sync-antigravity-config.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AntigravityConfigSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.dotfiles_cfg = self.root / 'dotfiles/antigravity/settings.json'
        self.dotfiles_cfg.parent.mkdir(parents=True)
        self.dotfiles_cfg.write_text(json.dumps({
            'altScreenMode': 'always',
            'model': 'Gemini 4 Hydrogen (XHigh)',
        }) + '\n', encoding='utf-8')
        self.live_cfg = self.home / '.gemini/antigravity-cli/settings.json'

    def test_seeds_missing_config_with_private_mode_and_is_idempotent(self):
        changed = module.apply(home=self.home, dotfiles_config=self.dotfiles_cfg)
        self.assertEqual(changed, ['altScreenMode', 'model'])
        self.assertEqual(self.live_cfg.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(self.live_cfg.read_text(encoding='utf-8')), {
            'altScreenMode': 'always',
            'model': 'Gemini 4 Hydrogen (XHigh)',
        })
        mtime = self.live_cfg.lstat().st_mtime_ns
        self.assertEqual(module.apply(home=self.home, dotfiles_config=self.dotfiles_cfg), [])
        self.assertEqual(self.live_cfg.lstat().st_mtime_ns, mtime)

    def test_merges_shared_keys_while_preserving_trusted_workspaces_and_local_keys(self):
        self.live_cfg.parent.mkdir(parents=True)
        self.live_cfg.write_text(json.dumps({
            'model': 'older-model',
            'trustedWorkspaces': ['/private/company/secret-repo'],
            'extraLocalFlag': True,
        }) + '\n', encoding='utf-8')
        self.live_cfg.chmod(0o600)

        dry = module.apply(dry_run=True, home=self.home, dotfiles_config=self.dotfiles_cfg)
        self.assertEqual(dry, ['altScreenMode', 'model'])
        self.assertNotIn('altScreenMode', json.loads(self.live_cfg.read_text(encoding='utf-8')))

        applied = module.apply(home=self.home, dotfiles_config=self.dotfiles_cfg)
        self.assertEqual(applied, ['altScreenMode', 'model'])
        self.assertEqual(json.loads(self.live_cfg.read_text(encoding='utf-8')), {
            'model': 'Gemini 4 Hydrogen (XHigh)',
            'trustedWorkspaces': ['/private/company/secret-repo'],
            'extraLocalFlag': True,
            'altScreenMode': 'always',
        })
        self.assertEqual(self.live_cfg.stat().st_mode & 0o777, 0o600)

    def test_replaces_symlink_with_regular_file_so_app_saves_cannot_mutate_dotfiles(self):
        self.live_cfg.parent.mkdir(parents=True)
        self.live_cfg.symlink_to(self.dotfiles_cfg)
        module.apply(home=self.home, dotfiles_config=self.dotfiles_cfg)
        self.assertFalse(self.live_cfg.is_symlink())
        self.assertEqual(self.live_cfg.stat().st_mode & 0o777, 0o600)

    def test_save_excludes_trusted_workspaces_and_preserves_dotfiles_order(self):
        self.live_cfg.parent.mkdir(parents=True)
        self.live_cfg.write_text(json.dumps({
            'altScreenMode': 'always',
            'model': 'Gemini Updated',
            'trustedWorkspaces': ['/Users/private/client-work'],
        }) + '\n', encoding='utf-8')

        changed = module.save(dotfiles_config=self.dotfiles_cfg, live_config=self.live_cfg)
        self.assertEqual(changed, ['model'])
        saved = json.loads(self.dotfiles_cfg.read_text(encoding='utf-8'))
        self.assertEqual(saved, {'altScreenMode': 'always', 'model': 'Gemini Updated'})
        self.assertNotIn('trustedWorkspaces', saved)

    def test_live_config_path_respects_antigravity_home_env(self):
        custom = module.live_config_path(env={'ANTIGRAVITY_HOME': '/tmp/custom-agy'})
        self.assertEqual(custom, Path('/tmp/custom-agy/settings.json'))


if __name__ == '__main__':
    unittest.main()
