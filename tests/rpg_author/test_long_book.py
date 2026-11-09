"""201 chapters in one source-locked native world: bounded long-book QA."""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tests.rpg_author import long_book_fixture as novel
from tools.rpg_author.auto_author import (
    _full_chapter_coverage, _source_analysis, author_complete_book,
)
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.long_book import (
    MAX_LONG_CHAPTERS, chapter_windows, review_chapter_window,
    verify_chapter_window, outline_context,
    check_long_backbone, verify_featured_gameplay,
)
from tools.rpg_author.source_adapter import make_index, parse_book
from tools.rpg_author.validate import assertion_registry, validate_story


class LargeBookPlanningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.idx = make_index(parse_book(
            novel.SOURCE_FILENAME, novel.SOURCE.encode("utf-8")))
        assert cls.idx["chapter_count"] == novel.COUNT
        assert len(cls.idx["chunks"]) == novel.COUNT
        cls.analyses = [
            _source_analysis({
                "summary": "Действие в исходной синтетической главе.",
                "assertions": [{
                    "statement": "Путница увидела очередную отметку",
                    "kind": "NARRATED", "quote": chunk["text"],
                }],
                "unresolved": [],
            }, chunk, cls.idx["source_fingerprint"], ordinal)
            for ordinal, chunk in enumerate(cls.idx["chunks"])
        ]
        cls.windows = chapter_windows(cls.idx, cls.analyses)

    def reviewed(self):
        return [
            review_chapter_window(
                novel.FakeLongSourceLockedAuthor().ask(
                    "chapter_outline", request),
                request)
            for request in self.windows
        ]

    def test_201_chapters_in_bounded_skill_windows_and_checkpoints(self):
        self.assertEqual(len(self.windows), 26)
        self.assertEqual(self.windows[-1]["chapter_end"], 200)
        results = self.reviewed()
        for record, request in zip(results, self.windows):
            self.assertEqual(verify_chapter_window(record, request), record)
        context = outline_context(results, self.idx, self.analyses)
        self.assertEqual(len(context), 201)
        self.assertEqual(context[-1]["featured"][0]["assertion_id"],
                         novel.aid(200))

    def test_claim_drop_and_fake_chapter_rejected(self):
        request = self.windows[0]
        answer = novel.FakeLongSourceLockedAuthor().ask(
            "chapter_outline", request)
        answer["chapters"][0]["featured_assertion_ids"] = []
        with self.assertRaises(AuthoringError) as cm:
            review_chapter_window(answer, request)
        self.assertEqual(cm.exception.code, "long_book_source_events_dropped")
        answer = novel.FakeLongSourceLockedAuthor().ask(
            "chapter_outline", request)
        answer["chapters"][-1]["chapter_index"] += 1
        with self.assertRaises(AuthoringError):
            review_chapter_window(answer, request)

    def test_narrated_fact_deferred_must_be_explicitly_tracked(self):
        request = deepcopy(self.windows[0])
        request["chapters"][0]["chunks"][0]["claims"].append({
            "assertion_id": "extra_narrated_claim",
            "kind": "NARRATED",
            "statement": "Ещё одно оригинальное событие",
            "quote": "Путница увидела вторую отметку",
        })
        answer = novel.FakeLongSourceLockedAuthor().ask(
            "chapter_outline", request)
        # The synthetic author initially selects both narrated facts.
        # Deliberately DROP the second claim so the negative test really
        # exercises silent omission instead of a valid complete outline.
        answer["chapters"][0]["featured_assertion_ids"] = [
            novel.aid(0)
        ]
        with self.assertRaises(AuthoringError) as missing:
            review_chapter_window(answer, request)
        self.assertEqual(missing.exception.code,
                         "long_book_source_events_dropped")
        answer["chapters"][0]["deferred_assertion_ids"] = [
            "extra_narrated_claim"
        ]
        answer["chapters"][0]["deferred_reason"] = (
            "В книге событие есть, но для короткой RPG сцены пока "
            "выбрана другая развилка, поэтому его нельзя скрывать.")
        accepted = review_chapter_window(answer, request)
        self.assertEqual(accepted["chapters"][0]["deferred_assertion_ids"],
                         ["extra_narrated_claim"])

    def test_sparse_base_story_validated_but_not_mistaken_for_final_book(self):
        story = novel.backbone(self.idx)
        validate_story(story, self.idx, self.analyses)
        report = check_long_backbone(story, self.idx, self.analyses)
        self.assertEqual(report["missing_chapters_to_fill"], 197)
        self.assertEqual(len(report["insertable_source_gaps"]), 3)
        _full_chapter_coverage(story, self.idx, self.analyses)
        broken = deepcopy(story)
        broken["scenes"][1]["assertion_ids"] = [novel.aid(0)]
        with self.assertRaises(AuthoringError) as err:
            check_long_backbone(broken, self.idx, self.analyses)
        self.assertEqual(err.exception.code, "long_book_anchor_quote_missing")
        broken = deepcopy(story)
        broken["scenes"][0]["choices"][0]["next_scene_id"] = "other_end"
        with self.assertRaises(AuthoringError) as err:
            check_long_backbone(broken, self.idx, self.analyses)
        self.assertEqual(err.exception.code,
                         "long_book_anchor_not_insertable")

    def test_every_selected_chapter_event_must_reach_native_provenance(self):
        reviews = self.reviewed()
        registry = assertion_registry(self.analyses, self.idx)
        scenes = []
        for chapter in range(novel.COUNT):
            claim = novel.aid(chapter)
            key = canonical({
                "source_fingerprint": self.idx["source_fingerprint"],
                "chunk_id": registry[claim]["chunk"]["id"],
                "assertion_id": claim,
            })
            scenes.append({
                "scene_id": "chapter_%03d" % chapter,
                "chapter_index": chapter,
                "origin": "SOURCE_PASSAGE",
                "assertion_ids": [digest(b"claim:" + key)[:32]],
            })
        report = verify_featured_gameplay(
            self.idx, self.analyses, reviews, {"scene_origins": scenes})
        self.assertEqual(report["featured_source_events_in_game"], 201)
        self.assertEqual(report["deferred_original_events_not_attested_as_playable"],
                         0)
        with self.assertRaises(AuthoringError) as err:
            verify_featured_gameplay(
                self.idx, self.analyses, reviews, {
                    "scene_origins": scenes[:-1]})
        self.assertEqual(err.exception.code, "long_book_featured_event_missing")

    def test_dense_chapter_windows_shrink_without_dropping_any_source(self):
        first = self.windows[0]
        one = {**first, "window_id": "w0000_0000",
               "chapter_end": 0, "chapters": first["chapters"][:1]}
        two = {**first, "window_id": "w0000_0001",
               "chapter_end": 1, "chapters": first["chapters"][:2]}
        ceiling = (len(canonical(one)) + len(canonical(two))) // 2
        self.assertLess(len(canonical(one)), ceiling)
        self.assertLess(ceiling, len(canonical(two)))
        with patch("tools.rpg_author.long_book.MAX_WINDOW_BYTES", ceiling):
            slices = chapter_windows(self.idx, self.analyses)
        self.assertEqual(slices[0]["chapter_end"], 0)
        self.assertEqual(len(slices), novel.COUNT)
        self.assertEqual(slices[-1]["chapter_end"], novel.COUNT - 1)
        with patch("tools.rpg_author.long_book.MAX_WINDOW_BYTES", 1):
            with self.assertRaises(AuthoringError) as error:
                chapter_windows(self.idx, self.analyses)
        self.assertEqual(error.exception.code,
                         "long_book_single_chapter_over_budget")

    def test_unsupported_book_refuses_before_any_skill_response(self):
        chapters = "".join(
            "<section><p>Добавочная глава номер %03d.</p></section>" % i
            for i in range(201, MAX_LONG_CHAPTERS + 1))
        long_source = novel.SOURCE.replace(
            "</body>", chapters + "</body>")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source_path = root / "above_bound.fb2"
            source_path.write_text(long_source, encoding="utf-8")
            fake = novel.FakeLongSourceLockedAuthor()
            with self.assertRaises(AuthoringError) as error:
                author_complete_book(
                    book=source_path, project_root=root / "project",
                    workdir=root / "work", output=root / "game.bworld",
                    provider=fake, delegate_review=False)
            self.assertEqual(error.exception.code,
                             "long_book_requires_volumes")
            self.assertEqual(fake.calls, 0)

    def test_beyond_native_book_limit_is_refused_without_truncation(self):
        idx = dict(self.idx, chapter_count=MAX_LONG_CHAPTERS + 1)
        with self.assertRaises(AuthoringError) as cm:
            chapter_windows(idx, self.analyses)
        self.assertEqual(cm.exception.code, "long_book_requires_volumes")

    def test_checkpointed_201_chapter_authoring_before_human_review(self):
        # All source chunks, all 26 Skill windows, base writer, and all three
        # source-verified 197-event acts run. No model API, no fake success.
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / novel.SOURCE_FILENAME
            source.write_text(novel.SOURCE, encoding="utf-8")
            fake = novel.FakeLongSourceLockedAuthor()
            result = author_complete_book(
                book=source, project_root=root / "project",
                workdir=root / "private", output=root / "game.bworld",
                provider=fake, delegate_review=False)
            self.assertEqual(result["status"], "needs_explicit_act_review")
            self.assertFalse((root / "game.bworld").exists())
            self.assertEqual(fake.stages.count("analysis"), 201)
            self.assertEqual(fake.stages.count("chapter_outline"), 26)
            self.assertEqual(fake.stages.count("story"), 1)
            self.assertTrue((root / "private" / "long_backbone.json").exists())
            self.assertEqual(len(list((root / "private").glob(
                "chapter_outline_w*.json"))), 26)


if __name__ == "__main__":
    unittest.main()
