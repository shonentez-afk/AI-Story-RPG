"""ChatGPT Skill-first, bookwide source-locked CANON v5 causal review producer.

This is an AUTHORING bridge, not a second game engine. A native Dart
\`compile_reviewed_causal_canon\` operation remains the only trusted compiler.
No book/model data or API keys leave the caller's private directory.
"""
from __future__ import annotations

import io
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from .common import (
    atomic_write, canonical, digest, fields, outside_repository,
    parse_json, read_bytes, require, string,
)
from . import project

FORMAT = "ai_story_source_causal_review_v2"
WINDOW = 8
GM = re.compile(r"gm_[a-z0-9_]{1,59}\Z")
NPC = re.compile(r"npc_[a-f0-9]{32}\Z")
REF = re.compile(r"[a-z][a-z0-9_]{0,63}\Z")
VALID_OPS = frozenset({
    "fact_known", "fact_unknown", "item_owner", "memory_present",
    "memory_absent", "goal_is", "promise_open", "promise_closed",
    "trust_min", "trust_max", "life_is", "flag_is",
})
EFFECT_OPS = frozenset({
    "learn_fact", "grant_item", "consume_item", "stat_delta",
    "set_flag", "advance_time",
})


def _indexed_source(index: dict, data: dict) -> tuple[list[dict], dict]:
    """Review sealed ZIP entries and verify every source quote from UTF-16."""
    require(index["source_fingerprint"] == data["source_fingerprint"],
            "source_changed", "Book source differs from its verified world")
    require(data["manifest"].get("format_version") == 5 and
            data["manifest"].get("canon_review_format") ==
                "ai_story_literal_canon_review_v1" and
            not data["manifest"].get("canon_causality_format"),
            "not_literal_canon_base", "Compile a fresh native literal v5 base")
    provenance = data["provenance"]
    blueprint = data["blueprint"]
    scenes = blueprint.get("scenes")
    origins = provenance.get("scene_origins")
    require(type(scenes) is list and 1 <= len(scenes) <= 5000 and
            type(origins) is list and len(origins) == len(scenes) and
            blueprint.get("source_fingerprint") == index["source_fingerprint"] and
            blueprint.get("actors") == ["player"] and
            index.get("chapter_count") == index.get("indexed_chapter_count") and
            len(index.get("chunks", [])) > 0,
            "incomplete_canon_source", "Literal v5 is missing complete source scenes")
    chunks = {c["id"]: c for c in index["chunks"]}
    require(len(chunks) == len(index["chunks"]),
            "duplicate_source_chunk", "Source chunk registry has duplicate IDs")
    origins_by_id = {o["scene_id"]: o for o in origins}
    require(len(origins_by_id) == len(origins),
            "duplicate_source_scene", "Source scene provenance has duplicates")
    verified = []
    for n, scene in enumerate(scenes):
        sid = scene.get("id")
        origin = origins_by_id.get(sid)
        require(type(sid) is str and type(scene.get("text")) is str and
                origin is not None and origin.get("origin") == "SOURCE_PASSAGE"
                and type(origin.get("source_refs")) is list and
                len(origin["source_refs"]) > 0,
                "unverified_source_scene", "Every original scene needs its own quote")
        citations = []
        for src in origin["source_refs"]:
            chunk = chunks.get(src.get("chunk_id"))
            require(chunk is not None and
                    chunk["chapter_index"] == src.get("chapter_index") and
                    chunk["chapter_id"] == src.get("chapter_id") and
                    chunk["block_index"] == src.get("block_index"),
                    "source_quote_mismatch", "Quote points at another source chunk")
            raw = chunk["text"].encode("utf-16-le")
            start = src.get("start_utf16")
            end = src.get("end_utf16")
            low = chunk.get("start_utf16")
            high = chunk.get("end_utf16")
            require(type(start) is int and type(end) is int and
                    type(low) is int and type(high) is int and
                    low <= start < end <= high and end - start <= 180,
                    "source_quote_mismatch", "Source quote offsets exceed original")
            try:
                quote = raw[(start - low) * 2:(end - low) * 2].decode("utf-16-le")
            except UnicodeError as exc:
                raise ValueError("Quote crosses a UTF-16 surrogate pair") from exc
            require(quote.strip() and
                    digest(quote.encode("utf-8")) == src.get("quote_sha256"),
                    "source_quote_mismatch", "Exact original quote hash disagrees")
            citations.append({
                "quote": quote, "quote_sha256": src["quote_sha256"],
                "chapter_index": chunk["chapter_index"],
            })
        require(origin.get("chapter_index") ==
                    citations[0]["chapter_index"],
                "source_quote_mismatch", "Scene is assigned to another chapter")
        verified.append({
            "scene_id": sid, "order": n,
            "chapter_index": origin["chapter_index"],
            "source_quote_sha256": citations[0]["quote_sha256"],
            "source_evidence": citations,
            "scene_text_excerpt": scene["text"][:540],
            "_full_source_scene": scene["text"],
        })
    require(len({s["scene_id"] for s in verified}) == len(verified),
            "duplicate_source_scene", "Canonical scenes must be unique")
    return verified, blueprint


def _read_native_base(path: Path, index: dict) -> dict:
    raw = read_bytes(path, 20 * 1024 * 1024)
    with zipfile.ZipFile(io.BytesIO(raw), "r") as archive:
        allowed = {
            "manifest.json", "scenario/blueprint.json",
            "source/provenance.json", "world.sqlite",
        }
        require(set(archive.namelist()) == allowed,
                "unsafe_native_archive", "Unexpected files in literal CANON world")
        require(all(0 < archive.getinfo(name).file_size <= 12 * 1024 * 1024
                    for name in allowed) and
                sum(archive.getinfo(name).file_size for name in allowed)
                    <= 20 * 1024 * 1024,
                "unsafe_native_archive", "Unexpected decompressed archive size")
        payload = {name: archive.read(name) for name in allowed}
    manifest = parse_json(payload["manifest.json"])
    provenance = parse_json(payload["source/provenance.json"])
    blueprint = parse_json(payload["scenario/blueprint.json"])
    for name in allowed - {"manifest.json"}:
        require(manifest.get("hashes", {}).get(name) == digest(payload[name]) and
                manifest.get("sizes", {}).get(name) == len(payload[name]),
                "native_archive_tampered", "Source-locked archive payload changed")
    require(manifest.get("source_fingerprint") ==
                index["source_fingerprint"] ==
                provenance.get("source_fingerprint"),
            "source_changed", "Native world is not this private source edition")
    return {"manifest": manifest, "provenance": provenance,
            "blueprint": blueprint,
            "source_fingerprint": index["source_fingerprint"],
            "archive_sha256": digest(raw)}


def _cast(answer: dict, scenes: list[dict], index: dict) -> dict:
    required = {"characters", "witnesses", "invariants", "npc_reactions"}
    if "delayed_decisions" in answer:
        required.add("delayed_decisions")
    fields(answer, required, "ChatGPT causal cast")
    by_id = {x["scene_id"]: x for x in scenes}
    characters, witnesses, invariants, reactions = (
        answer["characters"], answer["witnesses"],
        answer["invariants"], answer["npc_reactions"])
    delayed = answer.get("delayed_decisions", [])
    require(type(characters) is list and 1 <= len(characters) <= 15 and
            type(witnesses) is list and 1 <= len(witnesses) <= 128 and
            type(invariants) is list and 1 <= len(invariants) <= 256 and
            type(reactions) is list and len(reactions) <= 256 and
            type(delayed) is list and len(delayed) <= 256,
            "causal_cast_incomplete",
            "Native v2 requires reviewed NPC identities and a future invariant")
    actor_ids, by_ref, by_name = set(), {}, set()
    for c in characters:
        fields(c, {"ref", "name", "first_scene_id"}, "source NPC identity")
        ref, name, scene = c["ref"], c["name"], c["first_scene_id"]
        require(type(ref) is str and REF.fullmatch(ref) and
                type(name) is str and 1 <= len(name) <= 85 and
                scene in by_id and
                name in by_id[scene]["_full_source_scene"] and
                ref not in by_ref and name.casefold() not in by_name,
                "causal_npc_identity_unproven",
                "First source NPC identity is missing or repeated")
        first = min((s["order"] for s in scenes
                     if name in s["_full_source_scene"]), default=-1)
        require(first == by_id[scene]["order"],
                "causal_npc_early_spoiler",
                "NPC appears before the claimed first source encounter")
        actor = "npc_" + digest(canonical({
            "source_fingerprint": index["source_fingerprint"],
            "ref": ref, "first_scene_id": scene,
        }))[:32]
        require(NPC.fullmatch(actor) and actor not in actor_ids,
                "causal_npc_duplicate", "Duplicate stable source NPC")
        by_ref[ref] = actor
        by_name.add(name.casefold())
        actor_ids.add(actor)
    selected = {x["ref"]: x for x in characters}
    out_witnesses = []
    witness_keys = set()
    for w in witnesses:
        fields(w, {"ref", "scene_id", "mode"}, "source NPC witness")
        scene = by_id.get(w["scene_id"])
        ref = w["ref"]
        require(ref in by_ref and scene is not None and
                w["mode"] in ("present", "reported") and
                selected[ref]["name"] in scene["_full_source_scene"] and
                (w["scene_id"], ref) not in witness_keys,
                "causal_npc_witness_unproven",
                "NPC presence or report lacks a source scene")
        witness_keys.add((w["scene_id"], ref))
        out_witnesses.append({
            "scene_id": w["scene_id"],
            "actor_id": by_ref[ref],
            "display_name": selected[ref]["name"],
            "source_quote_sha256": scene["source_quote_sha256"],
            "mode": w["mode"],
        })
    require({w["actor_id"] for w in out_witnesses} == actor_ids,
            "causal_npc_missing_witness",
            "Every reviewed NPC must have at least one cited appearance")
    seen_inv = set()
    out_invariants = []
    for row in invariants:
        fields(row, {"ref", "scene_id", "forbidden_memory_id",
                     "minimum_trust", "maximum_trust"}, "future source obligation")
        scene = by_id.get(row["scene_id"])
        ref = row["ref"]
        mem = row["forbidden_memory_id"]
        a, b = row["minimum_trust"], row["maximum_trust"]
        require(ref in by_ref and scene is not None and
                scene["order"] != 0 and type(mem) is str and GM.fullmatch(mem) and
                (a is None or type(a) is int and -100 <= a <= 100) and
                (b is None or type(b) is int and -100 <= b <= 100) and
                (a is None or b is None or a <= b) and
                (row["scene_id"], ref, mem) not in seen_inv,
                "causal_invariant_invalid", "Unverified source NPC obligation")
        seen_inv.add((row["scene_id"], ref, mem))
        out_invariants.append({
            "scene_id": row["scene_id"],
            "actor_id": by_ref[ref],
            "forbidden_memory_id": mem,
            "minimum_trust": a, "maximum_trust": b,
            "source_quote_sha256": scene["source_quote_sha256"],
        })
    out_reactions = []
    for row in reactions:
        fields(row, {"scene_id", "actor_ref", "trigger_memory_id",
                     "minimum_trust", "response_memory_id", "next_goal_id",
                     "relay_fact_id", "relay_to_ref"}, "source NPC decision")
        scene = by_id.get(row["scene_id"])
        ref, receiver = row["actor_ref"], row["relay_to_ref"]
        fact = row["relay_fact_id"]
        require(scene is not None and ref in by_ref and
                (row["scene_id"], ref) in witness_keys and
                next(w["mode"] for w in witnesses
                     if w["scene_id"] == row["scene_id"] and w["ref"] == ref)
                    == "present" and
                all(type(row[k]) is str and GM.fullmatch(row[k])
                    for k in ("trigger_memory_id", "response_memory_id",
                              "next_goal_id")) and
                type(row["minimum_trust"]) is int and
                -100 <= row["minimum_trust"] <= 100 and
                ((receiver is None and fact is None) or
                 (receiver in by_ref and receiver != ref and
                  (row["scene_id"], receiver) in witness_keys and
                  type(fact) is str and GM.fullmatch(fact))),
                "causal_npc_reaction_invalid",
                "Autonomous decision lacks trusted participating witnesses")
        out_reactions.append({
            "scene_id": row["scene_id"],
            "source_quote_sha256": scene["source_quote_sha256"],
            "actor_id": by_ref[ref],
            "trigger_memory_id": row["trigger_memory_id"],
            "minimum_trust": row["minimum_trust"],
            "response_memory_id": row["response_memory_id"],
            "next_goal_id": row["next_goal_id"],
            "relay_fact_id": fact,
            "relay_to_actor_id": by_ref[receiver] if receiver else None,
        })
    out_delayed = []
    used_triggers = set()
    produced = {(row["actor_id"], row["response_memory_id"])
                for row in out_reactions}
    for row in delayed:
        fields(row, {
            "scene_id", "actor_ref", "trigger_memory_id",
            "turns_after_trigger", "minimum_trust",
            "response_memory_id", "next_goal_id",
        }, "source-delayed autonomous NPC decision")
        scene = by_id.get(row["scene_id"])
        ref = row["actor_ref"]
        key = (ref, row["trigger_memory_id"])
        response_key = (by_ref.get(ref), row["response_memory_id"])
        require(scene is not None and ref in by_ref and
                (row["scene_id"], ref) in witness_keys and
                next(w["mode"] for w in witnesses
                     if w["scene_id"] == row["scene_id"] and
                     w["ref"] == ref) == "present" and
                type(row["turns_after_trigger"]) is int and
                1 <= row["turns_after_trigger"] <= 32 and
                type(row["minimum_trust"]) is int and
                -100 <= row["minimum_trust"] <= 100 and
                all(type(row[field]) is str and GM.fullmatch(row[field])
                    for field in ("trigger_memory_id",
                                  "response_memory_id", "next_goal_id")) and
                row["trigger_memory_id"] != row["response_memory_id"] and
                key not in used_triggers and response_key not in produced,
                "causal_delayed_decision_unproven",
                "Autonomous delayed NPC response has no source-locked trigger")
        used_triggers.add(key)
        produced.add(response_key)
        out_delayed.append({
            "scene_id": row["scene_id"],
            "source_quote_sha256": scene["source_quote_sha256"],
            "actor_id": by_ref[ref],
            "trigger_memory_id": row["trigger_memory_id"],
            "turns_after_trigger": row["turns_after_trigger"],
            "minimum_trust": row["minimum_trust"],
            "response_memory_id": row["response_memory_id"],
            "next_goal_id": row["next_goal_id"],
        })
    return {
        "witnesses": out_witnesses, "invariants": out_invariants,
        "npc_reactions": out_reactions,
        "npc_delayed_decisions": out_delayed,
        "actor_ids": actor_ids, "ref_to_actor": by_ref,
    }


def _predicate(value: dict, actor_ids: set[str], blueprint: dict):
    fields(value, {"op", "actor_id", "id", "value"}, "causal prerequisite")
    op, actor, key, val = (value[x] for x in ("op", "actor_id", "id", "value"))
    all_actors = {"player", *actor_ids}
    require(op in VALID_OPS and actor in all_actors,
            "causal_invalid_actor", "Unknown actor or predicate operation")
    gm = lambda x: type(x) is str and GM.fullmatch(x)
    allowed_fact = key in blueprint["facts"] or gm(key)
    allowed_item = key in blueprint["items"] or gm(key)
    if op in ("fact_known", "fact_unknown"):
        ok = allowed_fact and val is None
    elif op == "item_owner":
        ok = allowed_item and val in all_actors
    elif op in ("memory_present", "memory_absent", "goal_is",
                "promise_open", "promise_closed"):
        ok = actor != "player" and gm(key) and val is None
    elif op in ("trust_min", "trust_max"):
        ok = actor != "player" and key is None and type(val) is int and -100 <= val <= 100
    elif op == "life_is":
        ok = actor != "player" and key is None and val in ("present", "absent", "dead")
    elif op == "flag_is":
        ok = (actor == "player" and
              type(key) is str and
              key in blueprint["initial_state"]["flags"] and
              type(val) is bool)
    else:
        ok = False
    require(ok, "causal_invalid_prerequisite",
            "Source-only prerequisite uses an unapproved fact, NPC or item")


def _effect(value: dict, actor_ids: set[str], blueprint: dict):
    require(type(value) is dict and value.get("op") in EFFECT_OPS,
            "causal_invalid_effect", "Unrecognized native typed effect")
    op, key = value["op"], value.get("id")
    expected = {
        "learn_fact": {"op", "id", "actor"},
        "grant_item": {"op", "id"},
        "consume_item": {"op", "id"},
        "stat_delta": {"op", "id", "amount"},
        "set_flag": {"op", "id", "value"},
        "advance_time": {"op", "amount"},
    }[op]
    fields(value, expected, "causal effect")
    if op == "learn_fact":
        ok = key in blueprint["facts"] and value["actor"] in {"player", *actor_ids}
    elif op in ("grant_item", "consume_item"):
        ok = key in blueprint["items"]
    elif op == "stat_delta":
        ok = (key in blueprint["initial_state"]["stats"] and
              type(value["amount"]) is int and
              0 < abs(value["amount"]) <= 1000)
    elif op == "set_flag":
        ok = (key in blueprint["initial_state"]["flags"] and
              type(value["value"]) is bool)
    else:
        ok = type(value["amount"]) is int and 1 <= value["amount"] <= 1000
    require(ok, "causal_invalid_effect", "Event changes unapproved game state")


def _window(answer: dict, requested: list[dict], scene_order: dict,
            cast: dict, blueprint: dict) -> list[dict]:
    fields(answer, {"window_id", "events"}, "full-book causal window")
    require(answer["window_id"] == requested[0]["window_id"] and
            type(answer["events"]) is list and
            len(answer["events"]) == len(requested),
            "causal_window_incomplete",
            "Every original scene in the window requires review")
    expected = {v["scene_id"] for v in requested}
    seen = set()
    output = []
    for row in answer["events"]:
        fields(row, {"scene_id", "evidence_quote", "depends_on",
                     "preconditions", "effects", "causal_reason",
                     "unresolved"}, "literary causal event")
        sid = row["scene_id"]
        reference = next((s for s in requested if s["scene_id"] == sid), None)
        require(sid in expected and sid not in seen and reference is not None,
                "causal_window_duplicate", "Wrong source window scene")
        seen.add(sid)
        quote = row["evidence_quote"]
        require(type(quote) is str and
                quote in [e["quote"] for e in reference["source_evidence"]],
                "causal_quote_hallucinated", "Literary event cites other source text")
        reason = row["causal_reason"]
        require(type(reason) is str and 20 <= len(reason.strip()) <= 1500 and
                type(row["unresolved"]) is bool,
                "causal_reason_missing", "Each event requires an explanation")
        causes = row["depends_on"]
        checks = row["preconditions"]
        effects = row["effects"]
        require(type(causes) is list and len(causes) <= 64 and
                all(type(x) is str for x in causes) and
                len(set(causes)) == len(causes) and
                all(x in scene_order and scene_order[x] < scene_order[sid]
                    for x in causes) and
                type(checks) is list and len(checks) <= 32 and
                type(effects) is list and len(effects) <= 24,
                "causal_forward_cycle", "Causal predecessors cannot be future events")
        for cond in checks:
            _predicate(cond, cast["actor_ids"], blueprint)
        for effect in effects:
            _effect(effect, cast["actor_ids"], blueprint)
        output.append({
            "scene_id": sid, "source_quote_sha256": reference["source_quote_sha256"],
            "depends_on": causes, "preconditions": checks, "effects": effects,
            "_causal_reason": reason, "_unresolved": row["unresolved"],
        })
    require(set(scene_order[x] for x in seen) ==
            set(scene_order[x] for x in expected),
            "causal_window_missing", "Causal window cannot silently omit source")
    return output


def author_causal_v5(*, project_root: Path, base_world: Path,
                     workdir: Path, output: Path, provider,
                     user_confirmed: bool = False,
                     native_root: Path | None = None,
                     world_output: Path | None = None) -> dict:
    """Whole-book private ChatGPT analysis -> reviewed *DRAFT* for native v2.

    Output is NEVER a .bworld. The native importer must revalidate the
    returned JSON+SHA against the exact original archive/edition.
    """
    if (native_root is None) != (world_output is None):
        require(False, "causal_native_paths",
                "Supply both native root and private .bworld output")
    if world_output is not None:
        world_output = outside_repository(world_output)
        require(world_output.suffix.lower() == ".bworld" and
                not world_output.exists(),
                "causal_native_paths", "Native compiled target must be a fresh .bworld")
    project_root, base_world = outside_repository(project_root), outside_repository(base_world)
    workdir, output = outside_repository(workdir), outside_repository(output)
    require(project_root != workdir and project_root not in workdir.parents and
            workdir not in project_root.parents and output.suffix == ".json" and
            not output.is_symlink(),
            "causal_private_paths", "Keep the source and original private review separate")
    _, state, index, _, _ = project.load_project(project_root)
    data = _read_native_base(base_world, index)
    scenes, blueprint = _indexed_source(index, data)
    workdir.mkdir(parents=True, exist_ok=True, mode=0o700)
    fingerprint = index["source_fingerprint"]
    cast_payload = {
        "book_title": index["title"], "source_fingerprint": fingerprint,
        "base_archive_sha256": data["archive_sha256"],
        "source_scene_count": len(scenes),
        "source_scene_excerpt_catalog": [
            {"scene_id": s["scene_id"], "chapter_index": s["chapter_index"],
             "source_excerpt": s["scene_text_excerpt"][:120]}
            for s in scenes
        ],
        "instruction": "Identify important REAL book actors with first appearance, "
                       "witnesses, future obligations and source-reviewed NPC decisions. "
                       "Use only these source passages, never invent a character.",
    }
    require(len(canonical(cast_payload)) <= 450 * 1024,
            "causal_cast_context_over_budget",
            "Source NPC roster exceeds one verified private Skill context; "
            "review it in multiple source windows, never truncate.")
    cast_answer = provider.ask("causal_npc", cast_payload)
    cast = _cast(cast_answer, scenes, index)
    scene_order = {scene["scene_id"]: i for i, scene in enumerate(scenes)}
    assembled = []
    for offset in range(0, len(scenes), WINDOW):
        rows = scenes[offset:offset + WINDOW]
        window_id = f"w{offset:04d}_{offset + len(rows) - 1:04d}"
        request = [
            {"window_id": window_id,
             **{k: v for k, v in s.items() if not k.startswith("_")}}
            for s in rows
        ]
        payload = {
            "window_id": window_id,
            "source_fingerprint": fingerprint,
            "source_scenes": request,
            "reviewed_npc_actor_ids": cast["ref_to_actor"],
            "already_reviewed_causal_event_ids":
                [event["scene_id"] for event in assembled[-16:]],
            "instruction": "Cite the literal exact source_quote, explain causes "
                           "and implications and type preconditions/effects. "
                           "Report unresolved rather than guessing a fact, "
                           "goal or obligation. Include every source scene.",
        }
        answer = provider.ask("causal_window", payload)
        assembled.extend(_window(answer, request, scene_order, cast, blueprint))
    unresolved = [x["scene_id"] for x in assembled if x["_unresolved"]]
    report = provider.ask("causal_literary_review", {
        "source_fingerprint": fingerprint,
        "base_archive_sha256": data["archive_sha256"],
        "event_count": len(assembled),
        "all_scene_reviews": [
            {"scene_id": x["scene_id"],
             "causal_reason": x["_causal_reason"],
             "unresolved": x["_unresolved"]}
            for x in assembled
        ],
        "unresolved_scene_ids": unresolved,
        "reviewed_npc_count": len(cast["actor_ids"]),
        "instruction": "Independent literary check: each source event is cited "
                       "and its motivation and downstream obligations coherent. "
                       "Return fail if any source premise is unproven.",
    })
    fields(report, {"verdict", "reviewed_scene_ids", "explanation"},
           "independent literary causal review")
    require(report["verdict"] in ("pass", "fail") and
            report["reviewed_scene_ids"] ==
                [s["scene_id"] for s in scenes] and
            type(report["explanation"]) is str and
            20 <= len(report["explanation"].strip()) <= 4000,
            "causal_literary_review_invalid",
            "Reviewer must check each scene of the exact same source")
    ready = (not unresolved and report["verdict"] == "pass" and
             user_confirmed is True)
    if not ready:
        return {
            "status": "needs_private_literary_or_user_review",
            "source_scene_count": len(scenes),
            "unresolved_scene_ids": unresolved,
            "review_verdict": report["verdict"],
            "user_confirmed": user_confirmed,
            "game_created": False,
            "native_causal_archive_compiled": False,
        }
    review = {
        "format": FORMAT,
        "review_scope": "human_reviewed_private_story_causality",
        "source_fingerprint": fingerprint,
        "base_archive_sha256": data["archive_sha256"],
        "user_confirmed": True,
        "semantic_canon_automatically_verified": False,
        "witnesses": cast["witnesses"],
        "invariants": cast["invariants"],
        "event_graph": [
            {key: value for key, value in row.items()
             if not key.startswith("_")}
            for row in assembled
        ],
        "npc_reactions": cast["npc_reactions"],
        "npc_delayed_decisions": cast["npc_delayed_decisions"],
    }
    encoded = canonical(review)
    require(len(encoded) <= 4 * 1024 * 1024,
            "causal_review_over_budget", "Native review size exceeds 4MiB")
    if output.exists():
        # Resume only if byte-identical, source-locked and fully reviewed.
        # Failed Dart compiles must not force a new literary answer or
        # silently overwrite an earlier approved review.
        require(not output.is_symlink() and read_bytes(output) == encoded,
                "causal_review_changed",
                "Existing private review differs from the reviewed source")
    else:
        atomic_write(output, encoded)
    world = None
    if native_root is not None:
        # The executable compiler MUST be the native PR#133 CLI, never a
        # Python reimplementation of game rules or a model-created ZIP.
        native_root = Path(native_root).expanduser().resolve()
        script = native_root / "apps/rpg_cli/bin/rpg_cli.dart"
        require(script.is_file() and
                (native_root / "packages/rpg_api/lib/rpg_api.dart").is_file() and
                shutil.which("dart") is not None,
                "native_v5_compiler_unavailable",
                "The separate checked-out native RPG project and Dart are required")
        from .project import _get
        source_bytes = _get(project_root, state["source_bytes_sha256"])
        with tempfile.TemporaryDirectory(prefix="causal_v5_native_",
                                          dir=workdir) as tmp:
            temp_source = Path(tmp) / state["source_name"]
            atomic_write(temp_source, source_bytes)
            command = [
                "dart", "run", "bin/rpg_cli.dart",
                "compile-reviewed-causal-v5",
                "--book", str(temp_source),
                "--base-world", str(base_world),
                "--review", str(output),
                "--approved-digest", digest(b"source-causal-review-v1\n" + encoded),
                "--user-confirmed", "true",
                "--output", str(world_output),
            ]
            try:
                reply = subprocess.run(command,
                                       cwd=native_root / "apps/rpg_cli",
                                       stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE,
                                       encoding="utf-8", timeout=180)
            except (OSError, subprocess.TimeoutExpired) as exc:
                raise RuntimeError(
                    "Native v5 CLI did not complete: no .bworld was accepted") from exc
            require(reply.returncode == 0,
                    "native_v5_compile_rejected",
                    "The real Dart importer rejected this book/source review: "
                    + reply.stderr[-1200:])
            try:
                outcome = parse_json(reply.stdout.encode("utf-8"))
            except (UnicodeError, ValueError) as exc:
                raise ValueError("Native v5 compiler returned invalid JSON") from exc
            require(type(outcome) is dict and
                    outcome.get("status") == "private_causal_v5_compiled" and
                    outcome.get("source_fingerprint") == fingerprint and
                    outcome.get("reviewed_npc_count") == len(cast["actor_ids"]) and
                    world_output.is_file() and
                    outcome.get("world_hash") ==
                        digest(read_bytes(world_output, 12 * 1024 * 1024)),
                    "native_v5_compiler_inconsistent",
                    "The native v5 result does not match verified source/archive bytes")
            world = {
                "native_archive": str(world_output),
                "world_hash": outcome["world_hash"],
                "native_rpg_engine_used": True,
                "no_python_game_engine": True,
            }
    return {
        "status": "private_causal_v5_native_compiled" if world else
                  "review_ready_for_native_compiler",
        "review_json_path": str(output),
        "approved_digest": digest(b"source-causal-review-v1\n" + encoded),
        "base_archive_sha256": data["archive_sha256"],
        "source_scene_count": len(scenes),
        "npc_actor_count": len(cast["actor_ids"]),
        "source_reviewed": True,
        "automatic_literary_canon_proven": False,
        "native_causal_archive_compiled": world is not None,
        "native_result": world,
    }
