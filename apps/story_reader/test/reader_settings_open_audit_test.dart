import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_reader.dart';
import 'package:ai_story_reader/book_reading_state.dart';
import 'package:ai_story_reader/reading_preferences.dart';
import 'package:ai_story_reader/reading_settings_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opening book clamps stale chapter and preserves reading',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_story_book_state_v1_ux-open': jsonEncode({
        'chapter': 99999, 'scrollOffset': 0, 'bookmarks': [0, 9999],
        'anchorBlock': -10, 'anchorFraction': 2.0,
      }),
    });
    const book = ImportedBook(title: 'Исправленная книга',
        author: 'Автор', chapters: ['Первая глава', 'Последняя глава']);
    await tester.pumpWidget(const MaterialApp(
      home: BookReaderPage(book: book, bookId: 'ux-open'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Последняя глава'), findsOneWidget);
    expect(find.text('Глава 2 из 2'), findsOneWidget);
    expect(find.byTooltip('Оглавление'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final saved = await BookReadingStore().load('ux-open');
    expect(saved.anchor, isNull);
  });

  testWidgets('damaged reader state does not block opening imported book',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_story_book_state_v1_bad': 'not json',
    });
    const book = ImportedBook(title: 'Читаемая книга', author: '',
        chapters: ['Первая страница']);
    await tester.pumpWidget(const MaterialApp(
      home: BookReaderPage(book: book, bookId: 'bad'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Первая страница'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader settings provides explicit close and live preview',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context, isScrollControlled: true,
          builder: (_) => ReadingSettingsSheet(
            preferences: const ReadingPreferences(),
            onChanged: (_) {},
          ),
        ),
        child: const Text('Открыть параметры'),
      ),
    ))));
    await tester.tap(find.text('Открыть параметры'));
    await tester.pumpAndSettle();
    expect(find.text('Размер текста: 18'), findsOneWidget);
    expect(find.text('Сепия'), findsOneWidget);
    await tester.ensureVisible(find.text('Готово'));
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Настройки чтения'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
