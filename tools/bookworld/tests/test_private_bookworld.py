"""Negative security and offline replay tests for PRIVATE .bworld v2.

The fixture is original synthetic text. Its proof hashes are deliberately
synthetic: verify checks internal integrity, not third-party copyright.
"""
import copy
import io
import json
import unittest
import zipfile
from pathlib import Path

from tools.bookworld import bookworld as original
from tools.bookworld import private_bookworld as private

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = ROOT / "shared_schemas" / "fixtures" / "private_classic_sample.json"


def sample():
    raw = json.loads(FIXTURE.read_text(encoding="utf-8"))
    return raw["blueprint"], raw["provenance"], raw["source_index"]


def repack(archive, replace=None, extra=None, compress=zipfile.ZIP_STORED):
    with zipfile.ZipFile(io.BytesIO(archive), "r") as z:
        blobs = {name: z.read(name) for name in private.PATHS}
    if replace:
        blobs.update(replace)
    if extra:
        blobs.update(extra)
    target = io.BytesIO()
    with zipfile.ZipFile(target, "w", compression=compress) as z:
        for name in (*private.PATHS, *(extra or {})):
            z.writestr(name, blobs[name])
    return target.getvalue()


class PrivateBworldTests(unittest.TestCase):
    def setUp(self):
        self.blueprint, self.provenance, self.index = sample()
        self.archive = private.build(self.blueprint, self.provenance, self.index)

    def test_reproducible_private_world_has_two_playable_endings(self):
        self.assertEqual(private.build(*sample()), self.archive)
        result = private.verify(self.archive)
        self.assertEqual(result["format_version"], 2)
        self.assertEqual(result["scene_count"], 3)
        self.assertEqual(result["source_fingerprint"], "a" * 64)
        self.assertTrue(result["private_only"])
        self.assertFalse(result["publication_authorized"])
        self.assertEqual(len(self.blueprint["scenes"][0]["choices"]), 3)

        # 20 deterministic repeated turns followed by either ending.
        by_id = {s["id"]: s for s in self.blueprint["scenes"]}
        for ending in ("help", "leave"):
            scene = by_id["entry"]
            for _ in range(20):
                scene = by_id[next(
                    c["next_scene_id"] for c in scene["choices"]
                    if c["id"] == "wait")]
                self.assertEqual(scene["id"], "entry")
            scene = by_id[next(
                c["next_scene_id"] for c in scene["choices"]
                if c["id"] == ending)]
            self.assertTrue(scene["terminal"])
            self.assertEqual(scene["id"], "canon_end" if ending == "help"
                             else "alternate_end")

    def test_original_demo_reader_still_rejects_private_v2(self):
        with self.assertRaises(original.BookworldError):
            original.verify(self.archive)
        self.assertNotIn(b"source/full_text", self.archive)
        self.assertNotIn(b"api_key", self.archive)

    def test_missing_wrong_rights_and_wrong_source_are_rejected(self):
        for mutation in (
            lambda bp, prov: bp.update(rights_status="original_demo"),
            lambda bp, prov: bp.update(source_fingerprint="f" * 64),
            lambda bp, prov: prov.update(rights_status="public_domain"),
            lambda bp, prov: prov.update(publication_authorized=True),
            lambda bp, prov: prov.update(model_provenance={
                "provider": "cloud", "model_id": "fake"}),
        ):
            bp, prov, index = sample()
            mutation(bp, prov)
            with self.subTest(bp=bp.get("rights_status"),
                              rights=prov.get("rights_status")):
                with self.assertRaises(original.BookworldError):
                    private.build(bp, prov, index)

    def test_forged_citation_and_early_spoilers_are_rejected(self):
        for bad in (
            {"id": "not_a_proof"},
            {"quote_sha256": "0" * 63},
            {"start_utf16": -1},
            {"start_utf16": 17, "end_utf16": 17},
            {"visible_after_chapter": 2},
            {"chapter_index": 1},
        ):
            bp, prov, index = sample()
            prov["scene_origins"][0]["source_refs"][0].update(bad)
            with self.subTest(bad=bad), self.assertRaises(
                    original.BookworldError):
                private.build(bp, prov, index)

    def test_causality_and_rule_security_even_if_archive_is_resigned(self):
        for adjust in (
            lambda bp: bp["scenes"][0]["choices"].clear(),
            lambda bp: bp["scenes"][0]["choices"].__setitem__(
                1, {**bp["scenes"][0]["choices"][1],
                    "next_scene_id": "entry"}),
            lambda bp: bp["scenes"][0]["choices"][0]["effects"].append(
                {"op": "run_python", "code": "print(1)"}),
            lambda bp: bp["scenes"][0]["choices"].__setitem__(
                2, {**bp["scenes"][0]["choices"][2],
                    "conditions": [{
                        "op": "flag_is", "id": "helped", "value": True}]}),
        ):
            bp, prov, index = sample()
            adjust(bp)
            with self.assertRaises(original.BookworldError):
                private.build(bp, prov, index)

    def test_zip_prefix_suffix_extra_deflate_and_crc_fail_closed(self):
        for archive in (
            b"prefix" + self.archive,
            self.archive + b"trailing",
            self.archive[:-1],
            repack(self.archive, extra={"../../evil.py": b"bad"}),
            repack(self.archive, compress=zipfile.ZIP_DEFLATED),
        ):
            with self.subTest(size=len(archive)):
                with self.assertRaises(original.BookworldError):
                    private.verify(archive)
        altered = bytearray(self.archive)
        altered[85] ^= 0x80
        with self.assertRaises(original.BookworldError):
            private.verify(bytes(altered))

    def test_authoring_rechecks_exact_quoted_text_not_just_claimed_hash(self):
        for mutation in (
            lambda index: index["chunks"][0].update(text="Подменённая сцена"),
            lambda index: index["chunks"][0].update(sha256_text="f" * 64),
            lambda index: index["chunks"][0].update(chapter_id="other"),
            lambda index: index.update(source_fingerprint="1" * 64),
        ):
            bp, prov, index = sample()
            mutation(index)
            with self.assertRaises(original.BookworldError):
                private.build(bp, prov, index)

    def test_source_digest_or_archive_resign_cannot_bypass_schema(self):
        bp, prov, index = sample()
        prov["scene_origins"][0]["source_refs"][0]["quote_sha256"] = "fake"
        malformed = original.canonical(prov)
        # Repack with altered provenance and an unchanged manifest.
        with self.assertRaises(original.BookworldError):
            private.verify(repack(self.archive,
                replace={"source/provenance.json": malformed}))

    def test_author_and_scene_provenance_cannot_be_silently_omitted(self):
        for mutation in (
            lambda p: p.pop("scene_origins"),
            lambda p: p["scene_origins"].pop(),
            lambda p: p["scene_origins"][0].update(assertion_ids=[]),
        ):
            bp, prov, index = sample()
            mutation(prov)
            with self.assertRaises(original.BookworldError):
                private.build(bp, prov, index)


if __name__ == "__main__":
    unittest.main()
