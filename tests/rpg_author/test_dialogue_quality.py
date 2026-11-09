"""Synthetic privacy-safe E6c dialogue audit contract tests."""
from __future__ import annotations
from copy import deepcopy
import unittest
from tools.rpg_author.common import AuthoringError
from tools.rpg_author.dialogue_quality import audit_blueprint
from tools.rpg_author.gameplay_quality import _apply, _permitted

FINGERPRINT = "e"*64


def fixture(*, one_shot=True, wrong_speaker=False, requires_fact=None):
    q = {"id":"ask_one", "label":"Спросить о потерянной вещи", "next_scene_id":"reply",
         "conditions": [] if not one_shot else
            [{"op":"flag_is","id":"asked","value":False}],
         "effects": [] if not one_shot else
            [{"op":"set_flag","id":"asked","value":True}]}
    back = {"id":"back", "label":"Вернуться к разговору", "next_scene_id":"talk",
            "conditions":[], "effects":[]}
    exit_ = {"id":"leave", "label":"Продолжить путь", "next_scene_id":"end",
             "conditions":[], "effects":[]}
    bp={"source_fingerprint":FINGERPRINT,"entry_scene_id":"talk",
        "items":[],"facts":["known_truth"],
        "initial_state":{"scene_id":"talk","flags":{"asked":False},
                         "stats":{},"inventory":[],"knowledge":{"player":[]}},
        "scenes":[{"id":"talk","text":"Разговор у колодца", "terminal":False,
                   "choices":[q,exit_]},
                  {"id":"reply","text":"Королевна: — Почему?\n\n"+
                   ("Дракон: — Это моя тайна." if wrong_speaker
                    else "Лягушонок: — Такова моя история."),
                   "terminal":False,"choices":[back]},
                  {"id":"end","text":"Игра закончилась", "terminal":True,
                   "choices":[]}]}
    contract={"format":"ai_story_dialogue_topics_v1",
              "source_fingerprint":FINGERPRINT,
              "topics":[{"question_id":"ask_one","source_scene_id":"talk",
                          "answer_scene_id":"reply","speaker":"Лягушонок",
                          "one_shot":True,"requires_fact":requires_fact}]}
    return bp,contract


class DialogueQualityTests(unittest.TestCase):
    def replay(self, bp, route):
        """Execute the reported witness, checking every choice is available."""
        start = bp['initial_state']
        state = (start['scene_id'],
                 tuple(sorted(k for k, v in start['flags'].items() if v)),
                 tuple(sorted(start['inventory'])),
                 tuple(sorted(start['stats'].items())),
                 tuple(sorted(start['knowledge']['player'])))
        scenes = {s['id']: s for s in bp['scenes']}
        for choice_id in route:
            choices = [c for c in scenes[state[0]]['choices']
                       if c['id'] == choice_id]
            self.assertEqual(len(choices), 1, (state[0], choice_id, route))
            choice = choices[0]
            self.assertTrue(all(_permitted(rule, set(state[1]), set(state[2]),
                                           dict(state[3]), set(state[4]))
                                for rule in choice['conditions']), route)
            state = _apply(state, choice)
        return state

    def repeat_witness(self, bp, contract):
        report = audit_blueprint(bp, contract)
        issues = [i for i in report['issues']
                  if i['code'] == 'REPEATABLE_DIALOGUE_REWARD']
        self.assertEqual(len(issues), 1)
        route = issues[0]['example_route']
        self.assertGreaterEqual(route.count('ask_one'), 2, route)
        self.replay(bp, route)
        return route

    def test_one_shot_dialogue_passes(self):
        bp,c=fixture()
        r=audit_blueprint(bp,c)
        self.assertEqual(r['warning_count'],0)
        self.assertEqual(r['metrics']['reachable_topics'],1)
        self.assertEqual(r['metrics']['one_shot_topics'],1)
        self.assertIn('not_literary_certified',r['status'])

    def test_farming_the_same_question_is_rejected(self):
        bp,c=fixture(one_shot=False)
        r=audit_blueprint(bp,c)
        self.assertIn('REPEATABLE_DIALOGUE_REWARD',{e['code'] for e in r['issues']})

    def test_missing_speaker_detected(self):
        bp,c=fixture(wrong_speaker=True)
        r=audit_blueprint(bp,c)
        self.assertIn('MISSING_NPC_VOICE',{e['code'] for e in r['issues']})

    def test_knowledge_leak_detected(self):
        bp,c=fixture(requires_fact='known_truth')
        r=audit_blueprint(bp,c)
        self.assertIn('UNAUTHORIZED_DISCLOSURE',{e['code'] for e in r['issues']})

    def test_question_cannot_supply_its_own_prerequisite(self):
        bp, c = fixture(requires_fact='known_truth')
        bp['scenes'][0]['choices'][0]['effects'].append(
            {'op': 'learn_fact', 'id': 'known_truth'})
        r = audit_blueprint(bp, c)
        issue = next(i for i in r['issues'] if i['code'] == 'UNAUTHORIZED_DISCLOSURE')
        route = issue['example_route']
        self.assertEqual(route[-1], 'ask_one')
        self.assertNotIn('known_truth', self.replay(bp, route[:-1])[4])
        self.assertIn('known_truth', self.replay(bp, route)[4])

    def test_initial_knowledge_satisfies_prerequisite(self):
        bp, c = fixture(requires_fact='known_truth')
        bp['initial_state']['knowledge']['player'] = ['known_truth']
        self.assertEqual(audit_blueprint(bp, c)['warning_count'], 0)

    def test_knowledge_learned_earlier_unlocks_question(self):
        bp, c = fixture(requires_fact='known_truth')
        bp['scenes'][0]['choices'][0]['conditions'].append(
            {'op': 'knows_fact', 'id': 'known_truth'})
        bp['scenes'][0]['choices'].append(
            {'id': 'read_clue', 'label': 'Прочитать подсказку',
             'next_scene_id': 'talk', 'conditions': [],
             'effects': [{'op': 'learn_fact', 'id': 'known_truth'}]})
        self.assertEqual(audit_blueprint(bp, c)['warning_count'], 0)

    def test_answer_can_teach_a_fact_when_it_is_not_a_prerequisite(self):
        bp, c = fixture()
        bp['scenes'][0]['choices'][0]['effects'].append(
            {'op': 'learn_fact', 'id': 'known_truth'})
        self.assertEqual(audit_blueprint(bp, c)['warning_count'], 0)

    def test_repeat_witness_contains_both_questions_and_return(self):
        bp, c = fixture(one_shot=False)
        self.assertEqual(self.repeat_witness(bp, c), ['ask_one', 'back', 'ask_one'])

    def test_repeat_witness_follows_detour_and_flag_reset(self):
        bp, c = fixture()
        bp['scenes'][1]['choices'][0]['next_scene_id'] = 'detour'
        bp['scenes'].append(
            {'id': 'detour', 'text': 'Обходной путь', 'terminal': False,
             'choices': [{'id': 'reset_and_return', 'label': 'Вернуться',
                          'next_scene_id': 'talk', 'conditions': [],
                          'effects': [{'op': 'set_flag', 'id': 'asked', 'value': False}]}]})
        self.assertEqual(self.repeat_witness(bp, c),
                         ['ask_one', 'back', 'reset_and_return', 'ask_one'])

    def test_repeat_witness_does_not_use_shortcut_instead_of_first_question(self):
        bp, c = fixture(one_shot=False)
        bp['scenes'][0]['choices'].insert(
            0, {'id': 'shortcut', 'label': 'Пройти мимо', 'next_scene_id': 'reply',
                'conditions': [], 'effects': []})
        self.assertEqual(self.repeat_witness(bp, c), ['ask_one', 'back', 'ask_one'])

    def test_repeat_witness_includes_both_self_loop_actions(self):
        bp, c = fixture(one_shot=False)
        bp['scenes'][0]['choices'][0]['next_scene_id'] = 'talk'
        bp['scenes'][0]['text'] = 'Лягушонок: — Такова моя история.'
        c['topics'][0]['answer_scene_id'] = 'talk'
        self.assertEqual(self.repeat_witness(bp, c), ['ask_one', 'ask_one'])

    def test_wrong_book_is_rejected(self):
        bp,c=fixture();c['source_fingerprint']='0'*64
        with self.assertRaises(AuthoringError) as e:
            audit_blueprint(bp,c)
        self.assertEqual(e.exception.code,'wrong_source')

    def test_bounded_state_budget_enforced(self):
        bp,c=fixture()
        with self.assertRaises(AuthoringError):
            audit_blueprint(bp,c,max_states=1)

    def test_wrong_destination_detected(self):
        bp,c=fixture();c['topics'][0]['answer_scene_id']='end'
        r=audit_blueprint(bp,c)
        self.assertIn('WRONG_DIALOGUE_ANSWER',{e['code'] for e in r['issues']})

    def test_schema_exactness(self):
        bp,c=fixture();c['topics'][0]['unexpected']='ignore-me'
        with self.assertRaises(AuthoringError):audit_blueprint(bp,c)


if __name__=='__main__':unittest.main()
