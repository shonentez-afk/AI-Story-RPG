import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_reader.dart';
import 'package:ai_story_reader/book_reading_state.dart';
import 'package:ai_story_reader/reading_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('large FB2 chapter builds blocks lazily', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final book = ImportedBook(
      title: 'Большая книга',
      author: 'Автор',
      chapters: const [''],
      structuredChapters: [
        BookChapter(id: 'long', blocks: List.generate(300, (index) =>
          BookBlock(kind: BookBlockKind.paragraph, text: 'Абзац номер $index ' * 10))),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: BookReaderPage(book: book)));
    await tester.pumpAndSettle();
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.textContaining('Абзац номер 0'), findsOneWidget);
    expect(find.textContaining('Абзац номер 299'), findsNothing);
  });

  testWidgets('table of contents uses FB2 heading, title only first chapter',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const book = ImportedBook(
      title: 'Путешествие',
      author: 'Автор',
      chapters: ['', ''],
      structuredChapters: [
        BookChapter(id: 'a', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'Первый раздел'),
          BookBlock(kind: BookBlockKind.paragraph, text: 'Начало'),
        ]),
        BookChapter(id: 'b', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'Второй раздел'),
          BookBlock(kind: BookBlockKind.paragraph, text: 'Продолжение'),
        ]),
      ],
    );
    await tester.pumpWidget(const MaterialApp(home: BookReaderPage(book: book)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Оглавление'));
    await tester.pumpAndSettle();
    expect(find.text('Второй раздел'), findsOneWidget);
    await tester.tap(find.text('Второй раздел'));
    await tester.pumpAndSettle();
    expect(find.text('Продолжение'), findsOneWidget);
    expect(find.text('Автор'), findsNothing);
  });
  testWidgets('chapter actions fit narrow screens with large accessibility text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const book = ImportedBook(title: 'Книга', author: '', chapters: [
      'Глава с небольшим текстом',
      'Продолжение',
    ]);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const BookReaderPage(book: book),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Далее'), 220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Далее'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved position restores inside long chapter after reopening',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_story_book_state_v1_test-long': jsonEncode({
        'chapter': 0,
        'scrollOffset': 420.0,
        'bookmarks': <int>[],
      }),
    });
    final book = ImportedBook(
      title: 'Длинная глава',
      author: '',
      chapters: const [''],
      structuredChapters: [
        BookChapter(id: 'chapter_0', blocks: List.generate(120,
          (index) => BookBlock(kind: BookBlockKind.paragraph,
            text: 'Новый абзац номер $index. Очень длинная история.' * 4))),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: BookReaderPage(book: book, bookId: 'test-long')));
    await tester.pumpAndSettle();
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(scroll.controller!.offset, greaterThan(100));
  });

  testWidgets('semantic source paragraph survives font and width reflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final book = ImportedBook(
      title: 'Длинная книга для проверки',
      author: '',
      chapters: const [''],
      structuredChapters: [
        BookChapter(
          id: 'chapter_0',
          blocks: List.generate(160, (i) => BookBlock(
            kind: BookBlockKind.paragraph,
            text: 'Текст параграфа $i. ' * 18,
          )),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: BookReaderPage(book: book, bookId: 'semantic-test'),
    ));
    await tester.pumpAndSettle();
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.textContaining('Текст параграфа 64.'),
      350,
      scrollable: scroll,
      maxScrolls: 120,
    );
    await tester.pump(const Duration(milliseconds: 450));
    final old = await BookReadingStore().load('semantic-test');
    expect(old.anchor, isNotNull);
    expect(old.anchor!.blockIndex, greaterThan(0));

    // Resize while the reader is still open: metrics must preserve the
    // semantic source location, not just after an app restart.
    tester.view.physicalSize = const Size(350, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpAndSettle();
    // A direct centered sliver is required for an anchored reflow;
    // a legacy raw pixel offset is not sufficient after resize.
    final liveView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(liveView.center, isNotNull);
    final afterResize = await BookReadingStore().load('semantic-test');
    final visibleParagraphs = tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    ).map((widget) => RegExp(r'Текст параграфа (\\d+)')
        .firstMatch(widget.data ?? '')?.group(1))
        .whereType<String>().take(16).join(', ');
    final targetParagraph = find.textContaining(
      'Текст параграфа ${old.anchor!.blockIndex}.',
    );
    final mountedParagraph = find.textContaining(
      'Текст параграфа ${old.anchor!.blockIndex}.',
      skipOffstage: false,
    );
    final viewportRect = tester.getRect(find.byType(CustomScrollView));
    String mountedRect = 'not mounted';
    if (mountedParagraph.evaluate().isNotEmpty) {
      try {
        mountedRect = '${tester.getRect(mountedParagraph)}';
      } catch (_) {
        mountedRect = 'mounted, no rect';
      }
    }
    final position = liveView.controller!.position;
    expect(targetParagraph, findsOneWidget, reason:
        'visible=$visibleParagraphs, saved=${old.anchor!.blockIndex}, '
        'fraction=${old.anchor!.fraction}, '
        'post=${afterResize.anchor?.blockIndex}, '
        'offset=${position.pixels}, min=${position.minScrollExtent}, '
        'max=${position.maxScrollExtent}, viewport=$viewportRect, '
        'mounted=$mountedRect, allSelectable=${find.byType(SelectableText, skipOffstage: false).evaluate().length}');
    expect(tester.getRect(targetParagraph).overlaps(
      tester.getRect(find.byType(CustomScrollView)),
    ), isTrue, reason: 'Target paragraph must actually intersect viewport');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await ReadingSettingsStore().save(
      const ReadingPreferences(fontSize: 25, lineHeight: 1.9),
    );
    await tester.pumpWidget(MaterialApp(
      home: BookReaderPage(book: book, bookId: 'semantic-test'),
    ));
    await tester.pumpAndSettle();
    final target = find.textContaining(
      'Текст параграфа ${old.anchor!.blockIndex}.',
    );
    expect(target, findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 450));
    final after = await BookReadingStore().load('semantic-test');
    expect(after.anchor, isNotNull);
    expect(after.chapter, old.chapter);
  });
}
