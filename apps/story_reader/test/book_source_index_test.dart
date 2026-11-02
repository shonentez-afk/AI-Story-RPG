import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_index_preview_page.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TXT indexing keeps every UTF-16 unit including newlines and emoji',
      () {
    final original = ('Строка с emoji 😀! Следующий шаг?\n\n' * 600);
    final book = BookImporter.parse(
      'story.txt', Uint8List.fromList(utf8.encode(original)),
    );
    // The importer preserves the complete TXT text including whitespace.
    final parsedText = book.chapters.single;
    expect(parsedText, original);
    final a = BookSourceIndexer.index(book, maxChunkUtf16: 257);
    final b = BookSourceIndexer.index(book, maxChunkUtf16: 257);
    expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
    expect(a.chapterCount, 1);
    expect(a.indexedChapterCount, 1);
    expect(a.indexedTextUtf16, parsedText.length);
    expect(a.textIndexCoverage, 1);
    expect(a.gameplayCoverage, 0);
    expect(a.canPublishBookworld, false);
    expect(a.chunks.length, greaterThan(2));
    expect(a.chunks.map((x) => x.text).join(), parsedText);
    var cursor = 0;
    for (final chunk in a.chunks) {
      expect(chunk.startUtf16, cursor);
      expect(chunk.endUtf16, greaterThan(cursor));
      expect(
        parsedText.substring(chunk.startUtf16, chunk.endUtf16),
        chunk.text,
      );
      expect(chunk.sha256Text,
          sha256.convert(utf8.encode(chunk.text)).toString());
      expect(chunk.text.codeUnits.first >= 0xDC00 &&
          chunk.text.codeUnits.first <= 0xDFFF, false);
      expect(chunk.text.codeUnits.last >= 0xD800 &&
          chunk.text.codeUnits.last <= 0xDBFF, false);
      cursor = chunk.endUtf16;
    }
    expect(cursor, parsedText.length);
    final differentChunking =
        BookSourceIndexer.index(book, maxChunkUtf16: 4096);
    expect(differentChunking.sourceFingerprint, a.sourceFingerprint);
    expect(differentChunking.chunks.map((x) => x.text).join(), parsedText);
  });

  test('FB2 chapters, text/heading order and media review are explicit', () {
    const fb2 = '''<?xml version="1.0" encoding="UTF-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
 <description><title-info><book-title>Оригинальная повесть</book-title>
 <author><first-name>Автор</first-name></author></title-info></description>
 <body>
  <section><title><p>Глава 1</p></title><p>Начало истории.</p>
  <image href="#drawing"/></section>
  <section><title><p>Глава 2</p></title><p>Финал истории.</p></section>
 </body>
</FictionBook>''';
    final book = BookImporter.parse(
      'original.fb2', Uint8List.fromList(utf8.encode(fb2)),
    );
    final index = BookSourceIndexer.index(book);
    expect(index.chapterCount, 2);
    expect(index.indexedChapterCount, 2);
    expect(index.unindexedMediaBlocks, 1);
    expect(index.chapters[0].hasUnindexedMedia, true);
    expect(index.chunks.first.text, 'Глава 1');
    expect(index.chunks.any((c) => c.text == 'Начало истории.'), true);
    expect(index.chunks.last.chapterIndex, 1);
    expect(index.chunks.last.text, 'Финал истории.');
    expect(index.toJson()['stage'], 'SOURCE_INDEX_ONLY');
    expect(index.toJson()['can_publish_bookworld'], false);
    final stored = index.toJson()['chunks'] as List;
    expect((stored.first as Map)['analysis_status'], 'PENDING');
    expect(index.gameplayCoverage, 0);
  });

  test('empty, unsafe size and invalid chunk policies fail closed', () {
    expect(() => BookSourceIndexer.index(
      const ImportedBook(title: '', author: '', chapters: ['A']),
    ), throwsFormatException);
    expect(() => BookSourceIndexer.index(
      const ImportedBook(title: 'Empty', author: '', chapters: ['']),
    ), throwsFormatException);
    expect(() => BookSourceIndexer.index(
      const ImportedBook(title: 'No', author: '', chapters: []),
    ), throwsFormatException);
    expect(() => BookSourceIndexer.index(
      const ImportedBook(title: 'Valid', author: '', chapters: ['A']),
      maxChunkUtf16: 0,
    ), throwsFormatException);
    expect(() => BookSourceIndexer.index(
      const ImportedBook(title: 'Valid', author: '', chapters: ['A']),
      maxChunkUtf16: 20000,
    ), throwsFormatException);
  });

  test('media-only chapters never count as indexed chapters', () {
    const book = ImportedBook(
      title: 'Повесть',
      author: '',
      chapters: ['', ''],
      structuredChapters: [
        BookChapter(id: 'p1', blocks: [
          BookBlock(kind: BookBlockKind.image, resourceId: 'cover'),
        ]),
        BookChapter(id: 'p2', blocks: [
          BookBlock(kind: BookBlockKind.paragraph, text: 'Доступный текст'),
        ]),
      ],
    );
    final result = BookSourceIndexer.index(book);
    expect(result.chapterCount, 2);
    expect(result.indexedChapterCount, 1);
    expect(result.unindexedMediaBlocks, 1);
    expect(result.chapters.first.fullyIndexed, false);
    expect(result.chunks.single.chapterId, 'p2');
    expect(result.canPublishBookworld, false);
  });

  test('the production Dart source index is transferable across isolates',
      () async {
    const book = ImportedBook(
      title: 'Текст для фонового анализа',
      author: '',
      chapters: ['Начало', 'Продолжение'],
    );
    final indexed = await Isolate.run(() => BookSourceIndexer.index(book));
    expect(indexed.indexedChapterCount, 2);
    expect(indexed.chunks.map((x) => x.text).join(),
        'НачалоПродолжение');
    expect(indexed.canPublishBookworld, false);
  });

  testWidgets('source index preview never claims playable RPG', (tester) async {
    const book = ImportedBook(
      title: 'Оригинальная короткая история',
      author: '',
      chapters: ['Начало.', 'Конец.'],
    );
    await tester.pumpWidget(MaterialApp(
      home: SourceIndexPreviewPage(
        book: book,
        indexer: (value) async => BookSourceIndexer.index(value),
        checkpointRepository: MemorySourceAnalysisCheckpointRepository(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Подготовка книги'), findsOneWidget);
    expect(find.text('Главы с текстом: 2 из 2'), findsOneWidget);
    expect(find.text('Текстовое покрытие индекса: 100.0%'),
        findsOneWidget);
    expect(find.textContaining('Готового игрового мира нет'), findsOneWidget);
    // Source sections are lazy slivers below the new M2b review header.
    // Scroll to them as a real user would instead of requiring eager build.
    await tester.scrollUntilVisible(
      find.text('Глава 1'), 180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Глава 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Глава 2'), 180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Глава 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source index error remains scrollable at 320dp/200%',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: SourceIndexPreviewPage(
        book: const ImportedBook(
          title: 'Пустая', author: '', chapters: [''],
        ),
        indexer: (value) async => BookSourceIndexer.index(value),
        checkpointRepository: MemorySourceAnalysisCheckpointRepository(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось проиндексировать'),
        findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
