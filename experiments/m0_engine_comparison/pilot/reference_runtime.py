"""M0 deterministic *reference oracle*, not the chosen Dart game engine.

Input is the single shared scenario.json. A saved event log is replayed and
validated before allowing restore. No network, eval, LLM, or external runtime.
"""
import copy
import hashlib
import json
from pathlib import Path

def canonical(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':'))

def fingerprint(scenario):
    return hashlib.sha256(canonical(scenario).encode('utf-8')).hexdigest()

class InvalidAction(ValueError):
    pass

class ReferenceGame:
    def __init__(self, scenario):
        self.scenario = scenario
        self.nodes = {s['id']: s for s in scenario['scenes']}
        self.scene = scenario['entry']
        self.values = copy.deepcopy(scenario['initial'])
        self.history = []
        self.used_ids = set()

    def current(self):
        return self.nodes[self.scene]

    def available(self):
        def allowed(choice):
            for k, want in choice.get('when', {}).items():
                actual = self.values[k]
                if isinstance(want, dict):
                    if set(want) != {'gte'} or actual < want['gte']:
                        return False
                elif actual != want:
                    return False
            return True
        return [c for c in self.current()['choices'] if allowed(c)]

    def act(self, choice_id, action_id=None):
        action_id = action_id or f'a{len(self.history)+1}'
        if action_id in self.used_ids:
            raise InvalidAction('Duplicate action ID')
        found = [c for c in self.available() if c['id'] == choice_id]
        if len(found) != 1:
            raise InvalidAction('Choice unavailable')
        c = found[0]
        proposed = copy.deepcopy(self.values)
        for key, value in c.get('set', {}).items():
            if type(proposed[key]) is not type(value):
                raise InvalidAction('Invalid value type')
            proposed[key] = value
        for key, amount in c.get('inc', {}).items():
            if type(proposed[key]) is not int or type(amount) is not int:
                raise InvalidAction('Invalid increment')
            proposed[key] += amount
        old = self.scene
        self.scene, self.values = c['next'], proposed
        self.history.append({'action_id': action_id, 'choice_id': choice_id, 'from': old, 'to': self.scene})
        self.used_ids.add(action_id)
        return self.scene

    def save(self):
        return {'version': 1, 'scenario_hash': fingerprint(self.scenario),
                'scene': self.scene, 'values': copy.deepcopy(self.values),
                'history': copy.deepcopy(self.history)}

    @classmethod
    def restore(cls, scenario, saved):
        if saved.get('version') != 1 or saved.get('scenario_hash') != fingerprint(scenario):
            raise ValueError('Incompatible save')
        game = cls(scenario)
        for event in saved['history']:
            if game.scene != event['from']:
                raise ValueError('Corrupt event log')
            game.act(event['choice_id'], event['action_id'])
            if game.scene != event['to']:
                raise ValueError('Corrupt event log')
        if game.scene != saved['scene'] or game.values != saved['values']:
            raise ValueError('Corrupt snapshot')
        return game

def load_demo():
    return json.loads((Path(__file__).parent/'scenario.json').read_text('utf-8'))

if __name__ == '__main__':
    game = ReferenceGame(load_demo())
    while not game.current().get('ending'):
        print('\n'+game.current()['text'])
        options = game.available()
        for i, c in enumerate(options, 1):
            print(f'{i}. {c["text"]}')
        try:
            choice = int(input('> '))
            game.act(options[choice-1]['id'])
        except (ValueError, IndexError):
            print('Недопустимый выбор')
    print(game.current()['text'])
