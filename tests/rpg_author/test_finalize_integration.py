"""E6e complete synthetic book workflow, including refusal and positive archive QA."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from tools.rpg_author import project
from tools.rpg_author.common import canonical
from tools.rpg_author.finalize import finalize
from tests.rpg_author.fixtures import TEXT, analysis, story
from tests.rpg_author.fixtures_rich import enrichment
from tests.rpg_author.test_finalize import review_fixture


class FinalizeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        source = self.base / "book.txt"
        source.write_text(TEXT, encoding="utf-8")
        self.root = self.base / "private_project"
        project.init_project(self.root, source)
        project.submit_analysis(self.root, analysis())
        project.submit_story(self.root, story())
        self.game = self.base / "finished.bworld"
        self.overlay = self.base / "enrichment.json"
        self.review = self.base / "review.json"
        plan, overlay, review = review_fixture()
        real = story()
        enriched = enrichment()
        from tools.rpg_author.common import digest
        review["source_fingerprint"] = real["source_fingerprint"]
        review["story_sha256"] = digest(canonical(real))
        review["enrichment_sha256"] = digest(canonical(enriched))
        review["scenes"] = [
            {"scene_id": s["id"], "verdict": "pass",
             "notes": "The original source and causal development were reviewed.",
             "source_assertion_ids": s["assertion_ids"]}
            for s in real["scenes"]]
        review["endings"] = [
            {"scene_id": s["id"], "verdict": "pass",
             "notes": "The outcome was reviewed separately for causality."}
            for s in real["scenes"] if s["terminal"]]
        self.overlay.write_bytes(canonical(enriched))
        self.review.write_bytes(canonical(review))

    def test_quality_warning_refuses_build_and_preserves_reason(self):
        result = finalize(self.root, self.overlay, self.review, self.game,
                          no_interactive_questions=True)
        self.assertEqual(result["status"], "rejected")
        self.assertEqual(result["failure"]["code"], "gameplay_warnings")
        self.assertFalse(self.game.exists())
        report = json.loads(self.game.with_suffix(".finalization.json").read_text())
        self.assertEqual(report["failure"]["code"], "gameplay_warnings")
        self.assertFalse(report["user_ready"])
        self.assertFalse(report["device_playtest_completed"])

    def test_all_clear_build_is_source_bound_and_not_device_attested(self):
        overlay = json.loads(self.overlay.read_text(encoding="utf-8"))
        overlay["stats"] = {}
        overlay["facts"] = {}
        overlay["choices"] = {
            "take_rope": {"conditions": [], "effects": [
                {"op": "grant_item", "id": "rope"}]},
            "leave_rope": {"conditions": [], "effects": []},
            "rescue": {"conditions": [
                {"op": "has_item", "id": "rope"}], "effects": [
                {"op": "consume_item", "id": "rope"}]},
            "go_for_help": {"conditions": [], "effects": []},
        }
        self.overlay.write_bytes(canonical(overlay))
        review = json.loads(self.review.read_text(encoding="utf-8"))
        from tools.rpg_author.common import digest
        review["enrichment_sha256"] = digest(canonical(overlay))
        self.review.write_bytes(canonical(review))
        result = finalize(self.root, self.overlay, self.review, self.game,
                          no_interactive_questions=True)
        self.assertEqual(result["status"],
                         "structurally_complete_literary_report_checked_device_untested",
                         result)
        self.assertTrue(self.game.exists())
        self.assertTrue(self.game.with_suffix(".attribution.json").exists())
        self.assertFalse(result["user_ready"])
        self.assertFalse(result["literary_truth_attested"])
        self.assertFalse(result["device_playtest_completed"])
        self.assertEqual(result["archive_sha256"],
                         digest(self.game.read_bytes()))


if __name__ == "__main__":
    unittest.main()
