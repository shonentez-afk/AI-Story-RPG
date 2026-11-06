"""E6c: read-only, state-exhaustive QA for dialogue-question scenes.

A dialogue is represented by existing BookWorld scenes and typed choices; no
runtime or SQLite schema change. A private contract describes individual NPC
questions and their expected answer scenes. This never generates prose, calls
AI, grants items or changes a saved campaign.
"""
from __future__ import annotations

from collections import defaultdict, deque
from pathlib import Path
import io
import zipfile

from .common import (AuthoringError, digest, canonical, fields, identifier,
                     parse_json, read_bytes, read_json, require, string)
from .compatibility import check_contract
from .gameplay_quality import _apply, _permitted, MAX_STATES

FORMAT = "ai_story_dialogue_quality_e6c_v1"
CONTRACT = "ai_story_dialogue_topics_v1"


def audit_blueprint(blueprint: dict, contract: dict, *, max_states: int = MAX_STATES) -> dict:
    """Check entry, speaker labels, question destinations and no-repeat proofs.

    Structural verification and linguistic truth remain different gates.
    One-shot proof explores all future authorized transitions, not just the
    immediate return edge, and catches the same reward claimed after a detour.
    """
    fields(contract, {"format", "source_fingerprint", "topics"}, "dialogue contract")
    require(contract["format"] == CONTRACT and
            contract["source_fingerprint"] == blueprint.get("source_fingerprint"),
            "wrong_source", "Dialogue contract belongs to another book edition")
    topics = contract["topics"]
    require(type(topics) is list and 1 <= len(topics) <= 48,
            "invalid_topics", "Expected 1..48 bounded conversation topics")
    require(type(max_states) is int and 1 <= max_states <= MAX_STATES,
            "state_budget", "Dialogue state budget must be at most 2500")
    definitions = {}
    for row in topics:
        fields(row, {"question_id", "source_scene_id", "answer_scene_id",
                     "speaker", "one_shot", "requires_fact"}, "dialogue topic")
        for key in ("question_id", "source_scene_id", "answer_scene_id"):
            identifier(row[key], key)
        string(row["speaker"], "NPC speaker", 80)
        require(type(row["one_shot"]) is bool, "invalid_topic", "one_shot must be boolean")
        require(row["requires_fact"] is None or
                (isinstance(row["requires_fact"], str) and
                 row["requires_fact"] in blueprint["facts"]),
                "unknown_fact", "Unknown fact for a response knowledge boundary")
        require(row["question_id"] not in definitions,
                "duplicate_question", "A question must have one unique contract entry")
        definitions[row["question_id"]] = row
    scenes = {scene["id"]: scene for scene in blueprint["scenes"]}
    catalog = {}
    for s in scenes.values():
        for c in s["choices"]:
            require(c["id"] not in catalog, "duplicate_choice", "Repeated choice ID")
            catalog[c["id"]] = (s["id"], c)

    start = blueprint["initial_state"]
    initial = (start["scene_id"],
               tuple(sorted(k for k, present in start["flags"].items() if present)),
               tuple(sorted(start["inventory"])),
               tuple(sorted(start["stats"].items())),
               tuple(sorted(start["knowledge"].get("player", []))))
    visited = {initial}
    path = {initial: ()}
    pending = deque([initial])
    edges = defaultdict(list)
    asked = defaultdict(list)
    while pending:
        state = pending.popleft()
        sid, flags_raw, items_raw, stats_raw, facts_raw = state
        for c in scenes[sid]["choices"]:
            if not all(_permitted(rule, set(flags_raw), set(items_raw),
                                  dict(stats_raw), set(facts_raw))
                       for rule in c["conditions"]):
                continue
            next_state = _apply(state, c)
            edges[state].append((c["id"], next_state))
            if c["id"] in definitions:
                asked[c["id"]].append((state, next_state))
            if next_state not in visited:
                require(len(visited) < max_states, "state_budget",
                        "Cannot claim dialogue PASS when reachable-state budget is exceeded")
                visited.add(next_state)
                path[next_state] = path[state] + (c["id"],)
                pending.append(next_state)

    issues = []

    def issue(code: str, question: str, message: str, route=()):
        issues.append({"code": code, "severity": "warning", "question_id": question,
                       "message": message, "example_route": list(route)})

    for q, topic in sorted(definitions.items()):
        if q not in catalog:
            issue("MISSING_QUESTION", q, "Contract refers to absent choice")
            continue
        scene_id, definition = catalog[q]
        if scene_id != topic["source_scene_id"]:
            issue("WRONG_DIALOGUE_HUB", q, "Question appears in another scene")
        if definition["next_scene_id"] != topic["answer_scene_id"]:
            issue("WRONG_DIALOGUE_ANSWER", q, "Question does not lead to declared reply")
        answer = scenes.get(topic["answer_scene_id"])
        if answer is None:
            issue("MISSING_ANSWER", q, "Declared reply scene does not exist")
        elif topic["speaker"] + ":" not in answer["text"]:
            issue("MISSING_NPC_VOICE", q, "The reply contains no labelled NPC response")
        if not asked[q]:
            issue("UNREACHABLE_QUESTION", q, "Question is never available")
            continue
        fact = topic["requires_fact"]
        if fact is not None:
            for before, _ in asked[q]:
                if fact not in before[4]:
                    issue("UNAUTHORIZED_DISCLOSURE", q,
                          "The specified fact must be known before asking the question",
                          path[before] + (q,))
                    break
        if not topic["one_shot"]:
            continue
        source_states = {state for state, _ in asked[q]}
        for before, after in asked[q]:
            # Reconstruct a continuation from this exact first question.
            # A shortest path from the game entry may bypass that question.
            parents = {after: None}
            queue = deque([after])
            duplicate_path = None
            while queue:
                node = queue.popleft()
                if node in source_states:
                    continuation = []
                    while parents[node] is not None:
                        node, choice_id = parents[node]
                        continuation.append(choice_id)
                    duplicate_path = tuple(reversed(continuation)) + (q,)
                    break
                for choice_id, nxt in edges.get(node, ()):
                    if nxt not in parents:
                        parents[nxt] = (node, choice_id)
                        queue.append(nxt)
            if duplicate_path is not None:
                issue("REPEATABLE_DIALOGUE_REWARD", q,
                      "The same one-shot question can be taken twice in one campaign",
                      path[before] + (q,) + duplicate_path)
                break
    issues.sort(key=lambda i: (i["code"], i["question_id"]))
    return {"format": FORMAT,
            "status": "needs_dialogue_work" if issues else
                      "mechanically_reviewed_not_literary_certified",
            "warning_count": len(issues),
            "metrics": {"reachable_states": len(visited),
                        "declared_topics": len(topics),
                        "reachable_topics": len(asked),
                        "one_shot_topics": sum(x["one_shot"] for x in topics)},
            "issues": issues,
            "limitations": ["Speaker labels do not certify good dialogue writing",
                            "This does not evaluate NPC motives, tone or literary truth",
                            "An in-game save/load test on real devices remains separate"]}


def audit_archive(world_path: Path, contract_path: Path,
                  attribution_path: Path | None = None) -> dict:
    """Validate a rich v3 archive before reading dialogue, without old checkpoints."""
    check_contract()
    from tools.bookworld import private_rich_bookworld as rich
    from tools.bookworld.bookworld import BookworldError
    raw = read_bytes(world_path, 12 * 1024 * 1024)
    try:
        checked = rich.verify(raw)
    except (BookworldError, KeyError, TypeError, ValueError) as exc:
        raise AuthoringError("invalid_package", str(exc)) from exc
    if attribution_path is not None:
        from .rich_package import verify_rich_bundle
        verify_rich_bundle(world_path, attribution_path)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        bp = parse_json(z.read("scenario/blueprint.json"))
    report = audit_blueprint(bp, read_json(contract_path))
    report.update({"input_kind": "readonly_verified_bworld",
                   "archive_sha256": digest(raw),
                   "blueprint_sha256": digest(canonical(bp)),
                   "source_fingerprint": bp["source_fingerprint"],
                   "verified_format_version": checked["format_version"]})
    return report
