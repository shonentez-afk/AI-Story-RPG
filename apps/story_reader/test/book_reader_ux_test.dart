import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_reader.dart';

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

}
