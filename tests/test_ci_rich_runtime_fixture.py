"""Native rich-v3 Flutter CI fixture must not depend on E6d's pinned toolchain."""
from __future__ import annotations

import io
import json
import unittest
import zipfile

from tools.bookworld.ci_rich_runtime_fixture import build_runtime_fixture
from tools.bookworld import private_rich_bookworld as rich


class IndependentRichFixtureTests(unittest.TestCase):
    def test_signed_native_v3_real_inventory_stats_journal_routes(self):
        raw = build_runtime_fixture()
        self.assertEqual(raw, build_runtime_fixture())  # byte deterministic
        verified = rich.verify(raw)
        self.assertEqual(verified["format_version"], 3)
        self.assertEqual(verified["scene_count"], 4)
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            bp = json.loads(archive.read("scenario/blueprint.json"))
            prov = json.loads(archive.read("source/provenance.json"))
            manifest = json.loads(archive.read("manifest.json"))
        self.assertEqual(prov["presentation"]["hero"]["name"], "Лена")
        self.assertEqual(prov["presentation"]["item_names"], {"rope": "Верёвка"})
        self.assertEqual(prov["presentation"]["fact_names"], {
            "rescue_fact": "Мальчик спасён у реки"})
        self.assertEqual(bp["initial_state"]["stats"],
                         {"courage": 1, "insight": 1})
        self.assertEqual(prov["model_provenance"]["provider"], "none")
        self.assertFalse(prov["publication_authorized"])
        self.assertEqual(manifest["format_version"], 3)
        by_name = {scene["id"]: scene for scene in bp["scenes"]}
        road = {c["id"]: c for c in by_name["road"]["choices"]}
        self.assertEqual(road["take_rope"]["effects"][0],
                         {"op": "grant_item", "id": "rope"})
        self.assertEqual(road["leave_rope"]["effects"][0],
                         {"op": "stat_delta", "id": "insight", "amount": 1})
        river = {c["id"]: c for c in by_name["river"]["choices"]}
        self.assertEqual(river["rescue"]["conditions"],
                         [{"op": "has_item", "id": "rope"}])
        self.assertEqual(river["rescue"]["effects"][0],
                         {"op": "consume_item", "id": "rope"})
        self.assertEqual(river["rescue"]["effects"][1],
                         {"op": "learn_fact", "id": "rescue_fact",
                          "actor": "player"})
        self.assertEqual(river["rescue"]["effects"][2]["amount"], 2)
        self.assertTrue(by_name["safe"]["terminal"])
        self.assertTrue(by_name["help"]["terminal"])


if __name__ == "__main__":
    unittest.main()
