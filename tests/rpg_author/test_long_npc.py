"""E6p source-wide NPCs: late first meeting cannot leak into early game.

All inputs are ORIGINAL 201-chapter synthetic fiction. Python only validates
literary/source contracts; native actor, social memory and SQLite still belong
to the pinned BookWorld/Dart engine, tested separately in dart-parity.
"""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import tempfile
import unittest

from tests.rpg_author import long_book_fixture as plain
from tests.rpg_author import late_npc_book_fixture as late
from tools.rpg_author.auto_author import _source_analysis, author_complete_book
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.long_book import chapter_windows, review_chapter_window
from tools.rpg_author.long_npc import (
    prepare_long_npc_cast, verify_long_npc_cast,
    bind_long_npc_cast, check_native_long_npc_continuity,
)
from tools.rpg_author.source_adapter import make_index, parse_book
from tools.rpg_author.validate import validate_story


class FirstMentionCastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index = make_index(parse_book(
            late.SOURCE_FILENAME, late.SOURCE.encode("utf-8")))
        assert cls.index["chapter_count"] == 201
        cls.analyses = [
            _source_analysis({
                "summary": "Оригинальная синтетическая глава.",
                "assertions": [{
                    "statement": "Встреча и исходное подтверждённое действие",
                    "kind": "NARRATED", "quote": chunk["text"],
                }],
                "unresolved": [],
            }, chunk, cls.index["source_fingerprint"], i)
            for i, chunk in enumerate(cls.index["chunks"])
        ]
        cls.windows = chapter_windows(cls.index, cls.analyses)
        cls.outlines = [
            review_chapter_window(
                plain.FakeLongSourceLockedAuthor().ask("chapter_outline", task),
                task)
            for task in cls.windows
        ]
        cls.late_writer = late.FakeLateNpcAuthor()
        cls.proposal = cls.late_writer.ask("npc_cast", {})
        cls.cast = prepare_long_npc_cast(
            cls.proposal, cls.index, cls.analyses, cls.outlines)

    def test_late_first_source_identity_is_stable_and_bound_to_base_story(self):
        self.assertEqual(len(self.cast["characters"]), 1)
        actor = self.cast["characters"][0]["character_id"]
        self.assertTrue(actor.startswith("npc_"))
        self.assertEqual(verify_long_npc_cast(
            self.cast, self.index, self.analyses, self.outlines), self.cast)
        story = late.late_story()
        story["source_fingerprint"] = self.index["source_fingerprint"]
        validate_story(story, self.index, self.analyses)
        dossier, bound = bind_long_npc_cast(
            self.cast, story, self.index, self.analyses)
        self.assertEqual(dossier["characters"][0]["character_id"], actor)
        self.assertEqual(dossier["characters"][0]["source_scene_id"],
                         "chapter_100")
        self.assertEqual(bound["characters"][0]["first_chapter_index"], 100)
        self.assertNotIn(late.NAME, story["scenes"][0]["text"])

    def test_earlier_name_and_future_quote_cannot_be_first_contact(self):
        forged = deepcopy(self.proposal)
        forged["characters"][0]["first_chapter_index"] = 101
        forged["characters"][0]["identity_assertion_id"] = plain.aid(101)
        with self.assertRaises(AuthoringError) as error:
            prepare_long_npc_cast(
                forged, self.index, self.analyses, self.outlines)
        self.assertEqual(error.exception.code, "long_npc_earlier_mention")
        forged["characters"][0]["first_chapter_index"] = 100
        with self.assertRaises(AuthoringError) as error:
            prepare_long_npc_cast(
                forged, self.index, self.analyses, self.outlines)
        self.assertEqual(error.exception.code, "long_npc_identity_unproven")

    def test_invented_name_and_deferred_identity_rejected(self):
        fake = deepcopy(self.proposal)
        fake["characters"][0]["name"] = "Несуществующий Колдун"
        with self.assertRaises(AuthoringError) as error:
            prepare_long_npc_cast(
                fake, self.index, self.analyses, self.outlines)
        self.assertEqual(error.exception.code, "long_npc_identity_unproven")
        reduced = deepcopy(self.outlines)
        window = next(w for w in reduced if
                      w["chapters"][0]["chapter_index"] <= 100 <=
                      w["chapters"][-1]["chapter_index"])
        chapter = next(c for c in window["chapters"]
                       if c["chapter_index"] == 100)
        chapter["featured_assertion_ids"] = []
        chapter["deferred_assertion_ids"] = [plain.aid(100)]
        chapter["deferred_reason"] = (
            "Персонаж вынесен из игрового обзора: цитата временно "
            "отложена и требует отдельного редакторского решения.")
        with self.assertRaises(AuthoringError) as error:
            prepare_long_npc_cast(
                self.proposal, self.index, self.analyses, reduced)
        self.assertEqual(error.exception.code, "long_npc_identity_deferred")

    def test_missing_anchor_and_premature_name_are_not_accepted(self):
        story = plain.backbone(self.index)
        with self.assertRaises(AuthoringError) as error:
            bind_long_npc_cast(self.cast, story, self.index, self.analyses)
        self.assertEqual(error.exception.code,
                         "long_npc_missing_first_contact_anchor")
        story = late.late_story()
        story["scenes"][1]["text"] += " Лодочник уже прибыл."
        with self.assertRaises(AuthoringError) as error:
            bind_long_npc_cast(self.cast, story, self.index, self.analyses)
        self.assertEqual(error.exception.code, "long_npc_early_spoiler")

    def test_duplicate_identity_and_tampered_checkpoint_are_rejected(self):
        duplicate = deepcopy(self.proposal)
        duplicate["characters"].append(deepcopy(duplicate["characters"][0]))
        with self.assertRaises(AuthoringError):
            prepare_long_npc_cast(
                duplicate, self.index, self.analyses, self.outlines)
        stale = deepcopy(self.cast)
        stale["characters"][0]["character_id"] = "npc_" + "0" * 32
        with self.assertRaises(AuthoringError) as error:
            verify_long_npc_cast(stale, self.index,
                                 self.analyses, self.outlines)
        self.assertEqual(error.exception.code, "long_npc_roster_stale")

    def test_native_witness_and_knowledge_temporal_gate(self):
        story = late.late_story()
        dossier, bound = bind_long_npc_cast(
            self.cast, story, self.index, self.analyses)
        actor = dossier["characters"][0]["character_id"]
        scene_rows = story["scenes"]
        bp = {"actors": ["player", actor],
              "scenes": [{"id": s["id"], "text": s["text"]}
                         for s in scene_rows]}
        source = self.cast["characters"][0]
        prov = {
            "scene_origins": [
                {"scene_id": s["id"], "chapter_index": s["chapter_index"]}
                for s in scene_rows
            ],
            "npc_social": {
                "witnesses": [{
                    "scene_id": "chapter_100", "actor_id": actor,
                    "mode": "present",
                    "source_quote_sha256": source["identity_quote_sha256"],
                }],
                "rules": [],
                "choice_gates": [], "life_transitions": [],
                "item_transfers": [],
            },
            "npc_knowledge": {"grants": [{
                "scene_id": "chapter_100", "actor_id": actor,
            }]},
        }
        report = check_native_long_npc_continuity(
            self.cast, bound, bp, prov)
        self.assertEqual(report["first_source_witnessed_npc_count"], 1)
        broken = deepcopy(prov)
        broken["npc_social"]["witnesses"][0]["source_quote_sha256"] = "0" * 64
        with self.assertRaises(AuthoringError) as error:
            check_native_long_npc_continuity(
                self.cast, bound, bp, broken)
        self.assertEqual(error.exception.code,
                         "long_npc_native_first_witness_missing")
        broken = deepcopy(prov)
        broken["npc_knowledge"]["grants"][0]["scene_id"] = "chapter_080"
        with self.assertRaises(AuthoringError):
            check_native_long_npc_continuity(
                self.cast, bound, bp, broken)

    def test_approved_late_npc_compiles_real_base_v3_source_review(self):
        # Native Python writer/importer preflight; on failure this test
        # exposes the EXACT source/social validation, rather than hiding
        # it behind a generic AI retry code in the full Dart parity job.
        from tools.rpg_author import project
        from tools.rpg_author.validate import candidate_blueprint
        from tools.rpg_author.legacy_package import _provenance
        from tools.rpg_author.npc_skill import prepare_npc_review
        from tools.rpg_author.rich_package import compile_rich_from_project

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / late.SOURCE_FILENAME
            source.write_text(late.SOURCE, encoding="utf-8")
            checkpoint = root / "project"
            project.init_project(checkpoint, source)
            for analysis in self.analyses:
                project.submit_analysis(checkpoint, analysis)
            story = late.late_story()
            story["source_fingerprint"] = self.index["source_fingerprint"]
            project.submit_story(checkpoint, story)
            dossier, binding = bind_long_npc_cast(
                self.cast, story, self.index, self.analyses)
            fake = late.FakeLateNpcAuthor()
            overlay = {
                "format": "rpg_author_rich_enrichment_v1",
                "source_fingerprint": self.index["source_fingerprint"],
                "story_sha256": digest(canonical(story)),
                **fake.ask("enrichment", {
                    "story": story, "npc_dossiers": dossier,
                }),
            }
            bp = candidate_blueprint(story, self.index)
            origin = _provenance(story, self.index, self.analyses, bp)
            signed = prepare_npc_review(
                fake.ask("npc_review", {}), dossier, self.index,
                story, self.analyses, overlay, bp, origin,
                user_confirmed=True)
            # A catalog entry that exists ONLY in a future v4 act is
            # invalid at the base v3 compilation boundary. We must never
            # relax this native causal invariant to make a fixture pass.
            broken_overlay = deepcopy(overlay)
            broken_overlay["choices"]["go_100_160"]["effects"] = [
                effect for effect in
                broken_overlay["choices"]["go_100_160"]["effects"]
                if effect["id"] != late.FACT_LATER
            ]
            with self.assertRaises(AuthoringError) as unreachable:
                compile_rich_from_project(
                    checkpoint, broken_overlay, npc_review=signed)
            self.assertEqual(unreachable.exception.code, "rich_compile_rejected")
            self.assertIn("Unreachable item/fact catalog",
                          str(unreachable.exception))
            raw, attribution = compile_rich_from_project(
                checkpoint, overlay, npc_review=signed)
            self.assertTrue(raw.startswith(b"PK"))
            self.assertTrue(attribution)
            self.assertEqual(len(signed["actors"]), 1)

    def test_reproducible_201_chapter_full_skill_queue_to_review_gate(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            book = root / late.SOURCE_FILENAME
            book.write_text(late.SOURCE, encoding="utf-8")
            fake = late.FakeLateNpcAuthor()
            result = author_complete_book(
                book=book, project_root=root / "project",
                workdir=root / "work", output=root / "game.bworld",
                provider=fake, delegate_review=False)
            self.assertEqual(result["status"], "needs_explicit_npc_review")
            self.assertEqual(fake.stages.count("analysis"), 201)
            self.assertEqual(fake.stages.count("chapter_outline"), 26)
            self.assertEqual(fake.stages.count("npc_cast"), 1)
            self.assertEqual(fake.stages.count("npc_review"), 1)
            self.assertEqual(fake.stages.count("npc_dossiers"), 0)
            self.assertFalse((root / "game.bworld").exists())
            self.assertTrue((root / "work" / "long_npc_cast.json").exists())
            self.assertTrue((root / "work" /
                             "long_npc_bound_anchors.json").exists())
            self.assertTrue((root / "work" / "npc_review.json").exists())


if __name__ == "__main__":
    unittest.main()
