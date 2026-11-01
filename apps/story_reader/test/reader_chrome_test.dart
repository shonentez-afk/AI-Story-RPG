import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/book_reader.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/reader_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared chrome state contract', () {
    expect(ReaderChromeMode.normal.showTopBar, isTrue);
    expect(ReaderChromeMode.reading.showTopBar, isFalse);
    expect(ReaderChromeMode.reading.showGameBar, isTrue);
    expect(ReaderChromeMode.fullscreen.showGameBar, isFalse);
    expect(ReaderChromeMode.fullscreen.toggled, ReaderChromeMode.normal);
  });

  testWidgets('book reader shares identical mode button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const book = ImportedBook(title: 'Тестовая книга', author: '',
        chapters: ['Первый абзац']);
    await tester.pumpWidget(const MaterialApp(home: BookReaderPage(book: book)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Настройки чтения'), findsOneWidget);
    await tester.tap(find.byTooltip('Скрыть управление'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Настройки чтения'), findsNothing);
    await tester.longPress(find.byTooltip('Показать управление'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Полный экран'));
    await tester.pumpAndSettle();
    expect(find.text('Первый абзац'), findsOneWidget);
    await tester.tap(find.byTooltip('Показать управление'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Настройки чтения'), findsOneWidget);
  });
}
