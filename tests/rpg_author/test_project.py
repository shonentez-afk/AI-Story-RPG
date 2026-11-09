import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools.rpg_author import project
from tools.rpg_author.cli import main
from tools.rpg_author.common import ROOT, AuthoringError, canonical, digest
from tools.rpg_author.compatibility import check_contract
from tests.rpg_author.fixtures import TEXT, analysis, story
from tests.rpg_author.fixtures_rich import enrichment


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.book = self.base / "test_story.txt"
        self.book.write_text(TEXT, encoding="utf-8")
        self.root = self.base / "project"
        project.init_project(self.root, self.book)

    def ready(self):
        project.submit_analysis(self.root, analysis())
        project.submit_story(self.root, story())

    def test_checkpoint_can_resume_without_original_file(self):
        self.book.unlink()
        self.assertEqual(project.next_task(self.root)["task"], "analyze_chunks")
        project.submit_analysis(self.root, analysis())
        self.assertEqual(project.next_task(self.root)["task"], "write_story_plan")
        project.submit_story(self.root, story())
        self.assertEqual(project.next_task(self.root)["task"], "prepare_enrichment_and_build")
        self.assertTrue(project.validate_project(self.root)["valid_candidate"])

    def test_identical_resubmission_is_idempotent(self):
        self.ready()
        before = (self.root / "project.json").read_bytes()
        project.submit_analysis(self.root, analysis())
        project.submit_story(self.root, story())
        self.assertEqual(before, (self.root / "project.json").read_bytes())

    def test_revised_analysis_invalidates_story_without_deleting_checkpoint(self):
        self.ready()
        old = project.status(self.root)["story_sha256"]
        record = analysis()
        record["unresolved"] = ["Возраст персонажа не указан."]
        with self.assertRaises(AuthoringError):
            project.submit_analysis(self.root, record)
        project.submit_analysis(self.root, record, replace=True)
        self.assertIsNone(project.status(self.root)["story_sha256"])
        self.assertTrue((self.root / "objects" / old).is_file())

    def test_invalid_response_does_not_change_manifest(self):
        before = (self.root / "project.json").read_bytes()
        record = analysis()
        record["assertions"][0]["quote"] = "Подмена"
        with self.assertRaises(AuthoringError):
            project.submit_analysis(self.root, record)
        self.assertEqual(before, (self.root / "project.json").read_bytes())

    def test_manifest_commit_failure_leaves_previous_checkpoint_readable(self):
        with patch.object(project, "_manifest", side_effect=OSError("simulated interruption")):
            with self.assertRaises(OSError):
                project.submit_analysis(self.root, analysis())
        self.assertEqual(project.status(self.root)["chunks_with_analysis"], 0)
        self.assertFalse((self.root / ".write-lock").exists())
        project.submit_analysis(self.root, analysis())
        self.assertEqual(project.status(self.root)["chunks_with_analysis"], 1)

    def test_existing_lock_refuses_concurrent_writer(self):
        (self.root / ".write-lock").write_text("other writer")
        with self.assertRaises(AuthoringError) as error:
            project.submit_analysis(self.root, analysis())
        self.assertEqual(error.exception.code, "project_busy")
        self.assertTrue((self.root / ".write-lock").exists())

    def test_checkpoint_corruption_is_detected(self):
        manifest = json.loads((self.root / "project.json").read_text())
        (self.root / "objects" / manifest["source_bytes_sha256"]).write_bytes(b"Changed book")
        with self.assertRaises(AuthoringError) as error:
            project.status(self.root)
        self.assertEqual(error.exception.code, "corrupt_checkpoint")

    def test_object_directory_cannot_redirect_writes_to_repository(self):
        (self.root / "objects").rename(self.root / "original_objects")
        (self.root / "objects").symlink_to(ROOT, target_is_directory=True)
        with self.assertRaises(AuthoringError) as error:
            project.submit_analysis(self.root, analysis())
        self.assertEqual(error.exception.code, "unsafe_checkpoint_path")

    def test_source_index_cannot_be_replaced_with_a_resigned_forgery(self):
        manifest = json.loads((self.root / "project.json").read_text())
        index = json.loads((self.root / "objects" / manifest["source_index_sha256"]).read_text())
        index["chunks"][0]["text"] = "Вымысел"
        data = canonical(index)
        sha = digest(data)
        (self.root / "objects" / sha).write_bytes(data)
        manifest["source_index_sha256"] = sha
        (self.root / "project.json").write_bytes(canonical(manifest))
        with self.assertRaises(AuthoringError) as error:
            project.status(self.root)
        self.assertEqual(error.exception.code, "changed_index")

    def test_toolchain_change_does_not_silently_resume(self):
        with patch.object(project, "toolchain_id", return_value="0" * 64):
            with self.assertRaises(AuthoringError) as error:
                project.status(self.root)
        self.assertEqual(error.exception.code, "toolchain_changed")

    def test_upstream_contract_changes_are_detected_read_only(self):
        from tools.rpg_author import compatibility
        fake = {"files": {"tools/bookworld/private_bookworld.py": "0" * 64}}
        with patch.object(compatibility, "read_json", return_value=fake):
            with self.assertRaises(AuthoringError) as error:
                check_contract()
        self.assertEqual(error.exception.code, "contract_drift")

    def test_books_and_outputs_cannot_be_created_in_checkout(self):
        with self.assertRaises(AuthoringError) as error:
            project.init_project(ROOT / "tools/rpg_author/private_work", self.book)
        self.assertEqual(error.exception.code, "private_output_in_repository")
        self.ready()
        for output in (ROOT / "candidate.json", self.root / "project.json"):
            with self.subTest(output=output), self.assertRaises(AuthoringError):
                project.export_candidate(self.root, output)

    def test_export_is_deterministic_and_records_ai_authorship(self):
        self.ready()
        a, b = self.base / "a.json", self.base / "b.json"
        project.export_candidate(self.root, a)
        project.export_candidate(self.root, b)
        self.assertEqual(a.read_bytes(), b.read_bytes())
        value = json.loads(a.read_bytes())
        self.assertEqual(value["authorship"]["kind"], "external_ai_assisted")
        self.assertEqual(value["authorship"]["model_id_status"], "not_attested")
        self.assertFalse(value["package_built"])
        self.assertNotIn("model_provenance", value)
        with self.assertRaises(AuthoringError):
            project.export_candidate(self.root, a)
        with self.assertRaises(AuthoringError):
            project.export_candidate(self.root, self.base / "fake.bworld")

    def test_bworld_build_still_requires_a_complete_story(self):
        overlay = self.base / "enrichment.json"
        overlay.write_bytes(canonical(enrichment()))
        before = sorted(str(p.relative_to(self.base)) for p in self.base.rglob("*"))
        with self.assertRaises(AuthoringError) as error:
            project.build(self.root, overlay, self.base / "game.bworld")
        self.assertEqual(error.exception.code, "story_missing")
        self.assertEqual(before, sorted(str(p.relative_to(self.base)) for p in self.base.rglob("*")))

    def test_provenance_cannot_be_changed_to_none_in_manifest(self):
        path = self.root / "project.json"
        value = json.loads(path.read_bytes())
        value["authorship"] = {"provider": "none", "model_id": None}
        path.write_bytes(canonical(value))
        with self.assertRaises(AuthoringError) as error:
            project.status(self.root)
        self.assertEqual(error.exception.code, "authorship_changed")

    def test_cli_returns_machine_readable_errors_and_nonzero_status(self):
        self.ready()
        overlay = self.base / "enrichment.json"
        overlay.write_bytes(canonical({}))
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = main(["build", "--project", str(self.root), "--enrichment", str(overlay),
                         "--output", str(self.base / "game.bworld")])
        self.assertEqual(code, 2)
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(json.loads(err.getvalue())["code"], "invalid_fields")

    def test_v3_dependency_changes_cannot_bypass_contract_lock(self):
        from tools.rpg_author import compatibility
        actual = check_contract()
        for name in ("tools/bookworld/private_rich_bookworld.py",
                     "packages/bookworld_format/lib/private_rich_bookworld.dart",
                     "packages/bookworld_format/lib/private_bookworld_writer.dart"):
            with self.subTest(dependency=name):
                self.assertIn(name, actual["files"])
                altered = {"files": {name: "0" * 64}}
                with patch.object(compatibility, "read_json", return_value=altered):
                    with self.assertRaises(AuthoringError) as error:
                        check_contract()
                self.assertEqual(error.exception.code, "contract_drift")

    def test_e6g_lock_checks_migrated_native_dart_authoring_and_v4_reader(self):
        # E6g is pinned to the reviewed PR #133 sync head, not Flutter
        # re-export wrappers alone. A wrong Git object cannot be blessed
        # by changing a version label or a derived toolchain ID.
        from tools.rpg_author import compatibility
        lock = check_contract()
        self.assertEqual(lock["format"], "rpg_author_compatibility_v2")
        self.assertEqual(lock["digest_algorithm"], "git_blob_sha1")
        self.assertEqual(lock["application_baseline"],
                         "b7581f71d8a14f4fd4679979ef0be94ae412f11b")
        pinned = (
            "packages/story_authoring/lib/story_authoring.dart",
            "packages/story_authoring/lib/src/book_import.dart",
            "packages/story_authoring/lib/src/book_source_index.dart",
            "packages/story_authoring/lib/src/book_text_decoder.dart",
            "packages/bookworld_format/lib/private_rich_bookworld.dart",
            "packages/bookworld_format/lib/private_bookworld_writer.dart",
        )
        for name in pinned:
            with self.subTest(name=name):
                self.assertRegex(lock["files"][name], r"^[a-f0-9]{40}$")
                altered = {**lock, "files": {**lock["files"], name: "0" * 40}}
                with patch.object(compatibility, "read_json", return_value=altered):
                    with self.assertRaises(AuthoringError) as error:
                        check_contract()
                self.assertEqual(error.exception.code, "contract_drift")

    def test_another_book_changes_identity_and_cannot_reuse_analysis(self):
        second = self.base / "different.txt"
        second.write_text("На станции потерялся билет. Смотритель помог пассажиру.")
        second_root = self.base / "second_project"
        result = project.init_project(second_root, second)
        self.assertNotEqual(result["source_fingerprint"], project.status(self.root)["source_fingerprint"])
        with self.assertRaises(AuthoringError) as error:
            project.submit_analysis(second_root, analysis())
        self.assertEqual(error.exception.code, "wrong_source")

    def test_existing_project_is_not_overwritten(self):
        before = (self.root / "project.json").read_bytes()
        with self.assertRaises(AuthoringError):
            project.init_project(self.root, self.book)
        self.assertEqual(before, (self.root / "project.json").read_bytes())
