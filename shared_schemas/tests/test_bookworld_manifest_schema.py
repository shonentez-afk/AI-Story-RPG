import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from tools.bookworld.bookworld import build

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = json.loads((ROOT / "shared_schemas/v1/bookworld_manifest.schema.json")
                    .read_text(encoding="utf-8"))
BLUEPRINT = json.loads((ROOT / "shared_schemas/fixtures/manor_world_m17.json")
                       .read_text(encoding="utf-8"))


class ManifestSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Draft202012Validator.check_schema(SCHEMA)
        cls.validator = Draft202012Validator(SCHEMA)
        from zipfile import ZipFile
        from io import BytesIO
        with ZipFile(BytesIO(build(BLUEPRINT))) as z:
            cls.manifest = json.loads(z.read("manifest.json"))

    def test_original_demo_manifest(self):
        self.assertEqual(list(self.validator.iter_errors(self.manifest)), [])

    def test_forged_rights_source_and_ai_modes(self):
        for key, value in [
            ("rights_status", "public_domain"),
            ("source_fingerprint", "fake-source"),
            ("model_provenance", {"provider": "some_ai", "model_id": "gpt"}),
            ("build_status", "ready_for_any_book"),
        ]:
            payload = dict(self.manifest)
            payload[key] = value
            with self.subTest(key=key):
                self.assertTrue(list(self.validator.iter_errors(payload)))

    def test_extra_field_and_missing_integrity_catalog(self):
        payload = dict(self.manifest)
        payload["scripts"] = ["run-me.py"]
        self.assertTrue(list(self.validator.iter_errors(payload)))
        payload = dict(self.manifest)
        payload["hashes"] = {}
        self.assertTrue(list(self.validator.iter_errors(payload)))


if __name__ == "__main__":
    unittest.main()
