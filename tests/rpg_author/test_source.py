import unittest

from tools.rpg_author.common import AuthoringError, digest, utf16_len
from tools.rpg_author.source_adapter import make_index, parse_book


class SourceTests(unittest.TestCase):
    def test_txt_preserves_bom_whitespace_crlf_and_unicode(self):
        text = " \r\nС😀.\t\n" * 200
        index = make_index(parse_book("story.txt", b"\xef\xbb\xbf" + text.encode()), 257)
        self.assertEqual("".join(c["text"] for c in index["chunks"]), text)
        self.assertEqual(index["text_total_utf16"], 9 * 200)
        cursor = 0
        for chunk in index["chunks"]:
            self.assertEqual(chunk["start_utf16"], cursor)
            cursor = chunk["end_utf16"]
            self.assertEqual(utf16_len(chunk["text"]), cursor - chunk["start_utf16"])

    def test_chunk_boundary_does_not_split_surrogate(self):
        text = "я" * 255 + "😀" + "б" * 100
        index = make_index(parse_book("story.txt", text.encode()), 256)
        self.assertEqual(index["chunks"][0]["end_utf16"], 255)
        self.assertTrue(index["chunks"][1]["text"].startswith("😀"))
        self.assertEqual("".join(c["text"] for c in index["chunks"]), text)

    def test_fingerprint_independent_of_chunking(self):
        book = parse_book("story.txt", ("Текст. " * 400).encode())
        self.assertEqual(make_index(book, 256)["source_fingerprint"],
                         make_index(book, 4096)["source_fingerprint"])

    def test_fingerprint_uses_exact_dart_field_order_not_sorted_json(self):
        index = make_index(parse_book("abc.txt", "С😀.".encode()))
        expected = ('{"title":"abc","author":"","chapters":['
                    '{"chapter_id":"chapter_0","blocks":['
                    '{"kind":"paragraph","text":"С😀.","resource_id":null}]}]}')
        self.assertEqual(index["source_fingerprint"], digest(expected.encode()))
        self.assertEqual(index["text_total_utf16"], 4)

    def test_nested_fb2_inline_images_and_appendix(self):
        text = '''<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
        <description><title-info><book-title>Книга</book-title>
        <author><first-name>Анна</first-name><last-name>Автор</last-name></author>
        </title-info></description><body><section><title><p>Начало</p></title>
        <p>До <emphasis>света</emphasis><image href="#picture"/> после.</p>
        <section><p>Вложенная часть.</p></section></section></body>
        <body name="notes"><section><title><p>1</p></title><p>Сноска.</p></section></body>
        </FictionBook>'''
        book = parse_book("input.fb2", text.encode())
        index = make_index(book)
        self.assertEqual(book["author"], "Анна Автор")
        self.assertEqual(index["chapter_count"], 2)
        self.assertEqual([b["text"] for b in book["chapters"][0]["blocks"]],
                         ["Начало", "До света", "", "после.", "Вложенная часть."])
        self.assertEqual(index["media_blocks_for_review"], 1)
        self.assertEqual(book["chapters"][1]["blocks"][0]["text"], "Примечания")

    def test_fb2_preserves_crlf_cr_and_quoted_attribute_whitespace(self):
        xml = ('<?xml version="1.0"?>\r\n<FictionBook>\r\n<body><section>\r\n'
               '<p>Строка\r\nпродолжение.</p><p>Один\rдва.</p>'
               '<p>А\r\n&lt;&amp; Б</p><!-- ignored\r\n -->'
               '<image href="#name\r\nwith\ttabs"/>'
               '</section></body></FictionBook>')
        book = parse_book("book.fb2", xml.encode())
        blocks = book["chapters"][0]["blocks"]
        self.assertEqual([b["text"] for b in blocks[:3]],
                         ["Строка\r\nпродолжение.", "Один\rдва.", "А\r\n<& Б"])
        self.assertEqual(blocks[3]["resource_id"], "name\r\nwith\ttabs")
        self.assertEqual(make_index(book)["chunks"][0]["end_utf16"], 20)

    def test_cdata_is_refused_instead_of_silently_losing_book_text(self):
        for text in ('<p>А<![CDATA[Б]]>В</p>', '<p><![CDATA[Весь текст]]></p>'):
            with self.subTest(text=text), self.assertRaises(AuthoringError) as caught:
                parse_book("book.fb2", ('<FictionBook><body>' + text + '</body></FictionBook>').encode())
            self.assertEqual(caught.exception.code, "unsupported_fb2_cdata")

    def test_invalid_cdata_comment_and_markup_remain_errors(self):
        for content in ('<![CDATA[broken', '<!-- broken', '<?broken', '<p x="broken'):
            with self.subTest(content=content), self.assertRaises(AuthoringError):
                parse_book("book.fb2", ('<FictionBook><body>' + content).encode())

    def test_three_numbered_parts_split_but_two_do_not(self):
        for count, expected in ((2, 1), (3, 3)):
            parts = ["Рассказ первый", "Рассказ второй", "Рассказ третий"][:count]
            xml = '<FictionBook><body><section>' + ''.join(f'<p>{p}</p><p>Сюжет.</p>' for p in parts)
            xml += '</section></body></FictionBook>'
            self.assertEqual(len(parse_book("book.fb2", xml.encode())["chapters"]), expected)

    def test_supported_encodings(self):
        xml = '<?xml version="1.0" encoding="windows-1251"?><FictionBook><body><p>Привет.</p></body></FictionBook>'
        self.assertEqual(make_index(parse_book("old.fb2", xml.encode("cp1251")))["chunks"][0]["text"], "Привет.")
        for encoding in ("utf-16", "utf-8", "cp1251"):
            with self.subTest(encoding=encoding):
                self.assertEqual(parse_book("text.txt", "Текст книги".encode(encoding))["chapters"][0]["blocks"][0]["text"], "Текст книги")

    def test_dtd_rejected_even_when_utf16_encoded(self):
        text = '<!DOCTYPE FictionBook [<!ENTITY x "secret">]><FictionBook><body><p>&x;</p></body></FictionBook>'
        for encoding in ("utf-8", "utf-16"):
            with self.subTest(encoding=encoding), self.assertRaises(AuthoringError) as error:
                parse_book("book.fb2", text.encode(encoding))
            self.assertEqual(error.exception.code, "unsafe_xml")

    def test_invalid_formats_empty_books_and_broken_xml(self):
        for name, data in (("bad.epub", b"abc"), ("book.zip", b"abc"), ("a.txt", b"  "),
                           ("a.fb2", b"<broken>"), ("a.fb2", b"<html/>")):
            with self.subTest(name=name), self.assertRaises(AuthoringError):
                make_index(parse_book(name, data))

    def test_media_only_chapter_does_not_count_as_analyzed_text(self):
        xml = '<FictionBook><body><section><image href="#x"/></section><section><p>Текст.</p></section></body></FictionBook>'
        index = make_index(parse_book("book.fb2", xml.encode()))
        self.assertEqual(index["chapter_count"], 2)
        self.assertEqual(index["indexed_chapter_count"], 1)
        self.assertFalse(index["chapters"][0]["text_indexed"])

    def test_deep_xml_and_invalid_chunk_sizes(self):
        xml = '<FictionBook><body>' + '<section>' * 130 + '<p>Text</p>' + '</section>' * 130 + '</body></FictionBook>'
        with self.assertRaises(AuthoringError) as error:
            parse_book("book.fb2", xml.encode())
        self.assertEqual(error.exception.code, "xml_complexity")
        for size in (0, 255, 12001, True):
            with self.subTest(size=size), self.assertRaises(AuthoringError):
                make_index(parse_book("book.txt", b"text"), size)
