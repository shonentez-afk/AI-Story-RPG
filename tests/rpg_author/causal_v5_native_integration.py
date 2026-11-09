"""Cross-check the PRIVATE external author against the ACTUAL Dart core.

The synthetic story is authored here and has no third-party rights.
This test uses TWO independent GitHub worktrees to prove real portability.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile

from tests.rpg_author.fixtures_acts import SOURCE, SOURCE_FILENAME
from tests.rpg_author.test_causal_v5_authoring import FakePrivateBookSkill
from tools.rpg_author import project
from tools.rpg_author.common import digest
from tools.rpg_author.unified_v5 import author_game_v5


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-root", required=True, type=Path)
    native = parser.parse_args().native_root.resolve()
    app = native / "apps/rpg_cli"
    assert (app / "bin/rpg_cli.dart").is_file()

    def cli(*args: str) -> dict:
        result = subprocess.run(["dart", "run", "bin/rpg_cli.dart", *args],
                                cwd=app, text=True, encoding="utf-8",
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=150)
        if result.returncode != 0:
            raise RuntimeError("Native Dart CLI failed: " +
                               result.stderr[-2000:])
        return json.loads(result.stdout)

    with tempfile.TemporaryDirectory(prefix="e6q_to_native_v5_") as temp:
        base = Path(temp)
        source = base / SOURCE_FILENAME
        source.write_text(SOURCE, encoding="utf-8")
        private_project = base / "private-source-index"
        # The command itself creates/reuses the immutable source index,
        # verifies native code OIDs, compiles source-literal v5 and asks the
        # source-wide ChatGPT Skill for a native causal NPC review. No manual
        # two-step authoring and no Python RPG runtime.
        private_work = base / "skill-work"
        review_file = private_work / "source-causal-review-v2.json"
        final_world = base / "causal-v5.bworld"
        results = author_game_v5(
            book=source, project_root=private_project,
            workdir=private_work, output=final_world,
            provider=FakePrivateBookSkill(),
            user_confirmed=True, native_root=native,
        )
        assert (private_work / "literal-source-v5.bworld").is_file()
        assert results["unified_native_v5_workflow"] is True
        assert results["legacy_v4_saved_worlds_untouched"] is True
        assert results["cross_version_npc_ids_implicitly_migrated"] is False
        # The same verified literal source also supports genuinely NPC-free
        # books without inventing a character or making a causal-RPG claim.
        literal_fallback = base / "literal-only-v5.bworld"
        literal_result = author_game_v5(
            book=source, project_root=private_project,
            workdir=private_work, output=literal_fallback,
            provider=FakePrivateBookSkill(), user_confirmed=True,
            native_root=native, literal_only=True)
        assert literal_result["status"] == "private_source_literal_v5_compiled"
        assert literal_result["npc_causal_review_completed"] is False
        assert literal_fallback.read_bytes() == (
            private_work / "literal-source-v5.bworld").read_bytes()
        assert results["status"] == "private_causal_v5_native_compiled"
        assert results["native_causal_archive_compiled"] is True
        assert final_world.is_file()
        assert results["native_result"]["world_hash"] == digest(
            final_world.read_bytes())
        review = json.loads(review_file.read_text(encoding="utf-8"))
        assert len(review["event_graph"]) == 3
        assert len(review["npc_delayed_decisions"]) == 1
        assert review["semantic_canon_automatically_verified"] is False

        db = base / "native-sqlite-campaign"
        installed = cli("install", "--store", str(db),
                        "--world", str(final_world))
        assert installed["world_hash"] == results["native_result"]["world_hash"]
        opened = cli("start", "--store", str(db),
                     "--world-hash", installed["world_hash"])
        assert opened["active_plot_mode"] == "CANON"
        assert opened["revision"] == 0
        assert opened["source_literal_canon"] is True
        assert opened["dynamic_ai_action_available"] is True
        game_id = opened["campaign_id"]
        moved = cli("choose", "--store", str(db),
                    "--campaign", game_id, "--choice", "canon_next_00000",
                    "--action", "native_story_advance", "--revision", "0")
        assert moved["applied"] is True
        assert moved["revision"] == 1
        assert moved["active_plot_mode"] == "CANON"
        assert len(moved["npc_encountered"]) == 1
        assert moved["npc_encountered"][0]["display_name"] == "Лодочник"

        save = base / "portable-causal.bwsave"
        receipt = cli("export-save", "--store", str(db),
                      "--campaign", game_id, "--output", str(save))
        assert receipt["status"] == "exported"
        restored = cli("import-save", "--store", str(db),
                       "--world-hash", installed["world_hash"],
                       "--input", str(save))
        assert restored["revision"] == 1
        assert restored["state_hash"] == moved["state_hash"]
        assert restored["npc_encountered"] == moved["npc_encountered"]
        print(json.dumps({
            "status": "synthetic_e6q_native_v5_compiled_and_replayed",
            "source_scene_count": len(review["event_graph"]),
            "native_engine": True, "portable_replay_equal": True,
            "arbitrary_book_literary_truth_proven": False,
        }, ensure_ascii=False))


if __name__ == "__main__":
    main()
