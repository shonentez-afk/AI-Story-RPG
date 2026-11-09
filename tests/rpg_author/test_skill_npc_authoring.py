"""Complete ChatGPT Skill -> native NPC source authoring acceptance.

A fictional three-chapter FB2 is used. Real private books never enter CI.
The pinned Python writer, actual v4 author and Dart parity remain authority.
"""
from __future__ import annotations

from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tests.rpg_author import fixtures_acts as book
from tests.rpg_author.fixtures_npc_acts import (
    ACTOR, NPC_FACT, reviewed_npc_acts,
)
from tools.rpg_author import project
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.npc_skill import (
    DOSSIERS_FORMAT, REVIEW_FORMAT, prepare_npc_dossiers,
    prepare_npc_review, prepare_npc_v4_extension, verify_source_dossiers,
)
from tools.rpg_author.rich_package import compile_rich_from_project
from tools.rpg_author.native_v4_bridge import audited_extension


class SkillAuthorNpcTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        file = self.root / book.SOURCE_FILENAME
        file.write_text(book.SOURCE, encoding="utf-8")
        self.project = self.root / "project"
        project.init_project(self.project, file)
        self.idx = book.index()
        self.story = book.story_plan()
        self.analyses = book.analyses()
        for a in self.analyses:
            project.submit_analysis(self.project, a)
        project.submit_story(self.project, self.story)
        self.cast = {
            "characters": [{
                "ref": "boatman",
                "name": "Лодочник",
                "description": "Лодочник честно предупредил о течении.",
                "source_scene_id": "river",
                "assertion_id": "bridge_warning",
            }],
            "absence_reason": None,
        }
        self.dossiers = prepare_npc_dossiers(
            self.cast, self.idx, self.story, self.analyses)
        self.actor = self.dossiers["characters"][0]["character_id"]
        self.overlay = book.rich_enrichment()
        self.overlay["facts"][NPC_FACT] = "Лодочник знает опасное течение."
        # Source has a matching NPC acquisition effect ONLY after the
        # Skill has produced its persistent character_id.
        self.overlay["choices"]["call_help"]["effects"].append({
            "op": "learn_fact", "id": NPC_FACT, "actor": self.actor,
        })
        neutral = deepcopy(self.overlay)
        neutral["choices"]["call_help"]["effects"].pop()
        base, _ = compile_rich_from_project(self.project, neutral)
        with zipfile.ZipFile(io.BytesIO(base)) as z:
            self.base_bp = json.loads(z.read("scenario/blueprint.json"))
            self.base_prov = json.loads(z.read("source/provenance.json"))
        self.social_proposal = {
            "format": REVIEW_FORMAT,
            "knowledge_grants": [{
                "scene_id": "river", "choice_id": "call_help",
                "actor_id": self.actor, "fact_id": NPC_FACT,
                "assertion_id": "bridge_warning",
            }],
            "witnesses": [{
                "scene_id": "river", "actor_id": self.actor,
                "mode": "present", "assertion_id": "bridge_warning",
            }],
            "rules": [{
                "memory_id": "call_for_help", "scene_id": "river",
                "choice_id": "call_help", "observer_id": self.actor,
                "kind": "witnessed", "related_actor_id": "player",
                "relationship_delta": 0, "max_triggers": 1,
                "assertion_id": "bridge_warning",
            }],
            "choice_gates": [],
            "item_grants": [], "item_transfers": [],
            "life_transitions": [{
                "scene_id": "river", "choice_id": "call_help",
                "actor_id": self.actor, "next_state": "absent",
                "assertion_id": "bridge_warning",
            }],
            "dialogue_knowledge": {},
        }

    def create_review(self, proposal=None, *, consent=True):
        return prepare_npc_review(
            proposal or self.social_proposal, self.dossiers, self.idx,
            self.story, self.analyses, self.overlay,
            self.base_bp, self.base_prov, user_confirmed=consent)

    def test_source_identity_is_deterministic_and_private(self):
        first = self.dossiers["characters"][0]
        self.assertEqual(self.dossiers["format"], DOSSIERS_FORMAT)
        self.assertTrue(first["character_id"].startswith("npc_"))
        self.assertEqual(len(first["character_id"]), 36)
        self.assertEqual(verify_source_dossiers(
            self.dossiers, self.idx, self.story, self.analyses),
            self.dossiers)
        again = prepare_npc_dossiers(self.cast, self.idx,
                                     self.story, self.analyses)
        self.assertEqual(again, self.dossiers)
        self.assertFalse(self.dossiers["canon_identity_verified_by_ai"])

    def test_fake_or_future_speaker_rejected(self):
        for mutator in (
            lambda x: x["characters"][0].update(name="Чужой персонаж"),
            lambda x: x["characters"][0].update(assertion_id="bank_rope"),
            lambda x: x["characters"][0].update(source_scene_id="safe"),
        ):
            bad = deepcopy(self.cast)
            mutator(bad)
            with self.subTest(bad=bad):
                with self.assertRaises(AuthoringError):
                    prepare_npc_dossiers(
                        bad, self.idx, self.story, self.analyses)

    def test_tampered_character_id_is_rejected_during_resume(self):
        altered = deepcopy(self.dossiers)
        altered["characters"][0]["character_id"] = ACTOR
        with self.assertRaises(AuthoringError) as e:
            verify_source_dossiers(altered, self.idx,
                                   self.story, self.analyses)
        self.assertEqual(e.exception.code, "skill_npc_dossiers_stale")

    def test_source_grants_and_witnesses_compile_using_existing_native_v3(self):
        native = self.create_review()
        self.assertEqual(native["actors"], [self.actor])
        self.assertEqual(native["npc_social"]["format"],
                         "ai_story_npc_social_witness_v5")
        self.assertEqual(native["npc_knowledge"]["grants"][0]
                         ["source_quote_sha256"],
                         digest("Лодочник предупредил о течении."
                                .encode("utf-8")))
        raw, _ = compile_rich_from_project(
            self.project, self.overlay, npc_review=native)
        with zipfile.ZipFile(io.BytesIO(raw)) as world:
            bp = json.loads(world.read("scenario/blueprint.json"))
            prov = json.loads(world.read("source/provenance.json"))
        self.assertEqual(bp["actors"], ["player", self.actor])
        self.assertEqual(prov["npc_social"]["witnesses"][0]["actor_id"],
                         self.actor)
        self.assertFalse(prov["npc_social"]["literary_canon_verified"])

    def test_forged_social_approval_or_quote_does_not_pass(self):
        cases = [
            ("skill_npc_source_invalid", lambda x: x["witnesses"][0].update(
                assertion_id="road_found")),
            ("skill_npc_actor_unknown", lambda x: x["rules"][0].update(
                observer_id="npc_" + "f" * 32)),
        ]
        for code, mutate in cases:
            candidate = deepcopy(self.social_proposal)
            mutate(candidate)
            with self.subTest(code=code):
                with self.assertRaises(AuthoringError) as e:
                    self.create_review(candidate)
                self.assertEqual(e.exception.code, code)
        unconfirmed = self.create_review(consent=False)
        self.assertFalse(unconfirmed["npc_social"]["user_confirmed"])
        with self.assertRaises(AuthoringError):
            compile_rich_from_project(
                self.project, self.overlay, npc_review=unconfirmed)

    def test_skill_v4_actor_scoped_review_is_native_cited(self):
        base_npc, _ = compile_rich_from_project(
            self.project, self.overlay, npc_review=self.create_review())
        with zipfile.ZipFile(io.BytesIO(base_npc)) as z:
            bp = json.loads(z.read("scenario/blueprint.json"))
            prov = json.loads(z.read("source/provenance.json"))
        example = reviewed_npc_acts(bp, prov, overlay=self.overlay)
        # Replace the old test actor with a source-derived permanent ID.
        example = json.loads(json.dumps(example).replace(ACTOR, self.actor))
        signed = example["npc_actor_review"]
        stripped = {key: signed[key] for key in (
            "knowledge_grants", "witnesses", "memories", "choice_gates",
            "life_transitions",
        )}
        proposed = {
            "acts": example["acts"],
            "initial_state": example["initial_state"],
            "npc_actor_review": stripped,
        }
        prepared = prepare_npc_v4_extension(
            proposed, self.idx, self.story, self.overlay, bp, prov,
            npc_present=True, user_confirmed=True)
        self.assertEqual(prepared["format"], "rpg_author_v4_acts_v2")
        self.assertEqual(prepared["npc_actor_review"]
                         ["base_npc_social_sha256"],
                         digest(canonical(prov["npc_social"])))
        # Native author tests the ACTUAL rule semantics, not Python copy.
        proof = audited_extension(
            self.project, self.overlay, prepared,
            npc_review=self.create_review())
        self.assertEqual(proof["act_count"], 2)
        self.assertTrue(proof["npc_base_review_locked"])

    def test_no_character_cannot_forge_actor_scoped_v4_proposal(self):
        with self.assertRaises(AuthoringError) as e:
            prepare_npc_v4_extension({
                "acts": [], "initial_state": None,
                "npc_actor_review": {
                    "knowledge_grants": [], "witnesses": [],
                    "memories": [], "choice_gates": [],
                    "life_transitions": [],
                },
            }, self.idx, self.story, self.overlay,
                self.base_bp, self.base_prov,
                npc_present=False, user_confirmed=True)
        self.assertEqual(e.exception.code, "skill_npc_extension_invalid")


if __name__ == "__main__":
    unittest.main()
