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

WorldGameView _game({required List<NpcRelationView> npcs,
    Map<String, String> futureLife = const {},
    Map<String, String> custody = const {},
    Map<String, String> itemNames = const {},
    List<WorldEventView> journal = const []}) => WorldGameView(
  campaignId: 'campaign_a',
  worldTitle: 'Частная история', sceneId: 'canon_end',
  sceneText: 'Сохранённая финальная сцена.', revision: 2, tick: 2,
  isTerminal: true,
  stats: const {}, inventory: const [], flags: const {},
  knownFacts: const [], choices: const [], journal: journal,
  npcRelations: npcs, npcItemOwners: custody, itemNames: itemNames,
  npcLifeStates: futureLife,
  npcDisplayNames: {for (final id in futureLife.keys) id: 'Скрытый персонаж'},
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

  testWidgets('NPC item custody, hero inventory and signed journal stay '
      'aligned without exposing unencountered owners', (tester) async {
    final maria = 'npc_' + List.filled(32, 'a').join();
    final ivan = 'npc_' + List.filled(32, 'b').join();
    final hidden = 'npc_' + List.filled(32, 'f').join();
    final view = _game(
      npcs: [
        NpcRelationView(
          actorId: maria, displayName: 'Мария',
          directedScore: 12, memoryCount: 1,
          memoryKinds: const {'helped': 1}, lifeState: 'present',
        ),
        NpcRelationView(
          actorId: ivan, displayName: 'Иван',
          directedScore: -3, memoryCount: 1,
          memoryKinds: const {'witnessed': 1}, lifeState: 'present',
        ),
      ],
      custody: { 'letter': maria, 'sealed': hidden },
      itemNames: const { 'letter': 'Письмо', 'sealed': 'Секретный артефакт' },
      journal: const [
        WorldEventView(sequence: 1, sceneId: 'gate',
          sceneTitle: 'Встреча', choiceLabel: 'Передать письмо',
          changes: ['Передано персонажу: Письмо']),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: WorldPlayPage(
      gateway: _Gateway(view), campaignId: 'campaign_a',
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Предметы'));
    await tester.pumpAndSettle();
    expect(find.text('Письмо — у Мария'), findsOneWidget);
    expect(find.textContaining('Секретный артефакт'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NPC'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('world-npc-' + maria)), findsOneWidget);
    expect(find.byKey(Key('world-npc-' + ivan)), findsOneWidget);
    expect(find.text('Предмет у персонажа: Письмо'), findsOneWidget);
    expect(find.textContaining('Секретный артефакт'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Передано персонажу: Письмо'), findsOneWidget);
    expect(find.textContaining('Секретный артефакт'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('verified portrait address ignores duplicate names and future actors',
      () {
    final sameName = 'npc_' + List.filled(32, 'c').join();
    final other = 'npc_' + List.filled(32, 'd').join();
    final speaker = NpcRelationView(
        actorId: sameName, displayName: 'Мария',
        directedScore: 2, memoryCount: 1,
        memoryKinds: const {}, lifeState: 'present');
    final shadow = NpcRelationView(
        actorId: other, displayName: 'Мария',
        directedScore: 0, memoryCount: 0,
        memoryKinds: const {});
    final oldWorld = _game(npcs: [speaker]);
    expect(oldWorld.portraitStorageKeyFor('Мария'), sameName);
    final ambiguous = _game(npcs: [speaker, shadow]);
    expect(ambiguous.portraitStorageKeyFor('Мария'), isNull);
    // Two reviewed actors sharing a display label cannot resolve a
    // portrait from raw text. Unrevealed speech is never name-keyed.
    final reviewed = WorldGameView(
      campaignId: 'campaign_a', worldTitle: 'Игра', sceneId: 'gate',
      sceneText: 'Разговор', revision: 0, tick: 0, isTerminal: false,
      stats: const {}, inventory: const [], flags: const {},
      knownFacts: const [], choices: const [], journal: const [],
      npcRelations: [speaker], sceneSpeakerIdentityReviewed: true,
      visibleSpeakerActorIds: { 'Мария': sameName },
    );
    expect(reviewed.portraitStorageKeyFor('Мария'), sameName);
    expect(reviewed.portraitStorageKeyFor('Не встреченный'), isNull);
    // A locked line is not a license to open its portrait even when the
    // character was encountered in a prior scene.
    final locked = WorldGameView(
      campaignId: 'campaign_a', worldTitle: 'Игра', sceneId: 'gate',
      sceneText: 'Разговор', revision: 1, tick: 1, isTerminal: false,
      stats: const {}, inventory: const [], flags: const {},
      knownFacts: const [], choices: const [], journal: const [],
      npcRelations: [speaker], sceneSpeakerIdentityReviewed: true,
    );
    expect(locked.portraitStorageKeyFor('Мария'), isNull);
  });

  testWidgets('unmet NPC is not spoiled by future life transitions in Hero',
      (tester) async {
    final unseen = 'npc_' + List.filled(32, 'a').join();
    await tester.pumpWidget(MaterialApp(home: WorldPlayPage(
      gateway: _Gateway(_game(npcs: const [],
          futureLife: {unseen: 'dead'})), campaignId: 'campaign_a',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Герой'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Скрытый персонаж'), findsNothing);
    expect(find.textContaining('погиб'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
