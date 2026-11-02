import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_reader.dart';
import 'package:ai_story_reader/campaign_store.dart';
import 'package:ai_story_reader/campaigns_page.dart';
import 'package:ai_story_reader/game_panels.dart';
import 'package:ai_story_reader/game_progress.dart';
import 'package:ai_story_reader/home_page.dart';
import 'package:ai_story_reader/main.dart';
import 'package:ai_story_reader/reading_preferences.dart';
import 'package:ai_story_reader/save_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Continue uses actual save timestamps across pilot and BookWorld', () {
    final older = DateTime.utc(2026, 11, 1, 10);
    final newer = DateTime.utc(2026, 11, 2, 16);
    expect(shouldContinueWorld(
      hasPilot: true, hasWorld: true,
      pilotSavedAt: older, worldSavedAt: newer,
    ), isTrue);
    expect(shouldContinueWorld(
      hasPilot: true, hasWorld: true,
      pilotSavedAt: newer, worldSavedAt: older,
    ), isFalse);
    expect(shouldContinueWorld(
      hasPilot: false, hasWorld: true,
    ), isTrue);
    expect(shouldContinueWorld(
      hasPilot: true, hasWorld: false,
      pilotSavedAt: newer,
    ), isFalse);
    expect(shouldContinueWorld(
      hasPilot: true, hasWorld: true,
      pilotSavedAt: newer, worldSavedAt: null,
    ), isFalse);
  });

  test('all terminal outcomes have distinct saved titles and valid migration',
      () {
    for (final id in GameProgress.endingTitles.keys) {
      final completed = const GameProgress().apply(id);
      expect(completed.endingId, id);
      expect(completed.endingTitle, isNot('История завершена'));
      expect(completed.endingDescription.length, greaterThan(20));
      expect(GameProgress.fromJson(completed.toJson()).endingId, id);
    }
    final legacy = GameProgress.fromJson({
      'courage': 1, 'insight': 0, 'items': <String>[],
    });
    expect(legacy.endingId, isNull);
    expect(legacy.endingTitle, 'История завершена');
    expect(() => GameProgress.fromJson({
      'courage': 0, 'insight': 0, 'items': <String>[],
      'endingId': 'not_a_terminal_choice',
    }), throwsFormatException);
  });

  testWidgets('empty library presents an explicit TXT/FB2 import action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(home: LibraryPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Добавить книгу'), findsOneWidget);
    // If platform file storage is unavailable, show retry instead of
    // leaving a spinner running forever.
    expect(find.text('Повторить загрузку'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-import')), findsOneWidget);
    expect(find.byIcon(Icons.library_add_outlined), findsOneWidget);
    expect(find.text('Тайна особняка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings link opens campaign library, version is current',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('0.1.0 · BookWorld · тестовая версия'), 150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0.1.0 · BookWorld · тестовая версия'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Мои прохождения'), -150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Мои прохождения'));
    await tester.pumpAndSettle();
    expect(find.text('Импортировать .bwsave'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact campaign actions fit 320dp with 200% text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await CampaignStore().write(
      'campaign_accessible',
      const GameSaveRecord('unopened snapshot', []),
      sceneTitle: 'Длинное название главы особняка',
    );
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
      home: const CampaignsPage(),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Действия с прохождением'), findsOneWidget);
    expect(find.byTooltip('Экспортировать прохождение'), findsNothing);
    await tester.tap(find.byTooltip('Действия с прохождением'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить прохождение'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить прохождение?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect((await CampaignStore().all()).length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pilot ending shows its actual consequence instead of a generic end',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вернуться домой'));
    await tester.pumpAndSettle();
    expect(find.text('Вы вернулись домой'), findsOneWidget);
    expect(find.textContaining('Вы решили не входить'), findsOneWidget);
    expect(find.text('В главное меню'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OLED palette also controls RPG choice button colors',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_story_reading_v1_palette': 3,
    });
    // Explicit reader choice is separate from the app's light/dark mode.
    await ReadingSettingsStore().save(const ReadingPreferences(
      palette: ReadingPalette.oled,
    ));
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Войти и исследовать дом'),
    );
    expect(button.style?.foregroundColor?.resolve({}),
        const Color(0xFFFFFFFF));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large journal stays scrollable on 320dp at 200% text',
      (tester) async {
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
      home: Scaffold(body: Builder(builder: (context) =>
        TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => GameInfoSheet(
              panel: GamePanel.journal,
              currentScene: 'Библиотека',
              journalEntries: List.generate(150, (i) =>
                  'Сцена и принятое решение номер $i'),
            ),
          ),
          child: const Text('Журнал событий'),
        ),
      )),
    ));
    await tester.tap(find.text('Журнал событий'));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book first heading is not duplicated; nested headings remain',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const book = ImportedBook(
      title: 'Пример книги', author: 'Автор', chapters: [''],
      structuredChapters: [
        BookChapter(id: 'a', blocks: [
          BookBlock(kind: BookBlockKind.heading, text: 'Первая глава'),
          BookBlock(kind: BookBlockKind.paragraph, text: 'Начало истории'),
          BookBlock(kind: BookBlockKind.heading, text: 'Подраздел'),
        ]),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(home: BookReaderPage(book: book)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Первая глава'), findsOneWidget);
    expect(find.text('Подраздел'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

