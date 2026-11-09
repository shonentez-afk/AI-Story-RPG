"""E6k: no invented speaker identities, quoted dialogue or item custody."""
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
from tests.rpg_author.fixtures_npc_acts import ACTOR, NPC_FACT
from tests.rpg_author.fixtures_npc_scene_items import (
    reviewed_base_with_owned_item, reviewed_dialogue_and_custody,
)


class ReviewedNpcDialogueItemTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.private = Path(self.tmp.name)
        book = self.private / base.SOURCE_FILENAME
        book.write_text(base.SOURCE, encoding="utf-8")
        self.root = self.private / "project"
        project.init_project(self.root, book)
        self.idx = base.index()
        self.analysis = base.analyses()
        for item in self.analysis:
            project.submit_analysis(self.root, item)
        self.story = base.story_plan()
        project.submit_story(self.root, self.story)
        self.overlay, self.npc_review = reviewed_base_with_owned_item()
        raw, _ = compile_rich_from_project(
            self.root, self.overlay, npc_review=self.npc_review)
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            self.blueprint = json.loads(archive.read("scenario/blueprint.json"))
            self.provenance = json.loads(archive.read("source/provenance.json"))
        self.before_bp = canonical(self.blueprint)
        self.before_prov = canonical(self.provenance)

    def fixture(self):
        return reviewed_dialogue_and_custody(
            self.blueprint, self.provenance, self.overlay)

    def expand(self, extension):
        return extend_checked_world(self.blueprint, self.provenance,
                                    self.story, self.overlay, self.idx,
                                    self.analysis, extension)

    def test_signed_dialogue_gates_and_custody_review(self):
        bp, prov, report = self.expand(self.fixture())
        self.assertEqual(report["npc_dialogue_scenes_reviewed"], 1)
        self.assertEqual(report["npc_dialogue_signed_turns"], 2)
        self.assertEqual(report["npc_item_transfers_reviewed"], 1)
        self.assertEqual(report["npc_source_items_reviewed"], 1)
        self.assertFalse(report["dialogue_redaction_verified_by_native"])
        self.assertFalse(report["npc_item_owners_verified_by_native"])
        self.assertFalse(report["semantic_review_completed"])
        self.assertEqual(canonical(self.blueprint), self.before_bp)
        self.assertEqual(canonical(self.provenance), self.before_prov)
        speaker = prov["presentation"]["scene_dialogue_knowledge"]["rescue_decision"]
        self.assertEqual(speaker[0]["actor_id"], "player")
        self.assertEqual(speaker[1]["actor_id"], ACTOR)
        self.assertEqual(speaker[1]["required_fact_ids"], [NPC_FACT])
        self.assertEqual(speaker[1]["required_prior_choice_id"], "note_current")
        self.assertNotIn("assertion_id", speaker[1])
        self.assertEqual(prov["npc_social"]["item_grants"][0]["choice_id"],
                         "take_rope")
        self.assertEqual(prov["npc_social"]["item_transfers"][0]["choice_id"],
                         "pull_up")
        signed = prov["presentation"]["scene_dialogues"]["rescue_decision"]
        self.assertEqual(signed["turns"][0]["speaker"], "Лена")
        self.assertEqual(signed["turns"][1]["speaker"], "Лодочник")
        self.assertEqual(len(bp["scenes"]), 8)
        self.assertTrue(bp["book_id"].startswith("npc_scene_"))

    def test_readonly_audit_requires_real_native_build_later(self):
        report = audited_extension(
            self.root, self.overlay, self.fixture(), npc_review=self.npc_review)
        self.assertEqual(report["npc_item_transfers_reviewed"], 1)
        self.assertFalse(report["dialogue_redaction_verified_by_native"])
        self.assertFalse(list(self.private.glob("*.bworld")))

    def test_bad_source_approvals_and_speaker_spoofing_rejected(self):
        mutations = [
            ("scene_review_unapproved",
             lambda x: x["npc_scene_review"].__setitem__(
                 "base_npc_act_review_sha256", "a" * 64)),
            ("scene_review_unapproved",
             lambda x: x["npc_scene_review"].__setitem__(
                 "literary_canon_verified", True)),
            ("scene_unknown_actor",
             lambda x: x["npc_scene_review"]["dialogues"][0]["turns"][1].__setitem__(
                 "actor_id", "npc_" + "f" * 32)),
            ("scene_unknown_assertion",
             lambda x: x["npc_scene_review"]["dialogues"][0]["turns"][1].__setitem__(
                 "assertion_id", "bank_rope")),
            ("scene_invalid_acquisition",
             lambda x: x["npc_scene_review"]["item_grants"][0].__setitem__(
                 "choice_id", "rescue")),
            ("scene_unknown_actor",
             lambda x: x["npc_scene_review"]["item_transfers"][0].__setitem__(
                 "to_actor_id", "npc_" + "f" * 32)),
            ("scene_unknown_assertion",
             lambda x: x["npc_scene_review"]["item_transfers"][0].__setitem__(
                 "assertion_id", "bank_helpers")),
            ("scene_dialogue_mismatch",
             lambda x: x["npc_scene_review"]["dialogues"][0]["turns"][1].__setitem__(
                 "speaker", "Лжевестник")),
        ]
        for code, mutate in mutations:
            with self.subTest(code=code):
                candidate = self.fixture()
                mutate(candidate)
                with self.assertRaises(AuthoringError) as e:
                    self.expand(candidate)
                self.assertEqual(e.exception.code, code)

    def test_inventory_requires_same_choice_native_typed_consume(self):
        candidate = self.fixture()
        pull_up = candidate["acts"][1]["scenes"][1]["choices"][0]
        pull_up["effects"] = [
            e for e in pull_up["effects"] if e["op"] != "consume_item"]
        pull_up["effect_assertion_ids"] = pull_up["effect_assertion_ids"][:1]
        with self.assertRaises(AuthoringError) as e:
            self.expand(candidate)
        self.assertEqual(e.exception.code, "scene_invalid_transfer")

    def test_missing_speaker_review_cannot_be_inferred_by_name(self):
        candidate = self.fixture()
        candidate["npc_scene_review"]["dialogues"] = []
        with self.assertRaises(AuthoringError) as e:
            self.expand(candidate)
        self.assertEqual(e.exception.code, "scene_review_incomplete")
        candidate = self.fixture()
        candidate["npc_scene_review"]["dialogues"][0]["turns"][1]["turn_index"] = 0
        with self.assertRaises(AuthoringError) as e:
            self.expand(candidate)
        self.assertEqual(e.exception.code, "scene_dialogue_mismatch")
        candidate = self.fixture()
        candidate["acts"][1]["scenes"][0]["text"] = "Неподписанный разговор."
        with self.assertRaises(AuthoringError) as e:
            self.expand(candidate)
        self.assertEqual(e.exception.code, "scene_dialogue_missing")

    def test_item_grant_must_precede_transfer(self):
        candidate = self.fixture()
        candidate["npc_scene_review"]["item_grants"][0]["scene_id"] = "rope_rescue"
        with self.assertRaises(AuthoringError) as e:
            self.expand(candidate)
        self.assertEqual(e.exception.code, "scene_invalid_acquisition")
        candidate = self.fixture()
        candidate["npc_scene_review"]["item_transfers"][0]["from_actor_id"] = ACTOR
        with self.assertRaises(AuthoringError) as e:
            self.expand(candidate)
        self.assertEqual(e.exception.code, "scene_invalid_transfer")


if __name__ == "__main__":
    unittest.main()
