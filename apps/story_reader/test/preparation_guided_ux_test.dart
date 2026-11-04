import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_index_preview_page.dart';

// Scroll lazy slivers as a user would. ensureVisible() alone can target an
// eagerly built child of an off-screen SliverToBoxAdapter.
Future<void> revealInViewport(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 32; attempt++) {
    if (target.evaluate().isNotEmpty) {
      final y = tester.getCenter(target).dy;
      final height = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      // A control near the bottom edge is still tappable. Requiring
      // 85 px of blank space can be impossible at maxScrollExtent.
      if (y >= 72 && y <= height - 4) return;
      await tester.drag(find.byType(CustomScrollView).first,
          Offset(0, y > height - 4 ? -260 : 260));
    } else {
      await tester.drag(find.byType(CustomScrollView).first,
          const Offset(0, -260));
    }
    await tester.pumpAndSettle();
  }
  throw StateError('Target is not reachable in source preparation scroll');
}

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
    // The user flow is checked on desktop; compact screen checks are
    // exercised in separate accessibility/responsive tests.
    tester.view.physicalSize = const Size(900, 1750);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const book = ImportedBook(
      title: 'Тестовый рассказ', author: 'Автор',
      chapters: ['Его звали Артем. В городе Москва он увидел друга.'],
    );
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(page(book, store));
    await tester.pumpAndSettle();

    expect(find.text('Подготовка книги'), findsOneWidget);
    expect(find.text('Как создать RPG из этой книги'), findsOneWidget);
    expect(find.textContaining('Личная короткая или многосценная RPG собирается'),
        findsOneWidget);
    expect(find.textContaining('Автоматической RPG по всей книге пока нет'),
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
    expect(find.textContaining('Личная короткая или многосценная RPG собирается'),
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

    final advanced = find.byKey(const Key('prepare-advanced-mode'));
    await tester.scrollUntilVisible(advanced, 220,
        scrollable: find.byType(Scrollable).first, maxScrolls:30);
    expect(find.text('Полная RPG по всей книге'), findsOneWidget);
    expect(find.text('Дополнительно: экспериментальный поиск'), findsNothing);
    expect(find.byKey(const Key('prepare-advanced-evidence')), findsNothing);
    expect(find.byKey(const Key('prepare-open-story-editor')), findsOneWidget);
    await tester.ensureVisible(advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prepare-advanced-evidence')), findsOneWidget);
    expect(find.byKey(const Key('prepare-advanced-ai')), findsOneWidget);
    expect(find.byKey(const Key('prepare-advanced-story')), findsOneWidget);
    final glossary = find.byKey(const Key('prepare-advanced-glossary'));
    await tester.scrollUntilVisible(glossary, 140,
        scrollable: find.byType(Scrollable).first, maxScrolls:45);
    await tester.ensureVisible(glossary);
    await tester.pumpAndSettle();
    await tester.tap(glossary);
    await tester.pumpAndSettle();
    final term = find.text('Цитата и факт');
    await tester.scrollUntilVisible(term, 120,
        scrollable: find.byType(Scrollable).first, maxScrolls: 45);
    expect(term, findsOneWidget);
    expect(find.text('Игровой мир и прохождение'), findsOneWidget);
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

    // The chapter switch has its own focused small-book test below.
    expect(tester.takeException(), isNull);
  });


  testWidgets('chapters are opt-in and stay independent from source review',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1750);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const book = ImportedBook(title: 'Тест разделов', author: 'Автор',
        chapters: ['Первая глава', 'Вторая глава']);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(page(book, store));
    await tester.pumpAndSettle();
    expect(find.text('Глава 1'), findsNothing);
    final advanced = find.byKey(const Key('prepare-advanced-mode'));
    await revealInViewport(tester, advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('prepare-show-chapters'));
    await revealInViewport(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await revealInViewport(tester, find.text('Глава 1'));
    expect(find.text('Глава 1'), findsOneWidget);
    await revealInViewport(tester, find.text('Глава 2'));
    expect(find.text('Глава 2'), findsOneWidget);
    await revealInViewport(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Глава 1'), findsNothing);
    expect(await store.read(BookSourceIndexer.index(book).sourceFingerprint),
        isNull);
    expect(tester.takeException(), isNull);
  });
}
