"""一時的なローカルリポジトリで実際のGitを動かす回帰テスト。ネットワークは使わない。"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GIT = shutil.which('git', path=os.defpath)


class WorktreeGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='worktree guard ')
        self.root = Path(self.tmp.name)
        self.main = self.root / 'main checkout'
        self.child = self.root / 'feature checkout'
        self.remote = self.root / 'remote.git'
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull,
                        GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@example.invalid',
                        GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@example.invalid')
        self.run_git(self.root, 'init', '--bare', '--initial-branch=main', str(self.remote))
        self.run_git(self.root, 'clone', str(self.remote), str(self.main))
        (self.main / 'document.txt').write_text('before\n')
        self.run_git(self.main, 'add', 'document.txt')
        self.run_git(self.main, 'commit', '-m', 'initial')
        self.run_git(self.main, 'push', '-u', 'origin', 'main')
        self.run_git(self.main, 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
        self.run_git(self.main, 'worktree', 'add', '-b', 'feature', str(self.child))
        self.run_git(self.main, 'config', 'workflow.checkDuplicateEdits', 'true')
        self.run_git(self.main, 'config', 'core.hooksPath', str(ROOT / 'git-hooks'))

    def tearDown(self):
        self.tmp.cleanup()

    def run_git(self, cwd, *args, check=True):
        return subprocess.run([GIT, *args], cwd=cwd, env=self.env, check=check,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def commit_feature(self, name='document.txt'):
        (self.child / name).write_text('after\n')
        self.run_git(self.child, 'add', '--', name)
        self.run_git(self.child, 'commit', '-m', 'feature')

    def push(self):
        return self.run_git(self.child, 'push', 'origin', 'feature', check=False)

    def assert_blocked(self, result, path):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(path, result.stderr)
        self.assertIn('重複', result.stderr)
        self.assertNotEqual(self.run_git(self.remote, 'rev-parse', '--verify', 'refs/heads/feature', check=False).returncode, 0)

    def test_copied_tracked_edit_blocks_push_without_mutating_source(self):
        self.commit_feature()
        (self.main / 'document.txt').write_text('after\n')
        before = self.run_git(self.main, 'status', '--porcelain').stdout
        self.assert_blocked(self.push(), 'document.txt')
        self.assertEqual((self.main / 'document.txt').read_text(), 'after\n')
        self.assertEqual(self.run_git(self.main, 'status', '--porcelain').stdout, before)

    def test_copied_untracked_file_with_spaces_blocks_push(self):
        self.commit_feature('new document.txt')
        (self.main / 'new document.txt').write_text('after\n')
        self.assert_blocked(self.push(), 'new document.txt')
        self.assertEqual((self.main / 'new document.txt').read_text(), 'after\n')

    def test_staged_duplicate_is_detected_even_if_working_copy_has_new_edits(self):
        self.commit_feature()
        (self.main / 'document.txt').write_text('after\n')
        self.run_git(self.main, 'add', 'document.txt')
        (self.main / 'document.txt').write_text('later edit\n')
        self.assert_blocked(self.push(), 'document.txt')
        self.assertEqual((self.main / 'document.txt').read_text(), 'later edit\n')

    def test_unrelated_and_different_edits_are_not_treated_as_copies(self):
        self.commit_feature()
        (self.main / 'document.txt').write_text('someone else\n')
        (self.main / 'unrelated.txt').write_text('keep\n')
        self.assertEqual(self.push().returncode, 0)
        self.assertEqual((self.main / 'document.txt').read_text(), 'someone else\n')

    def test_disabled_repository_is_unaffected(self):
        self.commit_feature()
        (self.main / 'document.txt').write_text('after\n')
        self.run_git(self.main, 'config', 'workflow.checkDuplicateEdits', 'false')
        self.assertEqual(self.push().returncode, 0)

    def test_clean_source_can_push_then_fast_forward_after_merge(self):
        self.commit_feature()
        self.assertEqual(self.push().returncode, 0)
        self.run_git(self.remote, 'update-ref', 'refs/heads/main', self.run_git(self.child, 'rev-parse', 'HEAD').stdout.strip())
        self.run_git(self.main, 'pull', '--ff-only')
        self.assertEqual(self.run_git(self.main, 'status', '--porcelain').stdout, '')

    def test_existing_workspace_can_switch_branch_and_push_in_place(self):
        self.run_git(self.main, 'switch', '-c', 'in-place')
        (self.main / 'document.txt').write_text('in-place edit\n')
        self.run_git(self.main, 'add', 'document.txt')
        self.run_git(self.main, 'commit', '-m', 'in place')
        self.assertEqual(self.run_git(self.main, 'push', 'origin', 'in-place', check=False).returncode, 0)

    def test_duplicate_deletion_is_detected(self):
        self.run_git(self.child, 'rm', 'document.txt')
        self.run_git(self.child, 'commit', '-m', 'delete document')
        (self.main / 'document.txt').unlink()
        self.assert_blocked(self.push(), 'document.txt')

    def test_conditional_config_applies_only_to_dotfiles_and_its_worktrees(self):
        home = self.root / 'isolated home'
        home.mkdir()
        self.env.update(HOME=str(home), GIT_CONFIG_GLOBAL=str(ROOT / '.gitconfig'))
        repo = home / 'dotfiles'
        linked = home / 'linked'
        self.run_git(home, 'clone', str(self.remote), str(repo))
        config = repo / 'config/git/dotfiles.gitconfig'
        config.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / 'config/git/dotfiles.gitconfig', config)
        self.run_git(repo, 'worktree', 'add', '-b', 'scoped', str(linked))
        for path in (repo, linked):
            self.assertEqual(self.run_git(path, 'config', '--get', 'pull.ff').stdout.strip(), 'only')
            self.assertEqual(self.run_git(path, 'config', '--get', 'workflow.checkDuplicateEdits').stdout.strip(), 'true')
        for key in ('pull.ff', 'workflow.checkDuplicateEdits'):
            self.assertEqual(self.run_git(self.remote, 'config', '--get', key, check=False).returncode, 1)


if __name__ == '__main__':
    unittest.main()
