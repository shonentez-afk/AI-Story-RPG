"""One-stage multi-act completion gate, synthetic FB2 only.

The standalone Python tests verify exact review/source/route claims and
no-overwrite behavior; real Dart/SQLite replay runs in run_dart_parity.py.
No user's book is placed in the public test repository.
"""
from __future__ import annotations

from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.rpg_author import project
from tools.rpg_author.cli import parser
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.complete_game import (
    REVIEW_FORMAT, REPORT_FORMAT, ROUTE_RESULT_FORMAT,
    finalize_extended_campaign, review_complete_campaign,
    verify_route_evidence,
)
from tools.rpg_author.rich_package import compile_rich_from_project
from tools.rpg_author.v4_acts import extend_checked_world
from tests.rpg_author import fixtures_acts as book
from tests.rpg_author.fixtures_npc_scene_items import (
    reviewed_base_with_owned_item, reviewed_dialogue_and_custody,
)

CAREFUL_ROUTE = [
    "take_rope", "study_bridge", "note_current",
    "rescue", "careful_route", "pull_up",
]
HELP_ROUTE = ["leave_rope", "call_help"]


def reviewed_campaign_fixture(blueprint, provenance, extension):
    """A separately DECLARED complete synthetic-book editorial pass."""
    return {
        "format": REVIEW_FORMAT,
        "source_fingerprint": blueprint["source_fingerprint"],
        "extension_sha256": digest(canonical(extension)),
        "blueprint_sha256": digest(canonical(blueprint)),
        "user_confirmed": True,
        "review_method": "independent_ai_pass",
        "review_completed": True,
        "literary_canon_verified": False,
        "aspects": {
            aspect: "pass" for aspect in (
                "motivation", "knowledge", "items", "causality",
                "chronology", "endings",
            )
        },
        "issues": [],
        "scenes": [
            {
                "scene_id": origin["scene_id"],
                "verdict": "pass",
                "notes": "Отдельно проверены причина выбора и источник в этой сцене.",
                "source_quote_sha256": sorted({
                    ref["quote_sha256"] for ref in origin["source_refs"]
                }),
            }
            for origin in provenance["scene_origins"]
        ],
        "routes": [
            {
                "id": "careful_rescue",
                "choice_ids": CAREFUL_ROUTE,
                "expected_ending_scene_id": "safe",
                "notes": "Проверена самостоятельная концовка со спасением и передачей верёвки.",
            },
            {
                "id": "call_for_help",
                "choice_ids": HELP_ROUTE,
                "expected_ending_scene_id": "help",
                "notes": "Проверена другая достижимая концовка через вызов помощи.",
            },
        ],
    }


class CompleteBookCampaignReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        source = root / book.SOURCE_FILENAME
        source.write_text(book.SOURCE, encoding="utf-8")
        self.author = root / "project"
        project.init_project(self.author, source)
        for chunk in book.analyses():
            project.submit_analysis(self.author, chunk)
        project.submit_story(self.author, book.story_plan())
        self.overlay, self.review_npc = reviewed_base_with_owned_item()
        raw, _ = compile_rich_from_project(
            self.author, self.overlay, npc_review=self.review_npc)
        with zipfile.ZipFile(io.BytesIO(raw)) as packaged:
            bp = json.loads(packaged.read("scenario/blueprint.json"))
            prov = json.loads(packaged.read("source/provenance.json"))
        self.extension = reviewed_dialogue_and_custody(
            bp, prov, self.overlay)
        self.blueprint, self.provenance, self.extension_preflight = (
            extend_checked_world(bp, prov, book.story_plan(), self.overlay,
                                 book.index(), book.analyses(), self.extension))
        self.review = reviewed_campaign_fixture(self.blueprint,
                                                self.provenance, self.extension)

    def checked(self, review=None, *, blueprint=None, provenance=None,
                extension=None):
        return review_complete_campaign(
            review if review is not None else self.review,
            blueprint if blueprint is not None else self.blueprint,
            provenance if provenance is not None else self.provenance,
            extension if extension is not None else self.extension)

    def test_all_eight_scenes_and_all_chapters_reported_without_canon_claim(self):
        proof = self.checked()
        self.assertEqual(proof["verified_scene_review_records"], 8)
        self.assertEqual(proof["reviewed_book_chapters"], 3)
        self.assertEqual(proof["source_chapters_with_gameplay"], 3)
        self.assertEqual(proof["reviewed_full_routes"], 2)
        self.assertFalse(proof["literary_truth_attested"])
        self.assertTrue(proof["author_report_cannot_prove_literary_quality"])
        self.assertEqual(self.extension_preflight["chapters_without_source_scenes"], [])

    def test_stale_revision_source_and_incomplete_scene_reviews_fail_closed(self):
        cases = [
            ("campaign_review_stale",
             lambda x: x["review"].update(extension_sha256="0"*64)),
            ("campaign_review_stale",
             lambda x: x["review"].update(blueprint_sha256="0"*64)),
            ("campaign_review_stale",
             lambda x: x["review"].update(literary_canon_verified=True)),
            ("campaign_review_stale",
             lambda x: x["review"]["aspects"].update(chronology="unchecked")),
            ("campaign_review_scene_missing",
             lambda x: x["review"]["scenes"].pop()),
            ("campaign_source_review_mismatch",
             lambda x: x["review"]["scenes"][0].update(
                 source_quote_sha256=["f"*64])),
            ("campaign_review_notes_missing",
             lambda x: x["review"]["scenes"][0].update(notes="pass")),
            ("campaign_route_review_invalid",
             lambda x: x["review"]["routes"][1].update(id="careful_rescue")),
            ("campaign_route_review_invalid",
             lambda x: x["review"]["routes"][1].update(
                 expected_ending_scene_id="safe")),
            ("campaign_route_review_invalid",
             lambda x: x["review"]["routes"][1].update(
                 choice_ids=CAREFUL_ROUTE)),
            ("campaign_not_multi_act",
             lambda x: (
                 x["extension"].update(acts=x["extension"]["acts"][:1]),
                 x["review"].update(
                     extension_sha256=digest(canonical(x["extension"]))))),
        ]
        for code, mutate in cases:
            with self.subTest(code=code):
                data = {
                    "review": deepcopy(self.review),
                    "extension": deepcopy(self.extension),
                }
                mutate(data)
                with self.assertRaises(AuthoringError) as err:
                    self.checked(data["review"], extension=data["extension"])
                self.assertEqual(err.exception.code, code)

    def test_missing_real_chapter_rejected_even_with_all_review_rows(self):
        source = deepcopy(self.provenance)
        target = [s for s in source["scene_origins"]
                  if s["chapter_index"] == 2]
        for row in target:
            row["origin"] = "EXPLICIT_ADAPTATION"
        with self.assertRaises(AuthoringError) as err:
            self.checked(provenance=source)
        self.assertEqual(err.exception.code, "campaign_chapters_uncovered")

    def test_engine_response_must_have_same_archive_and_both_endings(self):
        raw = b"exact native-verified bytes"
        response = {
            "format": ROUTE_RESULT_FORMAT,
            "archive_sha256": digest(raw),
            "true_rpg_api": True,
            "native_sqlite_portable_saves": True,
            "verified_routes": [
                {
                    "id": route["id"],
                    "choice_ids": route["choice_ids"],
                    "scene_ids": ["road"] *
                    len(route["choice_ids"]) +
                    [route["expected_ending_scene_id"]],
                    "ending_scene_id": route["expected_ending_scene_id"],
                    "terminal": True,
                    "portable_save_verified": True,
                    "revisions": len(route["choice_ids"]),
                    "journal_count": len(route["choice_ids"]),
                    "state_hash": "a"*64,
                    "visible_npc_item_owners": {},
                }
                for route in self.review["routes"]
            ],
        }
        accepted = verify_route_evidence(response, self.review["routes"],
                                         self.blueprint, self.provenance, raw)
        self.assertEqual(accepted["route_count"], 2)
        self.assertTrue(accepted["native_game_rules_reused"])
        for mutation in (
            lambda x: x.update(archive_sha256="0"*64),
            lambda x: x["verified_routes"][1].update(
                ending_scene_id="safe"),
            lambda x: x["verified_routes"][0].update(
                portable_save_verified=False),
            lambda x: x["verified_routes"][0].update(
                choice_ids=HELP_ROUTE),
            lambda x: x["verified_routes"][0].update(
                scene_ids=["fake_scene"]*7),
        ):
            with self.subTest(mutation=mutation):
                bad = deepcopy(response)
                mutation(bad)
                with self.assertRaises(AuthoringError) as err:
                    verify_route_evidence(bad, self.review["routes"],
                                          self.blueprint, self.provenance, raw)
                self.assertEqual(err.exception.code, "native_route_invalid_response")

    def test_one_command_requires_explicit_private_inputs_and_no_overwrite(self):
        args = parser().parse_args([
            "finalize-extended",
            "--project", "/private/project",
            "--enrichment", "/private/overlay.json",
            "--extension", "/private/multi_acts.json",
            "--review", "/private/editorial.json",
            "--output", "/private/game.bworld",
            "--no-interactive-questions",
        ])
        self.assertEqual(args.command, "finalize-extended")
        self.assertTrue(args.no_interactive_questions)
        root = Path(self.temp.name)
        world = root / "existing.bworld"
        world.write_bytes(b"do not overwrite")
        with self.assertRaises(AuthoringError) as err:
            finalize_extended_campaign(
                self.author, root / "overlay.json", root / "extension.json",
                root / "review.json", world,
                no_interactive_questions=True)
        self.assertEqual(err.exception.code, "output_exists")
        self.assertEqual(world.read_bytes(), b"do not overwrite")
        self.assertFalse((root / "existing.attribution.json").exists())

    def test_no_questions_is_a_declaration_not_proof(self):
        self.assertNotIn("literary_truth_attested", self.review)
        self.assertNotIn("user_ready", self.review)
        self.assertTrue(self.review["user_confirmed"])
        self.assertEqual(REPORT_FORMAT,
                         "rpg_author_complete_native_campaign_acceptance_v1")


if __name__ == "__main__":
    unittest.main()
