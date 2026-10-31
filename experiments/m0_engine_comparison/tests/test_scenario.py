import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pilot"))
from compile_pilot import validate, compile_ink

DATA = json.loads((ROOT / "pilot" / "scenario.json").read_text("utf-8"))

class M0ScenarioTests(unittest.TestCase):
    def test_graph(self):
        validate(DATA)

    def test_gates(self):
        cs = {c["id"]: c for scene in DATA["scenes"] for c in scene["choices"]}
        self.assertEqual(cs["open_gate"]["when"], {"has_key": True})
        self.assertEqual(cs["trust_talk"]["when"], {"guard_trust": {"gte": 1}})
        self.assertEqual(cs["ask_witness"]["when"], {"witness_alive": True})
        self.assertEqual(cs["show_evidence"]["when"], {"has_letter": True})

    def test_ink_generation(self):
        text = compile_ink(DATA)
        self.assertIn("=== witness ===", text)
        self.assertIn("guard_trust >= 1", text)
        self.assertNotIn("EXTERNAL", text)

    def test_all_scenes_reachable_ignoring_gates(self):
        scenes = {s["id"]: s for s in DATA["scenes"]}
        seen, queue = set(), [DATA["entry"]]
        while queue:
            scene_id = queue.pop()
            if scene_id in seen:
                continue
            seen.add(scene_id)
            queue += [c["next"] for c in scenes[scene_id]["choices"]]
        self.assertEqual(set(scenes), seen)

if __name__ == "__main__":
    unittest.main()
