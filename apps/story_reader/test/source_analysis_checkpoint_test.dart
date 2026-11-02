import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_index_preview_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = ImportedBook(
    title: 'Оригинальная книга', author: 'Автор',
    chapters: ['Его звали Артем. В городе Москва он встретил друга.'],
  );

  test('private file store writes, replaces, reads and deletes checkpoints',
      () async {
    final dir = await Directory.systemTemp.createTemp('story_m2b2_');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileSourceAnalysisCheckpointRepository(
      rootDirectory: () async => dir,
    );
    final index = BookSourceIndexer.index(book);
    final blank = SourceAnalysisSession.create(index);
    final processed = blank.processBatch(index);

    expect(await store.read(index.sourceFingerprint), isNull);
    await store.write(index.sourceFingerprint, blank.encode());
    expect(SourceAnalysisSession.decode(
        index, (await store.read(index.sourceFingerprint))!).pendingCount, 1);
    await store.write(index.sourceFingerprint, processed.encode());
    expect(SourceAnalysisSession.decode(
        index, (await store.read(index.sourceFingerprint))!).processedCount, 1);
    await expectLater(store.read('../other-file'), throwsFormatException);
    await store.delete(index.sourceFingerprint);
    expect(await store.read(index.sourceFingerprint), isNull);
  });

  testWidgets('one preparation page resumes review without showing spoilers',
      (tester) async {
    final store = MemorySourceAnalysisCheckpointRepository();
    Future<BookSourceIndex> indexer(ImportedBook value) async =>
        BookSourceIndexer.index(value);
    Widget page() => MaterialApp(home: SourceIndexPreviewPage(
      book: book, indexer: indexer, checkpointRepository: store,
      batchProcessor: (index, current) async => current.processBatch(index),
      checkpointEncoder: (session) async => session.encode(),
      checkpointDecoder: (index, raw) async =>
          SourceAnalysisSession.decode(index, raw),
    ));

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Обработано фрагментов: 0 из 1'), findsOneWidget);
    expect(find.text('Артем'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('prepare-search-mentions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-search-mentions')));

    await tester.pumpAndSettle();
    expect(find.text('Обработано фрагментов: 1 из 1'), findsOneWidget);
    expect(find.text('Артем'), findsNothing);
    expect(find.text('Проверить найденные имена (возможны спойлеры)'),
        findsOneWidget);
    final index = BookSourceIndexer.index(book);
    expect(SourceAnalysisSession.decode(
        index, (await store.read(index.sourceFingerprint))!).reviewCount,
        greaterThan(0));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Обработано фрагментов: 1 из 1'), findsOneWidget);
    expect(find.text('Артем'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkpoint write failure leaves confirmed progress intact',
      (tester) async {
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(home: SourceIndexPreviewPage(
      book: book,
      indexer: (value) async => BookSourceIndexer.index(value),
      checkpointRepository: store,
      batchProcessor: (index, current) async => current.processBatch(index),
      checkpointEncoder: (session) async => session.encode(),
      checkpointDecoder: (index, raw) async =>
          SourceAnalysisSession.decode(index, raw),
    )));
    await tester.pumpAndSettle();
    store.failNextWrite = true;
    await tester.ensureVisible(find.byKey(const Key('prepare-search-mentions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-search-mentions')));

    await tester.pumpAndSettle();
    expect(find.text('Обработано фрагментов: 0 из 1'), findsOneWidget);
    expect(find.textContaining('Предыдущий checkpoint сохранён'),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('prepare-search-mentions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-search-mentions')));

    await tester.pumpAndSettle();
    expect(find.text('Обработано фрагментов: 1 из 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid checkpoint shows explicit recovery without book loss',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final store = MemorySourceAnalysisCheckpointRepository();
    await store.write(index.sourceFingerprint, 'invalid JSON');
    await tester.pumpWidget(MaterialApp(home: SourceIndexPreviewPage(
      book: book,
      indexer: (value) async => BookSourceIndexer.index(value),
      checkpointRepository: store,
      batchProcessor: (index, current) async => current.processBatch(index),
      checkpointEncoder: (session) async => session.encode(),
      checkpointDecoder: (index, raw) async =>
          SourceAnalysisSession.decode(index, raw),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось восстановить анализ'),
        findsOneWidget);
    expect(find.text('Сбросить поиск имён'), findsOneWidget);
    await tester.ensureVisible(find.text('Сбросить поиск имён'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить поиск имён'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить найденные имена и места?'), findsOneWidget);
    await tester.tap(find.text('Сбросить поиск имён').last);
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), isNull);
    expect(find.text('Обработано фрагментов: 0 из 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
