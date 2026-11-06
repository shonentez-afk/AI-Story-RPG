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
import re

from tools.bookworld import bookworld as legacy
from tools.bookworld import private_bookworld as v2

PATHS = v2.PATHS
PROVENANCE_FORMAT = "ai_story_private_provenance_v2"
BUILD_TOOL = {"name": "ai_story_private_rich_bookworld", "version": "3.0"}
MAX_SCENES = 192
MAX_STATES = 2500


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


# Keep in lockstep with RichSceneDialogue.parse in bookworld_format.
# Names are never inferred: unattributed quotes remain narrator prose.
_ATTRIBUTED = re.compile(
    r'^([А-ЯЁA-Z][А-Яа-яЁёA-Za-z0-9 .-]{0,49}):[ \t]*(«[^»\n]{1,1200}»|"[^"\n]{1,1200}"|—[ \t]*[^\n]{1,1200})[.!?]?
    expected = {"hero", "item_names", "item_descriptions",
                "stat_names", "fact_names", "scene_names"}
    has_dialogues = type(meta) is dict and "scene_dialogues" in meta
    if has_dialogues:
        expected.add("scene_dialogues")
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
        # Comparison is with the signed scene text, NOT a second model
        # response, and catches omitted scenes/lines and forged speakers.
        if signed != expected_dialogues:
            fail("Signed v3 dialogue diverges from exact scene text")


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
        valid = rule.get("id") in facts and rule.get("actor") == "player"
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
                                     ("actors", 1, 1)]:
        values = bp[catalog]
        if type(values) is not list or not minlen <= len(values) <= maxlen or \
                any(not _id(v) for v in values) or len(set(values)) != len(values):
            fail(f"Invalid {catalog} catalog")
    if bp["actors"] != ["player"]:
        fail("Only private player knowledge is supported in v3")
    state = bp["initial_state"]
    _keys(state, {"scene_id", "revision", "tick", "stats", "inventory",
                  "flags", "knowledge"}, "initial state")
    if state["scene_id"] != bp["entry_scene_id"] or \
            not _id(state["scene_id"]) or state["revision"] != 0 or \
            state["tick"] != 0 or state["inventory"] != [] or \
            state["knowledge"] != {"player": []}:
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
             (), tuple(sorted(initial["stats"].items())), ())
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
            dict(stat_entries), set(known_facts)
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
                    return rule["id"] in facts
                return False
            if not all(permits(r) for r in choice["conditions"]):
                continue
            available += 1
            f, it, st, fa = set(flags), set(items), dict(stats), set(facts)
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
                    fa.add(key)
            nxt = (choice["next_scene_id"], tuple(sorted(f)), tuple(sorted(it)),
                   tuple(sorted(st.items())), tuple(sorted(fa)))
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


def _provenance(prov, bp):
    keys = {"format", "bookworld_id", "source_fingerprint", "source_title",
            "source_author", "source_chapters_total", "source_chapters_indexed",
            "semantic_catalog_sha256", "intermediate_draft_sha256",
            "rights_status", "publication_authorized", "model_provenance",
            "scene_origins", "presentation"}
    _keys({k: v for k, v in prov.items() if k != "gameplay_review"},
          keys, "rich provenance")
    if prov["format"] != PROVENANCE_FORMAT:
        fail("Wrong rich provenance format")
    _model(prov["model_provenance"])
    _presentation(prov["presentation"], bp)
    if "gameplay_review" in prov:
        _gameplay_review(prov["gameplay_review"], bp, prov)
    old = dict(prov)
    old.pop("gameplay_review", None)
    old.pop("presentation")
    old["format"] = "ai_story_private_provenance_v1"
    old["model_provenance"] = {"provider": "none", "model_id": None}
    v2._valid_provenance(old, bp)
    return old


def _manifest(bp, prov, payloads):
    return {
        "format": "ai_story_bookworld", "format_version": 3,
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


def _presentation(meta, bp):
    _keys(meta, {"hero", "item_names", "item_descriptions",
                 "stat_names", "fact_names", "scene_names"}, "presentation")
    _keys(meta["hero"], {"name", "description"}, "hero")
    if not _txt(meta["hero"]["name"], 120) or \
            not _txt(meta["hero"]["description"], 1200):
        fail("Missing playable hero")
    _names(meta["item_names"], bp["items"], 100)
    _names(meta["item_descriptions"], bp["items"], 400)
    _names(meta["stat_names"], bp["initial_state"]["stats"], 100)
    _names(meta["fact_names"], bp["facts"], 180)
    _names(meta["scene_names"], (s["id"] for s in bp["scenes"]), 120)


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
        valid = rule.get("id") in facts and rule.get("actor") == "player"
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
                                     ("actors", 1, 1)]:
        values = bp[catalog]
        if type(values) is not list or not minlen <= len(values) <= maxlen or \
                any(not _id(v) for v in values) or len(set(values)) != len(values):
            fail(f"Invalid {catalog} catalog")
    if bp["actors"] != ["player"]:
        fail("Only private player knowledge is supported in v3")
    state = bp["initial_state"]
    _keys(state, {"scene_id", "revision", "tick", "stats", "inventory",
                  "flags", "knowledge"}, "initial state")
    if state["scene_id"] != bp["entry_scene_id"] or \
            not _id(state["scene_id"]) or state["revision"] != 0 or \
            state["tick"] != 0 or state["inventory"] != [] or \
            state["knowledge"] != {"player": []}:
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
             (), tuple(sorted(initial["stats"].items())), ())
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
            dict(stat_entries), set(known_facts)
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
                    return rule["id"] in facts
                return False
            if not all(permits(r) for r in choice["conditions"]):
                continue
            available += 1
            f, it, st, fa = set(flags), set(items), dict(stats), set(facts)
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
                    fa.add(key)
            nxt = (choice["next_scene_id"], tuple(sorted(f)), tuple(sorted(it)),
                   tuple(sorted(st.items())), tuple(sorted(fa)))
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


def _provenance(prov, bp):
    keys = {"format", "bookworld_id", "source_fingerprint", "source_title",
            "source_author", "source_chapters_total", "source_chapters_indexed",
            "semantic_catalog_sha256", "intermediate_draft_sha256",
            "rights_status", "publication_authorized", "model_provenance",
            "scene_origins", "presentation"}
    _keys({k: v for k, v in prov.items() if k != "gameplay_review"},
          keys, "rich provenance")
    if prov["format"] != PROVENANCE_FORMAT:
        fail("Wrong rich provenance format")
    _model(prov["model_provenance"])
    _presentation(prov["presentation"], bp)
    if "gameplay_review" in prov:
        _gameplay_review(prov["gameplay_review"], bp, prov)
    old = dict(prov)
    old.pop("gameplay_review", None)
    old.pop("presentation")
    old["format"] = "ai_story_private_provenance_v1"
    old["model_provenance"] = {"provider": "none", "model_id": None}
    v2._valid_provenance(old, bp)
    return old


def _manifest(bp, prov, payloads):
    return {
        "format": "ai_story_bookworld", "format_version": 3,
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
