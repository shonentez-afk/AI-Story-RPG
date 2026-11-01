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
}
