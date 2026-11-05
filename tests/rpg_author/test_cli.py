import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.rpg_author.common import ROOT
from tools.bookworld import private_bookworld
from tests.rpg_author.fixtures import TEXT, analysis, story


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
            self.assertEqual(self.run_cli("build", "--project", root, code=2)["code"],
                             "external_ai_provenance_unsupported")
            self.assertFalse(list(base.rglob("*.bworld")))

    def test_readonly_verify_of_existing_legacy_contract(self):
        fixture = json.loads((ROOT / "shared_schemas/fixtures/private_classic_sample.json").read_text())
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "legacy.bworld"
            data = private_bookworld.build(fixture["blueprint"], fixture["provenance"], fixture["source_index"])
            package.write_bytes(data)
            result = self.run_cli("verify", "--input", package)
            self.assertFalse(result["authorship_certified"])
            self.assertEqual(package.read_bytes(), data)
