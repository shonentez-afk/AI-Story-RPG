"""E6r contract/consent regression, without external LLM or real books."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tests.rpg_author import fixtures_acts as fixture
from tools.rpg_author.cli import parser
from tools.rpg_author.common import ROOT, AuthoringError
from tools.rpg_author.compatibility import check_contract, check_native_contract
from tools.rpg_author.source_causal_v2 import _predicate
from tools.rpg_author.unified_v5 import author_game_v5


class NoModel:
    def ask(self, stage, payload, feedback=""):
        raise AssertionError("No external AI or fake Skill response may be invoked")


class NativeV5UnifiedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / fixture.SOURCE_FILENAME
        self.source.write_text(fixture.SOURCE, encoding="utf-8")
        self.project = root / "source-project"
        self.workdir = root / "private-inbox"
        self.world = root / "complete-v5.bworld"

    def run_without_approval(self, **kwargs):
        return author_game_v5(
            book=self.source, project_root=self.project,
            workdir=self.workdir, output=self.world,
            provider=NoModel(), native_root=ROOT,
            user_confirmed=False, **kwargs)

    def test_exact_native_engine_contract_has_43_git_blob_pins(self):
        lock = check_contract()
        self.assertEqual(lock["format"], "rpg_author_compatibility_v2")
        self.assertEqual(len(lock["files"]), 43)
        self.assertEqual(check_native_contract(ROOT), lock)

    def test_native_checkout_tamper_rejected_before_any_compilation(self):
        with tempfile.TemporaryDirectory() as folder:
            other = Path(folder)
            locked = check_contract()
            for name in locked["files"]:
                destination = other / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, destination)
            self.assertEqual(check_native_contract(other), locked)
            changed = other / "packages/story_core/lib/src/engine.dart"
            changed.write_bytes(changed.read_bytes() + b"\n// forged\n")
            with self.assertRaises(AuthoringError) as failure:
                check_native_contract(other)
            self.assertEqual(failure.exception.code, "native_contract_drift")

    def test_no_user_consent_makes_private_source_checkpoint_only(self):
        result = self.run_without_approval()
        self.assertEqual(result["status"], "needs_explicit_owner_approval")
        self.assertFalse(result["game_created"])
        self.assertFalse(result["external_model_required"])
        self.assertTrue((self.project / "project.json").is_file())
        self.assertFalse(self.world.exists())
        self.assertFalse((self.workdir / "literal-source-v5.bworld").exists())
        self.assertEqual(result["requested_mode"], "reviewed_causal_v5")
        second = self.run_without_approval()
        self.assertEqual(result, second)

    def test_explicit_literal_fallback_does_not_claim_npc_causality(self):
        result = self.run_without_approval(literal_only=True)
        self.assertEqual(result["requested_mode"], "literal_only_v5")
        self.assertFalse(result["game_created"])

    def test_immutable_source_change_fails_closed(self):
        self.run_without_approval()
        self.source.write_text("Изменённая книга без исходных цитат.", encoding="utf-8")
        with self.assertRaises(AuthoringError) as failure:
            self.run_without_approval()
        self.assertEqual(failure.exception.code, "source_changed")

    def test_existing_output_is_never_overwritten(self):
        self.world.write_bytes(b"old-private-world")
        with self.assertRaises(AuthoringError) as failure:
            self.run_without_approval()
        self.assertEqual(failure.exception.code, "unsafe_private_output")
        self.assertEqual(self.world.read_bytes(), b"old-private-world")

    def test_source_review_supports_native_open_and_closed_promises(self):
        actor = "npc_" + "0" * 32
        blueprint = {
            "facts": [], "items": [],
            "initial_state": {"stats": {}, "flags": {}},
        }
        for op in ("promise_open", "promise_closed"):
            record = {"op": op, "actor_id": actor,
                      "id": "gm_owed_passage", "value": None}
            self.assertIsNone(_predicate(record, {actor}, blueprint))
            record["actor_id"] = "player"
            with self.assertRaises(AuthoringError) as blocked:
                _predicate(record, {actor}, blueprint)
            self.assertEqual(blocked.exception.code, "causal_invalid_prerequisite")
            record["actor_id"] = actor
            record["value"] = True
            with self.assertRaises(AuthoringError) as blocked:
                _predicate(record, {actor}, blueprint)
            self.assertEqual(blocked.exception.code, "causal_invalid_prerequisite")

    def test_one_cli_has_explicit_user_approval_and_literal_fallback(self):
        args = parser().parse_args([
            "author-game-v5", "--book", str(self.source),
            "--project", str(self.project),
            "--workdir", str(self.workdir),
            "--output", str(self.world),
            "--user-confirmed", "--literal-only",
        ])
        self.assertEqual(args.command, "author-game-v5")
        self.assertTrue(args.user_confirmed)
        self.assertTrue(args.literal_only)
        self.assertIsNone(args.native_root)


if __name__ == "__main__":
    unittest.main()
