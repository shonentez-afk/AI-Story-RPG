import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_index_preview_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget page(ImportedBook book,
      MemorySourceAnalysisCheckpointRepository store) => MaterialApp(
    home: SourceIndexPreviewPage(
      book: book,
      indexer: (value) async => BookSourceIndexer.index(value),
      checkpointRepository: store,
      batchProcessor: (index, current) async =>
          current.processBatch(index),
      checkpointEncoder: (session) async => session.encode(),
      checkpointDecoder: (index, raw) async =>
          SourceAnalysisSession.decode(index, raw),
    ),
  );

  testWidgets('preparation explains real steps and never promises a playable RPG',
      (tester) async {
    const book = ImportedBook(
      title: 'Тестовый рассказ', author: 'Автор',
      chapters: ['Его звали Артем. В городе Москва он увидел друга.'],
    );
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(page(book, store));
    await tester.pumpAndSettle();

    expect(find.text('Подготовка книги'), findsOneWidget);
    expect(find.text('Что делает подготовка?'), findsOneWidget);
    expect(find.text('Создать игровую историю — пока недоступно'),
        findsOneWidget);
    expect(find.textContaining('готовой игры из вашей книги ещё не создаём'),
        findsOneWidget);
    expect(find.text('Начать поиск имён и мест'), findsOneWidget);
    expect(find.text('Артем'), findsNothing);
    expect(await store.read(BookSourceIndexer.index(book).sourceFingerprint),
        isNull);

    await tester.ensureVisible(
        find.byKey(const Key('prepare-search-mentions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-search-mentions')));
    await tester.pumpAndSettle();
    expect(find.text('Поиск имён и мест завершён'), findsOneWidget);
    expect(find.text('Артем'), findsNothing);
    expect(find.text('Проверить найденные имена (возможны спойлеры)'),
        findsOneWidget);
    expect(find.text('Создать игровую историю — пока недоступно'),
        findsOneWidget);

    await tester.tap(
        find.text('Проверить найденные имена (возможны спойлеры)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Артем'), 220,
        scrollable: find.byType(Scrollable).first, maxScrolls:25);
    expect(find.text('Артем'), findsOneWidget);
    expect(find.text('Это имя персонажа'), findsOneWidget);
    await tester.ensureVisible(find.text('Это имя персонажа'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Это имя персонажа'));
    await tester.pumpAndSettle();
    final originalIndex = BookSourceIndexer.index(book);
    final restored = SourceAnalysisSession.decode(originalIndex,
        (await store.read(originalIndex.sourceFingerprint))!);
    expect(restored.mentions.where(
        (m) => m.decision == MentionDecision.accepted).length, 1);
    await tester.scrollUntilVisible(find.textContaining('Принято: 1'), -180,
        scrollable: find.byType(Scrollable).first, maxScrolls:25);
    expect(find.textContaining('Принято: 1'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.text('Дополнительно: экспериментальный поиск'), 220,
        scrollable: find.byType(Scrollable).first, maxScrolls:30);
    expect(find.text('Создать RPG по этой книге'), findsOneWidget);
    expect(find.text('Открыть локальный анализ'), findsNothing);
    await tester.tap(find.text('Дополнительно: экспериментальный поиск'));
    await tester.pumpAndSettle();
    expect(find.text('Открыть локальный анализ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long candidate lists reveal more without losing reviewed items',
      (tester) async {
    final book = ImportedBook(
      title: 'Много имён', author: 'Автор',
      chapters: List.generate(13, (i) => 'Его звали Артем. Глава $i.'),
    );
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(page(book, store));
    await tester.pumpAndSettle();
    expect(find.text('Глава 1'), findsNothing);

    await tester.ensureVisible(
        find.byKey(const Key('prepare-search-mentions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prepare-search-mentions')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.text('Проверить найденные имена (возможны спойлеры)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('prepare-review-more')), 250,
        scrollable: find.byType(Scrollable).first, maxScrolls:30);
    await tester.ensureVisible(find.byKey(const Key('prepare-review-more')));
    await tester.pumpAndSettle();
    expect(find.text('Показано 10 из 13 упоминаний'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prepare-review-more')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Показано 13 из 13 упоминаний'));
    expect(find.text('Показано 13 из 13 упоминаний'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const Key('prepare-show-chapters')), 260,
        scrollable: find.byType(Scrollable).first, maxScrolls:30);
    await tester.tap(find.byKey(const Key('prepare-show-chapters')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Глава 1'), 200,
        scrollable: find.byType(Scrollable).first, maxScrolls:20);
    expect(find.text('Глава 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
