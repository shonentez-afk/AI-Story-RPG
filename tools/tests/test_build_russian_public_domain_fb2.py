"""A real source must be complete; never replace a missing book with prose."""
import unittest
from xml.etree import ElementTree as ET
from tools.build_russian_public_domain_fb2 import (
    ArticleParagraphs, SOURCES, build_fb2, extract_real_tale,
)


def html_for(key: str, *, omit_last: bool = False) -> str:
    sections = SOURCES[key]["sections"]
    if omit_last:
        sections = sections[:-1]
    text = "Жили-были старик да старуха, Иван и лягушка в царстве. "
    paras = [text * 14 for _ in range(3)]
    return ('<div class="mw-parser-output"><h2>Содержание</h2>'
            '<p>Текст оглавления не должен попасть в рассказ.</p>' +
            "".join("<h2><span>" + section + "</span></h2>" +
                    "".join("<p>" + p + "</p>" for p in paras)
                    for section in sections) +
            '<h2>Примечания</h2><p>Вымышленная сноска.</p></div>')


class RussianPublicDomainBookTests(unittest.TestCase):
    def test_two_independent_historical_pages_parse_all_numbered_variants(self):
        for key, spec in SOURCES.items():
            with self.subTest(key=key):
                parts = extract_real_tale(html_for(key), key)
                self.assertEqual(tuple(num for num, _ in parts),
                                 spec["sections"])
                self.assertTrue(all(len(ps) == 3 for _, ps in parts))
                self.assertFalse(any("оглавления" in text or "сноска" in text
                         for _, ps in parts for text in ps))
                root = ET.fromstring(build_fb2(key, parts))
                ns = "{http://www.gribuser.ru/xml/fictionbook/2.0}"
                self.assertEqual(root.find(".//" + ns + "lang").text, "ru")
                self.assertEqual(len(root.findall(".//" + ns + "section")),
                                 len(spec["sections"]))

    def test_reject_partial_sections_even_with_plausible_paragraphs(self):
        for key in SOURCES:
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    extract_real_tale(html_for(key, omit_last=True), key)

    def test_reject_short_english_or_non_russian_text(self):
        for key, spec in SOURCES.items():
            with self.subTest(key=key):
                html = '<div class="mw-parser-output">' + "".join(
                    "<h2>" + x + "</h2><p>tiny</p><p>text</p>"
                    for x in spec["sections"]) + "</div>"
                with self.assertRaises(ValueError):
                    extract_real_tale(html, key)

    def test_editorial_superscripts_and_navigation_are_not_book_text(self):
        parser = ArticleParagraphs()
        parser.feed('<div class="mw-parser-output"><nav><p>Навигация</p></nav>'
            '<h2>95</h2><p>Рассказ <sup>[123]</sup> без сноски.</p>'
            '<p>Другой абзац.</p><h2>96</h2><p>Третий.</p>'
            '<p>Четвёртый.</p></div>')
        items = parser.chapters(("95", "96"))
        self.assertNotIn("123", items[0][1][0])
        self.assertFalse(any("Навигация" in x for _, ps in items for x in ps))


if __name__ == "__main__":
    unittest.main()
