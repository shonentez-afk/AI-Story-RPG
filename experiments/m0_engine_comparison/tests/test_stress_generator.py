import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pilot"))
from generate_stress import build
from reference_runtime import ReferenceGame

class StressGeneratorTest(unittest.TestCase):
    def test_1000_scenes(self):
        data = build()
        self.assertEqual(len(data["scenes"]), 1000)
        self.assertEqual(data["scenes"][-1]["ending"], True)
        game = ReferenceGame(data)
        for i in range(999):
            game.act(f"next_{i:04d}")
        self.assertEqual(game.scene, "scene_0999")
        self.assertEqual(game.values["visited"], 999)

    def test_reject_tiny(self):
        with self.assertRaises(ValueError):
            build(1)
