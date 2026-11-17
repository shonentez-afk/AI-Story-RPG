import unittest
from prune import plan, ARTIFACTS, DELETE


def run(i, branch='main', status='completed', conclusion='success'):
    return dict(id=i, created_at=f'2026-01-{i:03d}', head_branch=branch,
                status=status, conclusion=conclusion, workflow_id=1)


def release(i):
    return dict(id=i, tag_name=f'test-build-{i}', draft=False, immutable=False,
                prerelease=True, author={'login': 'github-actions[bot]'},
                body=f'/actions/runs/{i}', assets=[dict(name=n, state='uploaded', size=1)
                  for n in ('AI-Story-RPG-Android-debug.apk', 'AI-Story-RPG-Windows-portable.zip', 'SHA256SUMS.txt')])


class PolicyTest(unittest.TestCase):
    def test_releases_preserve_three_and_custom(self):
        custom = dict(release(1), tag_name='v1.0.0')
        result = plan([], [], [release(i) for i in range(2, 8)] + [custom], {'main'}, 900)
        self.assertEqual(result['kept_test_releases'], ['test-build-7', 'test-build-6', 'test-build-5'])
        self.assertEqual({r['id'] for r in result['releases']}, {2, 3, 4})
        self.assertIn(1, result['kept_run_ids'])

    def test_never_delete_active_or_own_runs(self):
        runs = [run(i) for i in range(1, 50)] + [run(0, status='queued')]
        result = plan(runs, [], [], {'main'}, 1)
        removed = {r['id'] for r in result['runs']}
        self.assertNotIn(0, removed); self.assertNotIn(1, removed)
        self.assertNotIn(49, removed); self.assertIn(2, removed)

    def test_unknown_evidence_protects_parent(self):
        a = dict(id=200, name='important-acceptance-report', created_at='x', workflow_run={'id': 2})
        result = plan([run(i) for i in range(1, 50)], [a], [], {'main'}, 900)
        self.assertIn(2, result['kept_run_ids'])
        self.assertEqual(result['artifacts'], [])

    def test_two_successful_artifacts_survive_new_failed_runs(self):
        runs = [run(i, conclusion='failure' if i > 3 else 'success') for i in range(1, 50)]
        artifacts = [dict(id=100+i, name=next(iter(ARTIFACTS)), created_at=f'{i:03d}',
                          expired=False, workflow_run={'id': i}) for i in range(1, 5)]
        result = plan(runs, artifacts, [], {'main'}, 900)
        self.assertTrue({102, 103} <= set(result['kept_artifact_ids']))
        self.assertIn(2, result['kept_run_ids']); self.assertIn(3, result['kept_run_ids'])

    def test_delete_allowlist_rejects_branches_and_non_test_tags(self):
        for path in ('/git/refs/heads/main', '/git/refs/tags/v1.0.0', '/issues/2', '/actions/runs/../secrets'):
            self.assertIsNone(DELETE.fullmatch(path))
        self.assertIsNotNone(DELETE.fullmatch('/git/refs/tags/test-build-10'))

    def test_open_branch_keeps_latest_failure_and_green(self):
        runs = [run(i) for i in range(1, 50)] + [run(0, 'feature/npc', conclusion='failure'), run(-1, 'feature/npc')]
        result = plan(runs, [], [], {'main', 'feature/npc'}, 900)
        self.assertTrue({0, -1} <= set(result['kept_run_ids']))

if __name__ == '__main__':
    unittest.main()
