"""Exact citations and deterministic state exploration, not semantic certification."""
from __future__ import annotations

from collections import deque

from .common import (AuthoringError, canonical, digest, fields, identifier,
                     require, string, string_list)
from .compatibility import check_contract


def validate_analysis(value, index: dict) -> dict:
    fields(value, {"format", "source_fingerprint", "chunk_id", "source_sha256",
                   "summary", "assertions", "unresolved"}, "chunk analysis")
    require(value["format"] == "rpg_author_chunk_analysis_v1"
            and value["source_fingerprint"] == index["source_fingerprint"],
            "wrong_source", "Analysis belongs to another book or format")
    chunk = next((c for c in index["chunks"] if c["id"] == value["chunk_id"]), None)
    require(chunk is not None and value["source_sha256"] == chunk["sha256_text"],
            "wrong_chunk", "Analysis refers to a missing or changed chunk")
    string(value["summary"], "summary", 2400)
    string_list(value["unresolved"], "unresolved", 32)
    for message in value["unresolved"]:
        string(message, "unresolved", 600)
    assertions = value["assertions"]
    require(type(assertions) is list and len(assertions) <= 32,
            "invalid_assertions", "Expected at most 32 assertions per chunk")
    ids = set()
    for claim in assertions:
        fields(claim, {"id", "statement", "kind", "start_utf16", "end_utf16", "quote"},
               "assertion")
        identifier(claim["id"], "assertion id")
        require(claim["id"] not in ids, "duplicate_id", "Duplicate assertion id")
        ids.add(claim["id"])
        string(claim["statement"], "statement", 1200)
        require(claim["kind"] in ("NARRATED", "REPORTED", "INFERRED"),
                "invalid_assertion_kind", "Distinguish narration, reported speech and inference")
        a, b = claim["start_utf16"], claim["end_utf16"]
        require(type(a) is int and type(b) is int
                and chunk["start_utf16"] <= a < b <= chunk["end_utf16"] and b - a <= 180,
                "invalid_quote_range", "Citation must fit its chunk and 180 UTF-16 units")
        string(claim["quote"], "quote", 180)
        units = chunk["text"].encode("utf-16-le")
        try:
            exact = units[2 * (a - chunk["start_utf16"]):
                          2 * (b - chunk["start_utf16"])].decode("utf-16-le")
        except UnicodeError as exc:
            raise AuthoringError("split_surrogate", "Citation splits a Unicode character") from exc
        require(exact == claim["quote"], "quote_mismatch", "Citation differs from the indexed source")
    return value


def assertion_registry(analyses: list[dict], index: dict) -> dict:
    registry = {}
    chunks = {c["id"]: c for c in index["chunks"]}
    for analysis in analyses:
        validate_analysis(analysis, index)
        chunk = chunks[analysis["chunk_id"]]
        for claim in analysis["assertions"]:
            require(claim["id"] not in registry, "duplicate_id",
                    f"Assertion id occurs in multiple chunks: {claim['id']}")
            registry[claim["id"]] = {"assertion": claim, "chunk": chunk}
    return registry


def candidate_blueprint(story: dict, index: dict) -> dict:
    """Data conversion only; callers must validate before treating this as usable."""
    fingerprint = index["source_fingerprint"]
    story_hash = digest(canonical(story))
    return {"format": "ai_story_blueprint_v1", "schema_version": 1,
            "book_id": f"book_{fingerprint[:12]}_{story_hash[:12]}",
            "title": story["title"], "entry_scene_id": story["entry_scene_id"],
            "rights_status": "private_adaptation", "source_fingerprint": fingerprint,
            "supported_modes": {"roles": ["PROTAGONIST"], "plots": ["ALTER_FATE"],
                                "interactions": ["CLASSIC"]},
            "items": [], "facts": [], "actors": ["player"],
            "initial_state": {"scene_id": story["entry_scene_id"], "revision": 0, "tick": 0,
                              "stats": {}, "inventory": [], "knowledge": {"player": []},
                              "flags": {f: f in story["initial_flags"] for f in sorted(story["flags"])}},
            "scenes": [{"id": s["id"], "text": s["text"], "terminal": s["terminal"],
                        "choices": [{"id": c["id"], "label": c["label"],
                                     "next_scene_id": c["next_scene_id"],
                                     "conditions": [{"op": "flag_is", "id": f, "value": v}
                                                    for key, v in (("requires", True), ("forbids", False))
                                                    for f in c[key]],
                                     "effects": [{"op": "set_flag", "id": f, "value": v}
                                                 for key, v in (("adds", True), ("removes", False))
                                                 for f in c[key]]} for c in s["choices"]]}
                       for s in story["scenes"]]}


def validate_story(story, index: dict, analyses: list[dict]) -> dict:
    fields(story, {"format", "source_fingerprint", "title", "entry_scene_id", "flags",
                   "initial_flags", "scenes"}, "story plan")
    require(story["format"] == "rpg_author_story_plan_v1"
            and story["source_fingerprint"] == index["source_fingerprint"],
            "wrong_source", "Story belongs to another book or format")
    registry = assertion_registry(analyses, index)
    require({a["chunk_id"] for a in analyses} == {c["id"] for c in index["chunks"]},
            "analysis_incomplete", "Every text chunk needs an explicit analysis record")
    string(story["title"], "title", 256)
    identifier(story["entry_scene_id"], "entry scene")
    for key in ("flags", "initial_flags"):
        string_list(story[key], key, 32)
        for flag in story[key]:
            identifier(flag, key)
    flags = set(story["flags"])
    require(set(story["initial_flags"]) <= flags, "unknown_flag", "Unknown initial flag")
    scenes = story["scenes"]
    require(type(scenes) is list and 3 <= len(scenes) <= 192,
            "scene_count", "Expected 3..192 scenes")
    scene_ids, choice_ids = set(), set()
    origins = set()
    for scene in scenes:
        fields(scene, {"id", "chapter_index", "origin", "assertion_ids", "text",
                       "terminal", "choices"}, "scene")
        identifier(scene["id"], "scene id")
        require(scene["id"] not in scene_ids, "duplicate_id", "Duplicate scene")
        scene_ids.add(scene["id"])
        string(scene["text"], "scene text", 6000)
        require(type(scene["chapter_index"]) is int
                and 0 <= scene["chapter_index"] < index["chapter_count"],
                "invalid_chapter", "Unknown scene chapter")
        require(scene["origin"] in ("SOURCE_PASSAGE", "EXPLICIT_ADAPTATION"),
                "invalid_origin", "Mark source passages and invented alternatives separately")
        origins.add(scene["origin"])
        string_list(scene["assertion_ids"], "assertion ids", 24)
        if scene["origin"] == "SOURCE_PASSAGE":
            require(bool(scene["assertion_ids"]), "missing_evidence", "Source scene needs citations")
        for aid in scene["assertion_ids"]:
            require(aid in registry, "unknown_assertion", f"Unknown assertion: {aid}")
            require(registry[aid]["chunk"]["chapter_index"] <= scene["chapter_index"],
                    "future_citation", "Scene cites a later chapter")
        choices = scene["choices"]
        require(type(scene["terminal"]) is bool and type(choices) is list
                and len(choices) <= 16 and scene["terminal"] != bool(choices),
                "invalid_choices", "Terminal scenes have no choices; others need 1..16")
        for choice in choices:
            fields(choice, {"id", "label", "next_scene_id", "requires", "forbids", "adds", "removes"},
                   "choice")
            identifier(choice["id"], "choice id")
            identifier(choice["next_scene_id"], "destination")
            require(choice["id"] not in choice_ids, "duplicate_id", "Choice ids must be globally unique")
            choice_ids.add(choice["id"])
            string(choice["label"], "choice label", 300)
            for key in ("requires", "forbids", "adds", "removes"):
                string_list(choice[key], key, 32)
                require(set(choice[key]) <= flags, "unknown_flag", f"{key}: unknown flag")
            require(not set(choice["requires"]) & set(choice["forbids"])
                    and not set(choice["adds"]) & set(choice["removes"]),
                    "contradictory_choice", "Choice both requires/forbids or adds/removes a flag")
            require(len(choice["requires"]) + len(choice["forbids"]) <= 32
                    and len(choice["adds"]) + len(choice["removes"]) <= 32,
                    "too_many_rules", "Choice exceeds the current engine's rule limit")
    require(origins == {"SOURCE_PASSAGE", "EXPLICIT_ADAPTATION"}, "missing_origin",
            "A private adaptation needs both a source scene and an explicit alternative")
    require(story["entry_scene_id"] in scene_ids
            and all(c["next_scene_id"] in scene_ids for s in scenes for c in s["choices"]),
            "missing_scene", "Missing entry or destination scene")
    report = simulate(story)
    # Reuse the EXISTING compiler's actual blueprint rules, unmodified.
    check_contract()
    from tools.bookworld import private_bookworld
    from tools.bookworld.bookworld import BookworldError
    try:
        private_bookworld._valid_blueprint(candidate_blueprint(story, index))
    except BookworldError as exc:
        raise AuthoringError("engine_contract", str(exc)) from exc
    report.update({"source_citations_verified": True, "engine_blueprint_valid": True,
                   "semantic_review_completed": False, "device_playtest_completed": False,
                   "dart_parity_verified": False, "package_built": False,
                   "status": "validated_candidate_not_a_playable_package",
                   "unresolved_source_notes": sum(len(a["unresolved"]) for a in analyses),
                   "media_blocks_for_review": index["media_blocks_for_review"],
                   "limitations": ["Exact quotes do not prove a model's interpretation",
                                   "Chapter citation gates do not prove event-level spoiler safety",
                                   "Literary quality and gameplay on a device are not certified",
                                   "External AI provenance is unsupported by the current .bworld importer"]})
    return report


def simulate(story: dict, max_states: int = 2500) -> dict:
    """Explore scene + flags, including paths to each distinct terminal scene.

    Only called after structural validation. A state-limit hit is a failure,
    never a successful partial coverage claim.
    """
    require(type(max_states) is int and 1 <= max_states <= 2500,
            "state_limit", "State limit must be 1..2500")
    scenes = {s["id"]: s for s in story["scenes"]}
    start = (story["entry_scene_id"], tuple(sorted(story["initial_flags"])))
    queue = deque([start])
    paths = {start: []}
    predecessors = {}
    terminal_states, visited_scenes, enabled_choices = set(), set(), set()
    endings, equivalent = {}, set()
    while queue:
        state = queue.popleft()
        sid, active_tuple = state
        scene, active = scenes[sid], set(active_tuple)
        visited_scenes.add(sid)
        if scene["terminal"]:
            terminal_states.add(state)
            endings.setdefault(sid, paths[state])
            continue
        available, destinations = 0, {}
        for choice in scene["choices"]:
            if not set(choice["requires"]) <= active or set(choice["forbids"]) & active:
                continue
            available += 1
            enabled_choices.add(choice["id"])
            flags = (active | set(choice["adds"])) - set(choice["removes"])
            dest = (choice["next_scene_id"], tuple(sorted(flags)))
            if dest in destinations:
                equivalent.add(tuple(sorted((destinations[dest], choice["id"]))))
            destinations[dest] = choice["id"]
            predecessors.setdefault(dest, set()).add(state)
            if dest not in paths:
                require(len(paths) < max_states, "state_limit",
                        "State exploration limit reached; validation is incomplete")
                paths[dest] = paths[state] + [choice["id"]]
                queue.append(dest)
        require(available > 0, "dead_end", f"No available choice in {sid}; route={paths[state]}")
    require(len(endings) >= 2, "missing_endings", "Need two reachable terminal scenes")
    require(visited_scenes == set(scenes), "unreachable_scene",
            "Unreachable scenes: " + ", ".join(sorted(set(scenes) - visited_scenes)))
    can_finish = set(terminal_states)
    queue = deque(terminal_states)
    while queue:
        for parent in predecessors.get(queue.popleft(), ()):
            if parent not in can_finish:
                can_finish.add(parent)
                queue.append(parent)
    require(len(can_finish) == len(paths), "trapped_cycle", "Some reachable states cannot reach an ending")
    all_choices = {c["id"] for s in scenes.values() for c in s["choices"]}
    return {"reachable_states": len(paths), "reachable_scenes": len(visited_scenes),
            "ending_routes": dict(sorted(endings.items())), "state_space_complete": True,
            "never_enabled_choices": sorted(all_choices - enabled_choices),
            "equivalent_choice_pairs": [list(x) for x in sorted(equivalent)]}
