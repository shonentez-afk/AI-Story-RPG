"""Regression for the *original* v1 runtime's stateful tab behavior.

The user-facing FB2 adaptation cannot yet encode these effects in v2.
This fixture must never be presented as a source-bound literary adaptation.
"""
import json
import unittest
import zipfile
from io import BytesIO

from tools.bookworld import bookworld
from tests.rpg_author.panel_state_demo import blueprint, build


class PanelStateFixtureTests(unittest.TestCase):
    def test_is_real_original_demo_archive_with_all_catalogs(self):
        raw = build()
        report = bookworld.verify(raw)
        self.assertEqual(report["format_version"], 1)
        with zipfile.ZipFile(BytesIO(raw)) as z:
            self.assertEqual(z.namelist(), list(bookworld.EXPECTED))
            meta = json.loads(z.read("manifest.json"))
            payload = json.loads(z.read("scenario/blueprint.json"))
            self.assertEqual(meta["model_provenance"],
                             {"provider": "none", "model_id": None})
            self.assertEqual(payload["rights_status"], "original_demo")
            self.assertIsNone(payload["source_fingerprint"])
            self.assertEqual(payload["items"], ["lantern", "rope", "medal"])
            self.assertIn("courage", payload["initial_state"]["stats"])
            self.assertIn("insight", payload["initial_state"]["stats"])
            self.assertEqual(payload["initial_state"]["inventory"], [])
            self.assertTrue(any(
                e["op"] == "consume_item"
                for scene in payload["scenes"]
                for choice in scene["choices"]
                for e in choice["effects"]
            ))
            self.assertTrue(any(
                e["op"] == "stat_delta"
                for scene in payload["scenes"]
                for choice in scene["choices"]
                for e in choice["effects"]
            ))
            self.assertTrue(any(
                e["op"] == "learn_fact"
                for scene in payload["scenes"]
                for choice in scene["choices"]
                for e in choice["effects"]
            ))

    def test_synthetic_world_is_deterministic_and_two_endings_reachable(self):
        raw1, raw2 = build(), build()
        self.assertEqual(raw1, raw2)
        world = blueprint()
        scenes = {s["id"]: s for s in world["scenes"]}
        self.assertEqual(len(scenes), 6)
        self.assertEqual({s["id"] for s in world["scenes"] if s["terminal"]},
                         {"end_saved", "end_away"})
        seen = {world["entry_scene_id"]}
        queue = [world["entry_scene_id"]]
        for scene_id in queue:
            for option in scenes[scene_id]["choices"]:
                if option["next_scene_id"] not in seen:
                    seen.add(option["next_scene_id"])
                    queue.append(option["next_scene_id"])
        self.assertEqual(seen, set(scenes))

    def test_v2_book_builder_remains_strict_and_does_not_launder_original_demo(self):
        from tools.bookworld import private_bookworld
        with self.assertRaises(bookworld.BookworldError):
            private_bookworld.build(blueprint(), {}, {})
