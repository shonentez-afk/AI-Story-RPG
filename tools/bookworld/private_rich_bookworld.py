"""Experimental *source-bound* private BookWorld v3 with real game state.

Independent compiler; does not alter or weaken BookWorld v1/v2 readers.
Same four strict ZIP_STORED members, but v3 requires a richer blueprint,
explicit actual AI provenance, localized presentation and a bounded causal
simulation including inventory/stat/knowledge effects.

This proves structural/source integrity, never literary or legal truth.
"""
from __future__ import annotations

from collections import deque
import io
import stat
import zipfile
import hashlib
import json
import re

from tools.bookworld import bookworld as legacy
from tools.bookworld import private_bookworld as v2

PATHS = v2.PATHS
PROVENANCE_FORMAT = "ai_story_private_provenance_v2"
BUILD_TOOL = {"name": "ai_story_private_rich_bookworld", "version": "3.0"}
MAX_SCENES = 192
MAX_STATES = 2500
NPC_GRANTS_FORMAT = "ai_story_npc_knowledge_grants_v1"
NPC_SOCIAL_FORMAT = "ai_story_npc_social_witness_v1"
NPC_SOCIAL_GATE_FORMAT = "ai_story_npc_social_witness_v2"
NPC_SOCIAL_ITEM_FORMAT = "ai_story_npc_social_witness_v3"
NPC_SOCIAL_AUTHOR_ITEM_FORMAT = "ai_story_npc_social_witness_v4"
NPC_SOCIAL_LIFE_FORMAT = "ai_story_npc_social_witness_v5"


def fail(message: str):
    raise legacy.BookworldError(message)


def _keys(value, expected: set, where):
    if type(value) is not dict or set(value) != expected:
        fail(f"{where}: unknown or missing fields")


def _id(value):
    return isinstance(value, str) and bool(legacy.ID_RE.fullmatch(value))


def _txt(value, limit=160):
    return isinstance(value, str) and bool(value.strip()) and len(value) <= limit


def _names(catalog, ids, limit):
    if type(catalog) is not dict or set(catalog) != set(ids) or \
            any(not _txt(name, limit) for name in catalog.values()):
        fail("Missing or unsafe localized catalog labels")


def _model(value):
    _keys(value, {"provider", "model_id", "model_id_status", "tool", "method"},
          "model provenance")
    if value["provider"] == "openai":
        if value["model_id"] not in (None, "gpt-6") or \
                value["model_id_status"] != ("user_declared" if value["model_id"]
                                             else "not_attested") or \
                value["tool"] != "ChatGPT" or value["method"] != "external":
            fail("Unverified or incompatible model attribution")
    elif value["provider"] == "zai":
        # The application requested this precise model through z.ai.
        # "requested" does NOT assert that a server response was audited.
        if value != {"provider": "zai", "model_id": "glm-4.7-flash",
                     "model_id_status": "requested",
                     "tool": "AI Story RPG", "method": "built_in"}:
            fail("Unverified built-in GLM attribution")
    elif value["provider"] == "unknown":
        # A locally reviewed draft can originate from a model or a human.
        # Do not falsely claim non-AI authorship or an attested model.
        if value != {"provider": "unknown", "model_id": None,
                     "model_id_status": "not_attested",
                     "tool": "AI Story RPG",
                     "method": "reviewed_local_compilation"}:
            fail("Invalid unattested model provenance")
    elif value != {"provider": "none", "model_id": None,
                   "model_id_status": "not_applicable", "tool": "none",
                   "method": "local_fixture"}:
        fail("Unknown model provenance")


# Identical to RichSceneDialogue.parse in bookworld_format.
# Only explicit speaker labels in already signed prose may become dialogue.
_ATTRIBUTED = re.compile(
    r'^([А-ЯЁA-Z][А-Яа-яЁёA-Za-z0-9 .-]{0,49}):[ \t]*(«[^»\n]{1,1200}»|"[^"\n]{1,1200}"|—[ \t]*[^\n]{1,1200})[.!?]?$'
)


def _exact_scene_dialogue(text):
    if not isinstance(text, str) or not text.strip() or len(text) > 50000:
        return None
    turns, speakers, spoken = [], set(), 0
    for source in text.replace("\r\n", "\n").split("\n"):
        line = source.strip()
        if not line:
            continue
        match = _ATTRIBUTED.fullmatch(line)
        if match is None:
            if len(line) > 5000:
                return None
            turns.append({"speaker": None, "text": line})
        else:
            speaker, speech = match.group(1).strip(), match.group(2).strip()
            if not speaker:
                return None
            if (speech.startswith("«") and speech.endswith("»")) or \
                    (speech.startswith('"') and speech.endswith('"')):
                speech = speech[1:-1].strip()
            elif speech.startswith("—"):
                speech = speech[1:].strip()
            if not speech:
                return None
            turns.append({"speaker": speaker, "text": speech})
            speakers.add(speaker)
            spoken += 1
        if len(turns) > 64:
            return None
    if spoken < 2 or len(speakers) < 2:
        return None
    return {
        "scene_text_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "turns": turns,
    }


def _presentation(meta, bp, social=None, origins=None):
    expected = {"hero", "item_names", "item_descriptions",
                "stat_names", "fact_names", "scene_names"}
    has_dialogues = type(meta) is dict and "scene_dialogues" in meta
    has_npc_review = type(meta) is dict and "scene_dialogue_knowledge" in meta
    has_responses = type(meta) is dict and "scene_dialogue_responses" in meta
    if has_dialogues:
        expected.add("scene_dialogues")
    if has_npc_review:
        expected.add("scene_dialogue_knowledge")
    if has_responses:
        expected.add("scene_dialogue_responses")
    _keys(meta, expected, "presentation")
    _keys(meta["hero"], {"name", "description"}, "hero")
    if not _txt(meta["hero"]["name"], 120) or \
            not _txt(meta["hero"]["description"], 1200):
        fail("Missing playable hero")
    _names(meta["item_names"], bp["items"], 100)
    _names(meta["item_descriptions"], bp["items"], 400)
    _names(meta["stat_names"], bp["initial_state"]["stats"], 100)
    _names(meta["fact_names"], bp["facts"], 180)
    _names(meta["scene_names"], (s["id"] for s in bp["scenes"]), 120)
    if has_dialogues:
        signed = meta["scene_dialogues"]
        if type(signed) is not dict:
            fail("Wrong v3 signed dialogue map")
        expected_dialogues = {}
        for scene in bp["scenes"]:
            parsed = _exact_scene_dialogue(scene["text"])
            if parsed is not None:
                expected_dialogues[scene["id"]] = parsed
        if signed != expected_dialogues:
            fail("Signed v3 dialogue diverges from exact scene text")

    npc_ids = set(bp["actors"]) - {"player"}
    reviewed = meta.get("scene_dialogue_knowledge")
    dialogue_scenes = meta.get("scene_dialogues", {})
    if npc_ids:
        # Omitting the optional signed projection must not revive legacy
        # unguarded parsing of NPC speech in a rich world.
        for scene in bp["scenes"]:
            if _exact_scene_dialogue(scene["text"]) is not None and \
                    scene["id"] not in dialogue_scenes:
                fail("Structured NPC speech requires signed reviewed turns")
    if not npc_ids:
        if has_npc_review:
            fail("Unexpected NPC speaker review in player-only world")
    elif not dialogue_scenes:
        if reviewed not in (None, {}):
            fail("NPC speaker review lacks signed scene")
    else:
        if type(reviewed) is not dict or set(reviewed) != set(dialogue_scenes):
            fail("Incomplete reviewed NPC speaker scenes")
        for scene_id, signed in dialogue_scenes.items():
            spoken = {i: turn["speaker"] for i, turn in
                      enumerate(signed["turns"]) if turn["speaker"] is not None}
            entries = reviewed[scene_id]
            if type(entries) is not list or len(entries) != len(spoken):
                fail("NPC spoken lines are missing review")
            seen = set()
            for entry in entries:
                required = {"turn_index", "speaker", "actor_id",
                            "required_fact_ids"}
                extra = {"required_social_memory_id",
                         "minimum_trust_to_player",
                         "required_prior_choice_id", "source_quote_sha256",
                         "private_fiction_confirmed"}
                if type(entry) is not dict or not required.issubset(entry) or \
                        set(entry).difference(required | extra):
                    fail("NPC spoken line has unreviewed social fields")
                index, actor, facts = (entry["turn_index"],
                                       entry["actor_id"],
                                       entry["required_fact_ids"])
                if type(index) is not int or index not in spoken or \
                        index in seen or entry["speaker"] != spoken[index] or \
                        actor not in bp["actors"] or \
                        (actor != "player" and actor not in npc_ids) or \
                        type(facts) is not list or len(facts) > 16 or \
                        any(type(fact) is not str or fact not in bp["facts"]
                            for fact in facts) or \
                        facts != sorted(set(facts)):
                    fail("Tampered NPC dialogue identity or secret gate")
                if "required_social_memory_id" in entry:
                    memory_id = entry["required_social_memory_id"]
                    if actor == "player" or type(social) is not dict or \
                            not isinstance(memory_id, str) or \
                            not any(rule["observer_id"] == actor and
                                    rule["memory_id"] == memory_id
                                    for rule in social["rules"]):
                        fail("Unreviewed NPC memory dialogue prerequisite")
                if "minimum_trust_to_player" in entry:
                    threshold = entry["minimum_trust_to_player"]
                    if actor == "player" or type(social) is not dict or \
                            type(threshold) is not int or \
                            not 1 <= threshold <= 100 or \
                            not any(rule["observer_id"] == actor and
                                    rule["related_actor_id"] == "player" and
                                    rule["relationship_delta"] > 0
                                    for rule in social["rules"]):
                        fail("Unreviewed NPC trust dialogue prerequisite")

                # All three keys are one explicit private-fiction gate.
                # A source quote grounds an earlier event but NEVER proves
                # that the NPC spoke the generated words in the book.
                has_prior = "required_prior_choice_id" in entry
                has_quote = "source_quote_sha256" in entry
                has_consent = "private_fiction_confirmed" in entry
                if has_prior or has_quote or has_consent:
                    prior = entry.get("required_prior_choice_id")
                    quote = entry.get("source_quote_sha256")
                    if not (has_prior and has_quote and has_consent) or \
                            entry.get("private_fiction_confirmed") is not True or \
                            actor == "player" or \
                            type(prior) is not str or type(quote) is not str or \
                            len(quote) != 64 or \
                            any(c not in "0123456789abcdef" for c in quote):
                        fail("Unapproved causal NPC line")
                    producers = [
                        (scene, choice)
                        for scene in bp["scenes"]
                        for choice in scene["choices"]
                        if choice["id"] == prior
                    ]
                    producer_scene, producer = (
                        producers[0] if len(producers) == 1 else (None, None)
                    )
                    origin_by_id = {
                        src["scene_id"]: src for src in (origins or [])
                    }
                    source = origin_by_id.get(
                        producer_scene["id"] if producer_scene else None)
                    target = origin_by_id.get(scene_id)
                    scene_graph = {
                        scene["id"]: [
                            choice["next_scene_id"] for choice in scene["choices"]
                        ] for scene in bp["scenes"]
                    }
                    reachable = False
                    if producer is not None:
                        todo, seen_scenes = [producer["next_scene_id"]], set()
                        while todo:
                            point = todo.pop()
                            if point == scene_id:
                                reachable = True
                                break
                            if point not in seen_scenes:
                                seen_scenes.add(point)
                                todo.extend(scene_graph.get(point, []))
                    if source is None or target is None or \
                            producer_scene["id"] == scene_id or \
                            not reachable or \
                            source["origin"] != "SOURCE_PASSAGE" or \
                            source["chapter_index"] > target["chapter_index"] or \
                            not any(
                                ref["quote_sha256"] == quote and
                                ref["visible_after_chapter"] <=
                                source["chapter_index"]
                                for ref in source["source_refs"]
                            ) or not all(
                                {"op": "learn_fact", "id": fact, "actor": actor}
                                in producer["effects"] for fact in facts
                            ):
                        fail("Causal NPC line lacks a source-bound learning event")
                seen.add(index)
            if seen != set(spoken):
                fail("Incomplete reviewed NPC dialogue turns")

    _npc_dialogue_responses(meta, bp, social, origins)


def _npc_dialogue_responses(meta, bp, social, origins):
    groups = meta.get("scene_dialogue_responses")
    if groups is None:
        return  # old signed rich-v3 world remains compatible
    if type(groups) is not dict or not 1 <= len(groups) <= 48 or \
            type(meta.get("scene_dialogues")) is not dict or \
            type(meta.get("scene_dialogue_knowledge")) is not dict or \
            bp["rights_status"] != "private_adaptation":
        fail("NPC response metadata needs complete signed review")
    scenes = {scene["id"]: scene for scene in bp["scenes"]}
    origin_map = {o["scene_id"]: o for o in origins}
    for scene_id, rows in groups.items():
        scene = scenes.get(scene_id)
        origin = origin_map.get(scene_id)
        reviews = meta["scene_dialogue_knowledge"].get(scene_id)
        if not scene or scene_id not in meta["scene_dialogues"] or \
                type(reviews) is not list or \
                not origin or origin["origin"] != "SOURCE_PASSAGE" or \
                type(rows) is not list or \
                not 2 <= len(scene["choices"]) <= 16 or \
                len(rows) != len(scene["choices"]) or scene["terminal"]:
            fail("NPC responses need signed source dialogue and choices")
        turns = meta["scene_dialogues"][scene_id]["turns"]
        actors = set()
        for review in reviews:
            i = review["turn_index"]
            if type(i) is not int or i < 0 or i >= len(turns) or \
                    turns[i]["speaker"] != review["speaker"]:
                fail("NPC response speaker review changed")
            if review["actor_id"] != "player":
                actors.add(review["actor_id"])
        if not actors:
            fail("NPC reply lacks permanent interlocutor")
        outcomes = set()
        for choice in scene["choices"]:
            memories = sorted([
                [rule["observer_id"], rule["memory_id"],
                 rule["relationship_delta"], rule["related_actor_id"]]
                for rule in (social or {}).get("rules", [])
                if rule["scene_id"] == scene_id and
                   rule["choice_id"] == choice["id"]
            ], key=lambda row: str(row))
            signature = {
                "next": choice["next_scene_id"],
                "effects": [
                    [effect["op"], effect.get("id"), effect.get("actor"),
                     effect.get("amount"), effect.get("value")]
                    for effect in choice["effects"]
                ],
                "npc_memories": memories,
            }
            outcomes.add(json.dumps(signature, sort_keys=True,
                                    separators=(",", ":"), ensure_ascii=False))
        if len(outcomes) < 2:
            fail("NPC reply choices have identical outcomes")
        used = set()
        for row in rows:
            expected = {"choice_id", "interlocutor_id", "player_line",
                        "source_quote_sha256", "private_fiction_confirmed"}
            if type(row) is not dict or set(row) != expected:
                fail("Unknown NPC reply fields")
            choice = row["choice_id"]
            actor = row["interlocutor_id"]
            line = row["player_line"]
            quote = row["source_quote_sha256"]
            if type(choice) is not str or choice in used or \
                    choice not in {c["id"] for c in scene["choices"]} or \
                    type(actor) is not str or actor not in actors or \
                    re.fullmatch(r"npc_[0-9a-f]{32}", actor) is None or \
                    type(line) is not str or not 4 <= len(line) <= 220 or \
                    line.strip() != line or \
                    any(c in line for c in ('«', '»', '"')) or \
                    any(ord(c) < 32 or ord(c) == 127 for c in line) or \
                    type(quote) is not str or \
                    re.fullmatch(r"[0-9a-f]{64}", quote) is None or \
                    row["private_fiction_confirmed"] is not True:
                fail("Unapproved or forged NPC reply line")
            if not any(ref["quote_sha256"] == quote and
                       ref["chapter_index"] <= origin["chapter_index"] and
                       ref["visible_after_chapter"] <= origin["chapter_index"]
                       for ref in origin["source_refs"]):
                fail("NPC reply is not source-bound")
            if social is not None:
                if not any(w["scene_id"] == scene_id and
                           w["actor_id"] == actor and w["mode"] == "present"
                           for w in social["witnesses"]):
                    fail("NPC reply lacks signed eyewitness presence")
                if any(e["actor_id"] == actor
                       for e in social.get("life_transitions", [])) and \
                        not any(g["scene_id"] == scene_id and
                                g["choice_id"] == choice and
                                g["actor_id"] == actor
                                for g in social.get("choice_gates", [])):
                    fail("NPC life-state dialogue needs core choice gate")
            used.add(choice)
        if used != {c["id"] for c in scene["choices"]}:
            fail("Unreviewed NPC reply option")


def _check_rule(rule, bp, effect):
    if type(rule) is not dict or not isinstance(rule.get("op"), str):
        fail("Non-typed game rule")
    op = rule["op"]
    inv = set(bp["items"])
    flags = set(bp["initial_state"]["flags"])
    facts = set(bp["facts"])
    stats = set(bp["initial_state"]["stats"])
    if op in (("grant_item", "consume_item") if effect else ("has_item",)):
        required = {"op", "id"}
        valid = rule.get("id") in inv
    elif op in (("set_flag",) if effect else ("flag_is",)):
        required = {"op", "id", "value"}
        valid = rule.get("id") in flags and type(rule.get("value")) is bool
    elif op in (("stat_delta",) if effect else ("stat_at_least",)):
        required = {"op", "id", "amount"}
        value = rule.get("amount")
        valid = rule.get("id") in stats and type(value) is int and (
            (-20 <= value <= 20 and value != 0) if effect else 0 <= value <= 1000000)
    elif op in (("learn_fact",) if effect else ("knows_fact",)):
        required = {"op", "id", "actor"}
        valid = rule.get("id") in facts and rule.get("actor") in bp["actors"]
    else:
        fail(f"Disallowed rich private rule {op}")
    if not valid or set(rule) != required:
        fail(f"Invalid references or arguments in {op}")


def _blueprint(bp):
    _keys(bp, {"format", "schema_version", "book_id", "title",
               "entry_scene_id", "rights_status", "source_fingerprint",
               "supported_modes", "items", "facts", "actors",
               "initial_state", "scenes"}, "blueprint v3")
    if bp["format"] != "ai_story_blueprint_v1" or \
            type(bp["schema_version"]) is not int or bp["schema_version"] != 1 or \
            bp["rights_status"] != "private_adaptation" or \
            not isinstance(bp["source_fingerprint"], str) or \
            not legacy.SHA_RE.fullmatch(bp["source_fingerprint"]) or \
            not _id(bp["book_id"]) or not _txt(bp["title"], 256) or \
            bp["supported_modes"] != {
                "roles": ["PROTAGONIST"], "plots": ["ALTER_FATE"],
                "interactions": ["CLASSIC"]}:
        fail("Wrong private rich identity/modes")
    for catalog, minlen, maxlen in [("items", 0, 32),
                                     ("facts", 0, 64),
                                     ("actors", 1, 16)]:
        values = bp[catalog]
        if type(values) is not list or not minlen <= len(values) <= maxlen or \
                any(not _id(v) for v in values) or len(set(values)) != len(values):
            fail(f"Invalid {catalog} catalog")
    if "player" not in bp["actors"]:
        fail("Private world requires player actor")
    if len(bp["actors"]) > 1 and any(
            not re.fullmatch(r"npc_[0-9a-f]{32}", actor)
            for actor in bp["actors"] if actor != "player"):
        fail("NPC needs permanent character_id")
    state = bp["initial_state"]
    _keys(state, {"scene_id", "revision", "tick", "stats", "inventory",
                  "flags", "knowledge"}, "initial state")
    if state["scene_id"] != bp["entry_scene_id"] or \
            not _id(state["scene_id"]) or state["revision"] != 0 or \
            state["tick"] != 0 or state["inventory"] != [] or \
            (type(state["knowledge"]) is not dict or
             set(state["knowledge"]) != set(bp["actors"]) or
             any(facts != [] for facts in state["knowledge"].values())):
        fail("Invalid rich initial state")
    stats, flags = state["stats"], state["flags"]
    if type(stats) is not dict or not 0 <= len(stats) <= 8 or \
            any(not _id(k) or type(v) is not int or v < 0 or v > 1000
                for k, v in stats.items()) or \
            type(flags) is not dict or len(flags) > 32 or \
            any(not _id(k) or type(v) is not bool for k, v in flags.items()):
        fail("Invalid initial hero stats or flags")
    scenes = bp["scenes"]
    if type(scenes) is not list or not 3 <= len(scenes) <= MAX_SCENES:
        fail("Incorrect scene count")
    scene_ids, choice_ids = set(), set()
    endings = set()
    for scene in scenes:
        _keys(scene, {"id", "text", "terminal", "choices"}, "scene")
        if not _id(scene["id"]) or scene["id"] in scene_ids or \
                not _txt(scene["text"], 6000) or \
                type(scene["terminal"]) is not bool or \
                type(scene["choices"]) is not list or \
                len(scene["choices"]) > 16 or \
                scene["terminal"] == bool(scene["choices"]):
            fail("Invalid rich scene")
        scene_ids.add(scene["id"])
        if scene["terminal"]:
            endings.add(scene["id"])
        for choice in scene["choices"]:
            _keys(choice, {"id", "label", "next_scene_id",
                           "conditions", "effects"}, "choice")
            if not _id(choice["id"]) or choice["id"] in choice_ids or \
                    not _id(choice["next_scene_id"]) or \
                    not _txt(choice["label"], 300) or \
                    type(choice["conditions"]) is not list or \
                    type(choice["effects"]) is not list or \
                    len(choice["conditions"]) > 32 or \
                    len(choice["effects"]) > 32:
                fail("Invalid rich choice")
            choice_ids.add(choice["id"])
            for condition in choice["conditions"]:
                _check_rule(condition, bp, False)
            for effect in choice["effects"]:
                _check_rule(effect, bp, True)
    if bp["entry_scene_id"] not in scene_ids or len(endings) < 2 or \
            any(c["next_scene_id"] not in scene_ids for s in scenes
                for c in s["choices"]):
        fail("Unreachable entry, missing ending or dangling destination")
    _causality(bp)


def _causality(bp):
    scenes = {s["id"]: s for s in bp["scenes"]}
    granted_items = {r["id"] for s in bp["scenes"] for c in s["choices"]
                     for r in c["effects"] if r["op"] == "grant_item"}
    learned_facts = {r["id"] for s in bp["scenes"] for c in s["choices"]
                     for r in c["effects"] if r["op"] == "learn_fact"}
    changed_stats = {r["id"] for s in bp["scenes"] for c in s["choices"]
                     for r in c["effects"] if r["op"] == "stat_delta"}
    if granted_items != set(bp["items"]) or learned_facts != set(bp["facts"]):
        fail("Unreachable item/fact catalog")
    initial = bp["initial_state"]
    start = (bp["entry_scene_id"],
             tuple(sorted(k for k, v in initial["flags"].items() if v)),
             (), tuple(sorted(initial["stats"].items())),
             tuple((actor, ()) for actor in sorted(bp["actors"])))
    seen = {start}
    queue = deque([start])
    parents = {}
    visited, terminals, endings = set(), set(), set()

    while queue:
        if len(seen) > MAX_STATES:
            fail("Rich causality exceeds bounded state budget")
        state = queue.popleft()
        scene_id, active_flags, owned_items, stat_entries, known_facts = state
        visited.add(scene_id)
        scene = scenes[scene_id]
        if scene["terminal"]:
            terminals.add(state)
            endings.add(scene_id)
            continue
        flags, items, stats, facts = set(active_flags), set(owned_items), \
            dict(stat_entries), {actor: set(values)
                                 for actor, values in known_facts}
        available = 0
        for choice in scene["choices"]:
            def permits(rule):
                op = rule["op"]
                if op == "has_item":
                    return rule["id"] in items
                if op == "flag_is":
                    return (rule["id"] in flags) == rule["value"]
                if op == "stat_at_least":
                    return stats[rule["id"]] >= rule["amount"]
                if op == "knows_fact":
                    return rule["id"] in facts[rule["actor"]]
                return False
            if not all(permits(r) for r in choice["conditions"]):
                continue
            available += 1
            f, it, st, fa = set(flags), set(items), dict(stats), {
                actor: set(values) for actor, values in facts.items()
            }
            for effect in choice["effects"]:
                op, key = effect["op"], effect["id"]
                if op == "grant_item":
                    it.add(key)
                elif op == "consume_item":
                    if key not in it:
                        fail("Available choice consumes an unowned item")
                    it.remove(key)
                elif op == "set_flag":
                    if effect["value"]:
                        f.add(key)
                    else:
                        f.discard(key)
                elif op == "stat_delta":
                    st[key] += effect["amount"]
                    if st[key] < 0 or st[key] > 1000000:
                        fail("Stat goes outside engine bounds")
                elif op == "learn_fact":
                    fa[effect["actor"]].add(key)
            nxt = (choice["next_scene_id"], tuple(sorted(f)), tuple(sorted(it)),
                   tuple(sorted(st.items())),
                   tuple((actor, tuple(sorted(values)))
                         for actor, values in sorted(fa.items())))
            parents.setdefault(nxt, set()).add(state)
            if nxt not in seen:
                seen.add(nxt)
                queue.append(nxt)
        if available == 0:
            fail("Rich scenario has a playable dead end")
    if len(endings) < 2 or visited != set(scenes):
        fail("Some game scenes or endings are unreachable")
    can_exit = set(terminals)
    work = list(terminals)
    while work:
        current = work.pop()
        for parent in parents.get(current, ()):
            if parent not in can_exit:
                can_exit.add(parent)
                work.append(parent)
    if can_exit != seen:
        fail("Rich scenario contains a state without path to any ending")


def _gameplay_review(review, bp, prov):
    """A declared private adaptation, NEVER an attestation of literary canon.

    Review data is bound to exact source-scene citation hashes and the actual
    typed effects. The importer checks it even when an attacker rehashes ZIP.
    """
    _keys(review, {"format", "review_scope", "source_fingerprint",
                   "base_archive_sha256", "source_payload_digest",
                   "user_confirmed", "literary_canon_verified", "effects"},
          "gameplay review")
    if review["format"] != "ai_story_private_gameplay_review_m2h8e1_v1" or \
            review["review_scope"] != "user_declared_private_game_fiction" or \
            review["source_fingerprint"] != bp["source_fingerprint"] or \
            review["user_confirmed"] is not True or \
            review["literary_canon_verified"] is not False or \
            not isinstance(review["base_archive_sha256"], str) or \
            not legacy.SHA_RE.fullmatch(review["base_archive_sha256"]) or \
            not isinstance(review["source_payload_digest"], str) or \
            not legacy.SHA_RE.fullmatch(review["source_payload_digest"]):
        fail("Incorrect private gameplay review declaration")
    effects = review["effects"]
    if type(effects) is not list or not (1 <= len(effects) <= 6):
        fail("Empty or oversized accepted gameplay effects")
    sources = {o["scene_id"]: o for o in prov["scene_origins"]}
    scenes = {s["id"]: s for s in bp["scenes"]}
    names = prov["presentation"]
    seen = set()
    for effect in effects:
        _keys(effect, {"scene_id", "choice_id", "op", "kind", "id",
                       "label", "source_quote_sha256", "review_note"},
              "reviewed gameplay effect")
        scene, choice, op, kind, key = (effect["scene_id"],
                                        effect["choice_id"],
                                        effect["op"], effect["kind"],
                                        effect["id"])
        note = effect["review_note"]
        label = effect["label"]
        source_sha = effect["source_quote_sha256"]
        if not all(_id(value) for value in (scene, choice, key)) or \
                not _txt(label, 120) or not _txt(note, 350) or \
                len(note) < 18 or not isinstance(source_sha, str) or \
                not legacy.SHA_RE.fullmatch(source_sha) or \
                not ((kind == "item" and op in ("grant_item", "consume_item"))
                     or (kind == "fact" and op == "learn_fact")):
            fail("Invalid gameplay review reference or semantic type")
        signature = (scene, choice, op, key)
        if signature in seen:
            fail("Duplicate reviewed effect")
        seen.add(signature)
        origin = sources.get(scene)
        if scene not in scenes or origin is None or \
                origin["origin"] != "SOURCE_PASSAGE" or \
                source_sha not in {r["quote_sha256"]
                                   for r in origin["source_refs"]}:
            fail("Gameplay claim lacks an original scene citation")
        matching = [c for c in scenes[scene]["choices"] if c["id"] == choice]
        if len(matching) != 1 or \
                sum(1 for e in matching[0]["effects"]
                    if e["op"] == op and e["id"] == key) != 1:
            fail("Reviewed effect does not match executable gameplay")
        if (kind == "item" and names["item_names"].get(key) != label) or \
                (kind == "fact" and names["fact_names"].get(key) != label):
            fail("Reviewed localized item or fact label mismatch")
    typed = {
        (s["id"], c["id"], e["op"], e["id"])
        for s in bp["scenes"] for c in s["choices"] for e in c["effects"]
        if e["op"] in ("grant_item", "consume_item", "learn_fact")
    }
    if seen != typed:
        fail("Unreviewed executable gameplay effect in a reviewed world")


def _npc_knowledge(prov, bp):
    """User-reviewed, source-linked NPC grants: no literary canon assertion.

    This explicit v1 extension is mandatory for any non-player knowledge in
    private rich v3. Old player-only archives remain byte-for-byte compatible.
    """
    npcs = set(bp["actors"]) - {"player"}
    extension = prov.get("npc_knowledge")
    if not npcs:
        if "npc_knowledge" in prov:
            fail("NPC review without NPC actors")
        return
    if not isinstance(extension, dict):
        fail("Unreviewed NPC actor catalog")
    _keys(extension, {"format", "review_scope", "source_fingerprint",
                      "user_confirmed", "literary_canon_verified", "grants"},
          "NPC knowledge review")
    if extension["format"] != NPC_GRANTS_FORMAT or \
            extension["review_scope"] != "user_declared_private_game_fiction" or \
            extension["source_fingerprint"] != bp["source_fingerprint"] or \
            extension["user_confirmed"] is not True or \
            extension["literary_canon_verified"] is not False:
        fail("Wrong NPC knowledge source/review")
    grants = extension["grants"]
    if type(grants) is not list or not 1 <= len(grants) <= 128:
        fail("Missing or oversized NPC grant evidence")
    scenes = {scene["id"]: scene for scene in bp["scenes"]}
    origins = {origin["scene_id"]: origin
               for origin in prov["scene_origins"]}
    if len(origins) != len(prov["scene_origins"]):
        fail("Duplicate NPC origin")
    reviewed = set()
    for grant in grants:
        _keys(grant, {"scene_id", "choice_id", "actor_id", "fact_id",
                      "source_quote_sha256"}, "NPC grant")
        sid, cid, actor, fact, quote = (
            grant["scene_id"], grant["choice_id"], grant["actor_id"],
            grant["fact_id"], grant["source_quote_sha256"])
        signature = (sid, cid, actor, fact)
        if not all(_id(value) for value in signature) or \
                actor not in npcs or fact not in bp["facts"] or \
                not isinstance(quote, str) or \
                not legacy.SHA_RE.fullmatch(quote) or \
                signature in reviewed:
            fail("Invalid or duplicate reviewed NPC grant")
        reviewed.add(signature)
        scene = scenes.get(sid)
        choices = [choice for choice in scene["choices"]
                   if choice["id"] == cid] if scene else []
        if len(choices) != 1 or sum(
                rule["op"] == "learn_fact" and
                rule.get("actor") == actor and rule.get("id") == fact
                for rule in choices[0]["effects"]) != 1:
            fail("Reviewed NPC grant does not exist as an action")
        origin = origins.get(sid)
        if not origin or origin["origin"] != "SOURCE_PASSAGE" or \
                not any(ref["quote_sha256"] == quote and
                        ref["visible_after_chapter"] <= origin["chapter_index"] and
                        ref["chapter_index"] <= origin["chapter_index"]
                        for ref in origin["source_refs"]):
            fail("NPC grant has no eligible source quotation")
    expected = {
        (scene["id"], choice["id"], effect["actor"], effect["id"])
        for scene in bp["scenes"] for choice in scene["choices"]
        for effect in choice["effects"]
        if effect["op"] == "learn_fact" and effect["actor"] != "player"
    }
    if expected != reviewed:
        fail("NPC knowledge actions do not match reviewed grant manifest")


def _npc_social(prov, bp):
    """Opt-in reviewed NPC witnesses and event classifications, not canon.

    Authoritative actions remain in the original deterministic event stream;
    this package only classifies hash-chained actions. It never fabricates
    presence, learns a secret, or grants an item based on prose inference.
    """
    reviewed = prov.get("npc_social")
    if reviewed is None:
        return
    life_format = (type(reviewed) is dict and
                   reviewed.get("format") == NPC_SOCIAL_LIFE_FORMAT)
    authored_item = (type(reviewed) is dict and
                     reviewed.get("format") == NPC_SOCIAL_AUTHOR_ITEM_FORMAT) or life_format
    item_format = (type(reviewed) is dict and
                   reviewed.get("format") == NPC_SOCIAL_ITEM_FORMAT) or authored_item
    gate_format = (type(reviewed) is dict and
                   reviewed.get("format") == NPC_SOCIAL_GATE_FORMAT) or item_format
    _keys(reviewed, {"format", "review_scope", "source_fingerprint",
                     "user_confirmed", "literary_canon_verified",
                     "witnesses", "rules"} |
          ({"choice_gates"} if gate_format else set()) |
          ({"item_transfers"} if item_format else set()) |
          ({"item_grants"} if authored_item else set()) |
          ({"life_transitions"} if life_format else set()), "NPC social")
    if reviewed["format"] not in (
            NPC_SOCIAL_FORMAT, NPC_SOCIAL_GATE_FORMAT,
            NPC_SOCIAL_ITEM_FORMAT, NPC_SOCIAL_AUTHOR_ITEM_FORMAT,
            NPC_SOCIAL_LIFE_FORMAT) or \
            reviewed["review_scope"] != "user_declared_private_game_fiction" or \
            reviewed["source_fingerprint"] != bp["source_fingerprint"] or \
            reviewed["user_confirmed"] is not True or \
            reviewed["literary_canon_verified"] is not False:
        fail("NPC social review is not authorized for this private source")
    witnesses, rules = reviewed["witnesses"], reviewed["rules"]
    if type(witnesses) is not list or type(rules) is not list or \
            not (0 if life_format else 1) <= len(witnesses) <= 128 or \
            not (0 if life_format else 1) <= len(rules) <= 128:
        fail("Missing or oversized NPC social declarations")
    origin = {item["scene_id"]: item
              for item in prov["scene_origins"]}
    if len(origin) != len(prov["scene_origins"]):
        fail("Ambiguous NPC scene evidence")
    scenes = {scene["id"]: scene for scene in bp["scenes"]}
    actors = set(bp["actors"])

    def citation(scene_id, digest):
        src = origin.get(scene_id)
        if not isinstance(digest, str) or \
                not legacy.SHA_RE.fullmatch(digest) or \
                src is None or src["origin"] != "SOURCE_PASSAGE":
            fail("Unverified NPC social quote")
        chapter = src["chapter_index"]
        if not any(ref["quote_sha256"] == digest and
                   ref["chapter_index"] <= chapter and
                   ref["visible_after_chapter"] <= chapter
                   for ref in src["source_refs"]):
            fail("NPC social witness cites absent or future passage")

    present = {}
    for row in witnesses:
        _keys(row, {"scene_id", "actor_id", "mode",
                    "source_quote_sha256"}, "NPC social witness")
        scene, actor, mode = (row["scene_id"], row["actor_id"], row["mode"])
        if not _id(scene) or scene not in scenes or \
                not _id(actor) or actor not in actors or actor == "player" or \
                not re.fullmatch(r"npc_[0-9a-f]{32}", actor) or \
                mode not in ("present", "reported") or \
                (scene, actor) in present:
            fail("NPC social witness is unknown/duplicated/unstable")
        citation(scene, row["source_quote_sha256"])
        present[(scene, actor)] = mode

    seen = set()
    used = set()
    memory_kinds = {"witnessed", "promiseReceived", "promiseBroken",
                    "helped", "betrayed", "rumorHeard"}
    for row in rules:
        _keys(row, {"memory_id", "scene_id", "choice_id", "observer_id",
                    "kind", "related_actor_id", "relationship_delta",
                    "max_triggers", "source_quote_sha256"}, "NPC social rule")
        memory, scene, choice, actor = (
            row["memory_id"], row["scene_id"],
            row["choice_id"], row["observer_id"])
        relation, delta, maximum = (
            row["related_actor_id"], row["relationship_delta"],
            row["max_triggers"])
        if not all(_id(v) for v in (memory, scene, choice, actor)) or \
                scene not in scenes or actor not in actors or \
                (actor != "player" and
                 not re.fullmatch(r"npc_[0-9a-f]{32}", actor)) or \
                not any(c["id"] == choice for c in scenes[scene]["choices"]) or \
                row["kind"] not in memory_kinds or \
                (relation is not None and
                 (not _id(relation) or relation not in actors or
                  relation == actor)) or \
                (relation != "player" and relation is not None and
                 not re.fullmatch(r"npc_[0-9a-f]{32}", relation)) or \
                type(delta) is not int or not -20 <= delta <= 20 or \
                type(maximum) is not int or not 1 <= maximum <= 10 or \
                (delta != 0 and relation is None) or \
                (actor, memory) in seen:
            fail("Invalid, inconsistent or duplicated NPC social memory")
        citation(scene, row["source_quote_sha256"])
        seen.add((actor, memory))
        if actor == "player":
            continue
        witness = present.get((scene, actor))
        if witness is None or \
                (witness == "reported" and
                 (row["kind"] != "rumorHeard" or delta != 0)):
            fail("NPC remembered an unseen event or rumor became trust")
        used.add((scene, actor))
    if item_format:
        transfers = reviewed["item_transfers"]
        if type(transfers) is not list or \
                not (0 if life_format else 1) <= len(transfers) <= 128:
            fail("Invalid NPC item custody review list")
        seen_transfers = set()
        for transfer in transfers:
            _keys(transfer, {"scene_id", "choice_id", "item_id",
                             "from_actor_id", "to_actor_id",
                             "source_quote_sha256"}, "NPC item transfer")
            scene, choice, item = (transfer["scene_id"],
                                   transfer["choice_id"],
                                   transfer["item_id"])
            sender, receiver = (transfer["from_actor_id"],
                                 transfer["to_actor_id"])
            if not all(_id(v) for v in (scene, choice, item,
                                         sender, receiver)) or \
                    scene not in scenes or item not in bp["items"] or \
                    sender not in actors or receiver not in actors or \
                    sender == receiver or \
                    ((sender == "player") == (receiver == "player")) or \
                    (scene, choice, item) in seen_transfers:
                fail("Invalid NPC item transfer identities")
            seen_transfers.add((scene, choice, item))
            npc = receiver if sender == "player" else sender
            if not re.fullmatch(r"npc_[0-9a-f]{32}", npc) or \
                    present.get((scene, npc)) != "present":
                fail("Item transfer NPC was not witnessed at the scene")
            citation(scene, transfer["source_quote_sha256"])
            choices = [c for c in scenes[scene]["choices"]
                       if c["id"] == choice]
            expected = "consume_item" if sender == "player" else "grant_item"
            if len(choices) != 1 or sum(
                    1 for effect in choices[0]["effects"]
                    if effect["op"] == expected and effect["id"] == item) != 1:
                fail("NPC item custody has no matching typed effect")
            used.add((scene, npc))

    if set(present) != used:
        fail("Orphaned or unreviewed NPC witness")

    if authored_item:
        grants = reviewed["item_grants"]
        if type(grants) is not list or \
                not (0 if life_format else 1) <= len(grants) <= 16 or \
                (life_format and not grants and reviewed["item_transfers"]):
            fail("Native item acquisition needs reviewed sources")
        origins = origin
        acquired = {}
        for grant in grants:
            _keys(grant, {"scene_id", "choice_id", "item_id",
                          "source_quote_sha256"}, "NPC item acquisition")
            scene, choice, item = (
                grant["scene_id"], grant["choice_id"], grant["item_id"])
            if not all(_id(v) for v in (scene, choice, item)) or \
                    item not in bp["items"] or item in acquired or \
                    item in bp["initial_state"]["inventory"] or \
                    scene not in scenes:
                fail("Unreviewed or duplicated NPC item acquisition")
            citation(scene, grant["source_quote_sha256"])
            eligible = [c for c in scenes[scene]["choices"]
                        if c["id"] == choice]
            if len(eligible) != 1 or sum(
                    e["op"] == "grant_item" and e["id"] == item
                    for e in eligible[0]["effects"]) != 1:
                fail("NPC item source must create exactly one typed item")
            acquired[item] = (scene, choice)
        transferred = {rule["item_id"] for rule in reviewed["item_transfers"]}
        if set(acquired) != transferred:
            fail("NPC item acquisition/transfer sets are inconsistent")
        for scene in bp["scenes"]:
            for choice in scene["choices"]:
                for effect in choice["effects"]:
                    item = effect.get("id")
                    if effect["op"] != "grant_item" or item not in acquired:
                        continue
                    source = acquired[item] == (scene["id"], choice["id"])
                    returned = any(
                        t["scene_id"] == scene["id"] and
                        t["choice_id"] == choice["id"] and
                        t["item_id"] == item and t["to_actor_id"] == "player"
                        for t in reviewed["item_transfers"])
                    if not source and not returned:
                        fail("Unreviewed extra item was created")
        for transfer in reviewed["item_transfers"]:
            item = transfer["item_id"]
            acq_scene, acq_choice = acquired[item]
            if origins[acq_scene]["chapter_index"] > \
                    origins[transfer["scene_id"]]["chapter_index"] or \
                    (acq_scene, acq_choice) == (
                        transfer["scene_id"], transfer["choice_id"]):
                fail("NPC item transferred before its source acquisition")

    if life_format:
        transitions = reviewed["life_transitions"]
        if type(transitions) is not list or not 1 <= len(transitions) <= 128:
            fail("Missing or oversized NPC life transitions")
        seen_life = set()
        for transition in transitions:
            _keys(transition, {"scene_id", "choice_id", "actor_id",
                               "next_state", "source_quote_sha256"},
                  "NPC life transition")
            scene, choice, actor = (transition["scene_id"],
                                    transition["choice_id"],
                                    transition["actor_id"])
            if not all(_id(v) for v in (scene, choice, actor)) or \
                    scene not in scenes or actor not in actors or \
                    not re.fullmatch(r"npc_[0-9a-f]{32}", actor) or \
                    transition["next_state"] not in ("present", "absent", "dead") or \
                    not any(c["id"] == choice
                            for c in scenes[scene]["choices"]) or \
                    (scene, choice, actor) in seen_life:
                fail("Invalid or duplicate NPC life event")
            citation(scene, transition["source_quote_sha256"])
            seen_life.add((scene, choice, actor))

    if gate_format:
        gates = reviewed["choice_gates"]
        if type(gates) is not list or len(gates) > 128 or \
                (not item_format and not gates):
            fail("NPC game choices need bounded reviewed social gates")
        seen_gates = set()
        for gate in gates:
            _keys(gate, {"scene_id", "choice_id", "actor_id",
                         "required_memory_id", "minimum_trust_to_player",
                         "source_quote_sha256"}, "NPC choice review")
            scene, choice, actor = (
                gate["scene_id"], gate["choice_id"], gate["actor_id"])
            memory, trust = (gate["required_memory_id"],
                             gate["minimum_trust_to_player"])
            if not all(_id(v) for v in (scene, choice, actor)) or \
                    scene not in scenes or actor not in actors or \
                    actor == "player" or \
                    not re.fullmatch(r"npc_[0-9a-f]{32}", actor) or \
                    not any(c["id"] == choice for c in
                            scenes[scene]["choices"]) or \
                    (scene, choice) in seen_gates or \
                    (memory is None and trust is None) or \
                    (memory is not None and not _id(memory)) or \
                    (trust is not None and
                     (type(trust) is not int or not 1 <= trust <= 100)):
                fail("Invalid NPC social choice identity/condition")
            seen_gates.add((scene, choice))
            citation(scene, gate["source_quote_sha256"])
            chapter = origin[scene]["chapter_index"]
            if memory is not None and not any(
                    rule["observer_id"] == actor and
                    rule["memory_id"] == memory and
                    origin[rule["scene_id"]]["chapter_index"] <= chapter
                    for rule in rules):
                fail("NPC choice requires future or unreviewed memory")
            if trust is not None and not any(
                    rule["observer_id"] == actor and
                    rule["related_actor_id"] == "player" and
                    rule["relationship_delta"] > 0 and
                    origin[rule["scene_id"]]["chapter_index"] <= chapter
                    for rule in rules):
                fail("NPC choice trust precedes its source event")
            if memory is not None and not any(
                    rule["observer_id"] == actor and
                    rule["memory_id"] == memory and
                    (rule["scene_id"], rule["choice_id"]) != (scene, choice)
                    for rule in rules):
                fail("NPC social choice cannot require unearned memory")
            if trust is not None and not any(
                    rule["observer_id"] == actor and
                    rule["related_actor_id"] == "player" and
                    rule["relationship_delta"] > 0 and
                    (rule["scene_id"], rule["choice_id"]) != (scene, choice)
                    for rule in rules):
                fail("NPC social choice cannot require unearned trust")

        # Match story_core: cyclic required-memory chains have no playable
        # starting choice, even if individual references look correct.
        gates_by_key = {(g["scene_id"], g["choice_id"]): g
                        for g in gates}
        visited, visiting = set(), set()

        def check_chain(key):
            if key in visited:
                return
            if key in visiting:
                fail("Circular NPC memory choice dependency")
            visiting.add(key)
            g = gates_by_key[key]
            required = g["required_memory_id"]
            if required is not None:
                rule = next(rule for rule in rules
                            if rule["observer_id"] == g["actor_id"] and
                            rule["memory_id"] == required)
                source = (rule["scene_id"], rule["choice_id"])
                if source in gates_by_key:
                    check_chain(source)
            visiting.remove(key)
            visited.add(key)

        for key in gates_by_key:
            check_chain(key)


def _provenance(prov, bp):
    keys = {"format", "bookworld_id", "source_fingerprint", "source_title",
            "source_author", "source_chapters_total", "source_chapters_indexed",
            "semantic_catalog_sha256", "intermediate_draft_sha256",
            "rights_status", "publication_authorized", "model_provenance",
            "scene_origins", "presentation"}
    _keys({k: v for k, v in prov.items()
           if k not in {"gameplay_review", "npc_knowledge", "npc_social"}},
          keys, "rich provenance")
    if prov["format"] != PROVENANCE_FORMAT:
        fail("Wrong rich provenance format")
    _model(prov["model_provenance"])
    _npc_social(prov, bp)
    _presentation(prov["presentation"], bp, prov.get("npc_social"),
                  prov["scene_origins"])
    _npc_knowledge(prov, bp)
    if "npc_knowledge" in prov and "gameplay_review" in prov:
        fail("NPC grant review and gameplay review must be unified")
    if "gameplay_review" in prov:
        _gameplay_review(prov["gameplay_review"], bp, prov)
    old = dict(prov)
    old.pop("gameplay_review", None)
    old.pop("npc_knowledge", None)
    old.pop("npc_social", None)
    old.pop("presentation")
    old["format"] = "ai_story_private_provenance_v1"
    old["model_provenance"] = {"provider": "none", "model_id": None}
    v2._valid_provenance(old, bp)
    return old


def _manifest(bp, prov, payloads):
    return {
        "format": "ai_story_bookworld", "format_version": 3,
        **({"npc_knowledge_format": NPC_GRANTS_FORMAT}
           if "npc_knowledge" in prov else {}),
        **({"npc_social_format": prov["npc_social"]["format"]}
           if "npc_social" in prov else {}),
        "bookworld_id": bp["book_id"],
        "source_fingerprint": bp["source_fingerprint"],
        "title": bp["title"], "author": prov["source_author"],
        "languages": ["ru"], "engine_min_version": "0.1.0",
        "scenario_format": "ai_story_blueprint_v1",
        "scenario_format_version": 1,
        "content_capabilities": bp["supported_modes"],
        "build_status": "private_rich_structural",
        "rights_status": "private_use_only",
        "build_tool": BUILD_TOOL,
        "model_provenance": prov["model_provenance"],
        "hashes": {name: legacy.digest(payloads[name]) for name in v2.PAYLOAD},
        "sizes": {name: len(payloads[name]) for name in v2.PAYLOAD},
        "blueprint_sha256": legacy.digest(payloads["scenario/blueprint.json"]),
    }


def build(blueprint: dict, provenance: dict, source_index: dict) -> bytes:
    _blueprint(blueprint)
    old = _provenance(provenance, blueprint)
    v2.verify_source_index(blueprint, old, source_index)
    payloads = {
        "scenario/blueprint.json": legacy.canonical(blueprint),
        "source/provenance.json": legacy.canonical(provenance),
        "world.sqlite": legacy.create_database(blueprint),
    }
    members = {"manifest.json": legacy.canonical(
        _manifest(blueprint, provenance, payloads)), **payloads}
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED,
                         allowZip64=False) as target:
        for path in PATHS:
            zi = zipfile.ZipInfo(path, date_time=legacy.ZIP_TIME)
            zi.compress_type = zipfile.ZIP_STORED
            zi.create_system = 3
            zi.external_attr = (stat.S_IFREG | 0o600) << 16
            target.writestr(zi, members[path])
    result = out.getvalue()
    if len(result) > legacy.MAX_ARCHIVE_BYTES:
        fail("Rich private archive exceeds size limit")
    verify(result)
    return result


def verify(archive: bytes) -> dict:
    files = v2._safe_entries(archive)
    bp = legacy.decode_object(files["scenario/blueprint.json"], "blueprint")
    prov = legacy.decode_object(files["source/provenance.json"], "provenance")
    manifest = legacy.decode_object(files["manifest.json"], "manifest")
    for path, obj in [("scenario/blueprint.json", bp),
                      ("source/provenance.json", prov), ("manifest.json", manifest)]:
        if files[path] != legacy.canonical(obj):
            fail("Non-canonical v3 JSON")
    _blueprint(bp)
    _provenance(prov, bp)
    if manifest != _manifest(bp, prov, {
            name: files[name] for name in v2.PAYLOAD}):
        fail("Manifest/provenance/rights/hash binding invalid")
    legacy._check_sqlite(files["world.sqlite"], bp)
    return {"bookworld_id": bp["book_id"],
            "source_fingerprint": bp["source_fingerprint"],
            "scene_count": len(bp["scenes"]),
            "archive_sha256": legacy.digest(archive),
            "private_only": True, "publication_authorized": False,
            "format_version": 3,
            "rich_gameplay": True}
