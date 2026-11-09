"""Strict source-chapter proof: never mistake packaged events for playable scenes.

Actual native route traversal is independently tested in run_dart_parity.py.
"""
from copy import deepcopy
import unittest

from tools.rpg_author.auto_author import _source_chapter_proof_spec
from tools.rpg_author.common import AuthoringError


class NativeSourceChapterProofTests(unittest.TestCase):
    def setUp(self):
        self.provenance = {
            "source_chapters_total": 3,
            "scene_origins": [
                {"scene_id": "opening", "origin": "SOURCE_PASSAGE",
                 "chapter_index": 0},
                {"scene_id": "alternative", "origin": "EXPLICIT_ADAPTATION",
                 "chapter_index": 1},
                {"scene_id": "middle", "origin": "SOURCE_PASSAGE",
                 "chapter_index": 1},
                {"scene_id": "ending", "origin": "SOURCE_PASSAGE",
                 "chapter_index": 2},
            ],
        }
        for origin in self.provenance["scene_origins"]:
            if origin["origin"] == "SOURCE_PASSAGE":
                origin["source_refs"] = [{
                    "chapter_index": origin["chapter_index"]
                }]

    def test_only_original_source_scenes_are_authoritative(self):
        spec = _source_chapter_proof_spec(self.provenance)
        self.assertEqual(spec["source_chapters_total"], 3)
        self.assertEqual(spec["source_passages"], [
            {"scene_id": "opening", "chapter_index": 0},
            {"scene_id": "middle", "chapter_index": 1},
            {"scene_id": "ending", "chapter_index": 2},
        ])

    def test_uncovered_chapter_cannot_be_hidden_by_fiction(self):
        broken = deepcopy(self.provenance)
        broken["scene_origins"][2]["origin"] = "EXPLICIT_ADAPTATION"
        with self.assertRaises(AuthoringError) as error:
            _source_chapter_proof_spec(broken)
        self.assertEqual(error.exception.code,
                         "native_chapter_provenance_incomplete")

    def test_earlier_quote_cannot_fake_later_book_chapter(self):
        broken = deepcopy(self.provenance)
        broken["scene_origins"][-1]["source_refs"] = [
            {"chapter_index": 0}
        ]
        with self.assertRaises(AuthoringError) as error:
            _source_chapter_proof_spec(broken)
        self.assertEqual(error.exception.code,
                         "native_chapter_quote_unbound")
        broken["scene_origins"][-1]["source_refs"] = []
        with self.assertRaises(AuthoringError):
            _source_chapter_proof_spec(broken)

    def test_duplicate_original_scene_and_wrong_chapter_refused(self):
        broken = deepcopy(self.provenance)
        broken["scene_origins"][2]["scene_id"] = "opening"
        with self.assertRaises(AuthoringError):
            _source_chapter_proof_spec(broken)
        broken = deepcopy(self.provenance)
        broken["scene_origins"][0]["chapter_index"] = 3
        with self.assertRaises(AuthoringError):
            _source_chapter_proof_spec(broken)

    def test_invalid_total_and_missing_origin_are_refused(self):
        for total in (0, -1, "3", True, 10001):
            broken = deepcopy(self.provenance)
            broken["source_chapters_total"] = total
            with self.subTest(total=total), self.assertRaises(AuthoringError):
                _source_chapter_proof_spec(broken)
        broken = deepcopy(self.provenance)
        broken["scene_origins"].pop()
        with self.assertRaises(AuthoringError):
            _source_chapter_proof_spec(broken)


if __name__ == "__main__":
    unittest.main()
