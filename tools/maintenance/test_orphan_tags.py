import unittest
from execute_request import ORPHAN_TAGS, eligible

class OrphanTagPolicyTest(unittest.TestCase):
    def setUp(self):
        self.tag = 'test-build-258'
        self.sha = ORPHAN_TAGS[self.tag]
        self.ref = {'ref': 'refs/tags/' + self.tag, 'object': {'type': 'commit', 'sha': self.sha}}
        self.comparison = {'status': 'ahead', 'merge_base_commit': {'sha': self.sha}}

    def test_only_exact_orphan_ancestor_is_eligible(self):
        self.assertTrue(eligible(self.tag, self.sha, self.ref, None, self.comparison))
        self.assertFalse(eligible(self.tag, self.sha, self.ref, {'id': 1}, self.comparison))
        self.assertFalse(eligible('test-build-921', self.sha, self.ref, None, self.comparison))

    def test_changed_ref_and_non_commit_tag_are_preserved(self):
        self.ref['object']['sha'] = 'f' * 40
        self.assertFalse(eligible(self.tag, self.sha, self.ref, None, self.comparison))
        self.ref['object'] = {'sha': self.sha, 'type': 'tag'}
        self.assertFalse(eligible(self.tag, self.sha, self.ref, None, self.comparison))

    def test_unique_history_is_preserved(self):
        self.comparison['status'] = 'diverged'
        self.assertFalse(eligible(self.tag, self.sha, self.ref, None, self.comparison))
        self.comparison['status'] = 'ahead'
        self.comparison['merge_base_commit']['sha'] = 'f' * 40
        self.assertFalse(eligible(self.tag, self.sha, self.ref, None, self.comparison))

if __name__ == '__main__':
    unittest.main()
