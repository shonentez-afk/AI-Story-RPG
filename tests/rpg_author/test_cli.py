import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.rpg_author.common import ROOT
from tools.bookworld import private_bookworld
from tests.rpg_author.fixtures import TEXT, analysis, story
from tests.rpg_author.fixtures_rich import enrichment


class CommandLineTests(unittest.TestCase):
    def run_cli(self, *args, code=0):
        result = subprocess.run([sys.executable, "-m", "tools.rpg_author", *map(str, args)],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stderr)
        return json.loads(result.stdout if code == 0 else result.stderr)

    def test_complete_workflow_in_separate_processes(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            book, root = base / "test_story.txt", base / "work"
            book.write_text(TEXT, encoding="utf-8")
            self.run_cli("init", "--book", book, "--project", root)
            self.assertEqual(self.run_cli("next", "--project", root)["task"], "analyze_chunks")
            record, plan = base / "analysis.json", base / "story.json"
            record.write_text(json.dumps(analysis(), ensure_ascii=False), encoding="utf-8")
            plan.write_text(json.dumps(story(), ensure_ascii=False), encoding="utf-8")
            self.run_cli("accept-analysis", "--project", root, "--input", record)
            self.run_cli("accept-story", "--project", root, "--input", plan)
            report = self.run_cli("validate", "--project", root)
            self.assertEqual(len(report["validation"]["ending_routes"]), 2)
            candidate = base / "candidate.json"
            self.run_cli("export", "--project", root, "--output", candidate)
            self.assertTrue(candidate.is_file())
            overlay = base / "enrichment.json"
            overlay.write_text(json.dumps(enrichment(), ensure_ascii=False), encoding="utf-8")
            game = base / "game.bworld"
            result = self.run_cli("build", "--project", root, "--enrichment", overlay,
                                  "--output", game)
            self.assertEqual(result["status"], "private_rich_v3_built")
            sidecar = game.with_suffix(".attribution.json")
            checked = self.run_cli("verify", "--input", game, "--attribution", sidecar)
            self.assertTrue(checked["attribution_matches_archive"])
            self.assertFalse(checked["authorship_cryptographically_attested"])
            meta = json.loads(sidecar.read_text())
            self.assertIsNone(meta["scenario_generation"]["model_id"])
            self.assertEqual(meta["scenario_generation"]["provider"], "openai")
            # Previous explicit command names remain aliases of the same v3 path.
            alias_game = base / "alias.bworld"
            self.run_cli("build-rich", "--project", root, "--enrichment", overlay,
                         "--output", alias_game)
            self.assertEqual(alias_game.read_bytes(), game.read_bytes())
            self.run_cli("verify-rich", "--input", alias_game, "--attribution",
                         alias_game.with_suffix(".attribution.json"))
            # The reported defect: even a valid package must not legitimize a
            # conflicting sidecar model. Error must be machine-readable.
            meta["scenario_generation"]["provider"] = "forged"
            sidecar.write_text(json.dumps(meta), encoding="utf-8")
            rejected = self.run_cli("verify", "--input", game, "--attribution", sidecar, code=2)
            self.assertEqual(rejected["code"], "attribution_mismatch")
            invalid_overlay = enrichment()
            invalid_overlay["choices"]["take_rope"]["effects"].append(
                {"op": "grant_item", "id": "absent_item"})
            overlay.write_text(json.dumps(invalid_overlay), encoding="utf-8")
            rejected = self.run_cli("build", "--project", root, "--enrichment", overlay,
                                    "--output", base / "invalid.bworld", code=2)
            self.assertEqual(rejected["code"], "rich_compile_rejected")
            self.assertFalse((base / "invalid.bworld").exists())

    def test_doctor_announces_current_build_contract(self):
        report = self.run_cli("doctor")
        self.assertEqual(report["default_package_version"], 3)
        self.assertEqual(report["external_ai_bworld_export"], "supported_rich_v3")

    def test_readonly_verify_of_existing_legacy_contract(self):
        fixture = json.loads((ROOT / "shared_schemas/fixtures/private_classic_sample.json").read_text())
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "legacy.bworld"
            data = private_bookworld.build(fixture["blueprint"], fixture["provenance"], fixture["source_index"])
            package.write_bytes(data)
            result = self.run_cli("verify-legacy", "--input", package)
            self.assertFalse(result["authorship_certified"])
            self.assertEqual(package.read_bytes(), data)

    def test_opted_in_legacy_build_and_bundle_verify_using_real_cli(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            book, root = base / "test_story.txt", base / "work"
            book.write_text(TEXT, encoding="utf-8")
            self.run_cli("init", "--book", book, "--project", root)
            record, plan = base / "analysis.json", base / "story.json"
            record.write_text(json.dumps(analysis(), ensure_ascii=False), encoding="utf-8")
            plan.write_text(json.dumps(story(), ensure_ascii=False), encoding="utf-8")
            self.run_cli("accept-analysis", "--project", root, "--input", record)
            self.run_cli("accept-story", "--project", root, "--input", plan)
            package = base / "river.bworld"
            denied = self.run_cli("build-legacy", "--project", root, "--output", package, code=2)
            self.assertEqual(denied["code"], "legacy_ack_required")
            self.assertFalse(package.exists())
            result = self.run_cli("build-legacy", "--project", root, "--output", package,
                                  "--model-id", "gpt-6", "--ack-legacy-provenance")
            self.assertEqual(result["status"], "private_legacy_package_built")
            self.assertTrue(package.exists())
            sidecar = package.with_suffix(".attribution.json")
            self.assertTrue(sidecar.exists())
            audit = self.run_cli("verify-bundle", "--input", package, "--attribution", sidecar)
            self.assertEqual(audit["status"], "bundle_structurally_verified")
            self.assertFalse(audit["authorship_cryptographically_attested"])
