import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/book_storage.dart';

/// An entirely ORIGINAL synthetic structural fixture based on a user-supplied
/// illustrated FB2: 6 main tales, 3 numbered notes, 2 body elements,
/// 67 real tiny JPEG binaries (one cover + 66 in-story), >600 paragraphs.
/// The user's copyrighted book is NEVER checked into the public repository.
String illustratedCollectionFixture() {
  const jpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFAEBAAAAAAAAAAAAAAAAAAAABP/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/ALgAMt//2Q==';
  final source = StringBuffer('''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"
             xmlns:l="http://www.w3.org/1999/xlink">
<description><title-info>
  <book-title>Шесть проверочных сказок</book-title>
  <author><first-name>Тестовый</first-name>
          <last-name>Автор</last-name></author>
  <coverpage><image l:href="#image1.jpg"/></coverpage>
</title-info></description><body>''');
  var imageId = 2;
  for (var chapter = 0; chapter < 6; chapter++) {
    source.write('<section><title><p>Сказка ${chapter + 1}</p></title>');
    for (var paragraph = 0; paragraph < 111; paragraph++) {
      source.write('<p>Оригинальный тестовый текст '
          '${chapter + 1}:${paragraph + 1}.');
      if (chapter == 0 && paragraph == 0) {
        source.write('<a l:href="#bookmark0" type="note">1</a>');
      }
      source.write('</p>');
    }
    for (var image = 0; image < 11; image++) {
      source.write('<image l:href="#image${imageId++}.jpg"/>');
    }
    source.write('</section>');
  }
  source.write('</body><body name="notes">');
  for (var note = 0; note < 3; note++) {
    source.write('<section id="bookmark${note}"><title><p>${note + 1}</p>'
        '</title><p>Пояснение ${note + 1} к тексту.</p></section>');
  }
  source.write('</body>');
  for (var i = 1; i <= 67; i++) {
    source.write('<binary id="image${i}.jpg" '
        'content-type="image/jpeg">$jpeg</binary>');
  }
  source.write('</FictionBook>');
  return source.toString();
}

void main() {
  test('67 JPEG illustrations and cover survive FB2 parsing and indexing', () {
    final source = illustratedCollectionFixture();
    final book = BookImporter.parse('collection.fb2',
        Uint8List.fromList(utf8.encode(source)));
    expect(book.title, 'Шесть проверочных сказок');
    expect(book.author, 'Тестовый Автор');
    expect(book.images, hasLength(67));
    expect(book.cover, isNotNull);
    expect(book.cover, orderedEquals(book.images['image1.jpg']!.bytes));
    expect(book.structuredChapters, hasLength(7));
    expect(book.structuredChapters.first.blocks.first.text, 'Сказка 1');
    expect(book.structuredChapters[5].blocks.first.text, 'Сказка 6');
    final appendix = book.structuredChapters.last;
    expect(appendix.blocks.first.text, 'Примечания');
    expect(appendix.blocks.where((b) =>
        b.kind == BookBlockKind.heading).map((b) => b.text).toList(),
        ['Примечания', '1', '2', '3']);
    expect(book.chapters.last, contains('Пояснение 3 к тексту.'));
    expect(book.structuredChapters.take(6).expand((c) => c.blocks)
        .where((b) => b.kind == BookBlockKind.image), hasLength(66));
    expect(book.structuredChapters.take(6).expand((c) => c.blocks)
        .where((b) => b.kind == BookBlockKind.paragraph), hasLength(666));
    final index = BookSourceIndexer.index(book);
    expect(index.chapterCount, 7);
    expect(index.unindexedMediaBlocks, 66);
    expect(index.textIndexCoverage, 1);
    expect(index.canPublishBookworld, isFalse);
  });

  test('notes-only body stays readable instead of creating extra story '
      'chapters', () {
    const raw = '''<FictionBook><description><title-info>
      <book-title>История</book-title></title-info></description>
      <body><section><p>Начало сказки.</p></section></body>
      <body name="notes">
        <section><title><p>1</p></title><p>Первое примечание.</p></section>
        <section><title><p>2</p></title><p>Второе примечание.</p></section>
      </body></FictionBook>''';
    final book = BookImporter.parse('notes.fb2',
        Uint8List.fromList(utf8.encode(raw)));
    expect(book.chapters, hasLength(2));
    expect(book.chapters.first, 'Начало сказки.');
    expect(book.chapters.last, contains('Первое примечание.'));
    expect(book.chapters.last, contains('Второе примечание.'));
    expect(book.structuredChapters.last.blocks.first.text, 'Примечания');
  });

  test('illustrated collection is stored and reopened without missing '
      'images or extra chapters', () async {
    final temp = await Directory.systemTemp.createTemp('fb2-illustrated-');
    addTearDown(() => temp.delete(recursive: true));
    final original = BookImporter.parse('collection.fb2',
        Uint8List.fromList(utf8.encode(illustratedCollectionFixture())));
    final storage = BookStorage(rootDirectory: () async => temp);
    await storage.add(original);
    final scan = await storage.scan();
    expect(scan.unreadableCount, 0);
    expect(scan.books, hasLength(1));
    final reopened = scan.books.single.book;
    expect(reopened.structuredChapters, hasLength(7));
    expect(reopened.images, hasLength(67));
    expect(reopened.cover, isNotNull);
    expect(reopened.chapters.last, contains('Пояснение 3'));
    expect(reopened.structuredChapters.first.blocks.first.text, 'Сказка 1');
  });
}
