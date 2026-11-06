import 'package:ai_story_reader/scene_dialogue_stage.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/world_play_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sample =
    'В старом доме открылась дверь.\n'
    'Лена: «Ты меня слышишь?»\n'
    'Страж: «Да. Но прежде ответь на вопрос».\n'
    'За стеной послышались шаги.';
const _spoken =
    'Лена: «Ты меня слышишь?»\n'
    'Страж: «Слышу. Что тебе нужно?»';

class _DialogueGateway implements WorldLibraryGateway {
  int commits = 0;
  WorldGameView current = const WorldGameView(
    campaignId: 'dialogue_campaign',
    worldTitle: 'Тайна ворот',
    sceneId: 'gate',
    sceneText: _spoken,
    revision: 0,
    tick: 0,
    isTerminal: false,
    stats: {},
    inventory: [],
    flags: {},
    knownFacts: [],
    choices: [WorldChoiceView(id: 'ask_guard', label: 'Ответить стражу')],
    journal: [],
  );

  @override
  Future<WorldGameView> load(String id) async => current;

  @override
  Future<WorldChoiceResult> choose(String id, {
    required String actionId, required String choiceId,
    required int expectedRevision,
  }) async {
    commits++;
    expect(choiceId, 'ask_guard');
    expect(expectedRevision, 0);
    current = const WorldGameView(
      campaignId: 'dialogue_campaign',
      worldTitle: 'Тайна ворот',
      sceneId: 'end',
      sceneText: 'Страж открыл дверь.',
      revision: 1,
      tick: 1,
      isTerminal: true,
      stats: {}, inventory: [], flags: {}, knownFacts: [],
      choices: [], journal: [],
    );
    return WorldChoiceResult(applied: true, view: current);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only attributed quotes become dialogue; narrator text is preserved', () {
    final script = SceneDialogueScript.fromSceneText(_sample)!;
    expect(script.turns, hasLength(4));
    expect(script.turns[0].speaker, isNull);
    expect(script.turns[0].text, 'В старом доме открылась дверь.');
    expect(script.turns[1].speaker, 'Лена');
    expect(script.turns[1].text, 'Ты меня слышишь?');
    expect(script.turns[2].speaker, 'Страж');
    expect(script.turns[3].speaker, isNull);
    expect(SceneDialogueScript.fromSceneText(
        'В этой сцене герои разговаривают, но говорящие неизвестны.'),
        isNull);
    expect(SceneDialogueScript.fromSceneText(
        '— Как зовут тебя?\n— Я не знаю, кто спросил.'), isNull);
    expect(SceneDialogueScript.fromSceneText(
        'Лена: «Одна реплика»\nГлава: просто рассказ.'), isNull);
  });

  test('rich v3 scene produces the same signed speaker turns as UI, '
      'not an independent NPC truth claim', () {
    final presentation = RichSceneDialogue.presentationFor(_sample)!;
    final turns = RichSceneDialogue.verify(presentation, _sample);
    final script = SceneDialogueScript.fromSignedTurns(turns);
    final legacy = SceneDialogueScript.fromSceneText(_sample)!;
    expect(script.turns, hasLength(legacy.turns.length));
    for (var i = 0; i < script.turns.length; i++) {
      expect(script.turns[i].speaker, legacy.turns[i].speaker);
      expect(script.turns[i].text, legacy.turns[i].text);
    }
    expect(script.turns.first.isNarration, true);
    expect(script.turns.last.isNarration, true);
    expect(() => RichSceneDialogue.verify({
      'scene_text_sha256': presentation['scene_text_sha256'],
      'turns': [
        {'speaker': null, 'text': 'Подменённые слова.'},
        ...(presentation['turns'] as List).skip(1),
      ],
    }, _sample), throwsFormatException);
    expect(RichSceneDialogue.presentationFor(
        '— Кто говорит?\n— Никто не знает.'), isNull);
  });

  testWidgets('named speakers, portrait slots, history and saved reading position',
      (tester) async {
    final script = SceneDialogueScript.fromSceneText(_spoken)!;
    var completed = false;
    Widget stage() => MaterialApp(home: Scaffold(
      body: ListView(children: [
        DialogueStage(
          key: const ValueKey('stage-local'),
          script: script, campaignId: 'slot_01',
          sceneId: 'gate', revision: 0,
          textColor: const Color(0xff342e2a),
          pageColor: const Color(0xfff4ecdd),
          fontSize: 18, lineHeight: 1.5,
          onFinished: (value) => completed = value,
        ),
      ]),
    ));
    await tester.pumpWidget(stage());
    await tester.pumpAndSettle();
    expect(find.text('Лена'), findsOneWidget);
    expect(find.text('Ты меня слышишь?'), findsOneWidget);
    expect(find.byKey(const ValueKey('dialogue-speaker-portrait')),
        findsOneWidget);
    expect(completed, false);
    await tester.tap(find.byKey(const ValueKey('dialogue-history-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Лена: Ты меня слышишь?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialogue-next')));
    await tester.pumpAndSettle();
    expect(find.text('Страж'), findsOneWidget);
    expect(find.text('Слышу. Что тебе нужно?'), findsOneWidget);
    expect(completed, false);

    // Reopen the SAME committed scene: continue at the second line.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(stage());
    await tester.pumpAndSettle();
    expect(find.text('Страж'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialogue-next')));
    await tester.pumpAndSettle();
    expect(completed, true);
    expect(find.byKey(const ValueKey('dialogue-complete')), findsOneWidget);
  });

  testWidgets('verified rich v3 turns drive dialogue, portraits and '
      'choice gate without extra game-state writes', (tester) async {
    final gateway = _DialogueGateway();
    final signed = RichSceneDialogue.verify(
        RichSceneDialogue.presentationFor(_spoken), _spoken);
    gateway.current = WorldGameView(
      campaignId: 'dialogue_campaign', worldTitle: 'Тайна ворот',
      sceneId: 'gate', sceneText: _spoken,
      sceneDialogueTurns: signed,
      revision: 0, tick: 0, isTerminal: false,
      stats: const {}, inventory: const [], flags: const {},
      knownFacts: const [],
      choices: const [WorldChoiceView(
          id: 'ask_guard', label: 'Ответить стражу')],
      journal: const [],
    );
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(gateway: gateway, campaignId: 'dialogue_campaign'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byKey(const ValueKey('dialogue-stage')), findsOneWidget);
    expect(find.text('Лена'), findsOneWidget);
    expect(find.byKey(const ValueKey('world-dialogue-choice-gate')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('world-choice-ask_guard')), findsNothing);
    expect(gateway.commits, 0);
    await tester.tap(find.byKey(const ValueKey('dialogue-next')));
    await tester.pumpAndSettle();
    expect(find.text('Страж'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialogue-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dialogue-complete')), findsOneWidget);
    final choice = find.byKey(const ValueKey('world-choice-ask_guard'));
    await tester.scrollUntilVisible(choice, 100,
        scrollable: find.byType(Scrollable).first);
    expect(choice, findsOneWidget);
    expect(gateway.commits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choices remain hidden until conversation finishes',
      (tester) async {
    final gateway = _DialogueGateway();
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(gateway: gateway, campaignId: 'dialogue_campaign'),
    ));
    // An indeterminate loading indicator can keep pumpAndSettle active
    // while mocked asynchronous view/prefs settle; pump bounded frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byKey(const ValueKey('dialogue-stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('world-choice-ask_guard')), findsNothing);
    expect(gateway.commits, 0);
    await tester.tap(find.byKey(const ValueKey('dialogue-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-choice-ask_guard')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dialogue-next')));
    await tester.pumpAndSettle();
    final choice = find.byKey(const ValueKey('world-choice-ask_guard'));
    await tester.scrollUntilVisible(choice, 100,
        scrollable: find.byType(Scrollable).first);
    // A taller portrait card can leave the choice center under the
    // floating reading-mode button even though it is technically visible.
    // Scroll it fully clear of the bottom chrome before an actual tap.
    final scroll = find.byKey(const ValueKey('world-scene-scroll'));
    final viewport = tester.getRect(scroll);
    final buttonCenter = tester.getCenter(choice);
    if (buttonCenter.dy > viewport.bottom - 115) {
      await tester.drag(
        scroll, Offset(0, viewport.bottom - 180 - buttonCenter.dy),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(gateway.commits, 1);
    expect(find.text('История завершена'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no speaker data falls back to existing reading and choices',
      (tester) async {
    final gateway = _DialogueGateway();
    gateway.current = const WorldGameView(
      campaignId: 'dialogue_campaign', worldTitle: 'Тайна ворот',
      sceneId: 'gate', sceneText: 'Обычное повествование без имён говорящих.',
      revision: 0, tick: 0, isTerminal: false,
      stats: {}, inventory: [], flags: {}, knownFacts: [],
      choices: [WorldChoiceView(id: 'ask_guard', label: 'Ответить стражу')],
      journal: [],
    );
    await tester.pumpWidget(MaterialApp(
      home: WorldPlayPage(gateway: gateway, campaignId: 'dialogue_campaign'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dialogue-stage')), findsNothing);
    expect(find.text('Обычное повествование без имён говорящих.'),
        findsOneWidget);
    final choice = find.byKey(const ValueKey('world-choice-ask_guard'));
    await tester.scrollUntilVisible(choice, 100,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(choice).onPressed, isNotNull);
  });
}
