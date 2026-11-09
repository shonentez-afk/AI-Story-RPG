import 'package:ai_story_reader/world_play_page.dart';
import 'package:ai_story_reader/world_ui_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _maria = 'npc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hidden = 'npc_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final class _UiGateway implements WorldLibraryGateway {
  const _UiGateway(this.view);
  final WorldGameView view;
  @override
  Future<WorldGameView> load(String id) async {
    expect(id, 'ui_parity');
    return view;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

WorldGameView _view() => const WorldGameView(
  campaignId: 'ui_parity', worldTitle: 'Рассказ об Анне',
  sceneId: 'gm_scene_2', sceneText: 'Анна решила спасти мост.',
  revision: 4, tick: 7, isTerminal: true,
  activePlotMode: 'ALTER_FATE', sourceLiteralCanon: true,
  heroName: 'Путешественник',
  stats: {'gm_resolve': 51}, inventory: ['gm_rope'],
  itemNames: {'gm_rope': 'Верёвка'},
  knownFacts: ['gm_signal'], factNames: {'gm_signal': 'Сигнал'},
  flags: {'gm_has_plan': true},
  choices: [],
  journal: [
    WorldEventView(
      sequence: 3, sceneId: 'canon_00000',
      choiceLabel: 'Предупредить Анну',
      changes: ['Узнано: Сигнал', 'Новое обещание: спасти мост'],
    ),
    WorldEventView(
      sequence: 4, sceneId: 'gm_scene_2',
      choiceLabel: 'Исполнить обещание', changes: ['Получено: Верёвка'],
    ),
  ],
  npcRelations: [
    NpcRelationView(
      actorId: _maria, displayName: 'Анна',
      directedScore: 14, memoryCount: 4,
      memoryKinds: {'promiseReceived': 1, 'autonomousDecision': 1,
        'promiseFulfilled': 1, 'warned': 1},
      lifeState: 'present', currentGoal: 'gm_find_safe_shelter',
      openPromiseIds: ['gm_protect_bridge'],
      autonomousDecisionIds: ['gm_anna_seeks_help'],
    ),
  ],
  npcDisplayNames: {
    _maria: 'Анна', _hidden: 'Недоступный будущий персонаж',
  },
  npcItemOwners: {_hidden: 'gm_future_artifact'},
  alternatePlotContinuity: {
    'thread_id': 'gm_rescue_thread',
    'last_beat_id': 'gm_scene_2',
    'last_objective_id': 'gm_save_bridge',
    'last_lead_actor_id': _maria,
    'open_obligation_ids': ['gm_protect_bridge'],
    'next_directions': [
      {'kind': 'resolve_obligation', 'obligation_id': 'gm_protect_bridge'},
    ],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('real game panel shows autonomous NPC goals, promises, '
      'ALT_FATE obligations, hero and items without future spoilers',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: WorldPlayPage(
      gateway: _UiGateway(_view()), campaignId: 'ui_parity',
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('world-alternate-continuity')),
        findsOneWidget);
    expect(find.textContaining('Книжный ход событий изменён'), findsNothing);
    expect(find.textContaining('Открытые обязательства'), findsOneWidget);
    expect(find.textContaining('Недоступный будущий персонаж'), findsNothing);
    await tester.tap(find.text('NPC'));
    await tester.pumpAndSettle();
    expect(find.text('Анна'), findsWidgets);
    expect(find.text('Текущая цель: find safe shelter'), findsOneWidget);
    expect(find.text('Открытые обещания:'), findsOneWidget);
    expect(find.text('Самостоятельные решения:'), findsOneWidget);
    expect(find.text('• protect bridge'), findsOneWidget);
    expect(find.text('• anna seeks help'), findsOneWidget);
    expect(find.text('Исполненное обещание: 1'), findsOneWidget);
    expect(find.text('Самостоятельное решение: 1'), findsOneWidget);
    expect(find.textContaining('Недоступный будущий персонаж'), findsNothing);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Альтернативная ветка'), findsWidgets);
    expect(find.textContaining('Исполнить: protect bridge'), findsWidgets);
    expect(find.textContaining('Получено: Верёвка'), findsWidgets);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Герой'));
    await tester.pumpAndSettle();
    expect(find.text('Ход 4: Получено: Верёвка'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Предметы'));
    await tester.pumpAndSettle();
    expect(find.text('Верёвка'), findsOneWidget);
    expect(find.textContaining('Недоступный будущий персонаж'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long ALT_FATE continuity and four gaming panels remain '
      'reachable at 320dp and 200% accessibility scale', (tester) async {
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: WorldPlayPage(
          gateway: _UiGateway(_view()), campaignId: 'ui_parity'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-alternate-continuity')),
        findsOneWidget);
    expect(find.text('NPC'), findsOneWidget);
    await tester.tap(find.text('NPC'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('world-npc-relation-list')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('typed AI preview reports real resources, NPC actions, '
      'story direction and obligation without leaking future actors', () {
    final before = _view();
    final proposal = FreeformActionDraft.fromJson({
      'format': FreeformActionDraft.format,
      'scope': FreeformActionDraft.fictionScope,
      'player_text': 'Предупредить Анну и передать сигнал',
      'narration': 'Герой объясняет опасность у моста.',
      'effects': [
        {'op': 'grant_item', 'id': 'gm_river_bell'},
      ],
      'npc_interaction': {
        'actor_id': _maria,
        'memory_id': 'gm_warning_confirmed',
        'kind': 'promise_received',
        'trust_delta': 3,
        'goal_id': 'gm_protect_crossing',
        'learn_fact_id': 'gm_signal',
        'promise_id': 'gm_protect_bridge',
      },
      'plot_intent': 'continue',
      'plot_beat': {
        'format': 'ai_story_alternate_beat_v1',
        'beat_id': 'gm_new_crossing_scene',
        'thread_id': 'gm_rescue_thread',
        'previous_beat_id': 'gm_scene_2',
        'lead_actor_id': _maria,
        'objective_id': 'gm_save_bridge',
        'participant_actor_ids': ['player', _maria],
        'opened_obligation_ids': ['gm_help_next_village'],
        'resolved_obligation_ids': [],
        'route': 'protect',
      },
    });
    final lines = WorldUiPresenter.dynamicImpact(proposal, before);
    expect(lines, contains('Участник: Анна'));
    expect(lines, contains('Изменение доверия: +3'));
    expect(lines, contains('NPC узнает: Сигнал'));
    expect(lines, contains('Новая цель NPC: protect crossing'));
    expect(lines, contains('Обещание: protect bridge'));
    expect(lines, contains('Направление: Защита'));
    expect(lines, contains('Открыть обязательство: help next village'));
    expect(lines.last, contains('не изменены'));
    expect(lines.join(' '), isNot(contains('Недоступный будущий персонаж')));
  });
}
