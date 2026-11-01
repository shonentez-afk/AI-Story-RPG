import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = json.loads(
    (ROOT / "shared_schemas/v1/story_blueprint.schema.json").read_text(
        encoding="utf-8"
    )
)
BLUEPRINT = json.loads(
    (ROOT / "shared_schemas/fixtures/manor_world_m17.json").read_text(
        encoding="utf-8"
    )
)


class StoryBlueprintSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Draft202012Validator.check_schema(SCHEMA)
        cls.validator = Draft202012Validator(SCHEMA)

    def test_original_fixture_passes_draft_2020_12(self):
        self.assertEqual(list(self.validator.iter_errors(BLUEPRINT)), [])

    def test_unknown_executable_rule_is_rejected(self):
        bad = copy.deepcopy(BLUEPRINT)
        bad["scenes"][0]["choices"][0]["effects"] = [
            {"op": "eval", "python": "__import__('os')"}
        ]
        self.assertTrue(list(self.validator.iter_errors(bad)))

    def test_missing_manifest_fields_rejected(self):
        bad = copy.deepcopy(BLUEPRINT)
        del bad["source_fingerprint"]
        self.assertTrue(list(self.validator.iter_errors(bad)))

    def test_advertised_ai_without_compiler_is_rejected(self):
        bad = copy.deepcopy(BLUEPRINT)
        bad["supported_modes"]["interactions"] = ["AI_FREEFORM"]
        self.assertTrue(list(self.validator.iter_errors(bad)))

    def test_extra_fields_and_invalid_effect_rejected(self):
        bad = copy.deepcopy(BLUEPRINT)
        bad["scenes"][0]["choices"][0]["script"] = "call network"
        self.assertTrue(list(self.validator.iter_errors(bad)))
        bad = copy.deepcopy(BLUEPRINT)
        bad["scenes"][0]["choices"][0]["effects"] = [
            {"op": "stat_delta", "id": "insight", "amount": 0}
        ]
        self.assertTrue(list(self.validator.iter_errors(bad)))


if __name__ == "__main__":
    unittest.main()
