"""AI-book authoring QA: original three-chapter FB2, no real user book.

Test resumability, exact-source quotes, private ChatGPT skill queue, rejections
and real multi-act v3 preflight. Dart itself is tested in run_dart_parity.py.
"""
from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import contextlib
import io

from tests.rpg_author import fixtures_acts as book
from tools.rpg_author import project
from tools.rpg_author.ai_provider import (
    PrivateResponseInbox, strict_json_response,
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
        if stage == "npc_dossiers":
            # Legacy player-only fixture deliberately opts out; rich NPC
            # authoring is separately tested with source-based identifiers.
            return {
                "characters": [],
                "absence_reason":
                    "Synthetic regression covers the original player-only path.",
            }
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
                         ["analysis"] * 3 +
                         ["story", "npc_dossiers", "enrichment", "extension"])
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

    def test_parser_has_skill_only_no_model_selection_or_cloud_upload(self):
        args = parser().parse_args([
            "author-book", "--book", "/private/novel.fb2",
            "--project", "/private/project", "--workdir", "/private/work",
            "--output", "/private/game.bworld",
            "--response-dir", "/private/responses",
        ])
        self.assertEqual(args.command, "author-book")
        self.assertFalse(args.delegate_review)
        for forbidden in (["--provider", "zai"], ["--allow-cloud-book"],
                          ["--model", "glm-4.7-flash"]):
            with self.subTest(forbidden=forbidden):
                with contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit):
                        parser().parse_args([
                            "author-book", "--project", "/private/p",
                            "--workdir", "/private/w",
                            "--output", "/private/game.bworld", *forbidden,
                        ])
        from tools.rpg_author import ai_provider
        self.assertFalse(hasattr(ai_provider, "ZaiProvider"))
        self.assertFalse(hasattr(ai_provider, "urlopen"))
        self.assertFalse(hasattr(ai_provider, "ENDPOINT"))

    def test_strict_skill_json_and_feedback_request_instead_of_http(self):
        self.assertEqual(strict_json_response('{"a":1}'), {"a": 1})
        with self.assertRaises(AuthoringError):
            strict_json_response("not json")
        private = self.dir / "chatgpt_skill_answers"
        bridge = PrivateResponseInbox(private)
        with self.assertRaises(AuthoringError) as cm:
            bridge.ask("story", {"title": "Три берега"})
        self.assertEqual(cm.exception.code, "skill_response_needed")
        request_file = private / "requests" / "story.request.json"
        self.assertTrue(request_file.exists())
        task = json.loads(request_file.read_text(encoding="utf-8"))
        self.assertEqual(task["format"], "rpg_author_chatgpt_skill_request_v1")
        self.assertFalse(task["external_model_required"])
        self.assertFalse(task["send_book_to_external_api"])
        self.assertEqual(task["payload"]["title"], "Три берега")
        answer_file = private / "story.json"
        answer_file.write_text('{"title":"Принятая версия"}', encoding="utf-8")
        self.assertEqual(bridge.ask("story", {"title": "Три берега"}),
                         {"title": "Принятая версия"})
        with self.assertRaises(AuthoringError) as cm:
            bridge.ask("story", {"title": "Три берега"},
                       feedback="previous response lacks citations")
        self.assertEqual(cm.exception.code, "skill_revision_required")
        revised = json.loads(request_file.read_text(encoding="utf-8"))
        self.assertIn("lacks citations", revised["validation_feedback"])

    def test_one_skill_first_cli_creates_private_request_without_network(self):
        from tools.rpg_author.cli import main
        import contextlib
        import io
        response = io.StringIO()
        with contextlib.redirect_stdout(response):
            status = main([
                "author-book", "--book", str(self.source),
                "--project", str(self.project),
                "--workdir", str(self.private),
                "--output", str(self.output),
            ])
        self.assertEqual(status, 3)
        result = json.loads(response.getvalue())
        self.assertEqual(result["status"], "needs_skill_response")
        self.assertFalse(result["external_model_required"])
        self.assertFalse(result["game_created"])
        self.assertFalse(self.output.exists())
        request = self.private / "skill-responses" / "requests" / (
            "analysis_c0_b0_p0.request.json")
        task = json.loads(request.read_text(encoding="utf-8"))
        self.assertEqual(task["stage"], "analysis")
        self.assertEqual(task["payload"]["chunk"]["chapter_index"], 0)
        self.assertEqual(project.status(self.project)["chunks_with_analysis"], 0)

    def test_offline_inbox_rejects_missing_responses_and_symlink_escapes(self):
        inbox = self.dir / "private_responses"
        inbox.mkdir()
        provider = PrivateResponseInbox(inbox)
        with self.assertRaises(AuthoringError) as cm:
            provider.ask("story", {})
        self.assertEqual(cm.exception.code, "skill_response_needed")
        (inbox / "story.json").write_text('{"title":"test"}', encoding="utf-8")
        self.assertEqual(provider.ask("story", {})["title"], "test")
        (inbox / "story.json").unlink()
        (inbox / "story.json").symlink_to(self.source)
        with self.assertRaises(AuthoringError):
            provider.ask("story", {})


if __name__ == "__main__":
    unittest.main()
