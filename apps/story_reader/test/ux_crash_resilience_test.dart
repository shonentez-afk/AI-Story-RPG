import 'dart:async';

import 'package:ai_story_reader/book_storage.dart';
import 'package:ai_story_reader/home_page.dart';
import 'package:ai_story_reader/main.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/world_play_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Crash/UX regression: genuine Flutter widgets and error futures, with no
/// mocked world-state mutation. This is NOT a physical Windows GUI test.
const _start = WorldGameView(
  campaignId: 'ux-crash-probe',
  worldTitle: 'Проверка устойчивости',
  sceneId: 'bridge',
  sceneText: 'Перед героем старый мост.',
  revision: 0,
  tick: 0,
  isTerminal: false,
  heroName: 'Путешественник',
  stats: {'courage': 1},
  inventory: [],
  flags: {},
  knownFacts: [],
  choices: [
    WorldChoiceView(id: 'cross', label: 'Перейти мост'),
    WorldChoiceView(
      id: 'locked',
      label: 'Открыть дверь ключом',
      lockReason: 'condition_not_met:has_item',
    ),
  ],
  journal: [],
);
const _finished = WorldGameView(
  campaignId: 'ux-crash-probe',
  worldTitle: 'Проверка устойчивости',
  sceneId: 'shore',
  sceneText: 'Герой добрался до берега.',
  revision: 1,
  tick: 1,
  isTerminal: true,
  heroName: 'Путешественник',
  stats: {'courage': 2},
  inventory: [],
  flags: {},
  knownFacts: [],
  choices: [],
  journal: [
    WorldEventView(
      sequence: 1,
      sceneId: 'bridge',
      choiceLabel: 'Перейти мост',
      changes: ['Смелость: +1'],
    ),
  ],
);

class _FaultGateway implements WorldLibraryGateway {
  int loads = 0;
  int writes = 0;
  Future<WorldGameView> Function(int attempt)? loadResponse;
  Future<WorldChoiceResult> Function(int attempt)? choiceResponse;

  @override
  Future<WorldGameView> load(String campaignId) {
    loads++;
    return loadResponse?.call(loads) ?? Future.value(_start);
  }

  @override
  Future<WorldChoiceResult> choose(String campaignId, {
    required String actionId,
    required String choiceId,
    required int expectedRevision,
  }) {
    writes++;
    return choiceResponse?.call(writes) ??
        Future.value(const WorldChoiceResult(
          applied: true,
          view: _finished,
        ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnstableBooks extends BookStorage {
  int calls = 0;

  @override
  Future<BookLibraryScan> scan() {
    calls++;
    if (calls == 1) {
      return Future.error(const FormatException('Повреждённый каталог'));
    }
    return Future.value(const BookLibraryScan(
      books: [],
      unreadableCount: 0,
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('failed initial RPG load has retry, never a blank or crash',
      (tester) async {
    final gateway = _FaultGateway()
      ..loadResponse = (attempt) => attempt == 1
          ? Future.error(StateError('unavailable'))
          : Future.value(_start);
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: gateway,
        campaignId: 'ux-crash-probe',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сохранение не удалось открыть'), findsOneWidget);
    expect(find.text('Повторить загрузку'), findsOneWidget);
    await tester.tap(find.text('Повторить загрузку'));
    await tester.pumpAndSettle();
    expect(find.text('Перед героем старый мост.'), findsOneWidget);
    expect(find.byKey(const Key('world-choice-cross')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed refresh retains last committed scene and game panels',
      (tester) async {
    final gateway = _FaultGateway()
      ..loadResponse = (attempt) => attempt == 1
          ? Future.value(_start)
          : Future.error(StateError('temporary SQLite read failure'));
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: gateway,
        campaignId: 'ux-crash-probe',
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Обновить сохранённое состояние'));
    await tester.pumpAndSettle();
    expect(find.text('Перед героем старый мост.'), findsOneWidget);
    expect(find.text('Ходов: 0'), findsOneWidget);
    expect(find.textContaining('Последнее успешно загруженное состояние'),
        findsOneWidget);
    await tester.tap(find.text('Герой'));
    await tester.pumpAndSettle();
    expect(find.text('Герой: Путешественник'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed choice is retryable and cannot advance optimistically',
      (tester) async {
    final gateway = _FaultGateway()
      ..choiceResponse = (attempt) => attempt == 1
          ? Future.error(StateError('storage unavailable'))
          : Future.value(const WorldChoiceResult(
              applied: true,
              view: _finished,
            ));
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: gateway,
        campaignId: 'ux-crash-probe',
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('world-choice-cross')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ход не сохранён'), findsOneWidget);
    expect(find.text('Ходов: 0'), findsOneWidget);
    expect(gateway.writes, 1);
    await tester.tap(find.byKey(const Key('world-choice-cross')));
    await tester.pumpAndSettle();
    expect(gateway.writes, 2);
    expect(find.text('Ходов: 1'), findsOneWidget);
    expect(find.text('История завершена'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid double-tap commits one choice, locked choice commits none',
      (tester) async {
    final pending = Completer<WorldChoiceResult>();
    final gateway = _FaultGateway()
      ..choiceResponse = (_) => pending.future;
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: gateway,
        campaignId: 'ux-crash-probe',
      ),
    ));
    await tester.pumpAndSettle();
    final locked = find.byKey(const Key('world-choice-locked'));
    expect(tester.widget<FilledButton>(locked).onPressed, isNull);
    await tester.tap(find.byKey(const Key('world-choice-cross')));
    await tester.tap(find.byKey(const Key('world-choice-cross')));
    await tester.pump();
    expect(gateway.writes, 1);
    expect(find.text('Ходов: 0'), findsOneWidget);
    pending.complete(const WorldChoiceResult(applied: true, view: _finished));
    await tester.pumpAndSettle();
    expect(find.text('Ходов: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving game during pending load causes no setState-after-dispose',
      (tester) async {
    final pending = Completer<WorldGameView>();
    final gateway = _FaultGateway()..loadResponse = (_) => pending.future;
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: gateway,
        campaignId: 'ux-crash-probe',
      ),
    ));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    pending.complete(_start);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving game during pending write does not update dead widgets',
      (tester) async {
    final pending = Completer<WorldChoiceResult>();
    final gateway = _FaultGateway()
      ..choiceResponse = (_) => pending.future;
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: gateway,
        campaignId: 'ux-crash-probe',
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('world-choice-cross')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    pending.complete(const WorldChoiceResult(applied: true, view: _finished));
    await tester.pumpAndSettle();
    expect(gateway.writes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library failure is visible and retry restores import UI',
      (tester) async {
    final storage = _UnstableBooks();
    await tester.pumpWidget(MaterialApp(
      home: LibraryPage(bookStorage: storage),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Повторить загрузку'), findsOneWidget);
    await tester.tap(find.text('Повторить загрузку'));
    await tester.pumpAndSettle();
    expect(storage.calls, 2);
    expect(find.byKey(const ValueKey('library-import')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small-screen panel changes and desktop F11 do not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final gateway = _FaultGateway();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: WorldPlayPage(
        gateway: gateway,
        campaignId: 'ux-crash-probe',
      ),
    ));
    await tester.pumpAndSettle();
    for (final panel in ['Герой', 'Предметы', 'Журнал']) {
      await tester.tap(find.text(panel));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: panel);
      // A modal bottom sheet has no page back button. Pop its route, not
      // WidgetTester's AppBar pageBack helper.
      Navigator.of(tester.element(find.byType(WorldPlayPage))).pop();
      await tester.pumpAndSettle();
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated home to library and settings navigation stays stable',
      (tester) async {
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Как в системе'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Библиотека'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-import')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
