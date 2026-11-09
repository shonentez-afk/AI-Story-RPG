"""E6j: source-locked NPC knowledge + memory + cross-act trust authoring QA."""
from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.rpg_author import project
from tools.rpg_author.common import AuthoringError, canonical
from tools.rpg_author.native_v4_bridge import audited_extension
from tools.rpg_author.rich_package import compile_rich_from_project
from tools.rpg_author.v4_acts import extend_checked_world
from tests.rpg_author import fixtures_acts as base
from tests.rpg_author.fixtures_npc_acts import (
    ACTOR, NPC_FACT, reviewed_base, reviewed_npc_acts,
)


class NpcCrossActAuthoringTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.private = Path(self.tmp.name)
        source = self.private / base.SOURCE_FILENAME
        source.write_text(base.SOURCE, encoding="utf-8")
        self.root = self.private / "project"
        project.init_project(self.root, source)
        self.index = base.index()
        self.analyses = base.analyses()
        for record in self.analyses:
            project.submit_analysis(self.root, record)
        self.story = base.story_plan()
        project.submit_story(self.root, self.story)
        self.overlay, self.npc_review = reviewed_base()
        original, _ = compile_rich_from_project(
            self.root, self.overlay, npc_review=self.npc_review)
        with zipfile.ZipFile(io.BytesIO(original)) as bundle:
            self.bp = json.loads(bundle.read("scenario/blueprint.json"))
            self.prov = json.loads(bundle.read("source/provenance.json"))
        self.original_bp = canonical(self.bp)
        self.original_prov = canonical(self.prov)

    def propose(self):
        return reviewed_npc_acts(self.bp, self.prov, self.overlay)

    def check(self, proposal):
        return extend_checked_world(
            self.bp, self.prov, self.story, self.overlay,
            self.index, self.analyses, proposal)

    def test_source_bound_npc_knowledge_and_cross_act_trust(self):
        bp, prov, report = self.check(self.propose())
        self.assertEqual(report["act_count"], 2)
        self.assertEqual(report["total_scenes"], 8)
        self.assertEqual(report["npc_known_grants_added"], 1)
        self.assertEqual(report["npc_witnesses_added"], 2)
        self.assertEqual(report["npc_memories_added"], 2)
        self.assertEqual(report["npc_cross_act_gates_added"], 1)
        self.assertEqual(report["npc_life_transitions_added"], 1)
        self.assertTrue(report["actor_identity_reused_from_base"])
        self.assertFalse(report["npc_social_v5_validated_by_native"])
        self.assertFalse(report["literary_canon_verified"])
        self.assertEqual(canonical(self.bp), self.original_bp)
        self.assertEqual(canonical(self.prov), self.original_prov)
        self.assertTrue(bp["book_id"].startswith("npc_acts_"))
        self.assertEqual(bp["actors"], ["player", ACTOR])
        scenes = {scene["id"]: scene for scene in bp["scenes"]}
        effects = scenes["study_current"]["choices"][0]["effects"]
        self.assertIn({"op": "learn_fact", "actor": ACTOR,
                       "id": NPC_FACT}, effects)
        gate = scenes["rescue_decision"]["choices"][0]["conditions"]
        self.assertIn({"op": "knows_fact", "actor": ACTOR,
                       "id": NPC_FACT}, gate)
        self.assertEqual(
            prov["npc_knowledge"]["grants"][-1]["scene_id"], "study_current")
        self.assertEqual(
            prov["npc_social"]["choice_gates"][-1]["required_memory_id"],
            "shared_warning")
        self.assertEqual(
            prov["npc_social"]["life_transitions"][-1]["next_state"], "absent")
        self.assertEqual(report["chapters_without_source_scenes"], [])

    def test_readonly_preflight_preserves_private_project(self):
        result = audited_extension(
            self.root, self.overlay, self.propose(), npc_review=self.npc_review)
        self.assertEqual(result["status"],
                         "V4_ACT_NPC_REVIEW_PENDING_NATIVE_AND_LITERARY_ACCEPTANCE")
        self.assertFalse(result["native_causality_verified"])
        self.assertFalse(list(self.private.glob("*.bworld")))

    def test_missing_stale_nonconsensual_npc_proofs_refused(self):
        cases = [
            ("npc_act_review_mismatch",
             lambda p: p["npc_actor_review"].update(
                 base_npc_social_sha256="f" * 64)),
            ("npc_act_review_mismatch",
             lambda p: p["npc_actor_review"].update(user_confirmed=False)),
            ("npc_act_review_mismatch",
             lambda p: p["npc_actor_review"].update(literary_canon_verified=True)),
            ("npc_duplicate_grant",
             lambda p: p["npc_actor_review"]["knowledge_grants"].append(
                 deepcopy(p["npc_actor_review"]["knowledge_grants"][0]))),
            ("npc_unreviewed_quote",
             lambda p: p["npc_actor_review"]["knowledge_grants"][0].update(
                 assertion_id="bridge_warning")),
            ("npc_identity_missing",
             lambda p: p["npc_actor_review"]["knowledge_grants"][0].update(
                 actor_id="npc_" + "a" * 32)),
            ("npc_unearned_cross_act_memory",
             lambda p: p["npc_actor_review"]["choice_gates"][0].update(
                 required_memory_id="invented_future")),
            ("npc_unwitnessed_memory",
             lambda p: p["npc_actor_review"]["witnesses"][0].update(
                 mode="reported")),
            ("npc_duplicate_memory",
             lambda p: p["npc_actor_review"]["memories"][1].update(
                 memory_id="shared_warning")),
            ("npc_invalid_life_event",
             lambda p: p["npc_actor_review"]["life_transitions"][0].update(
                 next_state="revived")),
        ]
        for code, mutate in cases:
            with self.subTest(code=code):
                draft = self.propose()
                mutate(draft)
                with self.assertRaises(AuthoringError) as raised:
                    self.check(draft)
                self.assertEqual(raised.exception.code, code)

    def test_no_freeform_npc_fact_without_independent_review(self):
        candidate = self.propose()
        candidate["npc_actor_review"]["knowledge_grants"] = []
        with self.assertRaises(AuthoringError) as raised:
            self.check(candidate)
        self.assertEqual(raised.exception.code, "npc_empty_act_review")
        candidate = self.propose()
        candidate["npc_actor_review"]["knowledge_grants"][0]["fact_id"] = "forged"
        with self.assertRaises(AuthoringError) as raised:
            self.check(candidate)
        self.assertEqual(raised.exception.code, "unreviewed_act_npc_grant")

    def test_cross_act_gate_requires_an_earned_positive_earlier_memory(self):
        candidate = self.propose()
        candidate["npc_actor_review"]["memories"][0]["relationship_delta"] = 0
        with self.assertRaises(AuthoringError) as raised:
            self.check(candidate)
        self.assertEqual(raised.exception.code, "npc_unearned_cross_act_memory")
        candidate = self.propose()
        candidate["npc_actor_review"]["choice_gates"][0]["scene_id"] = (
            "study_current")
        candidate["npc_actor_review"]["choice_gates"][0]["choice_id"] = (
            "note_current")
        with self.assertRaises(AuthoringError) as raised:
            self.check(candidate)
        self.assertEqual(raised.exception.code, "npc_unearned_cross_act_memory")

    def test_stale_base_review_and_legacy_v1_are_not_auto_migrated(self):
        candidate = self.propose()
        candidate["format"] = "rpg_author_v4_acts_v1"
        with self.assertRaises(AuthoringError):
            self.check(candidate)
        candidate = self.propose()
        candidate["npc_actor_review"]["format"] = "unknown_v2"
        with self.assertRaises(AuthoringError) as raised:
            self.check(candidate)
        self.assertEqual(raised.exception.code, "npc_act_review_mismatch")


if __name__ == "__main__":
    unittest.main()
