import unittest

from tools.rpg_author.common import AuthoringError, parse_json
from tools.rpg_author.source_adapter import make_index, parse_book
from tools.rpg_author.validate import (assertion_registry, candidate_blueprint,
                                      simulate, validate_analysis, validate_story)
from tests.rpg_author.fixtures import analysis, choice, scene, source, story


class ValidationTests(unittest.TestCase):
    def check_error(self, code, callback):
        with self.assertRaises(AuthoringError) as caught:
            callback()
        self.assertEqual(caught.exception.code, code)

    def test_real_flag_routes_and_two_endings(self):
        report = validate_story(story(), source(), [analysis()])
        self.assertEqual(report["reachable_states"], 5)
        self.assertEqual(report["ending_routes"], {"safe": ["take_rope", "rescue"],
                                                  "help": ["leave_rope", "go_for_help"]})
        self.assertTrue(report["state_space_complete"])
        self.assertTrue(report["engine_blueprint_valid"])
        self.assertFalse(report["semantic_review_completed"])
        self.assertFalse(report["package_built"])
        self.assertNotIn("model_provenance", candidate_blueprint(story(), source()))

    def test_wrong_book_or_chunk_cannot_be_accepted(self):
        record = analysis()
        record["source_fingerprint"] = "a" * 64
        self.check_error("wrong_source", lambda: validate_analysis(record, source()))
        record = analysis()
        record["source_sha256"] = "0" * 64
        self.check_error("wrong_chunk", lambda: validate_analysis(record, source()))

    def test_quote_text_mismatch_and_absolute_utf16_offsets(self):
        record = analysis()
        record["assertions"][0]["quote"] = "Выдуманная цитата"
        self.check_error("quote_mismatch", lambda: validate_analysis(record, source()))
        index = make_index(parse_book("emoji.txt", "А😀Б.".encode()))
        record = {**analysis(), "source_fingerprint": index["source_fingerprint"],
                  "source_sha256": index["chunks"][0]["sha256_text"]}
        claim = record["assertions"][0]
        claim.update(start_utf16=1, end_utf16=3, quote="😀")
        validate_analysis(record, index)
        claim["end_utf16"] = 2
        self.check_error("split_surrogate", lambda: validate_analysis(record, index))

    def test_multiple_chunks_do_not_share_block_relative_zero(self):
        index = make_index(parse_book("long.txt", ("Я" * 600).encode()), 256)
        second = index["chunks"][1]
        record = {**analysis(), "source_fingerprint": index["source_fingerprint"],
                  "chunk_id": second["id"], "source_sha256": second["sha256_text"]}
        record["assertions"][0].update(start_utf16=256, end_utf16=260, quote="Я" * 4)
        validate_analysis(record, index)
        record["assertions"][0].update(start_utf16=0, end_utf16=4)
        self.check_error("invalid_quote_range", lambda: validate_analysis(record, index))

    def test_incomplete_source_pass_does_not_become_a_full_game(self):
        self.check_error("analysis_incomplete", lambda: validate_story(story(), source(), []))

    def test_duplicate_assertions_and_unknown_citations(self):
        self.check_error("duplicate_id", lambda: assertion_registry([analysis(), analysis()], source()))
        value = story()
        value["scenes"][0]["assertion_ids"] = ["not_in_book"]
        self.check_error("unknown_assertion", lambda: validate_story(value, source(), [analysis()]))

    def test_reported_speech_and_inference_remain_proposals(self):
        record = analysis()
        for kind in ("REPORTED", "INFERRED"):
            record["assertions"][0]["kind"] = kind
            report = validate_story(story(), source(), [record])
            self.assertFalse(report["semantic_review_completed"])

    def test_unavailable_choice_causes_state_specific_dead_end(self):
        value = story()
        value["scenes"][1]["choices"] = [choice("rescue", "safe", requires=["rope"])]
        self.check_error("dead_end", lambda: validate_story(value, source(), [analysis()]))

    def test_unreachable_scene_and_missing_ending_rejected(self):
        value = story()
        value["scenes"].append(scene("never", "Недостижимый конец."))
        self.check_error("unreachable_scene", lambda: validate_story(value, source(), [analysis()]))
        value = story()
        value["scenes"][1]["choices"][1]["next_scene_id"] = "safe"
        self.check_error("missing_endings", lambda: validate_story(value, source(), [analysis()]))

    def test_trapped_cycle_not_confused_with_reachable_endings(self):
        value = story()
        value["scenes"][0]["choices"].append(choice("enter_loop", "loop"))
        value["scenes"].append(scene("loop", "Круг.", [choice("again", "loop")]))
        self.check_error("trapped_cycle", lambda: validate_story(value, source(), [analysis()]))

    def test_state_budget_does_not_report_partial_success(self):
        self.check_error("state_limit", lambda: simulate(story(), max_states=2))

    def test_conflicting_or_unknown_flags_rejected(self):
        value = story()
        value["scenes"][0]["choices"][0]["removes"] = ["rope"]
        self.check_error("contradictory_choice", lambda: validate_story(value, source(), [analysis()]))
        value["scenes"][0]["choices"][0]["removes"] = ["magic"]
        self.check_error("unknown_flag", lambda: validate_story(value, source(), [analysis()]))

    def test_same_outcome_choices_warn_but_do_not_claim_literary_quality(self):
        value = story()
        value["scenes"][0]["choices"].append(choice("also_take", "river", adds=["rope"]))
        report = validate_story(value, source(), [analysis()])
        self.assertEqual(report["equivalent_choice_pairs"], [["also_take", "take_rope"]])

    def test_wrong_types_extra_fields_and_unicode_limits_fail_cleanly(self):
        mutations = [lambda s: s.update(extra="hidden"),
                     lambda s: s["scenes"][0].update(chapter_index=True),
                     lambda s: s["scenes"][0].update(text="😀" * 3001),
                     lambda s: s["scenes"][0].update(terminal=1),
                     lambda s: s["scenes"][0]["choices"][0].update(adds=[["rope"]])]
        for change in mutations:
            value = story()
            change(value)
            with self.subTest(value=str(value)[:80]), self.assertRaises(AuthoringError):
                validate_story(value, source(), [analysis()])

    def test_duplicate_json_keys_and_nonfinite_numbers_rejected(self):
        for data in (b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}', b'\xff'):
            with self.subTest(data=data), self.assertRaises(AuthoringError):
                parse_json(data)
