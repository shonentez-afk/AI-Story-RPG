#!/usr/bin/env python3
"""No third-party packages or network needed."""
import importlib.util
import json
import pathlib
import tempfile
import unittest

MOD = pathlib.Path(__file__).resolve().parents[1] / "generate.py"
spec = importlib.util.spec_from_file_location("architecture_map_generate", MOD)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)
SHA = "9e5c11eb4dc8c5fd70cd588baca4d3c12e565dbc"


class GeneratorTests(unittest.TestCase):
    def test_import_rejects_nonexistent_and_external_targets(self):
        known = {"packages/rpg_api/lib/rpg_api.dart", "apps/story_reader/lib/ui.dart"}
        self.assertEqual(gen.resolve_import("apps/story_reader/lib/ui.dart",
                         "package:rpg_api/rpg_api.dart", known),
                         "packages/rpg_api/lib/rpg_api.dart")
        self.assertIsNone(gen.resolve_import("apps/story_reader/lib/ui.dart",
                         "package:unknown/nonexistent.dart", known))
        self.assertIsNone(gen.resolve_import("apps/story_reader/lib/ui.dart",
                         "dart:io", known))

    def test_real_ast_separates_lexical_calls_and_imports(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name, content in {
                "packages/rpg_api/lib/rpg_api.dart": "class RpgApi {}\n",
                "apps/story_reader/lib/ui.dart":
                    "import 'package:rpg_api/rpg_api.dart';\n"
                    "class Ui {}\nvoid play() { maybe(); }\nvoid maybe() {}\n",
                "tools/check.py":
                    "def foo():\n    return bar()\n\ndef bar():\n    return 1\n",
            }.items():
                dest = root / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(content)
            g = gen.build(root, SHA)
            imports = [e for e in g["edges"] if e["kind"] == "import"]
            self.assertEqual(len(imports), 1)
            self.assertTrue(imports[0]["url"].endswith("ui.dart#L1"))
            calls = [e for e in g["edges"] if e["kind"] == "call_candidate"]
            self.assertTrue(any(e["confidence"] == "ast_call_candidate" for e in calls))
            self.assertEqual(g["sourceCommit"], SHA)
            self.assertEqual(g["statistics"]["trackedFiles"], 3)
            self.assertTrue(any(n["confidence"] == "ast_definition" for n in g["nodes"]))
            self.assertTrue(any(n["confidence"] == "lexical_definition" for n in g["nodes"]))

    def test_incorrect_sha_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                gen.build(pathlib.Path(tmp), "main")


if __name__ == "__main__":
    unittest.main()
