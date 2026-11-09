"""E6i: real multi-chapter source/act/choice contract; no private book fixture."""
from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.rpg_author import project
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.native_v4_bridge import audited_extension
from tools.rpg_author.rich_package import compile_rich_from_project
from tools.rpg_author.v4_acts import extend_reviewed_acts, extend_checked_world, _check_rule
from tests.rpg_author.fixtures_acts import (
    SOURCE, SOURCE_FILENAME, analyses, index, rich_enrichment, reviewed_acts,
    story_plan,
)


class ReviewedMultiActTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        source = self.base / SOURCE_FILENAME
        source.write_text(SOURCE, encoding="utf-8")
        self.root = self.base / "project"
        project.init_project(self.root, source)
        self.idx, self.records = index(), analyses()
        for record in self.records:
            project.submit_analysis(self.root, record)
        self.plan = story_plan()
        self.overlay = rich_enrichment()
        project.submit_story(self.root, self.plan)
        original, _ = compile_rich_from_project(self.root, self.overlay)
        with zipfile.ZipFile(io.BytesIO(original)) as archive:
            self.bp = json.loads(archive.read("scenario/blueprint.json"))
            self.prov = json.loads(archive.read("source/provenance.json"))
        self.original_bp = canonical(self.bp)
        self.original_prov = canonical(self.prov)

    def expand(self, proposal):
        return extend_checked_world(
            self.bp, self.prov, self.plan, self.overlay,
            self.idx, self.records, proposal)

    def test_two_acts_have_distinct_source_and_stateful_branching(self):
        bp, prov, report = self.expand(reviewed_acts(self.bp))
        self.assertEqual(report["act_count"], 2)
        self.assertEqual(report["added_scenes"], 4)
        self.assertEqual(report["total_scenes"], 8)
        self.assertEqual(report["distinct_source_quotes"], 4)
        self.assertEqual(report["distinct_source_events"], 4)
        self.assertEqual(report["branching_scenes"], 2)
        self.assertGreaterEqual(report["stateful_choices"], 4)
        self.assertEqual(report["chapters_without_source_scenes"], [])
        self.assertFalse(report["native_causality_verified"])
        self.assertFalse(report["literary_canon_verified"])
        scenes = {x["id"]: x for x in bp["scenes"]}
        self.assertEqual(scenes["road"]["choices"][0]["next_scene_id"], "inspect_knot")
        self.assertEqual(scenes["river"]["choices"][0]["next_scene_id"], "rescue_decision")
        self.assertEqual(scenes["study_current"]["choices"][0]["next_scene_id"], "river")
        self.assertEqual(scenes["rope_rescue"]["choices"][0]["next_scene_id"], "safe")
        gated = scenes["rescue_decision"]["choices"][0]
        self.assertEqual(gated["conditions"], [
            {"op": "knows_fact", "id": "current", "actor": "player"}])
        self.assertEqual(scenes["study_current"]["choices"][0]["effects"],
                         [{"op": "learn_fact", "id": "current", "actor": "player"}])
        self.assertEqual(len(prov["scene_origins"]), 8)
        self.assertEqual(canonical(self.bp), self.original_bp)
        self.assertEqual(canonical(self.prov), self.original_prov)
        self.assertTrue(bp["book_id"].startswith("acts_"))

    def test_readonly_preflight_uses_actual_complete_project(self):
        report = audited_extension(self.root, self.overlay, reviewed_acts(self.bp))
        self.assertEqual(report["act_count"], 2)
        self.assertEqual(report["status"],
                         "V4_MULTI_ACT_PREFLIGHT_REQUIRES_NATIVE_AND_LITERARY_REVIEW")
        self.assertFalse(list(self.base.glob("*.bworld")))

    def test_identity_and_editorial_truth_are_fail_closed(self):
        for field in ("source_fingerprint", "story_sha256",
                      "enrichment_sha256", "base_blueprint_sha256"):
            with self.subTest(field=field):
                proposed = reviewed_acts(self.bp)
                proposed[field] = "0" * 64
                with self.assertRaises(AuthoringError) as error:
                    self.expand(proposed)
                self.assertEqual(error.exception.code, "act_source_mismatch")
        proposed = reviewed_acts(self.bp)
        proposed["editorial_review"]["character_continuity_reviewed"] = False
        with self.assertRaises(AuthoringError) as error:
            self.expand(proposed)
        self.assertEqual(error.exception.code, "act_unreviewed")
        proposed = reviewed_acts(self.bp)
        proposed["editorial_review"]["literary_canon_verified"] = True
        with self.assertRaises(AuthoringError) as error:
            self.expand(proposed)
        self.assertEqual(error.exception.code, "act_unreviewed")

    def test_no_repeated_literary_events_or_quotes(self):
        cases = [
            ("act_duplicate_event", lambda p: p["acts"][1]["scenes"][0].update(
                event_id="knot_event")),
            ("act_reused_quote", lambda p: p["acts"][1]["scenes"][0].update(
                assertion_ids=["bridge_damage"])),
            ("act_duplicate_choice", lambda p: p["acts"][1]["scenes"][0]["choices"][0].update(
                id="take_rope")),
            ("act_future_quote", lambda p: p["acts"][0]["scenes"][0].update(
                assertion_ids=["bank_rope"])),
            ("act_missing_quote", lambda p: p["acts"][0]["scenes"][0].update(
                assertion_ids=[])),
        ]
        for code, mutation in cases:
            with self.subTest(code=code):
                item = reviewed_acts(self.bp)
                mutation(item)
                with self.assertRaises(AuthoringError) as err:
                    self.expand(item)
                self.assertEqual(err.exception.code, code)

    def test_chapter_coverage_and_monotone_act_order(self):
        candidate = reviewed_acts(self.bp)
        candidate["acts"][0]["scenes"][1]["origin"] = "EXPLICIT_ADAPTATION"
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "act_uncovered_chapter")
        candidate = reviewed_acts(self.bp)
        candidate["acts"][1]["chapter_start"] = 0
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "act_chronology")

    def test_cycle_and_unreachable_event_rejected(self):
        candidate = reviewed_acts(self.bp)
        candidate["acts"][0]["scenes"][0]["choices"][0]["next_scene_id"] = "inspect_knot"
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "act_trapped_cycle")
        candidate = reviewed_acts(self.bp)
        candidate["acts"][0]["scenes"][0]["choices"][0]["next_scene_id"] = "@exit"
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "act_unreachable_event")

    def test_reject_unwitnessed_effects_invalid_rules_and_empty_act(self):
        candidate = reviewed_acts(self.bp)
        candidate["acts"][0]["scenes"][0]["choices"][0]["effect_assertion_ids"] = []
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "act_unwitnessed_effect")
        candidate = reviewed_acts(self.bp)
        candidate["acts"][0]["scenes"][0]["choices"][0]["effects"] = [
            {"op": "eval", "code": "do_something()"}]
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "invalid_act_rule")
        candidate = reviewed_acts(self.bp)
        for scene in candidate["acts"][0]["scenes"]:
            for choice in scene["choices"]:
                choice["effects"], choice["effect_assertion_ids"] = [], []
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "act_no_consequence")

    def test_npc_knowledge_cannot_bypass_an_independent_grant_review(self):
        bp = deepcopy(self.bp)
        bp["actors"].append("npc_1")
        bp["initial_state"]["knowledge"]["npc_1"] = []
        with self.assertRaises(AuthoringError) as err:
            _check_rule({"op": "learn_fact", "id": "current", "actor": "npc_1"},
                        bp, effect=True)
        self.assertEqual(err.exception.code, "unreviewed_act_npc_grant")

    def test_explicit_initial_inventory_and_tick_are_source_witnessed(self):
        candidate = reviewed_acts(self.bp)
        candidate["initial_state"] = {
            "tick": 1, "items": [
                {"item_id": "rope", "assertion_id": "road_found"}],
            "facts": [],
        }
        bp, prov, _ = self.expand(candidate)
        self.assertEqual(bp["initial_state"]["inventory"], ["rope"])
        self.assertEqual(bp["initial_state"]["tick"], 1)
        self.assertTrue(prov["initial_state_review"]["user_confirmed"])
        candidate["initial_state"]["items"][0]["assertion_id"] = "bridge_warning"
        with self.assertRaises(AuthoringError) as err:
            self.expand(candidate)
        self.assertEqual(err.exception.code, "initial_future_evidence")


if __name__ == "__main__":
    unittest.main()
