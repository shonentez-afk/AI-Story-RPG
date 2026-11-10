"""Platform-independent MCP QA boundary tests; run on GitHub Linux CI."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.windows_qa_mcp.backend_windows import matches_executable, validate_relative_point
from tools.windows_qa_mcp.core import Config, QAError, QAService

PNG = bytes.fromhex('89504e470d0a1a0a') + b'PNG fixture bytes'  # evidence only validates signature


class FakeBackend:
    def __init__(self):
        self.calls = []
        self.accessibility_empty = False
        self.truncated = False
        self.nodes = [
            {'node_id': 'n0002', 'name': 'Продолжить', 'automation_id': 'start', 'enabled': True},
            {'node_id': 'n0003', 'name': 'Заблокировано', 'automation_id': 'locked', 'enabled': False},
        ]

    def status(self):
        return {'available': True, 'fake': True}

    def launch(self):
        self.calls.append(('launch',))
        return {'pid': 42}

    def close(self):
        self.calls.append(('close',))
        return {'pid': 42, 'close_requested': True, 'forced_kill': False}

    def attach(self, pid=None):
        self.calls.append(('attach', pid))
        return {'pid': pid or 42}

    def tree(self, max_nodes=160, max_depth=9):
        self.calls.append(('tree', max_nodes, max_depth))
        return {'nodes': self.nodes, 'truncated': self.truncated,
                'accessibility_empty': self.accessibility_empty}

    def click(self, selector):
        self.calls.append(('click', selector))
        return {'clicked': selector}

    def click_xy(self, x, y):
        self.calls.append(('click_xy', x, y))
        return {'clicked_image': [x, y]}

    def set_text(self, selector, content):
        self.calls.append(('set_text', selector, len(content)))
        return {'typed_characters': len(content)}

    def type_focused(self, content):
        self.calls.append(('type_focused', len(content)))
        return {'typed_characters': len(content)}

    def press(self, key):
        self.calls.append(('press', key))
        return {'pressed': key}

    def scroll(self, direction, steps):
        self.calls.append(('scroll', direction, steps))
        return {'direction': direction, 'steps': steps}

    def screenshot(self):
        return PNG


class QATests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.backend = FakeBackend()
        self.qa = QAService(Config(None, Path(self.tmp.name), True), self.backend)

    def call(self, tool, **kwargs):
        return self.qa.call(tool, kwargs)[0]

    def test_actions_require_evidence_run(self):
        with self.assertRaisesRegex(QAError, 'qa_begin'):
            self.call('qa_click', name='Продолжить')
        self.assertEqual(self.backend.calls, [])

    def test_preflight_status_and_attach(self):
        self.assertTrue(self.call('qa_status')['backend']['available'])
        self.assertEqual(self.call('qa_attach')['pid'], 42)
        self.assertEqual(self.call('qa_attach', pid=16)['pid'], 16)
        with self.assertRaises(QAError):
            self.call('qa_attach', pid=True)

    def test_input_off_by_default_even_if_launch_called(self):
        qa = QAService(Config(None, Path(self.tmp.name), False), self.backend)
        for name, args in [('qa_launch', {}), ('qa_click', {'name': 'Продолжить'}),
                           ('qa_click_xy', {'x': 1, 'y': 1}), ('qa_press', {'key': 'ENTER'}),
                           ('qa_type_focused', {'text': 'a'}), ('qa_scroll', {'steps': 1}), ('qa_close', {})]:
            with self.subTest(name=name), self.assertRaisesRegex(QAError, 'disabled'):
                qa.call(name, args)
        self.assertEqual(self.backend.calls, [])

    def test_click_exact_selector_and_no_ambiguous_fallback(self):
        self.call('qa_begin', name='click')
        self.assertEqual(self.call('qa_click', name='Продолжить')['clicked'], {'name': 'Продолжить'})
        for selector in ({}, {'node_id': '', 'name': ''},
                         {'name': 'Продолжить', 'node_id': 'n0002'}, {'name': 3}):
            with self.subTest(selector=selector), self.assertRaises(QAError):
                self.call('qa_click', **selector)

    def test_coordinate_validation(self):
        self.call('qa_begin', name='coordinate')
        self.assertEqual(self.call('qa_click_xy', x=12, y=8)['clicked_image'], [12, 8])
        for coords in ({'x': -1, 'y': 3}, {'x': True, 'y': 0}, {'x': 10001, 'y': 0}, {'x': 5}):
            with self.subTest(coords=coords), self.assertRaises(QAError):
                self.call('qa_click_xy', **coords)
        validate_relative_point(0, 1, 20, 20)
        with self.assertRaises(QAError):
            validate_relative_point(20, 1, 20, 20)

    def test_keyboard_navigation_is_allowlisted(self):
        self.call('qa_begin', name='keyboard')
        self.assertEqual(self.call('qa_press', key='esc')['pressed'], 'ESC')
        for key in ('CTRL+ALT+DELETE', 'WIN+R', 'ALT+F4', 'F12', 'ENTER; whoami'):
            with self.subTest(key=key), self.assertRaises(QAError):
                self.call('qa_press', key=key)

    def test_text_not_logged_in_report(self):
        secret = 'ключ не сохранять'
        self.call('qa_begin', name='field')
        self.call('qa_set_text', name='Поле', text=secret)
        self.call('qa_type_focused', text=secret)
        report = self.call('qa_report')
        record = Path(report['json']).read_text(encoding='utf-8')
        self.assertNotIn(secret, record)
        self.assertEqual(report['status'], 'NOT_TESTED')
        with self.assertRaises(QAError):
            self.call('qa_set_text', text='x' * 3001, name='Поле')

    def test_screenshot_and_checksum(self):
        with self.assertRaisesRegex(QAError, 'qa_begin'):
            self.call('qa_screenshot', label='first')
        self.call('qa_begin', name='My Scene 1')
        meta, image = self.qa.call('qa_screenshot', {'label': '../scene:1'})
        self.assertEqual(image, PNG)
        self.assertEqual(Path(meta['file']).parent, self.qa.evidence.run_dir)
        self.assertEqual(meta['bytes'], len(PNG))
        self.assertTrue(Path(meta['file']).is_file())
        self.assertTrue(Path(meta['file']).name.endswith('scene-1.png'))

    def test_assert_positive_and_negative(self):
        self.call('qa_begin', name='assert')
        self.assertTrue(self.call('qa_assert', text_contains='Продолж')['passed'])
        self.assertTrue(self.call('qa_assert', automation_id='locked', enabled=False)['passed'])
        self.assertTrue(self.call('qa_assert', text_contains='НЕТ', present=False)['passed'])
        self.assertFalse(self.call('qa_assert', text_contains='Продолжить', present=False)['passed'])
        result = self.call('qa_report')
        self.assertEqual(result['checks_passed'], 3)
        self.assertEqual(result['checks_failed'], 1)
        self.assertEqual(result['status'], 'FAIL')
        self.assertTrue(Path(result['markdown']).exists())

    def test_no_false_pass_from_incomplete_tree(self):
        self.call('qa_begin', name='truncation')
        self.backend.truncated = True
        r = self.call('qa_assert', text_contains='future', present=False)
        self.assertFalse(r['passed'])
        self.assertTrue(r['inconclusive'])
        self.backend.truncated = False
        self.backend.accessibility_empty = True
        r = self.call('qa_assert', text_contains='future', present=False)
        self.assertFalse(r['passed'])
        self.assertTrue(r['inconclusive'])

    def test_assert_requires_selector_and_types(self):
        self.call('qa_begin', name='types')
        for args in ({}, {'text_contains': ''}, {'text_contains': 'x', 'present': 0},
                     {'automation_id': 'a', 'enabled': 'yes'}):
            with self.subTest(args=args), self.assertRaises(QAError):
                self.call('qa_assert', **args)

    def test_wait_text_no_infinite_polling(self):
        self.assertTrue(self.call('qa_wait_text', text_contains='Продолжить', timeout_seconds=1)['found'])
        for s in (0, 21, 1.2, 'x'):
            with self.subTest(timeout_seconds=s), self.assertRaises(QAError):
                self.call('qa_wait_text', text_contains='x', timeout_seconds=s)

    def test_report_requires_run_and_run_has_unique_folder(self):
        with self.assertRaisesRegex(QAError, 'qa_begin'):
            self.call('qa_report')
        first = self.call('qa_begin', name='a')['directory']
        second = self.call('qa_begin', name='a')['directory']
        self.assertNotEqual(first, second)

    def test_graceful_close_is_scoped_and_logged(self):
        self.call('qa_begin', name='close')
        self.assertTrue(self.call('qa_close')['close_requested'])
        self.assertEqual(self.backend.calls[-1], ('close',))
        report = self.call('qa_report')
        data = json.loads(Path(report['json']).read_text(encoding='utf-8'))
        self.assertEqual(data['actions'][-1]['operation'], 'qa_close')

    def test_explicit_blocker_prevents_false_green_and_report_includes_reason(self):
        self.call('qa_begin', name='coverage')
        self.assertTrue(self.call('qa_assert', text_contains='Продолжить')['passed'])
        self.call('qa_note', scenario='external AI', status='BLOCKED', reason='No explicit consent')
        report = self.call('qa_report')
        self.assertEqual(report['status'], 'BLOCKED')
        payload = json.loads(Path(report['json']).read_text(encoding='utf-8'))
        self.assertEqual(payload['notes'][0]['scenario'], 'external AI')
        with self.assertRaises(QAError):
            self.call('qa_note', scenario='fabrication', status='PASS', reason='not tested')

    def test_scroll_bounded(self):
        self.call('qa_begin', name='scroll')
        self.call('qa_scroll', direction='up', steps=8)
        for args in ({'direction': 'sideways'}, {'steps': 0}, {'steps': 9}, {'steps': True}):
            with self.subTest(args=args), self.assertRaises(QAError):
                self.call('qa_scroll', **args)

    def test_only_exact_executable_can_be_targeted(self):
        target = Path('C:/QA/ai_story_reader.exe')
        self.assertTrue(matches_executable(target, target))
        self.assertTrue(matches_executable('C:/qa/AI_STORY_READER.EXE', target))
        self.assertFalse(matches_executable('C:/QA/other.exe', None))
        self.assertFalse(matches_executable(target, None))
        self.assertFalse(matches_executable('C:/QA/ai_story_reader.exe.evil', None))
        self.assertFalse(matches_executable('D:/QA/ai_story_reader.exe', target))

    def test_config_only_enables_input_with_explicit_1(self):
        with patch.dict(os.environ, {'AI_STORY_QA_ALLOW_INPUT': 'true'}):
            self.assertFalse(Config.from_env().allow_input)
        with patch.dict(os.environ, {'AI_STORY_QA_ALLOW_INPUT': '1'}):
            self.assertTrue(Config.from_env().allow_input)


if __name__ == '__main__':
    unittest.main()