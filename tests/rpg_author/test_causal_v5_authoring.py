"""E6q: private source-wide semantic review producer, no second RPG runtime.

All test books and archives below are original synthetic fixtures. A Python
review report is NOT proof of genuine literary CANON or portable gameplay.
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tests.rpg_author import fixtures_acts as example
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author import project
from tools.rpg_author.cli import parser
from tools.rpg_author.source_causal_v2 import (
    author_causal_v5, _read_native_base, _indexed_source, _cast,
)


class FakePrivateBookSkill:
    def __init__(self, *, hallucinated=False, unresolved=False,
                 missing_scene=False):
        self.calls = []
        self.hallucinated = hallucinated
        self.unresolved = unresolved
        self.missing_scene = missing_scene

    def ask(self, stage, payload, feedback=""):
        self.calls.append(stage)
        if stage == "causal_npc":
            return {
                "characters": [{
                    "ref": "boatman", "name": "Лодочник",
                    "first_scene_id": "canon_00001",
                }],
                "witnesses": [{
                    "ref": "boatman", "scene_id": "canon_00001",
                    "mode": "present",
                }],
                "invariants": [{
                    "ref": "boatman", "scene_id": "canon_00002",
                    "forbidden_memory_id": "gm_storm_warning",
                    "minimum_trust": None, "maximum_trust": None,
                }],
                "npc_reactions": [{
                    "scene_id": "canon_00001",
                    "actor_ref": "boatman",
                    "trigger_memory_id": "gm_storm_warning",
                    "minimum_trust": 1,
                    "response_memory_id": "gm_saves_the_child",
                    "next_goal_id": "gm_reach_bank",
                    "relay_fact_id": None,
                    "relay_to_ref": None,
                }],
            }
        if stage == "causal_window":
            rows = payload["source_scenes"]
            events = []
            for i, scene in enumerate(rows):
                refs = payload["already_reviewed_causal_event_ids"]
                previous = ([rows[i - 1]["scene_id"]] if i else
                            ([refs[-1]] if refs else []))
                events.append({
                    "scene_id": scene["scene_id"],
                    "evidence_quote": (
                        "Фальшивая цитата отсутствует в источнике" if
                        self.hallucinated and i == 0 else
                        scene["source_evidence"][0]["quote"]),
                    "depends_on": previous,
                    "preconditions": [],
                    "effects": [],
                    "causal_reason": "Исходное событие зависит от предыдущих действий героев.",
                    "unresolved": self.unresolved and i == 1,
                })
            return {
                "window_id": payload["window_id"],
                "events": events[:-1] if self.missing_scene else events,
            }
        if stage == "causal_literary_review":
            return {
                "verdict": "pass",
                "reviewed_scene_ids": [
                    entry["scene_id"] for entry in
                    payload["all_scene_reviews"]
                ],
                "explanation": "Проверены точные цитаты и последовательность синтетических событий.",
            }
        raise AssertionError("Unexpected private author stage: " + stage)


class WholeBookCausalV5Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.book = self.root / example.SOURCE_FILENAME
        self.book.write_text(example.SOURCE, encoding="utf-8")
        self.project = self.root / "private-project"
        project.init_project(self.project, self.book)
        _, _, idx, _, _ = project.load_project(self.project)
        self.index = idx
        self.base = self.root / "base-v5.bworld"
        self.work = self.root / "private-review"
        self.output = self.root / "canon-causal-review.json"
        scenes, origins = [], []
        for i, chunk in enumerate(idx["chunks"]):
            sid = f"canon_{i:05d}"
            quote = chunk["text"][:35]
            scenes.append({"id": sid, "text": chunk["text"],
                           "terminal": i == len(idx["chunks"]) - 1,
                           "choices": []})
            origins.append({
                "scene_id": sid, "origin": "SOURCE_PASSAGE",
                "chapter_index": i,
                "source_refs": [{
                    "chunk_id": chunk["id"],
                    "chapter_index": chunk["chapter_index"],
                    "chapter_id": chunk["chapter_id"],
                    "block_index": chunk["block_index"],
                    "start_utf16": chunk["start_utf16"],
                    "end_utf16": chunk["start_utf16"] + len(quote),
                    "quote_sha256": digest(quote.encode("utf-8")),
                }],
            })
        self.bp = {
            "source_fingerprint": idx["source_fingerprint"],
            "actors": ["player"], "items": [], "facts": [],
            "initial_state": {"stats": {}, "flags": {}}, "scenes": scenes,
        }
        self.provenance = {
            "source_fingerprint": idx["source_fingerprint"],
            "scene_origins": origins,
        }
        self._write_world()

    def _write_world(self, *, tamper=False):
        payloads = {
            "scenario/blueprint.json": canonical(self.bp),
            "source/provenance.json": canonical(self.provenance),
            "world.sqlite": b"SQL synthetic source-bound archive (not a database)",
        }
        manifest = {
            "format_version": 5,
            "source_fingerprint": self.index["source_fingerprint"],
            "canon_review_format": "ai_story_literal_canon_review_v1",
            "hashes": {p: digest(data) for p, data in payloads.items()},
            "sizes": {p: len(data) for p, data in payloads.items()},
        }
        if tamper:
            manifest["hashes"]["scenario/blueprint.json"] = "0" * 64
        with zipfile.ZipFile(self.base, "w", zipfile.ZIP_STORED) as z:
            z.writestr("manifest.json", canonical(manifest))
            for path, data in payloads.items():
                z.writestr(path, data)

    def _run(self, fake=None, *, consent=True):
        return author_causal_v5(
            project_root=self.project, base_world=self.base,
            workdir=self.work, output=self.output,
            provider=fake or FakePrivateBookSkill(),
            user_confirmed=consent)

    def test_complete_private_source_graph_requires_exact_book_and_consent(self):
        model = FakePrivateBookSkill()
        result = self._run(model)
        self.assertEqual(result["status"], "review_ready_for_native_compiler")
        self.assertEqual(model.calls,
                         ["causal_npc", "causal_window", "causal_literary_review"])
        record = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertEqual(record["format"], "ai_story_source_causal_review_v2")
        self.assertEqual(len(record["event_graph"]), 3)
        self.assertEqual(len(record["witnesses"]), 1)
        self.assertEqual(len(record["npc_reactions"]), 1)
        self.assertFalse(record["semantic_canon_automatically_verified"])
        self.assertEqual(record["base_archive_sha256"], digest(self.base.read_bytes()))
        self.assertEqual(digest(b"source-causal-review-v1\\n" +
                                canonical(record)), result["approved_digest"])
        self.assertNotIn("_causal_reason", str(record))
        self.assertFalse(result["native_causal_archive_compiled"])

    def test_no_confirmation_no_review_or_game_export(self):
        result = self._run(consent=False)
        self.assertEqual(result["status"],
                         "needs_private_literary_or_user_review")
        self.assertFalse(self.output.exists())

    def test_hallucinated_quote_blocks_all_export(self):
        with self.assertRaises(AuthoringError) as reason:
            self._run(FakePrivateBookSkill(hallucinated=True))
        self.assertEqual(reason.exception.code, "causal_quote_hallucinated")
        self.assertFalse(self.output.exists())

    def test_missing_scene_or_unresolved_cause_fails_closed(self):
        with self.assertRaises(AuthoringError) as reason:
            self._run(FakePrivateBookSkill(missing_scene=True))
        self.assertEqual(reason.exception.code, "causal_window_incomplete")
        self.assertFalse(self.output.exists())
        result = self._run(FakePrivateBookSkill(unresolved=True))
        self.assertEqual(result["status"],
                         "needs_private_literary_or_user_review")
        self.assertFalse(self.output.exists())

    def test_tampered_native_archive_cannot_claim_source_provenance(self):
        self._write_world(tamper=True)
        with self.assertRaises(AuthoringError) as reason:
            self._run()
        self.assertEqual(reason.exception.code, "native_archive_tampered")
        self.assertFalse(self.output.exists())

    def test_first_encounter_cannot_be_backdated(self):
        data = _read_native_base(self.base, self.index)
        scenes, _ = _indexed_source(self.index, data)
        wrong = FakePrivateBookSkill().ask("causal_npc", {})
        wrong["characters"][0]["first_scene_id"] = "canon_00000"
        with self.assertRaises(AuthoringError):
            _cast(wrong, scenes, self.index)

    def test_cli_exposes_explicit_private_no_api_authoring(self):
        cmd = parser().parse_args([
            "author-causal-v5", "--project", str(self.project),
            "--base-world", str(self.base), "--workdir", str(self.work),
            "--output", str(self.output),
        ])
        self.assertFalse(cmd.user_confirmed)
        self.assertIsNone(cmd.response_dir)


if __name__ == "__main__":
    unittest.main()
