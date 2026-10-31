"""Generate canonical expected outcomes for cross-runtime M0 comparison."""
import json
from pathlib import Path
from reference_runtime import ReferenceGame, load_demo

ROOT = Path(__file__).resolve().parent
SCENARIO = load_demo()
PATHS = {
    "leave": ["leave"],
    "no_evidence": ["talk", "enter_yard", "ignore_witness", "tower_empty", "accuse"],
    "truth_via_letter": ["talk", "enter_yard", "save_witness", "find_letter", "show_evidence"],
    "truth_via_witness": ["talk", "befriend", "save_witness", "ask_witness", "trust_talk", "show_evidence"],
    "key_opens_hall": ["market", "take_key", "open_gate", "search_hall", "find_letter", "show_evidence"],
}
def export():
    items = []
    for label, actions in PATHS.items():
        game = ReferenceGame(SCENARIO)
        for action in actions:
            game.act(action)
        items.append({
            "case": label,
            "choices": actions,
            "final_scene": game.scene,
            "final_state": game.values,
            "visible_choice_ids": [c["id"] for c in game.available()],
            "history_length": len(game.history),
        })
    return {"format": "ai-story-rpg/m0-contract-v1", "scenario": SCENARIO["id"], "cases": items}

if __name__ == "__main__":
    dest = ROOT / "expected_contract.json"
    dest.write_text(json.dumps(export(), ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(f"Wrote {dest}: {len(PATHS)} paths")
