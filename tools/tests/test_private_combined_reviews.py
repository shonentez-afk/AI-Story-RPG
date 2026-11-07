"""Independent regression for composed ordinary and NPC review coverage."""
from copy import deepcopy
import json
from pathlib import Path
import unittest

from tools.bookworld import bookworld as legacy
from tools.bookworld import private_rich_bookworld as rich

NPC = "npc_" + "c" * 32
ROOT = Path(__file__).resolve().parents[2]


def fixture():
    data = json.loads((ROOT / "shared_schemas/fixtures/private_classic_sample.json")
                      .read_text(encoding="utf-8"))
    bp, prov = data["blueprint"], data["provenance"]
    bp["actors"] = ["player", NPC]
    bp["facts"] = ["player_seen", "npc_seen"]
    bp["initial_state"]["knowledge"] = {"player": [], NPC: []}
    bp["scenes"][0]["choices"][0]["effects"] = [
        {"op": "learn_fact", "id": "player_seen", "actor": "player"},
        {"op": "learn_fact", "id": "npc_seen", "actor": NPC},
    ]
    bp["scenes"][0]["choices"][1]["conditions"] = [
        {"op": "knows_fact", "id": "player_seen", "actor": "player"},
        {"op": "knows_fact", "id": "npc_seen", "actor": NPC},
    ]
    prov["format"] = rich.PROVENANCE_FORMAT
    prov["model_provenance"] = {
        "provider": "none", "model_id": None,
        "model_id_status": "not_applicable", "tool": "none", "method": "local_fixture",
    }
    prov["presentation"] = {
        "hero": {"name": "Player", "description": "Independent synthetic review test"},
        "item_names": {}, "item_descriptions": {}, "stat_names": {},
        "fact_names": {"player_seen": "Maria", "npc_seen": "NPC meeting"},
        "scene_names": {"entry": "Start", "canon_end": "Help", "alternate_end": "Leave"},
    }
    quote = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
    prov["npc_knowledge"] = {
        "format": rich.NPC_GRANTS_FORMAT,
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": bp["source_fingerprint"],
        "user_confirmed": True, "literary_canon_verified": False,
        "grants": [{"scene_id": "entry", "choice_id": "wait", "actor_id": NPC,
                    "fact_id": "npc_seen", "source_quote_sha256": quote}],
    }
    prov["gameplay_review"] = {
        "format": "ai_story_private_gameplay_review_m2h8e1_v1",
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": bp["source_fingerprint"],
        "base_archive_sha256": "a" * 64, "source_payload_digest": "b" * 64,
        "user_confirmed": True, "literary_canon_verified": False,
        "effects": [{"scene_id": "entry", "choice_id": "wait", "op": "learn_fact",
                     "kind": "fact", "id": "player_seen", "label": "Maria",
                     "source_quote_sha256": quote,
                     "review_note": "Explicit private game fiction, never literary canon."}],
    }
    return data


class ComposedRichReviewTests(unittest.TestCase):
    def test_build_verify_uses_the_same_original_bytes_without_mutation(self):
        data = fixture()
        before = deepcopy(data)
        archive = rich.build(data["blueprint"], data["provenance"], data["source_index"])
        report = rich.verify(archive)
        self.assertEqual(report["scene_count"], 3)
        self.assertTrue(report["private_only"])
        self.assertFalse(report["publication_authorized"])
        self.assertEqual(data, before)

    def test_npc_source_review_cannot_cover_an_extra_player_effect(self):
        data = fixture()
        data["blueprint"]["scenes"][0]["choices"][0]["effects"].append(
            {"op": "learn_fact", "id": "npc_seen", "actor": "player"})
        with self.assertRaises(legacy.BookworldError):
            rich.build(data["blueprint"], data["provenance"], data["source_index"])

    def test_missing_and_forged_npc_coverage_is_not_skipped(self):
        for change in ("remove", "actor", "quote", "grant", "unapproved"):
            with self.subTest(change=change):
                data = fixture()
                prov = data["provenance"]
                npc = prov["npc_knowledge"]
                if change == "remove":
                    del prov["npc_knowledge"]
                elif change == "actor":
                    npc["grants"][0]["actor_id"] = "player"
                elif change == "quote":
                    npc["grants"][0]["source_quote_sha256"] = "f" * 64
                elif change == "grant":
                    npc["grants"] = []
                else:
                    npc["user_confirmed"] = False
                with self.assertRaises(legacy.BookworldError):
                    rich.build(data["blueprint"], prov, data["source_index"])

    def test_ordinary_review_cannot_be_reassigned_to_npc(self):
        data = fixture()
        effect = data["provenance"]["gameplay_review"]["effects"][0]
        effect["id"] = "npc_seen"
        effect["label"] = "NPC meeting"
        with self.assertRaises(legacy.BookworldError):
            rich.build(data["blueprint"], data["provenance"], data["source_index"])

    def test_unexpected_fields_do_not_become_approval(self):
        data = fixture()
        data["provenance"]["npc_knowledge"]["auto_approved"] = True
        with self.assertRaises(legacy.BookworldError):
            rich.build(data["blueprint"], data["provenance"], data["source_index"])


if __name__ == "__main__":
    unittest.main()
