"""AI-book authoring QA: original three-chapter FB2, no real user book.

Test resumability, exact-source quotes, private model consent, rejections
and real multi-act v3 preflight. Dart itself is tested in run_dart_parity.py.
"""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from tests.rpg_author import fixtures_acts as book
from tools.rpg_author import project
from tools.rpg_author.ai_provider import (
    PrivateResponseInbox, ZaiProvider, strict_json_response,
)
from tools.rpg_author.auto_author import (
    _source_analysis, author_complete_book,
)
from tools.rpg_author.cli import parser
from tools.rpg_author.common import AuthoringError, canonical
from tools.rpg_author.v4_acts import extend_reviewed_acts
from tools.rpg_author.rich_package import compile_rich_from_project


class FakeSourceLockedAuthor:
    def __init__(self, *, reject_quotes=False):
        self.calls = 0
        self.stages = []
        self.reject_quotes = reject_quotes
        self.mapping = {
            claim: "a_%05d_%02d" % (chapter, index)
            for chapter, group in enumerate(book.ASSERTION_IDS)
            for index, claim in enumerate(group)
        }

    def ask(self, stage, payload, feedback=""):
        self.calls += 1
        self.stages.append(stage)
        if stage == "analysis":
            item = payload["chunk"]
            pos = item["chapter_index"]
            record = book.analyses()[pos]
            proposed = [{
                "statement": c["statement"],
                "kind": c["kind"],
                "quote": c["quote"],
            } for c in record["assertions"]]
            if self.reject_quotes:
                proposed[0]["quote"] = "Этот текст отсутствует в книге"
            return {"summary": record["summary"],
                    "assertions": proposed, "unresolved": []}
        if stage == "story":
            story = deepcopy(book.story_plan())
            for scene in story["scenes"]:
                scene["assertion_ids"] = [
                    self.mapping[x] for x in scene["assertion_ids"]
                ]
            return story
        if stage == "enrichment":
            return book.rich_enrichment(book.index(), payload["story"])
        if stage == "extension":
            extension = book.reviewed_acts(payload["base_blueprint"])
            for act in extension["acts"]:
                for scene in act["scenes"]:
                    scene["assertion_ids"] = [
                        self.mapping[x] for x in scene["assertion_ids"]]
                    for choice in scene["choices"]:
                        choice["effect_assertion_ids"] = [
                            self.mapping[x] for x in choice["effect_assertion_ids"]]
            return {"acts": extension["acts"], "initial_state": None}
        if stage == "literary_review":
            template = payload["review_template"]
            routes = payload["native_discovered_routes"]
            return {
                "aspects": {x: "pass" for x in
                            ("motivation", "knowledge", "items", "causality",
                             "chronology", "endings")},
                "issues": [],
                "scenes": [
                    {"scene_id": row["scene_id"], "verdict": "pass",
                     "notes": "Проверены события, мотивация и источник для этой сцены."}
                    for row in template["scenes"]
                ],
                "routes": [
                    {**row, "notes": "Полный игровой путь проверен через настоящий Dart API."}
                    for row in routes
                ],
            }
        raise AssertionError("unexpected AI stage")


class NoCalls:
    calls = 0
    def ask(self, stage, payload, feedback=""):
        raise AssertionError("Resuming checkpoint must not call model again")


class BookAutopilotTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.source = self.dir / book.SOURCE_FILENAME
        self.source.write_text(book.SOURCE, encoding="utf-8")
        self.project = self.dir / "project"
        self.private = self.dir / "work"
        self.output = self.dir / "ready.bworld"

    def run_author(self, fake, *, delegate=False):
        return author_complete_book(
            book=self.source, project_root=self.project,
            workdir=self.private, output=self.output, provider=fake,
            delegate_review=delegate)

    def test_full_source_analysis_story_enrichment_resume_without_network(self):
        fake = FakeSourceLockedAuthor()
        status = self.run_author(fake)
        self.assertEqual(status["status"], "needs_explicit_act_review")
        self.assertEqual(status["book_chapters_analyzed"], 3)
        self.assertEqual(status["source_chunks_analyzed"], 3)
        self.assertEqual(fake.stages,
                         ["analysis"] * 3 + ["story", "enrichment", "extension"])
        current = project.status(self.project)
        self.assertEqual(current["chunks_with_analysis"], 3)
        self.assertEqual(current["stage"], "validated_candidate")
        self.assertFalse(self.output.exists())
        self.assertTrue((self.private / "enrichment.json").exists())
        self.assertTrue((self.private / "multi_act.json").exists())
        review = json.loads((self.private / "multi_act.json").read_text())
        self.assertFalse(review["editorial_review"]["user_confirmed"])
        self.assertEqual(len(review["acts"]), 2)
        self.assertEqual(self.run_author(NoCalls())["status"],
                         "needs_explicit_act_review")

    def test_reject_hallucinated_quotes_no_saved_claims(self):
        with self.assertRaises(AuthoringError) as cm:
            self.run_author(FakeSourceLockedAuthor(reject_quotes=True))
        self.assertEqual(cm.exception.code, "model_contract_rejected")
        self.assertEqual(project.status(self.project)["chunks_with_analysis"], 0)
        self.assertFalse(self.output.exists())

    def test_reject_changed_book_before_resume(self):
        self.run_author(FakeSourceLockedAuthor())
        self.source.write_text(book.SOURCE + " Несанкционированное изменение.",
                               encoding="utf-8")
        with self.assertRaises(AuthoringError) as cm:
            self.run_author(NoCalls())
        self.assertEqual(cm.exception.code, "book_changed")

    def test_exact_utf16_range_and_ambiguity(self):
        idx = book.index()
        chunk = idx["chunks"][0]
        good = {"summary": "Проверены оригинальные слова книги",
                "unresolved": [],
                "assertions": [{"statement": "Найдена верёвка", "kind": "NARRATED",
                                "quote": book.PARAGRAPHS[0][0]}]}
        checked = _source_analysis(good, chunk, idx["source_fingerprint"], 0)
        self.assertEqual(checked["assertions"][0]["id"], "a_00000_00")
        with self.assertRaises(AuthoringError):
            _source_analysis({**good, "assertions": [{
                **good["assertions"][0], "quote": "Несуществующая цитата"}]},
                chunk, idx["source_fingerprint"], 0)

    def test_parser_requires_one_private_workflow_and_cloud_optin(self):
        args = parser().parse_args([
            "author-book", "--book", "/private/novel.fb2",
            "--project", "/private/project", "--workdir", "/private/work",
            "--output", "/private/game.bworld",
            "--provider", "private-json",
            "--response-dir", "/private/responses",
        ])
        self.assertEqual(args.command, "author-book")
        self.assertFalse(args.allow_cloud_book)
        self.assertFalse(args.delegate_review)
        with patch.dict("os.environ", {"ZAI_API_KEY": "test-private-token"}):
            with self.assertRaises(AuthoringError) as cm:
                ZaiProvider(allow_cloud_book=False, sleep=lambda _: None)
        self.assertEqual(cm.exception.code, "cloud_consent_required")

    def test_strict_model_json_and_transient_429_auto_retry(self):
        self.assertEqual(strict_json_response('{"a":1}'), {"a": 1})
        with self.assertRaises(AuthoringError):
            strict_json_response("not json")
        class Reply:
            def __enter__(self):
                return self
            def __exit__(self, *_):
                return None
            def read(self, n):
                return json.dumps({
                    "choices": [{"message": {"content": '{"summary":"ok"}'}}]
                }).encode()
        attempt = []
        def transport(*args, **kwargs):
            attempt.append(1)
            if len(attempt) == 1:
                raise HTTPError("https://api.z.ai/", 429, "retry", {}, None)
            return Reply()
        with patch.dict("os.environ", {"ZAI_API_KEY": "test-private-token"}), \
                patch("tools.rpg_author.ai_provider.urlopen", side_effect=transport):
            client = ZaiProvider(allow_cloud_book=True, sleep=lambda _: None)
            self.assertEqual(client.ask("analysis", {"chunk": {}}),
                             {"summary": "ok"})
        self.assertEqual(len(attempt), 2)

    def test_offline_inbox_rejects_missing_responses_and_symlink_escapes(self):
        inbox = self.dir / "private_responses"
        inbox.mkdir()
        provider = PrivateResponseInbox(inbox)
        with self.assertRaises(AuthoringError) as cm:
            provider.ask("story", {})
        self.assertEqual(cm.exception.code, "missing_model_response")
        (inbox / "story.json").write_text('{"title":"test"}', encoding="utf-8")
        self.assertEqual(provider.ask("story", {})["title"], "test")
        (inbox / "story.json").unlink()
        (inbox / "story.json").symlink_to(self.source)
        with self.assertRaises(AuthoringError):
            provider.ask("story", {})


if __name__ == "__main__":
    unittest.main()
