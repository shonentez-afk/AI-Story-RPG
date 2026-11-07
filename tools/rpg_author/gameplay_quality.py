"""E6: deterministic, read-only game-design diagnostics for a rich BookWorld v3.

This is a mechanical audit, not a claim of literary or artistic quality.
It never writes a game, modifies checkpoints, or calls an AI service.
"""
from __future__ import annotations

from collections import defaultdict, deque
import io
import zipfile
from itertools import combinations
from pathlib import Path

from .common import AuthoringError, canonical, digest, parse_json, read_bytes, read_json, require
from .compatibility import check_contract
from .project import load_project
from .rich_package import _enrich
from .validate import candidate_blueprint, validate_story

FORMAT = "rpg_author_gameplay_quality_e6_v1"
MAX_STATES = 2500


def _key(rule):
    op = rule["op"]
    kind = {"flag_is": "flag", "set_flag": "flag",
            "has_item": "item", "grant_item": "item", "consume_item": "item",
            "knows_fact": "fact", "learn_fact": "fact",
            "stat_at_least": "stat", "stat_delta": "stat"}.get(op)
    return kind, rule.get("id")


def _permitted(rule, flags, items, stats, facts):
    op, key = rule["op"], rule["id"]
    if op == "flag_is":
        return (key in flags) == rule["value"]
    if op == "has_item":
        return key in items
    if op == "knows_fact":
        return key in facts
    if op == "stat_at_least":
        return stats[key] >= rule["amount"]
    raise AuthoringError("unsupported_rule", "Unknown condition: " + op)


def _apply(state, choice):
    _, flag_tuple, item_tuple, stat_tuple, fact_tuple = state
    flags, items, stats, facts = (set(flag_tuple), set(item_tuple),
                                  dict(stat_tuple), set(fact_tuple))
    for effect in choice["effects"]:
        op, key = effect["op"], effect["id"]
        if op == "set_flag":
            if effect["value"]:
                flags.add(key)
            else:
                flags.discard(key)
        elif op == "grant_item":
            items.add(key)
        elif op == "consume_item":
            require(key in items, "unowned_item", "Available choice spends an absent item")
            items.remove(key)
        elif op == "learn_fact":
            facts.add(key)
        elif op == "stat_delta":
            stats[key] += effect["amount"]
            require(0 <= stats[key] <= 1000000, "invalid_stat", "Stat out of range")
        else:
            raise AuthoringError("unsupported_rule", "Unknown effect: " + op)
    return (choice["next_scene_id"], tuple(sorted(flags)), tuple(sorted(items)),
            tuple(sorted(stats.items())), tuple(sorted(facts)))


def _issue(code, severity, message, *, scene_id=None, choice_ids=None,
           resource=None, route=None):
    result = {"code": code, "severity": severity, "message": message}
    if scene_id is not None:
        result["scene_id"] = scene_id
    if choice_ids is not None:
        result["choice_ids"] = list(choice_ids)
    if resource is not None:
        result["resource"] = {"kind": resource[0], "id": resource[1]}
    if route is not None:
        result["example_route"] = list(route)
    return result


def audit_blueprint(bp: dict, *, max_states: int = MAX_STATES) -> dict:
    """Exhaust reachable typed states; report actionable, conservative warnings.

    Same-scene choices are compared after applying effects. Conditions are
    evaluated against *reachable* states, not merely searched in raw JSON.
    """
    require(type(max_states) is int and 1 <= max_states <= MAX_STATES,
            "state_budget", "Invalid exhaustive state budget")
    scenes = {scene["id"]: scene for scene in bp["scenes"]}
    start = (bp["entry_scene_id"],
             tuple(sorted(k for k, v in bp["initial_state"]["flags"].items() if v)),
             tuple(sorted(bp["initial_state"]["inventory"])),
             tuple(sorted(bp["initial_state"]["stats"].items())),
             tuple(sorted(bp["initial_state"]["knowledge"].get("player", []))))
    paths = {start: ()}
    pending = deque([start])
    enabled = set()
    seen_scene = set()
    terminal_routes = {}
    terminal_inflows = defaultdict(set)
    scene_enabled_counts = defaultdict(set)
    evaluations = defaultdict(set)
    observed_reads = set()
    active_writes = set()
    active_spends = set()
    duplicate_examples = {}
    shallow_same_next = {}
    branch_states = 0

    while pending:
        state = pending.popleft()
        scene_id, flags_raw, items_raw, stats_raw, facts_raw = state
        seen_scene.add(scene_id)
        scene = scenes[scene_id]
        if scene["terminal"]:
            terminal_routes.setdefault(scene_id, paths[state])
            continue
        flags, items, stats, facts = (set(flags_raw), set(items_raw),
                                     dict(stats_raw), set(facts_raw))
        options = []
        for choice in scene["choices"]:
            valid = True
            for i, rule in enumerate(choice["conditions"]):
                allowed = _permitted(rule, flags, items, stats, facts)
                evaluations[(choice["id"], i)].add(allowed)
                observed_reads.add(_key(rule))
                if not allowed:
                    valid = False
            if not valid:
                continue
            enabled.add(choice["id"])
            for effect in choice["effects"]:
                active_writes.add(_key(effect))
                if effect["op"] == "consume_item":
                    active_spends.add(("item", effect["id"]))
            next_state = _apply(state, choice)
            if scenes[next_state[0]]["terminal"]:
                terminal_inflows[next_state[0]].add((scene_id, choice["id"]))
            options.append((choice, next_state))
            if next_state not in paths:
                require(len(paths) < max_states, "state_budget",
                        "Quality audit could not exhaust the world; no quality PASS allowed")
                paths[next_state] = paths[state] + (choice["id"],)
                pending.append(next_state)
        scene_enabled_counts[scene_id].add(len(options))
        if len(options) > 1:
            branch_states += 1
        for (choice_a, next_a), (choice_b, next_b) in combinations(options, 2):
            pair = tuple(sorted((choice_a["id"], choice_b["id"])))
            if next_a == next_b:
                duplicate_examples.setdefault((scene_id, pair), paths[state])
            elif next_a[0] == next_b[0]:
                shallow_same_next.setdefault((scene_id, pair), (next_a, next_b, paths[state]))

    declared = {("flag", name) for name in bp["initial_state"]["flags"]}
    declared |= {("stat", name) for name in bp["initial_state"]["stats"]}
    declared |= {("item", name) for name in bp["items"]}
    declared |= {("fact", name) for name in bp["facts"]}
    dynamic_reads = set()
    for scene in bp["scenes"]:
        for choice in scene["choices"]:
            for i, rule in enumerate(choice["conditions"]):
                if evaluations[(choice["id"], i)] == {False, True}:
                    dynamic_reads.add(_key(rule))

    issues = []
    for res in sorted(declared):
        kind, name = res
        if kind == "stat" and res not in observed_reads:
            issues.append(_issue("DECORATIVE_STAT", "warning",
                                 "Stat is displayed or changed but never used to authorize actions",
                                 resource=res))
        elif kind == "fact" and res not in observed_reads:
            issues.append(_issue("UNUSED_KNOWLEDGE", "warning",
                                 "Knowledge never unlocks a dialogue or action",
                                 resource=res))
        elif kind == "item" and res not in observed_reads and res not in active_spends:
            issues.append(_issue("UNUSED_ITEM", "warning",
                                 "Item is never a prerequisite or a spendable resource",
                                 resource=res))
        elif kind == "flag" and res in active_writes and res not in observed_reads:
            issues.append(_issue("UNREAD_FLAG", "warning",
                                 "Changed story flag never affects an available action",
                                 resource=res))
    for scene in bp["scenes"]:
        for choice in scene["choices"]:
            if choice["id"] not in enabled:
                issues.append(_issue("NEVER_ENABLED_CHOICE", "warning",
                                     "Choice is never available on any reachable state",
                                     scene_id=scene["id"], choice_ids=[choice["id"]]))
    for (scene_id, pair), route in sorted(duplicate_examples.items()):
        issues.append(_issue("EQUIVALENT_CHOICE", "warning",
                             "Different buttons lead to identical next scene and world state",
                             scene_id=scene_id, choice_ids=pair, route=route))
    for (scene_id, pair), (one, two, route) in sorted(shallow_same_next.items()):
        # This is a conservative warning: a stat/fact may still appear in a panel.
        # It only claims no subsequent game *condition* uses the differing facts.
        relevant = lambda s: (s[0],
                  tuple((k, v) for k, v in ((x, x in s[1]) for x in bp["initial_state"]["flags"])
                        if ("flag", k) in observed_reads),
                  tuple(x for x in s[2] if ("item", x) in observed_reads or
                                                 ("item", x) in active_spends),
                  tuple((k, v) for k, v in s[3] if ("stat", k) in observed_reads),
                  tuple(x for x in s[4] if ("fact", x) in observed_reads))
        if relevant(one) == relevant(two):
            issues.append(_issue("COSMETIC_ONLY_DIVERGENCE", "warning",
                                 "Choices merge immediately; their differing state never gates play",
                                 scene_id=scene_id, choice_ids=pair, route=route))
    for sid, inflows in sorted(terminal_inflows.items()):
        if len({scene for scene, _ in inflows}) >= 2:
            issues.append(_issue("REUSED_TERMINAL", "warning",
                                 "Distinct conflicts collapse into one terminal text; review whether the ending honors each route",
                                 scene_id=sid,
                                 choice_ids=sorted(choice for _, choice in inflows)))
    for sid, counts in sorted(scene_enabled_counts.items()):
        if counts == {1}:
            issues.append(_issue("FORCED_CONTINUE", "info",
                                 "Only one action is ever available here; consider narrative auto-continue",
                                 scene_id=sid))
    if terminal_routes:
        lengths = {sid: len(path) for sid, path in terminal_routes.items()}
        longest = max(lengths.values())
        for sid, length in sorted(lengths.items()):
            if longest >= 5 and length * 3 <= longest * 2:
                issues.append(_issue("EARLY_ENDING_REVIEW", "info",
                                     "Early ending: review whether it is earned or merely stops play",
                                     scene_id=sid, route=terminal_routes[sid]))

    if not dynamic_reads:
        issues.append(_issue("NO_STATE_DEPENDENT_GATE", "warning",
                             "All reachable choices are independent of accumulated world state"))

    severity_order = {"warning": 0, "info": 1}
    issues.sort(key=lambda issue: (severity_order[issue["severity"]],
                                   issue["code"], issue.get("scene_id", ""),
                                   issue.get("resource", {}).get("id", ""),
                                   tuple(issue.get("choice_ids", []))))
    warnings = sum(issue["severity"] == "warning" for issue in issues)
    return {"format": FORMAT, "status": "needs_design_work" if warnings else
            "mechanically_reviewed_not_literary_certified",
            "quality_certified": False,
            "metrics": {"reachable_states": len(paths), "reachable_scenes": len(seen_scene),
                        "reachable_endings": len(terminal_routes),
                        "choice_definitions": sum(len(s["choices"]) for s in bp["scenes"]),
                        "enabled_choices": len(enabled),
                        "branching_state_count": branch_states,
                        "responsive_resources": [dict(kind=k, id=v) for k, v in sorted(dynamic_reads)],
                        "forced_scenes": sum(counts == {1} for counts in scene_enabled_counts.values()),
                        "shortest_routes_to_endings": {sid: list(path)
                                                         for sid, path in sorted(terminal_routes.items())}},
            "warning_count": warnings, "issues": issues,
            "limitations": ["A structural rule read does not prove meaningful narrative payoff",
                            "Gameplay design cannot be certified automatically from JSON",
                            "Source-grounded literary and human playtesting remain separate"]}


def audit_project(root: Path, enrichment_path: Path,
                  npc_review_path: Path | None = None) -> dict:
    check_contract()
    _, state, index, analyses, story = load_project(root)
    require(story is not None, "story_missing", "A complete accepted StoryPlan is required")
    validate_story(story, index, analyses)
    enrichment = read_json(enrichment_path)
    reviewed = (read_json(outside_repository(npc_review_path))
                if npc_review_path is not None else None)
    bp, _ = _enrich(candidate_blueprint(story, index), story, index,
                    enrichment, npc_review=reviewed)
    report = audit_blueprint(bp)
    report.update({"source_fingerprint": index["source_fingerprint"],
                   "story_sha256": state["story_sha256"],
                   "enrichment_sha256": digest(canonical(enrichment))})
    return report


def audit_archive(world_path: Path, attribution_path: Path | None = None) -> dict:
    """Audit an E5/E6 .bworld *without* loading or migrating its authoring project."""
    check_contract()
    from tools.bookworld import private_rich_bookworld as rich
    from tools.bookworld.bookworld import BookworldError
    raw = read_bytes(world_path, 12 * 1024 * 1024)
    try:
        inspected = rich.verify(raw)
    except (BookworldError, KeyError, TypeError, ValueError) as exc:
        raise AuthoringError("invalid_package", str(exc)) from exc
    if attribution_path is not None:
        from .rich_package import verify_rich_bundle
        verify_rich_bundle(world_path, attribution_path)
    with zipfile.ZipFile(io.BytesIO(raw)) as bundle:
        bp = parse_json(bundle.read("scenario/blueprint.json"))
    report = audit_blueprint(bp)
    report.update({"source_fingerprint": bp["source_fingerprint"],
                   "blueprint_sha256": digest(canonical(bp)),
                   "archive_sha256": digest(raw),
                   "verified_format_version": inspected["format_version"],
                   "input_kind": "readonly_verified_bworld"})
    return report