"""Reproducible 1000-scene, 999-choice stress fixture for the M0 engines."""
import argparse
import json
from pathlib import Path

def build(count=1000):
    if count < 2:
        raise ValueError("Need at least two scenes")
    scenes = []
    for i in range(count):
        ending = i == count - 1
        scenes.append({
            "id": f"scene_{i:04d}",
            "text": f"Сцена {i + 1} из {count}.",
            "choices": [] if ending else [{
                "id": f"next_{i:04d}",
                "text": "Продолжить",
                "inc": {"visited": 1},
                "next": f"scene_{i + 1:04d}",
            }],
            **({"ending": True} if ending else {}),
        })
    return {
        "id": "m0_linear_stress_v1",
        "title": "M0 stress: large narrative",
        "initial": {"visited": 0},
        "entry": "scene_0000",
        "scenes": scenes,
    }

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(build(args.count), ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(f"Generated {args.count} scenes with {args.count - 1} transitions: {args.output}")
