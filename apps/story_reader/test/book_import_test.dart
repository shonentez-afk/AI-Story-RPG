import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';

void main() {
  test('TXT UTF-8 import', () {
    final book = BookImporter.parse('story.txt', Uint8List.fromList(utf8.encode('Привет')));
    expect(book.title, 'story');
    expect(book.chapters.single, 'Привет');
    expect(book.cover, isNull);
  });

  test('FB2 metadata, chapters and embedded PNG cover', () {
    const png = 'iVBORw0KGgo=';
    final xml = """<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info><book-title>Загадка</book-title>
<author><first-name>Иван</first-name><last-name>Иванов</last-name></author>
<coverpage><image l:href="#cover.jpg"/></coverpage></title-info></description>
<body><section><title><p>Первая глава</p></title><p>Начало</p></section></body>
<binary id="cover.jpg" content-type="image/png">$png</binary>
</FictionBook>""";
    final book = BookImporter.parse('test.fb2', Uint8List.fromList(utf8.encode(xml)));
    expect(book.title, 'Загадка');
    expect(book.author, 'Иван Иванов');
    expect(book.chapters.single, contains('Начало'));
    expect(book.cover, isNotNull);
  });
}
