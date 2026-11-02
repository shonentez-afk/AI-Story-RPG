import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/home_page.dart';
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
  const _FailingChoiceGateway();
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
  const gateway = DeviceWorldLibraryGateway();
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
    return gateway.install(bytes);
  }

  Future<void> tapChoice(WidgetTester tester, String id) async {
    final finder = find.byKey(ValueKey('world-choice-' + id));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('one library imports and displays verified worlds separately '
      'from legacy books and reading', (tester) async {
    final world = await install();
    await tester.pumpWidget(const MaterialApp(
      home: LibraryPage(worldGateway: gateway),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-import')), findsOneWidget);
    expect(find.text('Добавить книгу'), findsOneWidget);
    expect(find.textContaining('TXT, FB2'), findsOneWidget);
    expect(find.byKey(ValueKey('library-world-' + world.bookworldId)),
        findsOneWidget);
    // Existing pilot is still present and world is NOT a BookReaderPage.
    expect(find.text('Демо RPG • начать новое прохождение'), findsOneWidget);
    await tester.ensureVisible(find.byKey(
      ValueKey('library-world-' + world.bookworldId)));
    await tester.tap(find.byKey(
      ValueKey('library-world-' + world.bookworldId)));
    await tester.pumpAndSettle();
    expect(find.text('Подготовленный игровой мир'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('world-start')));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(find.text('insight: 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1. '), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('35 real UI choices commit to SQLite and reopen after 23',
      (tester) async {
    final world = await install();
    await tester.pumpWidget(MaterialApp(
      home: WorldCampaignsPage(world: world, gateway: gateway),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-start')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 23; i++) {
      await tapChoice(tester, 'inspect_gate');
    }
    expect(find.text('Ходов: 23'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    final saved = (await gateway.campaigns(worldHash: world.archiveHash)).single;
    expect(saved.revision, 23);
    await tester.tap(find.byKey(ValueKey('world-campaign-' + saved.id)));
    await tester.pumpAndSettle();
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

  testWidgets('storage failure does not optimistically advance RPG scene',
      (tester) async {
    final world = await install();
    final id = await gateway.start(world.archiveHash);
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(
        gateway: const _FailingChoiceGateway(), campaignId: id,
      ),
    ));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.text('Решений пока нет'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
