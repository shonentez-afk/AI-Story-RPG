import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/world_play_page.dart';
import 'package:flutter/material.dart';
import 'package:story_core/story_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI presentation test. Independent Python/Dart parity tests verify that
/// the same fields originate from the signed BookWorld v3/SQLite replay.
class _RichViewGateway implements WorldLibraryGateway {
  const _RichViewGateway();

  @override
  Future<WorldGameView> load(String id) async => const WorldGameView(
    campaignId: 'rich_test_slot',
    worldTitle: 'Река — приватная RPG',
    sceneId: 'safe',
    sceneText: 'На берегу наступила тишина.',
    revision: 2,
    tick: 2,
    isTerminal: true,
    stats: {'courage': 4, 'insight': 1},
    inventory: [],
    flags: {
      'rope': true,
      'player_is_npc_0123456789abcdef0123456789abcdef': true,
    },
    knownFacts: ['rescue_fact'],
    choices: [],
    journal: [
      WorldEventView(
        sequence: 1, sceneId: 'road', sceneTitle: 'Дорога',
        choiceLabel: 'Взять верёвку',
        changes: ['Получено: Верёвка', 'Смелость: +1'],
      ),
      WorldEventView(
        sequence: 2, sceneId: 'river', sceneTitle: 'У реки',
        choiceLabel: 'Спасти мальчика',
        changes: ['Использовано: Верёвка', 'Смелость: +2',
                  'Узнано: Мальчик спасён у реки'],
      ),
    ],
    heroName: 'Лена',
    heroDescription: 'Путешественница, помогающая мальчику у реки.',
    sceneSource: WorldSceneSourceView(
      chapterIndex: 1, chapterCount: 2,
      isSourcePassage: false, sourceTitle: 'Река',
    ),
    itemNames: {'rope': 'Верёвка'},
    itemDescriptions: {'rope': 'Прочная верёвка у дороги'},
    statNames: {'courage': 'Смелость', 'insight': 'Наблюдательность'},
    factNames: {'rescue_fact': 'Мальчик спасён у реки'},
    sceneNames: {'road': 'Дорога', 'river': 'У реки'},
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();


  test('knowledge-gated response hides secret button label until '
      'all actor knowledge and role conditions are satisfied', () {
    final signed = BlueprintChoice.fromJson({
      'id': 'answer_npc',
      'label': 'Раскрыть собеседнику секрет из книги',
      'next_scene_id': 'next',
      'conditions': [
        {
          'op': 'flag_is',
          'id': 'player_is_npc_0123456789abcdef0123456789abcdef',
          'value': true,
        },
        {'op': 'knows_fact', 'id': 'hero_read_123', 'actor': 'player'},
      ],
      'effects': <Object>[],
    });
    const hidden = 'Реплика скрыта до выполнения условий';

    // Even if the role gate fails FIRST, a later knows_fact gate makes
    // the signed dialogue response sensitive and its text must not leak.
    final noRoleOrFact = WorldChoiceView.fromVerifiedRules(
      signedChoice: signed,
      lockReason: 'condition_not_met:flag_is',
      verifiedKnowledge: {'player': <String>{}},
    );
    expect(noRoleOrFact.enabled, false);
    expect(noRoleOrFact.label, hidden);
    expect(noRoleOrFact.label, isNot(contains('секрет')));

    final noFact = WorldChoiceView.fromVerifiedRules(
      signedChoice: signed,
      lockReason: 'condition_not_met:knows_fact',
      verifiedKnowledge: {'player': <String>{}},
    );
    expect(noFact.label, hidden);

    // Knowledge exists, but another precondition is still false:
    // do not disclose the line to the wrong playable character.
    final wrongRole = WorldChoiceView.fromVerifiedRules(
      signedChoice: signed,
      lockReason: 'condition_not_met:flag_is',
      verifiedKnowledge: {'player': <String>{'hero_read_123'}},
    );
    expect(wrongRole.label, hidden);

    final ready = WorldChoiceView.fromVerifiedRules(
      signedChoice: signed,
      lockReason: null,
      verifiedKnowledge: {'player': <String>{'hero_read_123'}},
    );
    expect(ready.enabled, true);
    expect(ready.label, 'Раскрыть собеседнику секрет из книги');

    // Fail closed if a buggy adapter claims an unread fact's response
    // is enabled. Don't let an inconsistent engine projection reach UI.
    expect(() => WorldChoiceView.fromVerifiedRules(
      signedChoice: signed,
      lockReason: null,
      verifiedKnowledge: {'player': <String>{}},
    ), throwsFormatException);
  });

  test('ordinary item-gated choices keep the existing UX', () {
    final signed = BlueprintChoice.fromJson({
      'id': 'use_lamp', 'label': 'Использовать фонарь',
      'next_scene_id': 'next',
      'conditions': [{'op': 'has_item', 'id': 'lamp'}],
      'effects': <Object>[],
    });
    final locked = WorldChoiceView.fromVerifiedRules(
      signedChoice: signed, lockReason: 'condition_not_met:has_item',
      verifiedKnowledge: {'player': <String>{}},
    );
    expect(locked.label, signed.label);
    expect(locked.enabled, false);
  });

  testWidgets('current scene provenance is shown without future chapters',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: WorldPlayPage(
      gateway: _RichViewGateway(), campaignId: 'rich_test_slot',
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-book-origin')), findsOneWidget);
    expect(find.textContaining('Альтернативный сюжет · глава 2/2'),
        findsOneWidget);
    expect(find.textContaining('SOURCE_PASSAGE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich hero panel shows actual profile and stats', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: WorldPlayPage(
      gateway: _RichViewGateway(), campaignId: 'rich_test_slot',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Герой'));
    await tester.pumpAndSettle();
    expect(find.text('Герой: Лена'), findsOneWidget);
    expect(find.text('Роль: проверенная карточка персонажа'),
        findsOneWidget);
    // A stable actor ID is useful for troubleshooting, not normal prose.
    // The user can explicitly expand it without reading future NPC metadata.
    final diagnostics = find.byKey(const Key('world-hero-diagnostics'));
    await tester.ensureVisible(diagnostics);
    await tester.tap(diagnostics);
    await tester.pumpAndSettle();
    expect(find.textContaining('Постоянный ID: npc_01234567'),
        findsOneWidget);
    expect(find.textContaining('Знания и секреты NPC не присваиваются'),
        findsOneWidget);
    expect(find.text('Смелость: 4'), findsOneWidget);
    expect(find.text('Наблюдательность: 1'), findsOneWidget);
    // The hero sheet deliberately virtualizes its rows on compact devices.
    // Source-confirmed facts must remain reachable by physical scrolling.
    final fact = find.textContaining('Мальчик спасён у реки');
    await tester.scrollUntilVisible(fact, 90,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(fact, findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich inventory never fabricates a spent item', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: WorldPlayPage(
      gateway: _RichViewGateway(), campaignId: 'rich_test_slot',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предметы'));
    await tester.pumpAndSettle();
    expect(find.text('Предметов пока нет'), findsOneWidget);
    expect(find.textContaining('Прочная верёвка'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich journal shows verified committed changes in Russian',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: WorldPlayPage(
      gateway: _RichViewGateway(), campaignId: 'rich_test_slot',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Дорога: Взять верёвку'), findsOneWidget);
    expect(find.textContaining('Получено: Верёвка'), findsOneWidget);
    expect(find.textContaining('Использовано: Верёвка'), findsOneWidget);
    expect(find.textContaining('Узнано: Мальчик спасён у реки'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rich current inventory uses book labels and descriptions',
      (tester) async {
    // The live gateway normally derives these fields from v3 provenance.
    const view = WorldGameView(
      campaignId: 'demo', worldTitle: 'Река', sceneId: 'road',
      sceneText: 'У дороги.', revision: 1, tick: 1, isTerminal: true,
      stats: {'courage': 2}, inventory: ['rope'], flags: {},
      knownFacts: [], choices: [], journal: [],
      itemNames: {'rope': 'Верёвка'},
      itemDescriptions: {'rope': 'Прочная верёвка у дороги'},
    );
    // Confirm the data contract without inventing a special mutable world.
    expect(view.inventory, ['rope']);
    expect(view.itemNames[view.inventory.single], 'Верёвка');
    expect(view.itemDescriptions['rope'], 'Прочная верёвка у дороги');
  });
}
