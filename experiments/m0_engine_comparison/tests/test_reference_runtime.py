import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pilot'))
from reference_runtime import ReferenceGame, InvalidAction, load_demo, fingerprint

DATA = load_demo()

def play(*choices):
    game = ReferenceGame(DATA)
    for i, choice in enumerate(choices, 1):
        game.act(choice, action_id=f'choice-{i}')
    return game

class M0RuntimeTests(unittest.TestCase):
    def test_key_gate(self):
        self.assertNotIn('open_gate', [c['id'] for c in play('talk').available()])
        self.assertIn('open_gate', [c['id'] for c in play('market', 'take_key').available()])

    def test_dead_witness_gate(self):
        game = play('talk', 'enter_yard', 'ignore_witness')
        self.assertNotIn('ask_witness', [c['id'] for c in game.available()])

    def test_trust_gate(self):
        game = play('talk', 'befriend', 'save_witness', 'ask_witness')
        self.assertIn('trust_talk', [c['id'] for c in game.available()])
        game.act('trust_talk')
        self.assertTrue(game.values['has_letter'])

    def test_endings(self):
        self.assertEqual(play('leave').scene, 'end_leave')
        self.assertEqual(play('talk', 'enter_yard', 'ignore_witness', 'tower_empty', 'accuse').scene, 'end_failure')
        self.assertEqual(play('talk', 'enter_yard', 'save_witness', 'find_letter', 'show_evidence').scene, 'end_truth')

    def test_long_save_restore(self):
        actions = ['talk'] + ['befriend', 'return_gate']*9 + ['befriend', 'save_witness', 'find_letter', 'show_evidence']
        expected = play(*actions).save()
        restored = ReferenceGame.restore(DATA, play(*actions[:11]).save())
        for i, choice in enumerate(actions[11:], 12):
            restored.act(choice, action_id=f'choice-{i}')
        self.assertGreaterEqual(len(restored.history), 20)
        self.assertEqual(restored.save(), expected)

    def test_duplicate_action_is_atomic(self):
        game = play('talk')
        saved = game.save()
        with self.assertRaises(InvalidAction):
            game.act('enter_yard', action_id='choice-1')
        self.assertEqual(game.save(), saved)

    def test_reject_tampering(self):
        save = play('market', 'take_key').save()
        save['values']['has_key'] = False
        with self.assertRaises(ValueError):
            ReferenceGame.restore(DATA, save)

    def test_reject_wrong_source(self):
        save = play('market').save()
        changed = copy.deepcopy(DATA)
        changed['title'] = 'other'
        with self.assertRaises(ValueError):
            ReferenceGame.restore(changed, save)

    def test_independent_forks(self):
        base = play('talk')
        left = ReferenceGame.restore(DATA, base.save())
        right = ReferenceGame.restore(DATA, base.save())
        left.act('befriend')
        right.act('enter_yard')
        self.assertNotEqual(left.values, right.values)
        self.assertEqual(base.scene, 'gate')

    def test_source_is_not_mutated(self):
        before = fingerprint(DATA)
        play('market', 'take_key', 'open_gate', 'search_hall', 'find_letter')
        self.assertEqual(before, fingerprint(DATA))
