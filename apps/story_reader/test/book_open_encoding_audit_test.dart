import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_text_decoder.dart';

List<int> _russian1251(String text) => [
  for (final rune in text.runes)
    if (rune < 128)
      rune
    else if (rune >= 0x0410 && rune <= 0x042f)
      0xc0 + rune - 0x0410
    else if (rune >= 0x0430 && rune <= 0x044f)
      0xe0 + rune - 0x0430
    else if (rune == 0x0401)
      0xa8
    else if (rune == 0x0451)
      0xb8
    else
      throw FormatException('Invalid test character $rune'),
];

Uint8List _utf16Bom(String text, {required bool little}) {
  final bytes = <int>[if (little) ...[0xff, 0xfe] else ...[0xfe, 0xff]];
  for (final unit in text.codeUnits) {
    if (little) {
      bytes.addAll([unit & 255, (unit >> 8) & 255]);
    } else {
      bytes.addAll([(unit >> 8) & 255, unit & 255]);
    }
  }
  return Uint8List.fromList(bytes);
}

void main() {
  test('classic Windows-1251 FB2 opens with real title and text', () {
    const text = '<?xml version="1.0" encoding="windows-1251"?>'
        '<FictionBook>'
        '<description><title-info><book-title>Русская книга</book-title>'
        '</title-info></description>'
        '<body><section><title><p>Первая глава</p></title>'
        '<p>Привет, герой.</p></section></body>'
        '</FictionBook>';
    // Keep this fixture ASCII + Cyrillic, like many older Russian FB2.
    final bytes = Uint8List.fromList(_russian1251(text));
    final book = BookImporter.parse('история.fb2', bytes);
    expect(book.title, 'Русская книга');
    expect(book.chapters.single, contains('Привет, герой.'));
    expect(book.structuredChapters.single.blocks.first.text, 'Первая глава');
  });

  test('Windows-1251 TXT fallback and UTF-8 BOM preserve readable text', () {
    const russian = 'Привет мир\n\nНовая глава';
    final legacy = BookImporter.parse(
        'старый.txt', Uint8List.fromList(_russian1251(russian)));
    expect(legacy.chapters.single, russian);

    final utf8Book = BookImporter.parse('modern.txt',
        Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode(russian)]));
    expect(utf8Book.chapters.single, russian);
  });

  test('UTF-16 LE/BE with BOM decodes letters and Unicode emoji', () {
    const story = 'Герой 😀 рядом';
    for (final little in [true, false]) {
      expect(BookTextDecoder.decode('a.txt',
          _utf16Bom(story, little: little)), story);
    }
  });

  test('invalid declarations, damaged Unicode and random binary fail closed',
      () {
    const unsupported = '<?xml version="1.0" encoding="koi8-r"?>'
        '<FictionBook/>';
    expect(() => BookImporter.parse('a.fb2',
        Uint8List.fromList(utf8.encode(unsupported))), throwsFormatException);
    expect(() => BookImporter.parse('a.txt',
        Uint8List.fromList([0xff, 0x00, 0xff, 0x00])),
        throwsFormatException);
    expect(() => BookTextDecoder.decode('a.txt',
        Uint8List.fromList([0xff, 0xfe, 0x41])),
        throwsFormatException);
    expect(() => BookTextDecoder.decode('a.txt',
        Uint8List.fromList([0xff, 0xfe, 0x00, 0xd8])),
        throwsFormatException);
  });

  test('UTF-8 FB2 with quoted encoding works unchanged', () {
    const sample = '<?xml version="1.0" encoding="UTF-8"?>'
        '<FictionBook><body><section><p>Начало</p></section>'
        '</body></FictionBook>';
    final book = BookImporter.parse(
        'original.fb2', Uint8List.fromList(utf8.encode(sample)));
    expect(book.chapters.single, 'Начало');
  });
}
