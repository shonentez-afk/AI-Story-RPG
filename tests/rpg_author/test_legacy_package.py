"""Integration tests for explicitly opted-in v2+sidecar packaging."""
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author import project
from tools.rpg_author.legacy_package import (
    LEGACY_PROVENANCE, build_legacy, compile_from_project, verify_bundle
)
from tools.bookworld import private_bookworld
from tests.rpg_author.fixtures import TEXT, analysis, story


class LegacySidecarTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        source = self.base / "test_story.txt"
        source.write_text(TEXT, encoding="utf-8")
        self.root = self.base / "project"
        project.init_project(self.root, source)
        project.submit_analysis(self.root, analysis())
        project.submit_story(self.root, story())

    def test_both_files_are_created_with_exact_legacy_metadata(self):
        target = self.base / "trial.bworld"
        result = build_legacy(self.root, target,
                              acknowledgement=True, model_id="gpt-6")
        sidecar = target.with_suffix(".attribution.json")
        self.assertTrue(target.is_file())
        self.assertTrue(sidecar.is_file())
        self.assertEqual(result["archive_sha256"], digest(target.read_bytes()))
        with zipfile.ZipFile(target) as z:
            self.assertEqual(z.namelist(), list(private_bookworld.PATHS))
            manifest = json.loads(z.read("manifest.json"))
            provenance = json.loads(z.read("source/provenance.json"))
            blueprint = json.loads(z.read("scenario/blueprint.json"))
            self.assertEqual(manifest["model_provenance"], LEGACY_PROVENANCE)
            self.assertEqual(provenance["model_provenance"], LEGACY_PROVENANCE)
            self.assertEqual(len(provenance["scene_origins"]), len(blueprint["scenes"]))
            self.assertEqual(provenance["scene_origins"][0]["source_refs"][0]["quote_sha256"],
                             digest(TEXT.encode("utf-8")))
        side = json.loads(sidecar.read_bytes())
        self.assertEqual(side["scenario_generation"]["provider"], "openai")
        self.assertEqual(side["scenario_generation"]["model_id"], "gpt-6")
        self.assertEqual(side["scenario_generation"]["model_id_status"], "user_declared")
        self.assertEqual(side["bookworld_sha256"], digest(target.read_bytes()))
        self.assertEqual(side["blueprint_sha256"], digest(canonical(blueprint)))
        self.assertFalse(side["bookworld_packaging"]["legacy_value_means_no_model_used"])
        self.assertFalse(side["sidecar_is_verified_by_legacy_app"])
        verify = verify_bundle(target, sidecar)
        self.assertTrue(verify["authorship_disclosure_present"])
        self.assertFalse(verify["semantic_review_completed"])
        self.assertFalse(verify["device_playtest_completed"])
        self.assertEqual(private_bookworld.verify(target.read_bytes())["format_version"], 2)

    def test_not_opted_in_does_not_create_archive_or_sidecar(self):
        target = self.base / "trial.bworld"
        with self.assertRaises(AuthoringError) as ctx:
            build_legacy(self.root, target, model_id="gpt-6")
        self.assertEqual(ctx.exception.code, "legacy_ack_required")
        self.assertFalse(target.exists())
        self.assertFalse(target.with_suffix(".attribution.json").exists())

    def test_old_build_command_still_blocks(self):
        with self.assertRaises(AuthoringError) as ctx:
            project.build(self.root)
        self.assertEqual(ctx.exception.code, "external_ai_provenance_unsupported")

    def test_package_deterministic_and_sidecar_binds_exact_bytes(self):
        a, sa = compile_from_project(self.root, model_id="gpt-6")
        b, sb = compile_from_project(self.root, model_id="gpt-6")
        self.assertEqual(a, b)
        self.assertEqual(sa, sb)
        first = self.base / "trial.bworld"
        build_legacy(self.root, first, acknowledgement=True, model_id="gpt-6")
        with self.assertRaises(AuthoringError) as ctx:
            build_legacy(self.root, first, acknowledgement=True)
        self.assertEqual(ctx.exception.code, "output_exists")
        self.assertEqual(first.read_bytes(), a)

    def test_detect_changed_sidecar_or_package(self):
        target = self.base / "trial.bworld"
        build_legacy(self.root, target, acknowledgement=True, model_id="gpt-6")
        sidecar = target.with_suffix(".attribution.json")
        meta = json.loads(sidecar.read_bytes())
        meta["bookworld_sha256"] = "0" * 64
        sidecar.write_bytes(canonical(meta))
        with self.assertRaises(AuthoringError) as ctx:
            verify_bundle(target, sidecar)
        self.assertEqual(ctx.exception.code, "attribution_mismatch")

    def test_different_edition_never_reuses_old_evidence(self):
        alt = self.base / "different.txt"
        alt.write_text("Другая история о реке.", encoding="utf-8")
        foreign_project = self.base / "other_project"
        project.init_project(foreign_project, alt)
        with self.assertRaises(AuthoringError) as ctx:
            project.submit_analysis(foreign_project, analysis())
        self.assertEqual(ctx.exception.code, "wrong_source")

    def test_user_model_id_is_not_attested_when_absent(self):
        _, side = compile_from_project(self.root)
        data = json.loads(side)
        self.assertIsNone(data["scenario_generation"]["model_id"])
        self.assertEqual(data["scenario_generation"]["model_id_status"], "not_attested")
