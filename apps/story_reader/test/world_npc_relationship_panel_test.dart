import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/world_play_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gateway implements WorldLibraryGateway {
  _Gateway(this.view);
  final WorldGameView view;

  @override
  Future<WorldGameView> load(String campaignId) async {
    expect(campaignId, 'campaign_a');
    return view;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Only read-only load is supported');
}

WorldGameView _game({required List<NpcRelationView> npcs}) => WorldGameView(
  campaignId: 'campaign_a',
  worldTitle: 'Частная история', sceneId: 'canon_end',
  sceneText: 'Сохранённая финальная сцена.', revision: 2, tick: 2,
  isTerminal: true,
  stats: const {}, inventory: const [], flags: const {},
  knownFacts: const [], choices: const [], journal: const [],
  npcRelations: npcs,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('verified NPC trust and memory are visible in the game bar',
      (tester) async {
    final npc = 'npc_' + List.filled(32, 'c').join();
    final world = _game(npcs: [
      NpcRelationView(
        actorId: npc,
        displayName: 'Мария',
        directedScore: 20,
        memoryCount: 2,
        memoryKinds: const {'helped': 1, 'promiseReceived': 1},
        lifeState: 'present',
      ),
    ]);
    await tester.pumpWidget(MaterialApp(home: WorldPlayPage(
      gateway: _Gateway(world), campaignId: 'campaign_a',
    )));
    await tester.pumpAndSettle();
    expect(find.text('Герой'), findsOneWidget);
    expect(find.text('Предметы'), findsOneWidget);
    expect(find.text('Журнал'), findsOneWidget);
    await tester.tap(find.text('NPC'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-npc-relation-list')),
        findsOneWidget);
    expect(find.text('Персонажи'), findsOneWidget);
    expect(find.text('Мария'), findsOneWidget);
    expect(find.text('Отношение NPC к герою: +20'), findsOneWidget);
    expect(find.text('Запомненных событий: 2'), findsOneWidget);
    expect(find.text('Получил помощь: 1'), findsOneWidget);
    expect(find.text('Состояние: доступен'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unencountered NPC do not appear in reader interface',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: WorldPlayPage(
      gateway: _Gateway(_game(npcs: const [])),
      campaignId: 'campaign_a',
    )));
    await tester.pumpAndSettle();
    expect(find.text('NPC'), findsNothing);
    expect(find.text('Журнал'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NPC relationship sheet fits a narrow phone',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1280);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final npc = 'npc_' + List.filled(32, 'c').join();
    final world = _game(npcs: [
      NpcRelationView(
        actorId: npc, displayName: 'Незнакомая Мария',
        directedScore: -10, memoryCount: 1,
        memoryKinds: const {'betrayed': 1}, lifeState: 'absent',
      ),
    ]);
    await tester.pumpWidget(MaterialApp(home: WorldPlayPage(
      gateway: _Gateway(world), campaignId: 'campaign_a',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NPC'));
    await tester.pumpAndSettle();
    expect(find.text('Отношение NPC к герою: -10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
