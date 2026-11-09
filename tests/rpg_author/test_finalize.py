"""Synthetic E6e finalization gates. Never place a real book in CI."""
from __future__ import annotations

from copy import deepcopy
import unittest

from tools.rpg_author.common import AuthoringError, canonical, digest
from tools.rpg_author.finalize import dialogue_inventory, review_coverage


FINGERPRINT = "f" * 64


def review_fixture():
    story = {
        "format": "rpg_author_story_plan_v1",
        "source_fingerprint": FINGERPRINT,
        "scenes": [
            {"id": "entry", "terminal": False, "assertion_ids": ["a1"]},
            {"id": "end_a", "terminal": True, "assertion_ids": []},
            {"id": "end_b", "terminal": True, "assertion_ids": ["a2"]},
        ],
    }
    overlay = {"source_fingerprint": FINGERPRINT,
               "story_sha256": digest(canonical(story))}
    review = {
        "format": "ai_story_literary_review_v1",
        "source_fingerprint": FINGERPRINT,
        "story_sha256": digest(canonical(story)),
        "enrichment_sha256": digest(canonical(overlay)),
        "review_method": "independent_ai_pass",
        "review_completed": True,
        "aspects": {k: "pass" for k in (
            "motivation", "knowledge", "items", "causality", "chronology", "endings")},
        "issues": [],
        "scenes": [
            {"scene_id": "entry", "verdict": "pass",
             "notes": "Independent source analysis of the initial encounter.",
             "source_assertion_ids": ["a1"]},
            {"scene_id": "end_a", "verdict": "pass",
             "notes": "Independent analysis of the first ending.",
             "source_assertion_ids": []},
            {"scene_id": "end_b", "verdict": "pass",
             "notes": "Independent analysis of the second ending.",
             "source_assertion_ids": ["a2"]},
        ],
        "endings": [
            {"scene_id": "end_a", "verdict": "pass",
             "notes": "The first ending is based on the first choice."},
            {"scene_id": "end_b", "verdict": "pass",
             "notes": "The second ending follows a different choice."},
        ],
    }
    return story, overlay, review


def dialogue_fixture():
    bp = {"source_fingerprint": FINGERPRINT, "scenes": [
        {"id": "talk", "choices": [
            {"id": "ask_a"}, {"id": "ask_b"}, {"id": "leave"}]}]}
    contract = {"topics": [
        {"question_id": "ask_a"}, {"question_id": "ask_b"}]}
    inventory = {"format": "ai_story_question_inventory_v1",
                 "source_fingerprint": FINGERPRINT,
                 "question_ids": ["ask_a", "ask_b"]}
    return bp, contract, inventory


class E6eFinalizationGates(unittest.TestCase):
    def error(self, code, call):
        with self.assertRaises(AuthoringError) as caught:
            call()
        self.assertEqual(caught.exception.code, code)

    def test_literary_report_is_structurally_complete_not_certified(self):
        story, overlay, review = review_fixture()
        result = review_coverage(story, overlay, review)
        self.assertFalse(result["literary_truth_attested"])
        self.assertEqual(result["reviewed_endings"], 2)

    def test_report_rejects_outdated_overlay(self):
        story, overlay, review = review_fixture()
        overlay["changed"] = True
        self.error("literary_review_stale",
                   lambda: review_coverage(story, overlay, review))

    def test_report_rejects_unresolved_issue(self):
        story, overlay, review = review_fixture()
        review["issues"] = ["Unresolved motivation contradiction"]
        self.error("literary_review_incomplete",
                   lambda: review_coverage(story, overlay, review))

    def test_report_rejects_missing_scene(self):
        story, overlay, review = review_fixture()
        review["scenes"].pop()
        self.error("literary_review_incomplete",
                   lambda: review_coverage(story, overlay, review))

    def test_report_rejects_forged_citation_coverage(self):
        story, overlay, review = review_fixture()
        review["scenes"][0]["source_assertion_ids"] = []
        self.error("literary_review_incomplete",
                   lambda: review_coverage(story, overlay, review))

    def test_report_rejects_missing_ending(self):
        story, overlay, review = review_fixture()
        review["endings"].pop()
        self.error("literary_review_incomplete",
                   lambda: review_coverage(story, overlay, review))

    def test_dialogue_inventory_covers_questions(self):
        bp, contract, inventory = dialogue_fixture()
        r = dialogue_inventory(bp, contract, inventory)
        self.assertEqual(r["question_count"], 2)
        self.assertFalse(r["automated_discovery_of_unlisted_questions"])

    def test_missing_dialogue_topic_rejected(self):
        bp, contract, inventory = dialogue_fixture()
        contract["topics"].pop()
        self.error("dialogue_coverage_incomplete",
                   lambda: dialogue_inventory(bp, contract, inventory))

    def test_inventory_rejects_unknown_choice(self):
        bp, contract, inventory = dialogue_fixture()
        inventory["question_ids"].append("invented_question")
        self.error("question_inventory_invalid",
                   lambda: dialogue_inventory(bp, contract, inventory))

    def test_inventory_rejects_wrong_book(self):
        bp, contract, inventory = dialogue_fixture()
        inventory["source_fingerprint"] = "a" * 64
        self.error("question_inventory_invalid",
                   lambda: dialogue_inventory(bp, contract, inventory))

    def test_inventory_rejects_duplicate(self):
        bp, contract, inventory = dialogue_fixture()
        inventory["question_ids"].append("ask_a")
        self.error("question_inventory_invalid",
                   lambda: dialogue_inventory(bp, contract, inventory))


if __name__ == "__main__":
    unittest.main()
