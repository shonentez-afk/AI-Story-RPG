import unittest
from pathlib import Path
from types import SimpleNamespace
from tools.windows_qa_mcp.crash_events import extract_app_crash


class WindowsCrashEventTests(unittest.TestCase):
    def make(self, path='C:\\Games\\AI-Story-RPG-Windows\\ai_story_reader.exe'):
        inserts = ['ai_story_reader.exe', '', '', 'flutter_windows.dll', '', '',
                   '0xc0000005', '', '', '', path, '']
        return SimpleNamespace(EventID=1000, SourceName='Application Error',
                               StringInserts=inserts, TimeGenerated='2026-11-17 12:00:00')

    def test_exact_path_in_widows_event(self):
        target = Path('C:\\Games\\AI-Story-RPG-Windows\\ai_story_reader.exe')
        result = extract_app_crash(self.make(), target)
        self.assertEqual(result['exception_code'], '0xc0000005')
        self.assertEqual(result['faulting_module'], 'flutter_windows.dll')
        self.assertEqual(result['path_verified'], 'true')

    def test_wrong_path_not_attributed(self):
        target = Path('C:\\Games\\AI-Story-RPG-Windows\\ai_story_reader.exe')
        self.assertIsNone(extract_app_crash(self.make('C:\\Other\\ai_story_reader.exe'), target))

    def test_wrong_event_type_not_attributed(self):
        target = Path('C:\\Games\\AI-Story-RPG-Windows\\ai_story_reader.exe')
        obj = self.make()
        obj.EventID = 1001
        self.assertIsNone(extract_app_crash(obj, target))
        obj.EventID = 1000
        obj.SourceName = '.NET Runtime'
        self.assertIsNone(extract_app_crash(obj, target))

    def test_no_path_does_not_claim_crash(self):
        target = Path('C:\\Games\\AI-Story-RPG-Windows\\ai_story_reader.exe')
        obj = self.make()
        obj.StringInserts[10] = ''
        self.assertIsNone(extract_app_crash(obj, target))


if __name__ == '__main__':
    unittest.main()