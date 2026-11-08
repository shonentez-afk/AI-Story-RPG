"""E6h: source-locked v4 authoring, no private books or fake CANON."""
import io
import json
from pathlib import Path
import tempfile
import unittest
from copy import deepcopy
import zipfile

from tools.rpg_author import project
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.native_v4_bridge import audited_extension
from tools.rpg_author.rich_package import compile_rich_from_project
from tools.rpg_author.v4_expansion import FORMAT, extend_reviewed_world
from tests.rpg_author.fixtures import TEXT, analysis, source, story
from tests.rpg_author.fixtures_rich import enrichment


def proposal(bp, number=199):
    plan, overlay = story(), enrichment()
    return {
        "format": FORMAT,
        "source_fingerprint": source()["source_fingerprint"],
        "story_sha256": digest(canonical(plan)),
        "enrichment_sha256": digest(canonical(overlay)),
        "base_blueprint_sha256": digest(canonical(bp)),
        "editorial_review": {"user_confirmed": True,
                             "transition_causality_reviewed": True,
                             "literary_canon_verified": False},
        "insertions": [{
            "after_choice_id": "take_rope",
            "scenes": [{
                "id": f"passage_{i:03d}",
                "title": f"Переход {i}",
                "text": "Путь к реке, оригинальный синтетический цитируемый фрагмент.",
                "chapter_index": 0,
                "origin": "SOURCE_PASSAGE",
                "assertion_ids": ["rescue_event"],
                "choice_id": f"pass_next_{i:03d}",
                "choice_label": "Продолжить к реке",
            } for i in range(number)],
        }],
        "initial_state": None,
    }


class ReviewedV4ExtensionTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.base = Path(self.dir.name)
        path = self.base / "test_story.txt"
        path.write_text(TEXT, encoding="utf-8")
        self.project = self.base / "project"
        project.init_project(self.project, path)
        project.submit_analysis(self.project, analysis())
        project.submit_story(self.project, story())
        raw, _ = compile_rich_from_project(self.project, enrichment())
        with zipfile.ZipFile(io.BytesIO(raw)) as bundle:
            self.bp = json.loads(bundle.read("scenario/blueprint.json"))
            self.prov = json.loads(bundle.read("source/provenance.json"))
        self.source_bp = canonical(self.bp)
        self.source_prov = canonical(self.prov)

    def expand(self, plan):
        return extend_reviewed_world(
            self.bp, self.prov, story(), enrichment(),
            source(), [analysis()], plan)

    def test_203_scenes_verified_evidence_and_no_mutation(self):
        bp, origin, qa = self.expand(proposal(self.bp))
        self.assertEqual(qa["added_scenes"], 199)
        self.assertEqual(qa["total_scenes"], 203)
        self.assertFalse(qa["native_causality_verified"])
        self.assertFalse(qa["literary_canon_verified"])
        self.assertEqual(len(origin["scene_origins"]), 203)
        self.assertEqual(bp["scenes"][0]["choices"][0]["next_scene_id"],
                         "passage_000")
        self.assertEqual(bp["scenes"][199]["choices"][0]["next_scene_id"],
                         "river")
        self.assertEqual(len(origin["presentation"]["scene_names"]), 203)
        self.assertEqual(canonical(self.bp), self.source_bp)
        self.assertEqual(canonical(self.prov), self.source_prov)

    def test_explicit_review_and_hash_binding_are_required(self):
        for key, value, code in (
            ("source_fingerprint", "0" * 64, "extension_mismatch"),
            ("story_sha256", "0" * 64, "extension_mismatch"),
            ("enrichment_sha256", "0" * 64, "extension_mismatch"),
            ("base_blueprint_sha256", "0" * 64, "extension_mismatch"),
        ):
            with self.subTest(key=key):
                data = proposal(self.bp, 1)
                data[key] = value
                with self.assertRaises(AuthoringError) as caught:
                    self.expand(data)
                self.assertEqual(caught.exception.code, code)
        data = proposal(self.bp, 1)
        data["editorial_review"]["user_confirmed"] = False
        with self.assertRaises(AuthoringError) as caught:
            self.expand(data)
        self.assertEqual(caught.exception.code, "extension_not_reviewed")

    def test_reject_unknown_anchor_future_quote_duplicate_and_oversize(self):
        for mutation, code in (
            (lambda p: p["insertions"][0].update(after_choice_id="forged"),
             "invalid_extension_anchor"),
            (lambda p: p["insertions"][0]["scenes"][0].update(
                assertion_ids=["forged"]), "extension_unknown_assertion"),
            (lambda p: p["insertions"][0]["scenes"][0].update(
                id="river"), "duplicate_extension_id"),
            (lambda p: p["insertions"][0]["scenes"][0].update(
                chapter_index=1), "extension_chapter_order"),
        ):
            data = proposal(self.bp, 1)
            mutation(data)
            with self.subTest(code=code), self.assertRaises(AuthoringError) as caught:
                self.expand(data)
            self.assertEqual(caught.exception.code, code)
        data = proposal(self.bp, 1000)
        with self.assertRaises(AuthoringError) as caught:
            self.expand(data)
        self.assertEqual(caught.exception.code, "extended_scene_count")

    def test_opening_item_and_actor_fact_require_first_chapter_witness(self):
        data = proposal(self.bp, 1)
        data["initial_state"] = {
            "tick": 2,
            "items": [{"item_id": "rope", "assertion_id": "rescue_event"}],
            "facts": [{"actor_id": "player", "fact_id": "rescue_fact",
                       "assertion_id": "rescue_event"}],
        }
        bp, prov, report = self.expand(data)
        self.assertEqual(bp["initial_state"]["tick"], 2)
        self.assertEqual(bp["initial_state"]["inventory"], ["rope"])
        self.assertEqual(bp["initial_state"]["knowledge"]["player"], ["rescue_fact"])
        self.assertEqual(prov["initial_state_review"]["user_confirmed"], True)
        self.assertEqual(report["initial_items"], 1)
        data["initial_state"]["items"][0]["assertion_id"] = "forged"
        with self.assertRaises(AuthoringError) as caught:
            self.expand(data)
        self.assertEqual(caught.exception.code, "initial_future_evidence")

    def test_read_only_preflight_does_not_write_game_archive(self):
        result = audited_extension(self.project, enrichment(), proposal(self.bp, 1))
        self.assertEqual(result["total_scenes"], 5)
        self.assertFalse(result["native_causality_verified"])
        self.assertFalse(list(self.base.glob("*.bworld")))


if __name__ == "__main__":
    unittest.main()
