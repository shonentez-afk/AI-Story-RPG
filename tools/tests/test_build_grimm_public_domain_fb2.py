"""Negative tests for fail-closed, real-only Grimm corpus generation."""
import unittest
import xml.etree.ElementTree as ET

from tools import build_grimm_public_domain_fb2 as grimm


class PublicDomainGrimmGeneratorTests(unittest.TestCase):
    def test_rejects_incomplete_and_forged_contents(self):
        incomplete = (
            "*** START OF THE PROJECT GUTENBERG EBOOK GRIMMS' FAIRY TALES ***\n"
            "Grimms’ Fairy Tales\nEdgar Taylor and Marian Edwardes\n"
            "CONTENTS:\n THE GOLDEN BIRD\n"
            "THE BROTHERS GRIMM FAIRY TALES\n"
            "THE GOLDEN BIRD\nOnce upon a time...\n"
            "*** END OF THE PROJECT GUTENBERG EBOOK GRIMMS' FAIRY TALES ***"
        )
        with self.assertRaisesRegex(ValueError, "Expected all 62"):
            grimm.extract_tales(incomplete)

    def test_rejects_unknown_edition_or_truncated_download(self):
        source = (
            "*** START OF THE PROJECT GUTENBERG EBOOK UNRELATED ***\n"
            "NOT GRIMM\n"
            "*** END OF THE PROJECT GUTENBERG EBOOK UNRELATED ***"
        )
        with self.assertRaises(ValueError):
            grimm.extract_tales(source)

    def test_fb2_builder_preserves_actual_unicode_and_all_blocks(self):
        stories = [
            ("THE GOLDEN BIRD", ["A king saw a golden bird.", "A princess said ‘Yes’."]),
            ("HANSEL AND GRETEL", ["Brother & sister", "Mother <forest> cottage"]),
        ]
        fb2 = grimm.build_fb2(stories)
        root = ET.fromstring(fb2)
        namespace = {"fb2": grimm.FB2_NAMESPACE}
        sections = root.findall(".//fb2:body/fb2:section", namespace)
        self.assertEqual(len(sections), 2)
        self.assertEqual(
            sections[0].find("fb2:title/fb2:p", namespace).text, "THE GOLDEN BIRD"
        )
        self.assertEqual(
            sections[1].findall("fb2:p", namespace)[1].text,
            "Mother <forest> cottage",
        )
        self.assertIn("Wilhelm", fb2.decode("utf-8"))
        self.assertIn("Grimms' Fairy Tales", fb2.decode("utf-8"))


    def test_fixed_frog_prince_standalone_contains_one_real_tale(self):
        stories = [
            ("THE GOLDEN BIRD", ["a different story"]),
            ("THE FROG-PRINCE", ["Actual paragraph one", "Actual paragraph two"]),
        ]
        selection = [tale for tale in stories if tale[0] == "THE FROG-PRINCE"]
        self.assertEqual(len(selection), 1)
        fb2 = grimm.build_fb2(
            selection, book_title="The Frog-Prince (Grimm #2591 RPG test)")
        root = ET.fromstring(fb2)
        ns = {"fb2": grimm.FB2_NAMESPACE}
        sections = root.findall(".//fb2:body/fb2:section", ns)
        self.assertEqual(len(sections), 1)
        self.assertEqual(
            sections[0].find("fb2:title/fb2:p", ns).text, "THE FROG-PRINCE")
        self.assertEqual(
            [node.text for node in sections[0].findall("fb2:p", ns)],
            selection[0][1],
        )
        self.assertNotIn("a different story", fb2.decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
