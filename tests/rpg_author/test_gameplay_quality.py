"""E6 gameplay quality checks work independently of a real book or LLM."""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest

from tools.rpg_author.common import AuthoringError, canonical
from tools.rpg_author.gameplay_quality import audit_archive, audit_blueprint, audit_project
from tools.rpg_author.project import init_project, load_project, submit_analysis, submit_story
from tools.rpg_author.rich_package import _enrich, build_rich
from tools.rpg_author.validate import candidate_blueprint
from tests.rpg_author.fixtures import TEXT, analysis, source, story
from tests.rpg_author.fixtures_rich import enrichment


class GameplayQualityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index = source()
        cls.plan = story(cls.index)
        cls.overlay = enrichment(cls.index, cls.plan)

    def blueprint(self):
        return _enrich(candidate_blueprint(self.plan, self.index),
                       self.plan, self.index, self.overlay)[0]

    def test_diagnoses_nonreactive_stats_and_knowledge(self):
        report = audit_blueprint(self.blueprint())
        codes = {x["code"] for x in report["issues"]}
        self.assertIn("DECORATIVE_STAT", codes)
        self.assertIn("UNUSED_KNOWLEDGE", codes)
        self.assertNotIn("UNUSED_ITEM", codes)
        self.assertEqual(report["status"], "needs_design_work")
        self.assertIn({"kind": "item", "id": "rope"},
                      report["metrics"]["responsive_resources"])
        self.assertGreaterEqual(report["metrics"]["reachable_endings"], 2)
        json.loads(canonical(report))

    def test_equal_destination_and_effects_are_detected(self):
        bp = self.blueprint()
        bp["scenes"][0]["choices"][1]["effects"] = deepcopy(
            bp["scenes"][0]["choices"][0]["effects"])
        report = audit_blueprint(bp)
        self.assertTrue(any(x["code"] == "EQUIVALENT_CHOICE"
                            and x["choice_ids"] == ["leave_rope", "take_rope"]
                            for x in report["issues"]))

    def test_shared_ending_from_different_scenes_is_not_ignored(self):
        bp = self.blueprint()
        # Two distinct conflicts now collapse to a shared final text.
        bp["scenes"][0]["choices"][0]["next_scene_id"] = "safe"
        bp["scenes"][1]["choices"][1]["next_scene_id"] = "safe"
        report = audit_blueprint(bp)
        self.assertTrue(any(x["code"] == "REUSED_TERMINAL" and
                            x["scene_id"] == "safe" for x in report["issues"]))

    def test_limit_failure_is_not_silent_success(self):
        with self.assertRaises(AuthoringError) as ctx:
            audit_blueprint(self.blueprint(), max_states=2)
        self.assertEqual(ctx.exception.code, "state_budget")

    def test_verified_existing_bworld_can_be_audited_without_project_migration(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            book = base / "test_story.txt"
            book.write_text(TEXT, encoding="utf-8")
            root = base / "private_project"
            init_project(root, book, 4096)
            submit_analysis(root, analysis(self.index))
            submit_story(root, self.plan)
            overlay = base / "enrichment.json"
            overlay.write_bytes(canonical(self.overlay))
            output = base / "existing_game.bworld"
            build_rich(root, overlay, output)
            raw = output.read_bytes()
            # The read-only mode does not require or touch original E5 checkpoints.
            report = audit_archive(output, output.with_suffix(".attribution.json"))
            self.assertEqual(report["input_kind"], "readonly_verified_bworld")
            self.assertEqual(report["verified_format_version"], 3)
            self.assertEqual(output.read_bytes(), raw)
            corrupted = base / "corrupt.bworld"
            corrupted.write_bytes(raw[:-10] + b"badarchive")
            with self.assertRaises(AuthoringError):
                audit_archive(corrupted)

    def test_project_audit_does_not_change_checkpoints(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            book = base / "test_story.txt"
            book.write_text(TEXT, encoding="utf-8")
            root = base / "private_project"
            init_project(root, book, 4096)
            idx = source()
            self.assertEqual(idx["source_fingerprint"],
                             load_project(root)[2]["source_fingerprint"])
            submit_analysis(root, analysis(idx))
            submit_story(root, self.plan)
            overlay = base / "enrichment.json"
            overlay.write_bytes(canonical(self.overlay))
            before = (root / "project.json").read_bytes()
            report = audit_project(root, overlay)
            after = (root / "project.json").read_bytes()
            self.assertEqual(before, after)
            self.assertEqual(report["source_fingerprint"], idx["source_fingerprint"])
            self.assertEqual(report["warning_count"],
                             sum(x["severity"] == "warning" for x in report["issues"]))
            proc = subprocess.run([sys.executable, "-m", "tools.rpg_author",
                                   "gameplay-audit", "--project", str(root),
                                   "--enrichment", str(overlay), "--strict"],
                                  capture_output=True, text=True)
            self.assertEqual(proc.returncode, 3, proc.stderr)
            self.assertEqual(json.loads(proc.stdout)["status"], "needs_design_work")
            self.assertEqual((root / "project.json").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()