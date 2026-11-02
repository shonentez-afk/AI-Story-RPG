import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_storage.dart';
import 'package:ai_story_reader/home_page.dart';

const _stored = StoredBook(
  id: '779_002.json',
  book: ImportedBook(
    title: 'Самые красивые сказки (с иллюстрациями)',
    author: 'Ганс Христиан Андерсен',
    chapters: ['Оригинальный тестовый отрывок.'],
  ),
);

class _DeletionProbeStorage extends BookStorage {
  final List<StoredBook> records = [_stored];
  int removalAttempts = 0;
  bool failNextRemoval = false;

  @override
  Future<BookLibraryScan> scan() async => BookLibraryScan(
    books: List.unmodifiable(records),
    unreadableCount: 0,
  );

  @override
  Future<void> remove(String id) async {
    removalAttempts++;
    if (failNextRemoval) {
      failNextRemoval = false;
      throw const FileSystemException('Simulated disk write failure');
    }
    records.removeWhere((record) => record.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('one destructive action is an accessible visible trash button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = _DeletionProbeStorage();
    await tester.pumpWidget(MaterialApp(
      home: LibraryPage(bookStorage: storage),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byTooltip('Действия с книгой'), findsNothing);
    final button = find.byKey(
      const ValueKey('library-delete-779_002.json'));
    expect(button, findsOneWidget);
    expect(find.byTooltip('Удалить книгу'), findsOneWidget);
    expect(find.text('Читать'), findsOneWidget);
    expect(find.text('Подготовить к RPG'), findsOneWidget);
    final widget = tester.widget<IconButton>(button);
    expect(widget.onPressed, isNotNull);
    expect(widget.icon, isA<Icon>());
    expect((widget.icon as Icon).icon, Icons.delete_outline);

    // A tap on the trash must not open the reader or immediately remove data.
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Удалить книгу?'), findsOneWidget);
    expect(find.textContaining('Это действие нельзя отменить'),
        findsOneWidget);
    expect(storage.removalAttempts, 0);
    expect(storage.records.length, 1);
    expect(find.text('Оглавление'), findsNothing);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(storage.removalAttempts, 0);
    expect(find.text('Самые красивые сказки (с иллюстрациями)'),
        findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(storage.removalAttempts, 1);
    expect(storage.records, isEmpty);
    expect(find.byKey(const ValueKey('library-delete-779_002.json')),
        findsNothing);
    expect(find.text('Книга удалена из библиотеки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed deletion keeps book and gives an actionable error',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = _DeletionProbeStorage()..failNextRemoval = true;
    await tester.pumpWidget(MaterialApp(
      home: LibraryPage(bookStorage: storage),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Удалить книгу'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();

    expect(storage.removalAttempts, 1);
    expect(storage.records.length, 1);
    expect(find.textContaining('Не удалось удалить книгу:'),
        findsOneWidget);
    expect(find.byTooltip('Удалить книгу'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
