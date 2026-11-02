import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_storage.dart';
import 'package:ai_story_reader/home_page.dart';

class _Books extends BookStorage {
  @override
  Future<BookLibraryScan> scan() async => const BookLibraryScan(
    books: [StoredBook(
      id: '100_200.json',
      book: ImportedBook(
        title: 'Очень длинное название книги для узкого экрана',
        author: 'Имя автора с длинным описанием',
        chapters: ['Пример первого абзаца'],
      ),
    )],
    unreadableCount: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings and reading sheet are scrollable at 320dp/200%',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
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
      home: const SettingsPage(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Как в системе'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Мои прохождения'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // ListView lazily unmounts earlier tiles after scrolling to the bottom.
    // Scroll up until it is mounted, then align it inside the viewport.
    await tester.scrollUntilVisible(find.text('Оформление страниц'), -100,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    await tester.ensureVisible(find.text('Оформление страниц'));
    await tester.pumpAndSettle();
    // The tile is now actually inside the 320dp viewport after scrolling.
    expect(tester.getRect(find.text('Оформление страниц')).overlaps(
        tester.getRect(find.byType(Scaffold))), isTrue);
    await tester.tap(find.text('Оформление страниц'));
    await tester.pumpAndSettle();
    expect(find.text('Настройки чтения'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long book row offers direct actions at 320dp/200%',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
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
      home: LibraryPage(bookStorage: _Books()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Подготовить к RPG'), 180,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20);
    expect(find.text('Читать'), findsOneWidget);
    expect(find.byTooltip('Действия с книгой'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
