import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';

void main() {
  test('TXT UTF-8 import', () {
    final book = BookImporter.parse('story.txt', Uint8List.fromList(utf8.encode('Привет')));
    expect(book.title, 'story');
    expect(book.chapters.single, 'Привет');
    expect(book.cover, isNull);
  });

  test('TXT preserves boundary whitespace but rejects whitespace-only file',
      () {
    final original = ' \nПривет, глава!\n\n';
    final parsed = BookImporter.parse('space.txt',
        Uint8List.fromList(utf8.encode('\ufeff$original')));
    expect(parsed.chapters.single, original);
    expect(() => BookImporter.parse('empty.txt',
        Uint8List.fromList(utf8.encode(' \n\t '))),
      throwsFormatException);
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
    expect(book.structuredChapters.single.blocks.first.kind,
        BookBlockKind.heading);
    expect(book.structuredChapters.single.blocks.first.text,
        'Первая глава');
  });
  test('FB2 preserves image between paragraphs and nested sections', () {
    const xml = '''<FictionBook xmlns:l="http://www.w3.org/1999/xlink">
      <description><title-info><book-title>Книга</book-title></title-info></description>
      <body><section><p>До</p><image l:href="#inside"/>
        <section><p>После</p></section></section></body>
      <binary id="inside" content-type="image/png">iVBORw0KGgo=</binary>
    </FictionBook>''';
    final book = BookImporter.parse('book.fb2',
        Uint8List.fromList(utf8.encode(xml)));
    final blocks = book.structuredChapters.single.blocks;
    expect(blocks.map((b) => b.kind).toList(), [
      BookBlockKind.paragraph, BookBlockKind.image, BookBlockKind.paragraph
    ]);
    expect(blocks[1].resourceId, 'inside');
    expect(book.images.containsKey('inside'), isTrue);
  });


  test('sequential numbered inner stories become chapters in ONE FB2, '
      'retaining original block and picture order plus a notes appendix', () {
    const xml = '''<FictionBook xmlns:l="http://www.w3.org/1999/xlink">
      <description><title-info><book-title>Общая сказка</book-title>
      <coverpage><image l:href="#art1"/></coverpage></title-info></description>
      <body><section><title><p>Общая сказка</p></title>
        <p>Рассказ первый,</p><p>Начало.</p><image l:href="#art1"/>
        <p>Рассказ второй ДВОРЕЦ</p><p>Продолжение.</p>
        <image l:href="#art2"/>
        <p>Рассказ третий ФИНАЛ</p><p>Конец.</p>
      </section></body>
      <body name="notes"><section id="note1"><title><p>1</p></title>
      <p>Примечание отдельно от сюжета.</p></section></body>
      <binary id="art1" content-type="image/png">iVBORw0KGgo=</binary>
      <binary id="art2" content-type="image/png">iVBORw0KGgo=</binary>
    </FictionBook>''';
    final book = BookImporter.parse('parts.fb2',
        Uint8List.fromList(utf8.encode(xml)));
    expect(book.title, 'Общая сказка');
    expect(book.structuredChapters, hasLength(4)); // Three stories + notes.
    expect(book.structuredChapters.first.blocks.first.text, 'Общая сказка');
    expect(book.structuredChapters[1].blocks.first.text,
        'Рассказ второй ДВОРЕЦ');
    expect(book.structuredChapters[2].blocks.first.text,
        'Рассказ третий ФИНАЛ');
    expect(book.structuredChapters[3].blocks.first.text, 'Примечания');
    final content = book.structuredChapters.take(3)
        .expand((c) => c.blocks).toList();
    expect(content.where((b) => b.kind == BookBlockKind.image)
        .map((b) => b.resourceId), ['art1', 'art2']);
    expect(content.where((b) => b.kind != BookBlockKind.image)
        .map((b) => b.text), [
      'Общая сказка', 'Рассказ первый,', 'Начало.',
      'Рассказ второй ДВОРЕЦ', 'Продолжение.',
      'Рассказ третий ФИНАЛ', 'Конец.',
    ]);
    expect(book.cover, isNotNull);
    expect(book.images.length, 2);
    final index = BookSourceIndexer.index(book);
    expect(index.chapterCount, 4);
    expect(index.indexedChapterCount, 4);
    expect(index.unindexedMediaBlocks, 2);
    expect(index.textIndexCoverage, 1);
    expect(BookSourceIndexer.index(BookImporter.parse('parts.fb2',
        Uint8List.fromList(utf8.encode(xml)))).sourceFingerprint,
        index.sourceFingerprint);
  });

  test('incidental or non-sequential part headings never split old books', () {
    ImportedBook parseParts(String paragraphs) => BookImporter.parse(
      'book.fb2', Uint8List.fromList(utf8.encode(
        '<FictionBook><description><title-info><book-title>X</book-title>'
        '</title-info></description><body><section>'
        '$paragraphs</section></body></FictionBook>',
      )),
    );
    expect(parseParts('<p>Рассказ первый.</p><p>Текст.</p>'
        '<p>Рассказ второй.</p>').structuredChapters, hasLength(1));
    expect(parseParts('<p>Рассказ первый.</p><p>Рассказ третий.</p>'
        '<p>Рассказ второй.</p>').structuredChapters, hasLength(1));
    expect(parseParts('<p>Он вспомнил: рассказ первый, давно забытый.</p>'
        '<p>Рассказ второй.</p><p>Рассказ третий.</p>')
        .structuredChapters, hasLength(1));
  });

}
