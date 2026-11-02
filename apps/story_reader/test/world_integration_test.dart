import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/home_page.dart';
import 'package:ai_story_reader/campaign_store.dart';
import 'package:ai_story_reader/save_store.dart';
import 'package:ai_story_reader/campaigns_page.dart';
import 'package:ai_story_reader/world_campaigns_page.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/world_play_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PrivatePaths extends PathProviderPlatform {
  _PrivatePaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _FailingChoiceGateway extends DeviceWorldLibraryGateway {
  const _FailingChoiceGateway() : super(background: false);
  @override
  Future<WorldChoiceResult> choose(String campaignId, {
    required String actionId, required String choiceId,
    required int expectedRevision,
  }) async => throw StateError('test: failed to persist');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform previous;
  const gateway = DeviceWorldLibraryGateway(background: false);
  const fixture = '../../artifacts/bookworld/manor_m17_original_demo.bworld';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previous = PathProviderPlatform.instance;
    temp = Directory.systemTemp.createTempSync('rpg_flutter_world_');
    PathProviderPlatform.instance = _PrivatePaths(temp.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = previous;
    temp.deleteSync(recursive: true);
  });

  Future<WorldLibraryItem> install() async {
    final bytes = Uint8List.fromList(File(fixture).readAsBytesSync());
    // The in-process test host runs the real SQLite store; production runs
    // that identical code in Isolate.run by default.
    return gateway.install(bytes);
  }

  Future<void> settleWorker(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> tapChoice(WidgetTester tester, String id) async {
    final finder = find.byKey(ValueKey('world-choice-' + id));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder, 160, scrollable: find.byType(Scrollable).first,
      );
    } else {
      await tester.ensureVisible(finder);
    }
    await tester.tap(finder);
    await settleWorker(tester);
    expect(tester.takeException(), isNull);
  }

  test('default worker isolate reads and writes exact BookWorld', () async {
    const worker = DeviceWorldLibraryGateway();
    final bytes = Uint8List.fromList(File(fixture).readAsBytesSync());
    final world = await worker.install(bytes);
    final id = await worker.start(world.archiveHash);
    final first = await worker.load(id);
    expect(first.sceneId, 'gate');
    expect(first.revision, 0);
    final chosen = await worker.choose(id,
        actionId: 'worker_first', choiceId: 'inspect_gate',
        expectedRevision: 0);
    expect(chosen.applied, true);
    expect((await worker.load(id)).revision, 1);
  });

  testWidgets('one library imports and displays verified worlds separately '
      'from legacy books and reading', (tester) async {
    final world = await install();
    await tester.pumpWidget(const MaterialApp(
      home: LibraryPage(worldGateway: gateway),
    ));
    await settleWorker(tester);
    expect(find.byKey(const ValueKey('library-import')), findsOneWidget);
    expect(find.text('Добавить книгу'), findsOneWidget);
    expect(find.textContaining('TXT, FB2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('library-world-' + world.bookworldId)),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(ValueKey('library-world-' + world.bookworldId)),
        findsOneWidget);
    // Existing pilot is still present and world is NOT a BookReaderPage.
    expect(find.text('Демо RPG • начать новое прохождение'), findsOneWidget);
    await tester.ensureVisible(find.byKey(
      ValueKey('library-world-' + world.bookworldId)));
    await tester.tap(find.byKey(
      ValueKey('library-world-' + world.bookworldId)));
    await settleWorker(tester);
    expect(find.text('Подготовленный игровой мир'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('world-start')));
    await settleWorker(tester);
    expect(find.text('У ворот тихо. Вы можете осмотреть камни или пройти к рынку.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('world-choice-enter_hall')),
        findsOneWidget);
    final locked = tester.widget<FilledButton>(
        find.byKey(const ValueKey('world-choice-enter_hall')));
    expect(locked.onPressed, isNull);
    await tapChoice(tester, 'inspect_gate');
    expect(find.text('Ходов: 1'), findsOneWidget);
    await tester.tap(find.text('Герой'));
    await settleWorker(tester);
    expect(find.text('insight: 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await settleWorker(tester);
    await tester.tap(find.text('Журнал'));
    await settleWorker(tester);
    expect(find.textContaining('1. '), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('35 real UI choices commit to SQLite and reopen after 23',
      (tester) async {
    final world = await install();
    await tester.pumpWidget(MaterialApp(
      home: WorldCampaignsPage(world: world, gateway: gateway),
    ));
    await settleWorker(tester);
    await tester.tap(find.byKey(const ValueKey('world-start')));
    await settleWorker(tester);
    for (var i = 0; i < 23; i++) {
      await tapChoice(tester, 'inspect_gate');
    }
    expect(find.text('Ходов: 23'), findsOneWidget);
    await tester.pageBack();
    await settleWorker(tester);
    final saved = (await gateway.campaigns(worldHash: world.archiveHash)).single;
    expect(saved.revision, 23);
    await tester.tap(find.byKey(ValueKey('world-campaign-' + saved.id)));
    await settleWorker(tester);
    expect(find.text('Ходов: 23'), findsOneWidget);
    for (final choice in [
      'walk_market', 'ask_guard', 'walk_market', 'buy_map',
      'walk_market', 'find_key', 'enter_hall', 'learn_from_guard',
      'write_note', 'go_cellar', 'open_vault', 'publish_archive',
    ]) {
      await tapChoice(tester, choice);
    }
    expect(find.text('Ходов: 35'), findsOneWidget);
    expect(find.text('История завершена'), findsOneWidget);
    final restored = await gateway.load(saved.id);
    expect(restored.revision, 35);
    expect(restored.isTerminal, isTrue);
    expect(restored.flags['revealed'], isTrue);
    expect(restored.journal.length, 35);
    expect(restored.knownFacts, contains('archive_origin'));
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('unified saved campaigns list keeps legacy and BookWorld '
      'independent without a second library', (tester) async {
    final world = await install();
    final worldId = await gateway.start(world.archiveHash);
    await CampaignStore().write(
      'campaign_pilot_existing',
      const GameSaveRecord('old pilot snapshot', []),
      sceneTitle: 'Старая сцена',
    );
    await tester.pumpWidget(const MaterialApp(
      home: CampaignsPage(worldGateway: gateway),
    ));
    await settleWorker(tester);
    expect(find.text('Старая сцена'), findsOneWidget);
    expect(find.byKey(ValueKey('all-world-campaign-' + worldId)),
        findsOneWidget);
    expect(find.text('Библиотека'), findsNothing);
    await tester.tap(find.byKey(
        ValueKey('all-world-campaign-' + worldId)));
    await settleWorker(tester);
    expect(find.text('Ходов: 0'), findsOneWidget);
    await tapChoice(tester, 'inspect_gate');
    expect((await CampaignStore().all()).length, 1);
    expect((await gateway.load(worldId)).revision, 1);
  });

  testWidgets('home continues last BookWorld when no pilot slot exists',
      (tester) async {
    final world = await install();
    final worldId = await gateway.start(world.archiveHash);
    await tester.pumpWidget(const MaterialApp(home: HomePage(worldGateway: gateway)));
    await settleWorker(tester);
    expect(find.text(world.title), findsOneWidget);
    expect(find.text('Продолжить'), findsOneWidget);
    expect(find.text('Сохранённые кампании: 1'), findsOneWidget);
    await tester.tap(find.text('Продолжить'));
    await settleWorker(tester);
    expect(find.text('Ходов: 0'), findsOneWidget);
    await tapChoice(tester, 'inspect_gate');
    expect((await gateway.load(worldId)).revision, 1);
  });


  test('gateway guards stale deletion and archive reinstall', () async {
    final world = await install();
    final worldBytes = await gateway.exportWorld(world.archiveHash);
    expect(worldBytes, orderedEquals(File(fixture).readAsBytesSync()));
    final id = await gateway.start(world.archiveHash);
    await expectLater(gateway.deleteWorld(world.archiveHash),
        throwsFormatException);
    final choice = await gateway.choose(id,
      actionId: 'predelete', choiceId: 'inspect_gate', expectedRevision: 0,
    );
    expect(choice.applied, isTrue);
    final portable = await gateway.exportSave(id);
    await expectLater(gateway.deleteCampaign(id, expectedRevision: 0),
        throwsFormatException);
    expect((await gateway.load(id)).revision, 1);
    await gateway.deleteCampaign(id, expectedRevision: 1);
    await expectLater(gateway.load(id), throwsFormatException);
    await gateway.deleteWorld(world.archiveHash);
    expect(await gateway.worlds(), isEmpty);
    await gateway.install(worldBytes);
    final restoredId = await gateway.importSave(
      portable, expectedWorldHash: world.archiveHash,
    );
    expect(restoredId, isNot(id));
    expect((await gateway.load(restoredId)).revision, 1);
  });

  testWidgets('cancelling BookWorld delete leaves real SQLite intact',
      (tester) async {
    final world = await install();
    final id = await gateway.start(world.archiveHash);
    await tester.pumpWidget(MaterialApp(
      home: WorldCampaignsPage(world: world, gateway: gateway),
    ));
    await settleWorker(tester);
    await tester.tap(find.byTooltip('Действия с прохождением'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить с резервной копией'));
    // The parent route intentionally displays an indeterminate busy bar
    // while the confirmation dialog is open. pumpAndSettle cannot finish
    // while that animation is active; pump the dialog transition explicitly.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Удалить прохождение?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect((await gateway.campaigns(worldHash: world.archiveHash))
        .single.id, id);
    expect((await gateway.load(id)).revision, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('storage failure does not optimistically advance RPG scene',
      (tester) async {
    final world = await install();
    final id = await gateway.start(world.archiveHash);
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: const _FailingChoiceGateway(), campaignId: id,
      ),
    ));
    await settleWorker(tester);
    await tapChoice(tester, 'inspect_gate');
    expect(find.text('Ходов: 0'), findsOneWidget);
    expect(find.textContaining('Ход не сохранён'), findsOneWidget);
    expect((await gateway.load(id)).revision, 0);
    expect((await gateway.load(id)).journal, isEmpty);
  });

  testWidgets('compact screen keeps world journal accessible', (tester) async {
    final world = await install();
    final id = await gateway.start(world.archiveHash);
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
      home: WorldPlayPage(gateway: gateway, campaignId: id),
    ));
    await settleWorker(tester);
    await tester.tap(find.text('Журнал'));
    await settleWorker(tester);
    expect(find.text('Решений пока нет'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
