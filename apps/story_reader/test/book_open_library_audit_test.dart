import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_reader.dart';
import 'package:ai_story_reader/book_reading_state.dart';
import 'package:ai_story_reader/book_storage.dart';
import 'package:ai_story_reader/home_page.dart';

class _FakeBookStorage extends BookStorage {
  _FakeBookStorage(this.result);
  final BookLibraryScan result;
  @override
  Future<BookLibraryScan> scan() async => result;
}

class _FlakyReadingStore extends BookReadingStore {
  bool fail = true;
  int writes = 0;

  @override
  Future<BookReadingState> load(String id) async {
    if (fail) throw const FileSystemException('Имитация ошибки хранения');
    return const BookReadingState(chapter: 1,
        bookmarks: [1], scrollOffset: 0);
  }

  @override
  Future<void> save(String id, BookReadingState state) async {
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = ImportedBook(
    title: 'Настоящая книга',
    author: 'Тестовый автор',
    chapters: [
      'Уникальный первый абзац книги.',
      'Уникальный второй абзац книги.',
    ],
  );

  test('atomic import, safe corrupt-record isolation and no .tmp books',
      () async {
    final root = await Directory.systemTemp.createTemp('book-audit-');
    addTearDown(() => root.delete(recursive: true));
    final storage = BookStorage(rootDirectory: () async => root);
    await storage.add(book);
    final folder = Directory('${root.path}/ai_story_library');
    var names = (await folder.list().toList()).whereType<File>()
        .map((f) => f.path).toList();
    expect(names.where((p) => p.endsWith('.json')).length, 1);
    expect(names.any((p) => p.endsWith('.tmp')), false);

    await File('${folder.path}/123_456.json').writeAsString('{broken');
    await File('${folder.path}/999_999.json.tmp')
        .writeAsString('{incomplete');

    final scan = await storage.scan();
    expect(scan.books.length, 1);
    expect(scan.books.single.book.title, book.title);
    expect(scan.books.single.book.chapters.last, book.chapters.last);
    expect(scan.unreadableCount, 1);
    expect(await File('${folder.path}/123_456.json').exists(), true);
    expect((await storage.all()).length, 1);
  });

  testWidgets('library exposes visible Read and Prepare without context menu',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = _FakeBookStorage(const BookLibraryScan(
      books: [StoredBook(id: '123_456.json', book: book)],
      unreadableCount: 0,
    ));
    await tester.pumpWidget(MaterialApp(home: LibraryPage(
      bookStorage: storage,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Подготовить к RPG'), findsOneWidget);
    expect(find.text('Читать'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-prepare-123_456.json')),
        findsOneWidget);
    await tester.ensureVisible(find.text('Подготовить к RPG'));
    await tester.tap(find.text('Подготовить к RPG'));
    await tester.pump();
    expect(find.text('Подготовка книги'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Читать'));
    await tester.tap(find.text('Читать'));
    await tester.pumpAndSettle();
    expect(find.text('Уникальный первый абзац книги.'), findsOneWidget);
    expect(find.byTooltip('Оглавление'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreadable files are reported without hiding valid library',
      (tester) async {
    final storage = _FakeBookStorage(const BookLibraryScan(
      books: [StoredBook(id: '123_456.json', book: book)],
      unreadableCount: 2,
    ));
    await tester.pumpWidget(MaterialApp(home: LibraryPage(
      bookStorage: storage,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось прочитать книг: 2'), findsOneWidget);
    expect(find.text('Настоящая книга'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed reader-position load does not silently overwrite'
      ' previous progress and supports retry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = _FlakyReadingStore();
    await tester.pumpWidget(MaterialApp(home: BookReaderPage(
      book: book,
      bookId: 'test-book',
      readingStore: store,
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось восстановить место чтения'),
        findsOneWidget);
    expect(find.text('Уникальный первый абзац книги.'), findsNothing);
    expect(find.text('Повторить открытие'), findsOneWidget);
    expect(store.writes, 0);

    store.fail = false;
    await tester.tap(find.text('Повторить открытие'));
    await tester.pumpAndSettle();
    expect(find.text('Уникальный второй абзац книги.'), findsOneWidget);
    expect(find.byTooltip('Оглавление'), findsOneWidget);
    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
  });
}
