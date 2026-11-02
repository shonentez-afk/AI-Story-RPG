import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'package:ai_story_reader/home_page.dart';
import 'package:ai_story_reader/campaign_store.dart';
import 'package:ai_story_reader/save_store.dart';
import 'package:ai_story_reader/campaigns_page.dart';
import 'package:ai_story_reader/world_campaigns_page.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/world_play_page.dart';
import 'package:ai_story_reader/reading_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Test the actual shared system-file entry point without touching devices.
class _FixtureSavePicker extends FilePicker {
  _FixtureSavePicker(this.bytes);
  final Uint8List bytes;

  // file_picker 10.3.x already implements a concrete pickFiles method which
  // throws UnimplementedError. noSuchMethod cannot intercept that method.
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => FilePickerResult([
        PlatformFile(name: 'portable.bwsave', size: bytes.length, bytes: bytes),
      ]);
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
    await tester.pump();
    // At 200% accessibility text scale, the button can be built and only
    // partly inside the viewport. A real player scrolls farther before
    // tapping; do that here instead of sending a false off-screen click.
    final scroll = find.byKey(const ValueKey('world-scene-scroll'));
    if (scroll.evaluate().isNotEmpty) {
      final viewport = tester.getRect(scroll);
      final center = tester.getCenter(finder);
      if (center.dy > viewport.bottom - 24) {
        await tester.drag(
          scroll,
          Offset(0, viewport.bottom - 90 - center.dy),
        );
        await tester.pumpAndSettle();
      } else if (center.dy < viewport.top + 24) {
        await tester.drag(
          scroll,
          Offset(0, viewport.top + 90 - center.dy),
        );
        await tester.pumpAndSettle();
      }
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
    final portable = await worker.exportSave(id);
    final preview = await worker.previewSave(
      portable, expectedWorldHash: world.archiveHash,
    );
    expect(preview.revision, 1);
    expect(preview.worldHash, world.archiveHash);
    expect((await worker.campaigns()).length, 1);
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
      find.byKey(ValueKey('library-world-' + world.archiveHash)),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(ValueKey('library-world-' + world.archiveHash)),
        findsOneWidget);
    // Existing pilot is still present and world is NOT a BookReaderPage.
    expect(find.text('Демо RPG • начать новое прохождение'), findsOneWidget);
    await tester.ensureVisible(find.byKey(
      ValueKey('library-world-' + world.archiveHash)));
    await tester.tap(find.byKey(
      ValueKey('library-world-' + world.archiveHash)));
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
    expect(find.text('Наблюдательность: 1'), findsOneWidget);
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



  test('BookWorld preflight checks replay without importing, then restores',
      () async {
    final world = await install();
    final campaignId = await gateway.start(world.archiveHash);
    final result = await gateway.choose(campaignId,
      actionId: 'portable_preflight_first', choiceId: 'inspect_gate',
      expectedRevision: 0,
    );
    expect(result.applied, isTrue);
    final portable = await gateway.exportSave(campaignId);
    final inspected = await gateway.previewSave(
      portable, expectedWorldHash: world.archiveHash,
    );
    expect(inspected.sourceCampaignId, campaignId);
    expect(inspected.worldHash, world.archiveHash);
    expect(inspected.revision, 1);
    expect(inspected.stateHash.length, 64);
    expect(inspected.isTerminal, isFalse);
    expect((await gateway.campaigns()).length, 1);
    final wrongHash = List.filled(64, 'a').join();
    await expectLater(
      gateway.previewSave(portable, expectedWorldHash: wrongHash),
      throwsFormatException,
    );
    await expectLater(
      gateway.previewSave(
        portable.replaceFirst('"schema_version":2', '"schema_version":3'),
        expectedWorldHash: world.archiveHash,
      ),
      throwsFormatException,
    );
    expect((await gateway.campaigns()).length, 1);
    final importedId = await gateway.importSave(
      portable, expectedWorldHash: world.archiveHash,
    );
    expect(importedId, isNot(campaignId));
    expect((await gateway.load(importedId)).revision, 1);
    final importedPreview = await gateway.previewSave(
      await gateway.exportSave(importedId),
      expectedWorldHash: world.archiveHash,
    );
    expect(importedPreview.stateHash, inspected.stateHash);
    expect((await gateway.campaigns()).length, 2);
    expect((await gateway.load(campaignId)).revision, 1);
  });


  testWidgets('global save import accepts BookWorld v2 and cancel is read-only',
      (tester) async {
    final world = await install();
    final source = await gateway.start(world.archiveHash);
    final save = await gateway.exportSave(source);
    // FilePicker.platform is late-initialized only on installed device
    // plugins; a pure widget-test host may have no previous instance.
    FilePicker? previousPicker;
    try {
      previousPicker = FilePicker.platform;
    } catch (_) {
      // No native plugin in the Flutter test runner.
    }
    FilePicker.platform = _FixtureSavePicker(Uint8List.fromList(utf8.encode(save)));
    addTearDown(() {
      if (previousPicker != null) FilePicker.platform = previousPicker;
    });
    await tester.pumpWidget(MaterialApp(
      home: CampaignsPage(worldGateway: gateway),
    ));
    await settleWorker(tester);
    expect(find.byTooltip('Импортировать сохранение (.bwsave)'),
        findsOneWidget);

    Future<void> openPreview() async {
      await tester.tap(find.byTooltip('Импортировать сохранение (.bwsave)'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Импортировать прохождение?'), findsOneWidget);
      expect(find.textContaining('Ходов: 0'), findsOneWidget);
    }

    await openPreview();
    await tester.tap(find.text('Отмена'));
    await settleWorker(tester);
    expect((await gateway.campaigns()).length, 1);
    await openPreview();
    await tester.tap(find.text('Импортировать').last);
    await settleWorker(tester);
    expect((await gateway.campaigns()).length, 2);
    expect((await gateway.load(source)).revision, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global save import refuses missing BookWorld without writing',
      (tester) async {
    final world = await install();
    final original = await gateway.start(world.archiveHash);
    final save = await gateway.exportSave(original);
    await gateway.deleteCampaign(original, expectedRevision: 0);
    await gateway.deleteWorld(world.archiveHash);
    // FilePicker.platform is late-initialized only on installed device
    // plugins; a pure widget-test host may have no previous instance.
    FilePicker? previousPicker;
    try {
      previousPicker = FilePicker.platform;
    } catch (_) {
      // No native plugin in the Flutter test runner.
    }
    FilePicker.platform = _FixtureSavePicker(Uint8List.fromList(utf8.encode(save)));
    addTearDown(() {
      if (previousPicker != null) FilePicker.platform = previousPicker;
    });
    await tester.pumpWidget(MaterialApp(
      home: CampaignsPage(worldGateway: gateway),
    ));
    await settleWorker(tester);
    await tester.tap(find.byTooltip('Импортировать сохранение (.bwsave)'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Импортировать прохождение?'), findsNothing);
    expect(find.textContaining('соответствующий .bworld'), findsOneWidget);
    expect((await gateway.campaigns()), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library searches worlds without false books-not-found',
      (tester) async {
    final world = await install();
    await tester.pumpWidget(MaterialApp(
      home: LibraryPage(worldGateway: gateway),
    ));
    await settleWorker(tester);
    expect(find.text('По вашему запросу ничего не найдено.'), findsNothing);
    final search = find.byType(TextField);
    await tester.enterText(search, 'несуществующий мир');
    await tester.pump();
    expect(find.text('По вашему запросу ничего не найдено.'), findsOneWidget);
    await tester.enterText(search, world.title);
    await tester.pump();
    expect(find.text('По вашему запросу ничего не найдено.'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('library-world-' + world.archiveHash)),
      150, scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(ValueKey('library-world-' + world.archiveHash)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BookWorld read failure is scrollable at 320dp and 200% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
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
      home: const WorldPlayPage(
        gateway: gateway, campaignId: 'c_missing',
      ),
    ));
    await settleWorker(tester);
    expect(find.textContaining('Сохранение не удалось открыть'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
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


  testWidgets('BookWorld shares palette and typography with the book reader',
      (tester) async {
    final world = await install();
    final id = await gateway.start(world.archiveHash);
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(gateway: gateway, campaignId: id),
    ));
    await settleWorker(tester);
    expect(find.byTooltip('Настройки чтения'), findsOneWidget);
    await tester.tap(find.byTooltip('Настройки чтения'));
    await tester.pumpAndSettle();
    expect(find.text('Размер текста: 18'), findsOneWidget);
    await tester.tap(find.text('Тёмная').last);
    await tester.pumpAndSettle();
    // The theme chip updates the reader immediately; the ordered
    // preference write may still be in flight after the last animation.
    final reading = await ReadingSettingsStore().load();
    expect(reading.palette, ReadingPalette.dark);
    await tester.runAsync(() => ReadingSettingsStore().flush());
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('ai_story_reading_v1_palette'), 2);
    expect((await gateway.load(id)).revision, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(gateway: gateway, campaignId: id),
    ));
    await settleWorker(tester);
    final page = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(page.backgroundColor, const Color(0xFF272727));
    expect((await gateway.load(id)).revision, 0);
    expect(find.byKey(const ValueKey('world-choice-inspect_gate')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BookWorld chrome modes keep choices and real SQLite journal',
      (tester) async {
    final world = await install();
    final id = await gateway.start(world.archiveHash);
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(gateway: gateway, campaignId: id),
    ));
    await settleWorker(tester);
    expect(find.byTooltip('Режим экрана'), findsOneWidget);
    expect(find.text('Герой'), findsOneWidget);
    await tester.tap(find.byTooltip('Режим экрана'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Режим чтения').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Настройки чтения'), findsNothing);
    expect(find.text('Предметы'), findsOneWidget);
    expect(find.byKey(const ValueKey('world-choice-inspect_gate')),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(find.text('Предметы'), findsNothing);
    expect(find.byTooltip('Показать управление'), findsOneWidget);
    const scene = 'У ворот тихо. Вы можете осмотреть камни или пройти к рынку.';
    expect(find.text(scene), findsOneWidget);
    final locked = tester.widget<FilledButton>(
        find.byKey(const ValueKey('world-choice-enter_hall')));
    expect(locked.onPressed, isNull);
    // A tap on noninteractive narrative text peeks the game panels; it does
    // not submit an action or alter the saved checkpoint.
    await tester.tap(find.text(scene));
    await tester.pumpAndSettle();
    expect(find.text('Журнал'), findsOneWidget);
    expect((await gateway.load(id)).revision, 0);
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.text('Решений пока нет'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Настройки чтения'), findsOneWidget);
    expect(find.text('Герой'), findsOneWidget);
    await tapChoice(tester, 'inspect_gate');
    expect((await gateway.load(id)).revision, 1);
    expect((await gateway.load(id)).journal.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BookWorld fullscreen remains playable at 320dp and 200% text',
      (tester) async {
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
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Настройки чтения'), findsNothing);
    expect(find.byTooltip('Показать управление'), findsOneWidget);
    await tapChoice(tester, 'inspect_gate');
    expect((await gateway.load(id)).revision, 1);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Режим экрана'), findsOneWidget);
    expect(find.text('Герой'), findsOneWidget);
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
