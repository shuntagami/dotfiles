import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from io import BytesIO

spec = importlib.util.spec_from_file_location('sync_projects', Path(__file__).with_name('sync-mulmoterminal-projects.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProjectSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'project'
        self.repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        self.image = self.root / 'dog.JPG'
        self.image.write_bytes(b'fixture-image')
        self.profile = {'headerColor': '#112233'}
        self.settings = {'opacity': 0.15, 'fit': 'cover'}

    def apply(self, dry_run=False):
        return module.apply(self.repo, self.profile, self.image, self.settings, dry_run)

    def test_fresh_clone_and_idempotence(self):
        self.apply()
        before = (self.repo / '.mulmoterminal.json').read_bytes()
        self.apply()
        self.assertEqual(before, (self.repo / '.mulmoterminal.json').read_bytes())
        self.assertEqual(b'fixture-image', (self.repo / module.REL_IMAGE).read_bytes())
        self.assertEqual('', module.git(self.repo, 'status', '--porcelain'))

    def test_tracked_local_settings_preserved_background_added_to_other_layer(self):
        local = self.repo / '.mulmoterminal.local.json'
        local.write_text('{"headerColor":"#abcdef","buttons":[{"label":"keep"}]}')
        subprocess.run(['git', '-C', str(self.repo), 'add', local.name], check=True)
        before = local.read_bytes()
        self.apply()
        self.assertEqual(before, local.read_bytes())
        added = module.read(self.repo / '.mulmoterminal.json')
        self.assertNotIn('headerColor', added)
        self.assertIn('backgroundImage', added)

    def test_custom_background_preserved(self):
        (self.repo / '.mulmoterminal.local.json').write_text('{"backgroundImage":false}')
        self.apply()
        self.assertFalse((self.repo / module.REL_IMAGE).exists())
        self.assertNotIn('backgroundImage', module.read(self.repo / '.mulmoterminal.json'))

    def test_conflicting_image_fails_before_config_write(self):
        image = self.repo / module.REL_IMAGE
        image.parent.mkdir()
        image.write_bytes(b'other-image')
        with self.assertRaises(RuntimeError):
            self.apply()
        self.assertFalse((self.repo / '.mulmoterminal.json').exists())
        self.assertEqual(b'other-image', image.read_bytes())

    def test_dry_run_writes_nothing(self):
        self.apply(dry_run=True)
        self.assertFalse((self.repo / '.mulmoterminal.json').exists())
        self.assertFalse((self.repo / module.REL_IMAGE).exists())

    def test_live_notification_sends_existing_value_without_changing_files(self):
        self.apply()
        file = self.repo / '.mulmoterminal.json'
        before = file.read_bytes()
        with patch.object(module.urllib.request, 'urlopen', return_value=BytesIO(b'{}')) as call:
            self.assertEqual('notified', module.notify_views(self.repo))
        request = call.call_args.args[0]
        self.assertEqual('PUT', request.method)
        self.assertEqual({'cwd': str(self.repo), 'set': {'headerColor': '#112233'}}, json.loads(request.data))
        self.assertEqual(before, file.read_bytes())

    def test_offline_notification_preserves_successful_install(self):
        self.apply()
        with patch.object(module.urllib.request, 'urlopen', side_effect=OSError('offline')):
            self.assertIn('reload required', module.notify_views(self.repo))
        self.assertTrue((self.repo / module.REL_IMAGE).exists())

    def test_notification_does_not_reformat_existing_json(self):
        (self.repo / '.mulmoterminal.local.json').write_text('{"headerColor":"#abcdef"}')
        with patch.object(module.urllib.request, 'urlopen') as call:
            self.assertIn('reload required', module.notify_views(self.repo))
            call.assert_not_called()


if __name__ == '__main__':
    unittest.main()
