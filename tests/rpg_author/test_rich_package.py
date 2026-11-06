"""Source-bound rich v3 integration and fail-closed regression tests."""
from __future__ import annotations

from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from tools.bookworld import bookworld, private_bookworld, private_rich_bookworld
from tools.rpg_author import project
from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.rich_package import (compile_rich_from_project,
                                           build_rich, verify_rich_bundle)
from tests.rpg_author.fixtures import TEXT, analysis, story
from tests.rpg_author.fixtures_rich import enrichment


class RichPrivateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        source_file = self.base / "test_story.txt"
        source_file.write_text(TEXT, encoding="utf-8")
        self.project_dir = self.base / "project"
        project.init_project(self.project_dir, source_file)
        project.submit_analysis(self.project_dir, analysis())
        project.submit_story(self.project_dir, story())
        self.overlay = enrichment()

    def test_v3_real_state_source_evidence_and_actual_model(self):
        raw, side = compile_rich_from_project(self.project_dir, self.overlay,
                                              model_id="gpt-6")
        report = private_rich_bookworld.verify(raw)
        self.assertEqual(report["format_version"], 3)
        self.assertEqual(report["scene_count"], 4)
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            self.assertEqual(archive.namelist(), list(private_rich_bookworld.PATHS))
            m = json.loads(archive.read("manifest.json"))
            bp = json.loads(archive.read("scenario/blueprint.json"))
            prov = json.loads(archive.read("source/provenance.json"))
            self.assertEqual(m["format_version"], 3)
            self.assertEqual(m["model_provenance"], prov["model_provenance"])
            self.assertEqual(prov["model_provenance"]["provider"], "openai")
            self.assertEqual(prov["model_provenance"]["model_id"], "gpt-6")
            self.assertEqual(prov["model_provenance"]["model_id_status"], "user_declared")
            self.assertEqual(prov["rights_status"], "private_use_only")
            self.assertEqual(prov["publication_authorized"], False)
            self.assertEqual(bp["items"], ["rope"])
            self.assertEqual(bp["initial_state"]["stats"], {"courage": 1, "insight": 1})
            self.assertEqual(prov["presentation"]["item_names"]["rope"], "Верёвка")
            self.assertEqual(prov["presentation"]["hero"]["name"], "Лена")
            source_refs = [ref for s in prov["scene_origins"]
                           for ref in s["source_refs"]]
            self.assertGreater(len(source_refs), 0)
            self.assertEqual(source_refs[0]["quote_sha256"], digest(TEXT.encode("utf-8")))
            self.assertTrue(any(
                effect["op"] == "consume_item"
                for s in bp["scenes"] for c in s["choices"]
                for effect in c["effects"]
            ))
        metadata = json.loads(side)
        self.assertEqual(metadata["bookworld_sha256"], digest(raw))
        self.assertEqual(metadata["scenario_generation"]["provider"], "openai")
        self.assertTrue(metadata["bookworld_packaging"]["authorship_also_in_package"])
        # Strict historical formats must reject v3, not accept it as v1/v2.
        with self.assertRaises(bookworld.BookworldError):
            private_bookworld.verify(raw)
        with self.assertRaises(bookworld.BookworldError):
            bookworld.verify(raw)

    def test_reviewed_private_game_effect_is_bound_to_exact_source_scene(self):
        # Source-grounded is a byte-integrity condition; literary acquisition
        # is only explicitly USER-DECLARED private game fiction, not CANON.
        plain = deepcopy(self.overlay)
        plain["items"] = {}
        plain["stats"] = {}
        plain["facts"] = {}
        plain["choices"] = {}
        base, _ = compile_rich_from_project(self.project_dir, plain)
        with zipfile.ZipFile(io.BytesIO(base)) as archive:
            bp = json.loads(archive.read("scenario/blueprint.json"))
            prov = json.loads(archive.read("source/provenance.json"))
        idx = project.load_project(self.project_dir)[2]
        for origin in prov["scene_origins"]:
            candidates = [s for s in bp["scenes"]
                          if s["id"] == origin["scene_id"] and s["choices"]]
            if origin["origin"] == "SOURCE_PASSAGE" and \
                    origin["source_refs"] and candidates:
                scene = candidates[0]
                break
        else:
            self.fail("Synthetic project lacks a source-backed gameplay choice")
        action = scene["choices"][0]
        action["effects"].append({"op": "grant_item", "id": "source_token"})
        bp["items"] = ["source_token"]
        prov["presentation"]["item_names"] = {"source_token": "Знак пути"}
        prov["presentation"]["item_descriptions"] = {
            "source_token": "Частная игровая выдумка, не литературный факт."}
        review = {
            "format": "ai_story_private_gameplay_review_m2h8e1_v1",
            "review_scope": "user_declared_private_game_fiction",
            "source_fingerprint": idx["source_fingerprint"],
            "base_archive_sha256": digest(base),
            "source_payload_digest": "e" * 64,
            "user_confirmed": True,
            "literary_canon_verified": False,
            "effects": [{
                "scene_id": scene["id"],
                "choice_id": action["id"],
                "op": "grant_item", "kind": "item",
                "id": "source_token", "label": "Знак пути",
                "source_quote_sha256":
                    origin["source_refs"][0]["quote_sha256"],
                "review_note":
                    "Читатель разрешил вымышленный предмет только для игры.",
            }],
        }
        prov["gameplay_review"] = review
        compiled = private_rich_bookworld.build(bp, prov, idx)
        self.assertEqual(private_rich_bookworld.verify(compiled)["format_version"], 3)
        with zipfile.ZipFile(io.BytesIO(compiled)) as archive:
            saved = json.loads(archive.read("source/provenance.json"))
        self.assertEqual(saved["gameplay_review"], review)

        forged = deepcopy(prov)
        forged["gameplay_review"]["effects"][0]["source_quote_sha256"] = "f" * 64
        with self.assertRaises(bookworld.BookworldError):
            private_rich_bookworld.build(bp, forged, idx)
        false_canon = deepcopy(prov)
        false_canon["gameplay_review"]["literary_canon_verified"] = True
        with self.assertRaises(bookworld.BookworldError):
            private_rich_bookworld.build(bp, false_canon, idx)
        phantom = deepcopy(bp)
        phantom["scenes"][0]["choices"][0]["effects"].append(
            {"op": "grant_item", "id": "source_token"})
        with self.assertRaises(bookworld.BookworldError):
            private_rich_bookworld.build(phantom, prov, idx)

    def test_unattested_local_authoring_is_honest_and_rejects_false_claims(self):
        # A reviewed v2 plan may include model-assisted story proposals.
        # Its source archive cannot establish which provider authored prose.
        package, _ = compile_rich_from_project(self.project_dir, self.overlay,
                                               model_id="gpt-6")
        with zipfile.ZipFile(io.BytesIO(package)) as archive:
            blueprint = json.loads(archive.read("scenario/blueprint.json"))
            provenance = json.loads(archive.read("source/provenance.json"))
        idx = project.load_project(self.project_dir)[2]
        origin = {
            "provider": "unknown", "model_id": None,
            "model_id_status": "not_attested",
            "tool": "AI Story RPG", "method": "reviewed_local_compilation",
        }
        provenance["model_provenance"] = origin
        compiled = private_rich_bookworld.build(blueprint, provenance, idx)
        self.assertEqual(private_rich_bookworld.verify(compiled)["format_version"], 3)
        with zipfile.ZipFile(io.BytesIO(compiled)) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["model_provenance"], origin)
        changed = deepcopy(provenance)
        changed["model_provenance"]["model_id"] = "gpt-6"
        with self.assertRaises(bookworld.BookworldError):
            private_rich_bookworld.build(blueprint, changed, idx)

    def test_built_in_zai_glm_request_provenance_is_strict(self):
        # This is synthetic format verification, NOT a real GLM API response.
        package, _ = compile_rich_from_project(self.project_dir, self.overlay,
                                               model_id="gpt-6")
        with zipfile.ZipFile(io.BytesIO(package)) as archive:
            blueprint = json.loads(archive.read("scenario/blueprint.json"))
            provenance = json.loads(archive.read("source/provenance.json"))
        idx = project.load_project(self.project_dir)[2]
        marker = {
            "provider": "zai", "model_id": "glm-4.7-flash",
            "model_id_status": "requested",
            "tool": "AI Story RPG", "method": "built_in",
        }
        provenance["model_provenance"] = marker
        compiled = private_rich_bookworld.build(blueprint, provenance, idx)
        self.assertEqual(private_rich_bookworld.verify(compiled)["format_version"], 3)
        with zipfile.ZipFile(io.BytesIO(compiled)) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(manifest["model_provenance"], marker)
        changed = deepcopy(provenance)
        changed["model_provenance"]["model_id"] = "unknown"
        with self.assertRaises(bookworld.BookworldError):
            private_rich_bookworld.build(blueprint, changed, idx)

    def test_deterministic_archive_and_explicit_no_model_attestation(self):
        a, sa = compile_rich_from_project(self.project_dir, self.overlay)
        b, sb = compile_rich_from_project(self.project_dir, self.overlay)
        self.assertEqual(a, b)
        self.assertEqual(sa, sb)
        with zipfile.ZipFile(io.BytesIO(a)) as archive:
            provenance = json.loads(archive.read("source/provenance.json"))
        self.assertIsNone(provenance["model_provenance"]["model_id"])
        self.assertEqual(provenance["model_provenance"]["model_id_status"],
                         "not_attested")

    def test_stable_cli_output_refuses_overwrite(self):
        path = self.base / "overlay.json"
        path.write_bytes(canonical(self.overlay))
        target = self.base / "test_rich.bworld"
        result = build_rich(self.project_dir, path, target, model_id="gpt-6")
        self.assertEqual(result["status"], "private_rich_v3_built")
        sidecar = target.with_suffix(".attribution.json")
        self.assertTrue(target.is_file())
        self.assertTrue(sidecar.is_file())
        verified = verify_rich_bundle(target, sidecar)
        self.assertEqual(verified["status"], "rich_bundle_structurally_verified")
        with self.assertRaises(AuthoringError) as err:
            build_rich(self.project_dir, path, target)
        self.assertEqual(err.exception.code, "output_exists")

    def test_revision_mismatch_blocks_new_game(self):
        changed = deepcopy(self.overlay)
        changed["story_sha256"] = "f" * 64
        with self.assertRaises(AuthoringError) as err:
            compile_rich_from_project(self.project_dir, changed)
        self.assertEqual(err.exception.code, "wrong_enrichment")

    def test_flag_only_book_without_fabricated_items_or_stats(self):
        # Source-bound story with no invented possessions, stats or facts.
        plain = deepcopy(self.overlay)
        plain["items"] = {}
        plain["stats"] = {}
        plain["facts"] = {}
        plain["choices"] = {}
        raw, attribution = compile_rich_from_project(
            self.project_dir, plain, model_id="gpt-6")
        self.assertEqual(private_rich_bookworld.verify(raw)["format_version"], 3)
        self.assertTrue(attribution)
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            bp = json.loads(archive.read("scenario/blueprint.json"))
            meta = json.loads(archive.read("source/provenance.json"))
        self.assertEqual(bp["items"], [])
        self.assertEqual(bp["facts"], [])
        self.assertEqual(bp["initial_state"]["stats"], {})
        self.assertEqual(bp["initial_state"]["inventory"], [])
        self.assertEqual(bp["initial_state"]["flags"], {"rope": False})
        self.assertEqual(meta["presentation"]["item_names"], {})
        self.assertEqual(meta["presentation"]["stat_names"], {})
        self.assertEqual(meta["presentation"]["fact_names"], {})
        self.assertEqual(meta["presentation"]["hero"]["name"], "Лена")

        # Empty catalogs still reject ghost items in game actions.
        dishonest = deepcopy(plain)
        dishonest["choices"]["take_rope"] = {
            "conditions": [],
            "effects": [{"op": "grant_item", "id": "fictional_amulet"}],
        }
        with self.assertRaises((bookworld.BookworldError, AuthoringError)):
            compile_rich_from_project(self.project_dir, dishonest)

    def test_forged_or_unknown_items_rejected(self):
        altered = deepcopy(self.overlay)
        altered["choices"]["rescue"]["conditions"] = []
        # If a future author removes an item gate, a reachable rule may try to
        # consume an unowned rope: flag-only choices still remain source-bound.
        with self.assertRaises((bookworld.BookworldError, AuthoringError)):
            broken = deepcopy(altered)
            broken["choices"]["take_rope"]["effects"] = [
                {"op": "stat_delta", "id": "courage", "amount": 1}]
            compile_rich_from_project(self.project_dir, broken)
        ghost = deepcopy(self.overlay)
        ghost["items"]["ghost_key"] = {"name": "Несуществующий ключ",
                                          "description": "Отсутствует в игре"}
        with self.assertRaises((bookworld.BookworldError, AuthoringError)):
            compile_rich_from_project(self.project_dir, ghost)

    def test_non_source_quote_is_not_accepted_as_evidence(self):
        from tools.rpg_author.legacy_package import _provenance
        from tools.rpg_author.validate import candidate_blueprint
        idx = project.load_project(self.project_dir)[2]
        analysis_records = project.load_project(self.project_dir)[3]
        original_story = project.load_project(self.project_dir)[4]
        bp = candidate_blueprint(original_story, idx)
        bp["items"] = ["rope"]
        bp["facts"] = ["rescue_fact"]
        bp["initial_state"]["stats"] = {"courage": 1}
        for s in bp["scenes"]:
            for choice in s["choices"]:
                if choice["id"] == "take_rope":
                    choice["effects"].append({"op": "grant_item", "id": "rope"})
                    choice["effects"].append({"op": "stat_delta", "id": "courage", "amount": 1})
                if choice["id"] == "rescue":
                    choice["effects"].append({"op": "consume_item", "id": "rope"})
                    choice["effects"].append({"op": "learn_fact", "id": "rescue_fact",
                                              "actor": "player"})
                    choice["conditions"].append({"op": "has_item", "id": "rope"})
        prov = _provenance(original_story, idx, analysis_records, bp)
        prov["format"] = private_rich_bookworld.PROVENANCE_FORMAT
        prov["model_provenance"] = {"provider": "openai", "model_id": None,
                                    "model_id_status": "not_attested",
                                    "tool": "ChatGPT", "method": "external"}
        prov["presentation"] = {
            "hero": self.overlay["hero"],
            "stat_names": {"courage": "Смелость"},
            "item_names": {"rope": "Верёвка"},
            "item_descriptions": {"rope": "Верёвка у дороги"},
            "fact_names": {"rescue_fact": "Мальчик спасён"},
            "scene_names": self.overlay["scene_names"],
        }
        prov["scene_origins"][0]["source_refs"][0]["quote_sha256"] = "f" * 64
        with self.assertRaises(bookworld.BookworldError):
            private_rich_bookworld.build(bp, prov, idx)

    def test_missing_attribution_mismatch_rejected(self):
        target = self.base / "game.bworld"
        overlay = self.base / "overlay.json"
        overlay.write_bytes(canonical(self.overlay))
        build_rich(self.project_dir, overlay, target)
        meta_path = target.with_suffix(".attribution.json")
        meta = json.loads(meta_path.read_bytes())
        meta["bookworld_sha256"] = "0" * 64
        meta_path.write_bytes(canonical(meta))
        with self.assertRaises(AuthoringError) as err:
            verify_rich_bundle(target, meta_path)
        self.assertEqual(err.exception.code, "attribution_mismatch")
