"""Exact NPC scene presence + committed social actions in private rich-v3.

This synthetic test does NOT assert literary truth or actual GLM authoring.
"""
from copy import deepcopy
import unittest

from tools.bookworld import bookworld as legacy
from tools.bookworld import private_rich_bookworld as rich
from tools.bookworld.tests.test_rich_npc_knowledge import NPC, reviewed_sample


def social_sample():
    bp, prov, index = reviewed_sample()
    quote = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
    # This choice is gated by the real NPC promise/trust contract alone,
    # not by the older actor-specific fact predicate.
    bp["scenes"][0]["choices"][1]["conditions"].clear()
    bp["scenes"][0]["text"] = (
        "Встреча у ворот.\n"
        "Мария: «Я услышала обещание!»\n"
        "Игрок: «Обещаю».")
    prov["presentation"]["scene_dialogues"] = {
        "entry": rich._exact_scene_dialogue(bp["scenes"][0]["text"]),
    }
    prov["presentation"]["scene_dialogue_knowledge"] = {
        "entry": [
            {
                "turn_index": 1, "speaker": "Мария", "actor_id": NPC,
                "required_fact_ids": [],
                "required_social_memory_id": "guard_observed_promise",
                "minimum_trust_to_player": 7,
            },
            {
                "turn_index": 2, "speaker": "Игрок", "actor_id": "player",
                "required_fact_ids": [],
            },
        ],
    }
    prov["npc_social"] = {
        "format": rich.NPC_SOCIAL_GATE_FORMAT,
        "review_scope": "user_declared_private_game_fiction",
        "source_fingerprint": bp["source_fingerprint"],
        "user_confirmed": True,
        "literary_canon_verified": False,
        "witnesses": [{
            "scene_id": "entry", "actor_id": NPC, "mode": "present",
            "source_quote_sha256": quote,
        }],
        "rules": [{
            "memory_id": "guard_observed_promise", "scene_id": "entry",
            "choice_id": "wait", "observer_id": NPC,
            "kind": "promiseReceived", "related_actor_id": "player",
            "relationship_delta": 7, "max_triggers": 1,
            "source_quote_sha256": quote,
        }],
        "choice_gates": [{
            "scene_id": "entry", "choice_id": "help", "actor_id": NPC,
            "required_memory_id": "guard_observed_promise",
            "minimum_trust_to_player": 7,
            "source_quote_sha256": quote,
        }],
    }
    return bp, prov, index


def item_social_sample():
    """Two explicitly reviewed transfers of the SAME item, no duplicate."""
    bp, prov, index = social_sample()
    bp["items"].append("map")
    entry = bp["scenes"][0]
    choices = entry["choices"]
    next_scene = entry["id"]
    for option in choices:
        if option["id"] == "wait":
            option["effects"].append({"op": "grant_item", "id": "map"})
    choices.extend([
        {
            "id": "give_map", "label": "Передать карту NPC",
            "next_scene_id": next_scene,
            "conditions": [{"op": "has_item", "id": "map"}],
            "effects": [{"op": "consume_item", "id": "map"}],
        },
        {
            "id": "return_map", "label": "Получить карту обратно",
            "next_scene_id": next_scene,
            "conditions": [],
            "effects": [{"op": "grant_item", "id": "map"}],
        },
    ])
    prov["presentation"]["item_names"]["map"] = "Карта"
    prov["presentation"]["item_descriptions"]["map"] = (
        "Предмет, владелец которого проверяется игровым журналом")
    source_sha = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
    social = prov["npc_social"]
    social["format"] = rich.NPC_SOCIAL_ITEM_FORMAT
    social["item_transfers"] = [
        {
            "scene_id": "entry", "choice_id": "give_map",
            "item_id": "map", "from_actor_id": "player",
            "to_actor_id": NPC, "source_quote_sha256": source_sha,
        },
        {
            "scene_id": "entry", "choice_id": "return_map",
            "item_id": "map", "from_actor_id": NPC,
            "to_actor_id": "player", "source_quote_sha256": source_sha,
        },
    ]
    return bp, prov, index

def two_npc_item_social_sample():
    """A signed two-NPC private fixture using the SAME world/schema/SQLite.

    Both witnesses and their memories arise from one executable player
    decision. Future NPC dialogue is gated until that event is committed.
    Literary CANON is intentionally not claimed by this synthetic sample.
    """
    bp, prov, index = item_social_sample()
    second = "npc_" + "d" * 32
    bp["actors"].append(second)
    bp["initial_state"]["knowledge"][second] = []
    entry = bp["scenes"][0]
    entry["text"] = chr(10).join([
        "Встреча у ворот.",
        "Мария: «Я услышала обещание!»",
        "Иван: «Я тоже видел обещание».",
        "Игрок: «Обещаю».",
    ])
    signed = rich._exact_scene_dialogue(entry["text"])
    if signed is None or len(signed["turns"]) != 4:
        raise AssertionError("Two-NPC source dialogue did not tokenize exactly")
    prov["presentation"]["scene_dialogues"] = {"entry": signed}
    former = prov["presentation"]["scene_dialogue_knowledge"]["entry"]
    player = dict(former[1])
    player["turn_index"] = 3
    prov["presentation"]["scene_dialogue_knowledge"]["entry"] = [
        former[0],
        {
            "turn_index": 2, "speaker": "Иван", "actor_id": second,
            "required_fact_ids": [],
            "required_social_memory_id": "ivan_observed_promise",
        },
        player,
    ]
    social = prov["npc_social"]
    quote = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
    social["witnesses"].append({
        "scene_id": "entry", "actor_id": second, "mode": "present",
        "source_quote_sha256": quote,
    })
    social["rules"].append({
        "memory_id": "ivan_observed_promise",
        "scene_id": "entry", "choice_id": "wait",
        "observer_id": second, "kind": "promiseReceived",
        "related_actor_id": "player", "relationship_delta": 3,
        "max_triggers": 1, "source_quote_sha256": quote,
    })
    return bp, prov, index


def authored_item_social_sample():
    bp, prov, index = item_social_sample()
    origin = prov["scene_origins"][0]
    quote = origin["source_refs"][0]["quote_sha256"]
    prov["npc_social"]["format"] = rich.NPC_SOCIAL_AUTHOR_ITEM_FORMAT
    prov["npc_social"]["item_grants"] = [{
        "scene_id": "entry", "choice_id": "wait",
        "item_id": "map", "source_quote_sha256": quote,
    }]
    return bp, prov, index


class RichNpcSocialTests(unittest.TestCase):
    def test_source_reviewed_two_npc_runtime_fixture(self):
        bp, source, index = two_npc_item_social_sample()
        archive = rich.build(bp, source, index)
        inspected = rich.verify(archive)
        self.assertEqual(inspected["format_version"], 3)
        self.assertEqual(set(bp["actors"]),
                         {"player", "npc_" + "c" * 32, "npc_" + "d" * 32})
        self.assertEqual(len(source["npc_social"]["rules"]), 2)
        self.assertEqual(len(source["presentation"]
                             ["scene_dialogue_knowledge"]["entry"]), 3)
        self.assertEqual(archive, rich.build(bp, source, index))

    def test_v5_source_approved_life_events_and_negative_contracts(self):
        bp, prov, source = social_sample()
        social = prov["npc_social"]
        quote = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
        social["format"] = rich.NPC_SOCIAL_LIFE_FORMAT
        social["item_transfers"] = []
        social["item_grants"] = []
        social["life_transitions"] = [{
            "scene_id": "entry", "choice_id": "wait",
            "actor_id": NPC, "next_state": "absent",
            "source_quote_sha256": quote,
        }]
        archive = rich.build(bp, prov, source)
        self.assertEqual(rich.verify(archive)["format_version"], 3)
        self.assertEqual(archive, rich.build(bp, prov, source))
        for field, value in (
                ("next_state", "revived"),
                ("actor_id", "player"),
                ("choice_id", "missing"),
                ("source_quote_sha256", "f" * 64)):
            alt_bp, alt_prov, alt_source = deepcopy((bp, prov, source))
            alt_prov["npc_social"]["life_transitions"][0][field] = value
            with self.subTest(field=field), self.assertRaises(
                    legacy.BookworldError):
                rich.build(alt_bp, alt_prov, alt_source)
        alt_bp, alt_prov, alt_source = deepcopy((bp, prov, source))
        alt_prov["npc_social"]["life_transitions"] *= 2
        with self.assertRaises(legacy.BookworldError):
            rich.build(alt_bp, alt_prov, alt_source)
        alt_bp, alt_prov, alt_source = deepcopy((bp, prov, source))
        alt_prov["npc_social"]["life_transitions"] = []
        with self.assertRaises(legacy.BookworldError):
            rich.build(alt_bp, alt_prov, alt_source)
        # The source review does not silently upgrade an old version.
        alt_bp, alt_prov, alt_source = deepcopy((bp, prov, source))
        alt_prov["npc_social"]["format"] = rich.NPC_SOCIAL_AUTHOR_ITEM_FORMAT
        with self.assertRaises(legacy.BookworldError):
            rich.build(alt_bp, alt_prov, alt_source)

    def test_bounded_source_review_writer_verifier_old_format_parity(self):
        bp, prov, source = social_sample()
        archive = rich.build(bp, prov, source)
        self.assertEqual(rich.verify(archive)["format_version"], 3)
        self.assertEqual(archive, rich.build(bp, prov, source))

        del prov["npc_social"]
        for spoken in prov["presentation"]["scene_dialogue_knowledge"]["entry"]:
            spoken.pop("required_social_memory_id", None)
            spoken.pop("minimum_trust_to_player", None)
        previous = rich.build(bp, prov, source)
        self.assertEqual(rich.verify(previous)["format_version"], 3)

    def test_invalid_source_presence_actor_trust_or_unapproved_rules(self):
        variants = (
            "no_approval", "fake_quote", "wrong_scene", "unknown_actor",
            "missing_witness", "duplicate_witness", "reported_trust",
            "report_not_eye", "future_quote", "orphan_witness",
            "invalid_relation", "duplicate_rule", "unexpected_field",
        )
        for name in variants:
            with self.subTest(name=name):
                bp, prov, index = social_sample()
                social = prov["npc_social"]
                witness = social["witnesses"][0]
                rule = social["rules"][0]
                if name == "no_approval":
                    social["user_confirmed"] = False
                elif name == "fake_quote":
                    rule["source_quote_sha256"] = "f" * 64
                elif name == "wrong_scene":
                    witness["scene_id"] = "missing"
                elif name == "unknown_actor":
                    witness["actor_id"] = "npc_" + "d" * 32
                elif name == "missing_witness":
                    social["witnesses"].clear()
                elif name == "duplicate_witness":
                    social["witnesses"].append(deepcopy(witness))
                elif name == "reported_trust":
                    witness["mode"] = "reported"
                elif name == "report_not_eye":
                    witness["mode"] = "reported"
                    rule["kind"] = "betrayed"
                    rule["relationship_delta"] = 0
                elif name == "future_quote":
                    social["witnesses"][0]["source_quote_sha256"] = "f" * 64
                elif name == "orphan_witness":
                    social["rules"][0]["observer_id"] = "player"
                elif name == "invalid_relation":
                    rule["related_actor_id"] = NPC
                elif name == "duplicate_rule":
                    social["rules"].append(deepcopy(rule))
                elif name == "unexpected_field":
                    rule["fake_social_authority"] = True
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_spoiler_dialogue_requires_reviewed_memory_and_trust(self):
        for mutation in ("missing_social", "wrong_memory", "missing_actor",
                         "false_trust", "missing_review"):
            with self.subTest(mutation=mutation):
                bp, prov, index = social_sample()
                review = prov["presentation"]["scene_dialogue_knowledge"]
                turn = review["entry"][0]
                if mutation == "missing_social":
                    del prov["npc_social"]
                elif mutation == "wrong_memory":
                    turn["required_social_memory_id"] = "fake_memory"
                elif mutation == "missing_actor":
                    turn["actor_id"] = "player"
                elif mutation == "false_trust":
                    turn["minimum_trust_to_player"] = -100
                elif mutation == "missing_review":
                    del prov["presentation"]["scene_dialogue_knowledge"]
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_reviewed_authoritative_social_choice_gate_rejects_tampering(self):
        for mutation in ("wrong_memory", "missing_target", "wrong_actor",
                         "threshold_bool", "threshold_large", "fake_quote",
                         "duplicate", "self_condition", "no_approval",
                         "empty_gates"):
            with self.subTest(mutation=mutation):
                bp, prov, index = social_sample()
                gate = prov["npc_social"]["choice_gates"][0]
                if mutation == "wrong_memory":
                    gate["required_memory_id"] = "unreviewed_memory"
                elif mutation == "missing_target":
                    gate["choice_id"] = "invisible_choice"
                elif mutation == "wrong_actor":
                    gate["actor_id"] = "npc_" + "b" * 32
                elif mutation == "threshold_bool":
                    gate["minimum_trust_to_player"] = True
                elif mutation == "threshold_large":
                    gate["minimum_trust_to_player"] = 101
                elif mutation == "fake_quote":
                    gate["source_quote_sha256"] = "f" * 64
                elif mutation == "duplicate":
                    prov["npc_social"]["choice_gates"].append(deepcopy(gate))
                elif mutation == "self_condition":
                    gate["choice_id"] = "wait"
                elif mutation == "no_approval":
                    prov["npc_social"]["user_confirmed"] = False
                elif mutation == "empty_gates":
                    prov["npc_social"]["choice_gates"] = []
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_approved_references_still_cannot_form_a_memory_cycle(self):
        bp, prov, index = social_sample()
        social = prov["npc_social"]
        quote = prov["scene_origins"][0]["source_refs"][0]["quote_sha256"]
        social["rules"].append({
            "memory_id": "learned_after_help", "scene_id": "entry",
            "choice_id": "help", "observer_id": NPC,
            "kind": "witnessed", "related_actor_id": None,
            "relationship_delta": 0, "max_triggers": 1,
            "source_quote_sha256": quote,
        })
        social["choice_gates"].append({
            "scene_id": "entry", "choice_id": "wait", "actor_id": NPC,
            "required_memory_id": "learned_after_help",
            "minimum_trust_to_player": None,
            "source_quote_sha256": quote,
        })
        with self.assertRaises(legacy.BookworldError):
            rich.build(bp, prov, index)

    def test_native_item_creation_is_source_reviewed_not_minted(self):
        bp, prov, index = authored_item_social_sample()
        archive = rich.build(bp, prov, index)
        self.assertEqual(rich.verify(archive)["format_version"], 3)
        self.assertEqual(archive, rich.build(bp, prov, index))
        for change in ("absent_grant", "invented_item", "unseen_quote",
                       "other_choice", "duplicate_grant", "unreviewed_mint",
                       "before_acquisition", "initial_inventory"):
            with self.subTest(change=change):
                bp, prov, index = authored_item_social_sample()
                grants = prov["npc_social"]["item_grants"]
                if change == "absent_grant":
                    grants.clear()
                elif change == "invented_item":
                    grants[0]["item_id"] = "fake_item"
                elif change == "unseen_quote":
                    grants[0]["source_quote_sha256"] = "f" * 64
                elif change == "other_choice":
                    grants[0]["choice_id"] = "give_map"
                elif change == "duplicate_grant":
                    grants.append(deepcopy(grants[0]))
                elif change == "unreviewed_mint":
                    next(c for c in bp["scenes"][0]["choices"]
                         if c["id"] == "help")["effects"].append(
                             {"op": "grant_item", "id": "map"})
                elif change == "before_acquisition":
                    grants[0]["choice_id"] = "return_map"
                elif change == "initial_inventory":
                    bp["initial_state"]["inventory"].append("map")
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_owned_npc_item_transfers_are_portable_and_source_locked(self):
        bp, prov, index = item_social_sample()
        archive = rich.build(bp, prov, index)
        self.assertEqual(rich.verify(archive)["format_version"], 3)
        self.assertEqual(archive, rich.build(bp, prov, index))
        for mutation in ("forged_item", "absent_actor", "duplicate",
                         "fake_quote", "missing_effect", "self_transfer",
                         "unreviewed_witness", "missing_source_review"):
            with self.subTest(mutation=mutation):
                bp, prov, index = item_social_sample()
                social = prov["npc_social"]
                transfer = social["item_transfers"][0]
                if mutation == "forged_item":
                    transfer["item_id"] = "nonexistent"
                elif mutation == "absent_actor":
                    transfer["to_actor_id"] = "npc_" + "b" * 32
                elif mutation == "duplicate":
                    social["item_transfers"].append(deepcopy(transfer))
                elif mutation == "fake_quote":
                    transfer["source_quote_sha256"] = "f" * 64
                elif mutation == "missing_effect":
                    next(c for c in bp["scenes"][0]["choices"]
                         if c["id"] == "give_map")["effects"].clear()
                elif mutation == "self_transfer":
                    transfer["from_actor_id"] = NPC
                elif mutation == "unreviewed_witness":
                    social["witnesses"][0]["mode"] = "reported"
                elif mutation == "missing_source_review":
                    del social["item_transfers"]
                with self.assertRaises(legacy.BookworldError):
                    rich.build(bp, prov, index)

    def test_reported_rumor_cannot_grant_trust(self):
        bp, prov, index = social_sample()
        social = prov["npc_social"]
        social["witnesses"][0]["mode"] = "reported"
        social["rules"][0]["kind"] = "rumorHeard"
        social["rules"][0]["relationship_delta"] = 0
        social["rules"][0]["related_actor_id"] = None
        social["format"] = rich.NPC_SOCIAL_FORMAT
        del social["choice_gates"]
        for spoken in prov["presentation"]["scene_dialogue_knowledge"]["entry"]:
            spoken.pop("minimum_trust_to_player", None)
        self.assertEqual(rich.verify(rich.build(bp, prov, index))
                         ["format_version"], 3)


if __name__ == "__main__":
    unittest.main()
