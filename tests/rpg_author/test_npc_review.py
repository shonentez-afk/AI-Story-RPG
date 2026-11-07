"""E6f: synthetic source-reviewed NPC social-v5 authoring and negative tests.

No real book, private text, or claimed literary canon is used in CI.
"""
from __future__ import annotations

from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.bookworld import private_rich_bookworld as rich
from tools.rpg_author import project
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.rich_package import (compile_rich_from_project,
                                           build_rich, verify_rich_bundle)
from tools.rpg_author.npc_review import validate_review
from tests.rpg_author.fixtures import TEXT, source, story, analysis
from tests.rpg_author.fixtures_rich import enrichment

ACTOR = "npc_" + "c" * 32
FACT = "npc_remembered_source"


def reviewed_fixture():
    """Source-sha, scene ID, choice ID, NPC ID and consent all match exactly."""
    src, plan = source(), story()
    overlay = enrichment()
    overlay["facts"][FACT] = "Литературно проверенное свидетельство персонажа"
    overlay["choices"]["take_rope"]["effects"].append(
        {"op": "learn_fact", "id": FACT, "actor": ACTOR})
    quote = digest(TEXT.encode("utf-8"))
    social = {
        "format": rich.NPC_SOCIAL_LIFE_FORMAT,
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": src["source_fingerprint"],
        "user_confirmed": True,
        "literary_canon_verified": False,
        "witnesses": [{
            "scene_id": "road", "actor_id": ACTOR, "mode": "present",
            "source_quote_sha256": quote}],
        "rules": [{
            "memory_id": "road_witness", "scene_id": "road",
            "choice_id": "take_rope", "observer_id": ACTOR,
            "kind": "witnessed", "related_actor_id": "player",
            "relationship_delta": 1, "max_triggers": 1,
            "source_quote_sha256": quote}],
        "choice_gates": [], "item_transfers": [], "item_grants": [],
        "life_transitions": [{
            "scene_id": "road", "choice_id": "take_rope",
            "actor_id": ACTOR, "next_state": "absent",
            "source_quote_sha256": quote}],
    }
    reviewed = {
        "format": "rpg_author_reviewed_npc_overlay_v1",
        "source_fingerprint": src["source_fingerprint"],
        "story_sha256": digest(canonical(plan)),
        "enrichment_sha256": digest(canonical(overlay)),
        "actors": [ACTOR],
        "npc_knowledge": {
            "format": rich.NPC_GRANTS_FORMAT,
            "review_scope": "user_declared_private_game_fiction",
            "source_fingerprint": src["source_fingerprint"],
            "user_confirmed": True, "literary_canon_verified": False,
            "grants": [{
                "scene_id": "road", "choice_id": "take_rope",
                "actor_id": ACTOR, "fact_id": FACT,
                "source_quote_sha256": quote,
            }],
        },
        "npc_social": social,
        "dialogue_knowledge": {},
    }
    return overlay, reviewed


def reviewed_transfer_fixture():
    """Same exact source: item grant, custody transfer, NPC then departs."""
    plan = story()
    river = next(scene for scene in plan["scenes"] if scene["id"] == "river")
    river["origin"] = "SOURCE_PASSAGE"
    river["assertion_ids"] = ["rescue_event"]
    overlay, reviewed = reviewed_fixture()
    overlay["story_sha256"] = digest(canonical(plan))
    reviewed["story_sha256"] = digest(canonical(plan))
    reviewed["enrichment_sha256"] = digest(canonical(overlay))
    quote = digest(TEXT.encode("utf-8"))
    social = reviewed["npc_social"]
    social["witnesses"].append({
        "scene_id": "river", "actor_id": ACTOR, "mode": "present",
        "source_quote_sha256": quote,
    })
    social["item_grants"] = [{
        "scene_id": "road", "choice_id": "take_rope",
        "item_id": "rope", "source_quote_sha256": quote,
    }]
    social["item_transfers"] = [{
        "scene_id": "river", "choice_id": "rescue", "item_id": "rope",
        "from_actor_id": "player", "to_actor_id": ACTOR,
        "source_quote_sha256": quote,
    }]
    social["life_transitions"][0]["scene_id"] = "river"
    social["life_transitions"][0]["choice_id"] = "rescue"
    return plan, overlay, reviewed


class ReviewedSocialV5Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        book = self.base / "test_story.txt"
        book.write_text(TEXT, encoding="utf-8")
        self.root = self.base / "project"
        project.init_project(self.root, book)
        project.submit_analysis(self.root, analysis())
        project.submit_story(self.root, story())
        self.overlay, self.review = reviewed_fixture()

    def test_writer_verifier_sidecar_and_deterministic_identity(self):
        actors = validate_review(self.review, story(), source(), self.overlay)
        self.assertEqual(actors, [ACTOR])
        raw, attestation = compile_rich_from_project(
            self.root, self.overlay, npc_review=self.review)
        second, _ = compile_rich_from_project(
            self.root, self.overlay, npc_review=self.review)
        self.assertEqual(raw, second)
        self.assertEqual(rich.verify(raw)["format_version"], 3)
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            self.assertEqual(z.namelist(), list(rich.PATHS))
            manifest = json.loads(z.read("manifest.json"))
            blueprint = json.loads(z.read("scenario/blueprint.json"))
            prov = json.loads(z.read("source/provenance.json"))
            self.assertEqual(manifest["npc_social_format"], rich.NPC_SOCIAL_LIFE_FORMAT)
            self.assertEqual(manifest["npc_knowledge_format"], rich.NPC_GRANTS_FORMAT)
            self.assertEqual(blueprint["actors"], ["player", ACTOR])
            self.assertEqual(blueprint["initial_state"]["knowledge"][ACTOR], [])
            self.assertEqual(prov["npc_social"]["life_transitions"][0]["next_state"], "absent")
        plain_overlay = deepcopy(self.overlay)
        del plain_overlay["facts"][FACT]
        plain_overlay["choices"]["take_rope"]["effects"] = [
            effect for effect in plain_overlay["choices"]["take_rope"]["effects"]
            if effect.get("actor", "player") == "player"]
        plain, _ = compile_rich_from_project(self.root, plain_overlay)
        with zipfile.ZipFile(io.BytesIO(plain)) as z:
            old_identity = json.loads(z.read("scenario/blueprint.json"))["book_id"]
        self.assertNotEqual(old_identity, blueprint["book_id"])
        target = self.base / "world.bworld"
        target.write_bytes(raw)
        attribution = self.base / "world.attribution.json"
        attribution.write_bytes(attestation)
        self.assertTrue(verify_rich_bundle(target, attribution)["attribution_matches_archive"])

    def test_real_build_cli_facade_and_no_overwrite(self):
        overlay = self.base / "enrichment.json"
        review = self.base / "npc_review.json"
        overlay.write_bytes(canonical(self.overlay))
        review.write_bytes(canonical(self.review))
        target = self.base / "game.bworld"
        result = build_rich(self.root, overlay, target, npc_review_path=review)
        self.assertTrue(target.is_file())
        self.assertEqual(result["status"], "private_rich_v3_built")
        self.assertTrue(verify_rich_bundle(target, target.with_suffix(".attribution.json"))
                        ["attribution_matches_archive"])
        with self.assertRaises(AuthoringError) as err:
            build_rich(self.root, overlay, target, npc_review_path=review)
        self.assertEqual(err.exception.code, "output_exists")

    def test_source_locked_v5_item_custody_transfer_and_lifecycle(self):
        plan, overlay, reviewed = reviewed_transfer_fixture()
        project.submit_story(self.root, plan, replace=True)
        raw, sidecar = compile_rich_from_project(
            self.root, overlay, npc_review=reviewed)
        self.assertEqual(rich.verify(raw)["format_version"], 3)
        with zipfile.ZipFile(io.BytesIO(raw)) as bundle:
            blueprint = json.loads(bundle.read("scenario/blueprint.json"))
            social = json.loads(bundle.read("source/provenance.json"))["npc_social"]
        self.assertEqual(blueprint["items"], ["rope"])
        self.assertEqual(social["item_grants"][0]["choice_id"], "take_rope")
        self.assertEqual(social["item_transfers"][0]["to_actor_id"], ACTOR)
        self.assertEqual(social["life_transitions"][0]["next_state"], "absent")
        self.assertNotIn("item_owner", blueprint["initial_state"])
        forged = deepcopy(reviewed)
        forged["npc_social"]["item_grants"][0]["source_quote_sha256"] = "f" * 64
        with self.assertRaises(AuthoringError):
            compile_rich_from_project(self.root, overlay, npc_review=forged)
        omitted = deepcopy(reviewed)
        omitted["npc_social"]["item_grants"] = []
        with self.assertRaises(AuthoringError):
            compile_rich_from_project(self.root, overlay, npc_review=omitted)

    def test_nonconsensual_stale_forged_and_incomplete_reviews_are_rejected(self):
        variants = (
            ("wrong_story", lambda x: x.__setitem__("story_sha256", "f" * 64)),
            ("wrong_overlay", lambda x: x.__setitem__("enrichment_sha256", "f" * 64)),
            ("bad_actor", lambda x: x.__setitem__("actors", ["npc_bad"])),
            ("actor_order", lambda x: x.__setitem__("actors", [ACTOR, ACTOR])),
            ("unapproved_social", lambda x: x["npc_social"].__setitem__("user_confirmed", False)),
            ("unapproved_grant", lambda x: x["npc_knowledge"].__setitem__("user_confirmed", False)),
            ("future_quote", lambda x: x["npc_social"]["life_transitions"][0].__setitem__(
                "source_quote_sha256", "f" * 64)),
            ("new_life_state", lambda x: x["npc_social"]["life_transitions"][0].__setitem__(
                "next_state", "resurrected")),
            ("phantom_choice", lambda x: x["npc_social"]["life_transitions"][0].__setitem__(
                "choice_id", "phantom")),
            ("downgraded_life", lambda x: x["npc_social"].__setitem__(
                "format", rich.NPC_SOCIAL_AUTHOR_ITEM_FORMAT)),
            ("missing_knowledge", lambda x: x.__setitem__("npc_knowledge", {})),
            ("unsigned_fake_history", lambda x: x["dialogue_knowledge"].__setitem__(
                "road", [])),
        )
        for name, mutate in variants:
            with self.subTest(name=name):
                review = deepcopy(self.review)
                mutate(review)
                with self.assertRaises((AuthoringError, ValueError)):
                    compile_rich_from_project(self.root, self.overlay,
                                              npc_review=review)


if __name__ == "__main__":
    unittest.main()
