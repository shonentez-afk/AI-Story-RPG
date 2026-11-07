import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/npc_dialogue_responses_review_page.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

final _npc = 'npc_' + List.filled(32, 'c').join();

(VerifiedRichPrivateBookworld, Map<String, dynamic>, String) _fixture() {
  final raw = jsonDecode(File(
      '../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final source = Map<String, dynamic>.from(raw['blueprint'] as Map);
  (source['actors'] as List).add(_npc);
  (source['initial_state'] as Map)['knowledge'][_npc] = <String>[];
  final scene = (source['scenes'] as List).first as Map<String, dynamic>;
  scene['text'] = 'Мария: «Могу ли я тебе доверять?»\n'
      'Игрок: «Я отвечу после разговора.»';
  final blueprint = StoryBlueprint.fromJson(source);
  final origin = (raw['provenance'] as Map)['scene_origins'] as List;
  final quote = ((origin.first as Map)['source_refs'] as List)
      .first['quote_sha256'] as String;
  final signed = RichSceneDialogue.presentationFor(scene['text'] as String)!;
  final world = VerifiedRichPrivateBookworld(
    blueprint: blueprint,
    sourceFingerprint: blueprint.sourceFingerprint!,
    archiveSha256: List.filled(64, 'a').join(),
    provenanceSha256: List.filled(64, 'b').join(),
    presentation: {
      'scene_names': {
        'entry': 'Двор перед домом',
        'canon_end': 'Помощь Марии',
        'alternate_end': 'Другой путь',
      },
      'scene_dialogues': {'entry': signed},
      'scene_dialogue_knowledge': {
        'entry': [
          {'turn_index': 0, 'speaker': 'Мария',
           'actor_id': _npc, 'required_fact_ids': <String>[]},
          {'turn_index': 1, 'speaker': 'Игрок',
           'actor_id': 'player', 'required_fact_ids': <String>[]},
        ],
      },
    },
  );
  final origins = <String, dynamic>{
    for (final row in origin)
      (row as Map)['scene_id'] as String: row,
  };
  return (world, origins, quote);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eligibility hides terminal/unreviewed scenes and lists real outcomes',
      () {
    final (world, origins, quote) = _fixture();
    final candidates = NpcDialogueResponsesReviewPage.eligibleScenes(
      world: world, sceneOrigins: origins,
      sourceQuoteLabels: {quote: 'Подтверждённый разговор'},
    );
    expect(candidates, hasLength(1));
    expect(candidates.single.scene.id, 'entry');
    expect(candidates.single.actors[_npc], 'Мария');
    expect(candidates.single.sourceQuotes[quote], 'Подтверждённый разговор');
    expect(candidates.single.scene.choices.length, 3);
    expect(candidates.single.sceneLabel, 'Двор перед домом');
    expect(NpcDialogueResponsesReviewPage.eligibleScenes(
      world: world, sceneOrigins: const {},
    ), isEmpty);
  });

  testWidgets('author must choose scene, NPC, source, full replies and consent',
      (tester) async {
    final (world, origins, quote) = _fixture();
    NpcResponsesReviewDecision? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          result = await Navigator.of(context).push<
              NpcResponsesReviewDecision>(MaterialPageRoute(
            builder: (_) => NpcDialogueResponsesReviewPage(
              world: world, sceneOrigins: origins,
              sourceQuoteLabels: {quote: 'Глава 1 · встреча у дома'},
            ),
          ));
        },
        child: const Text('Открыть редактор'),
      )),
    )));
    await tester.tap(find.text('Открыть редактор'));
    await tester.pumpAndSettle();
    final approve = find.byKey(const Key('npc-reply-approve'));
    final accept = find.byKey(const Key('npc-reply-accept'));
    expect(find.textContaining('Доступно сцен: 1'), findsOneWidget);
    await tester.scrollUntilVisible(accept, 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    final scene = find.byKey(const Key('npc-reply-select-entry'));
    await tester.scrollUntilVisible(scene, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(scene);
    await tester.pumpAndSettle();
    expect(find.textContaining('Переход:'), findsWidgets);

    final actor = find.byKey(const Key('npc-reply-actor-entry'));
    await tester.scrollUntilVisible(actor, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(actor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мария').last);
    await tester.pumpAndSettle();

    final source = find.byKey(const Key('npc-reply-quote-entry'));
    await tester.scrollUntilVisible(source, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Глава 1 · встреча у дома').last);
    await tester.pumpAndSettle();
    for (final id in ['wait', 'help', 'leave']) {
      final field = find.byKey(Key('npc-reply-line-' + id));
      await tester.scrollUntilVisible(field, 220,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(field, 'Я выбираю решение ' + id + '.');
      await tester.pump();
    }
    await tester.scrollUntilVisible(approve, 220,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(accept, 220,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(result?.skipped, false);
    final plan = result!.proposal!;
    expect(plan.approvalDigest, hasLength(64));
    expect(plan.isLiteraryCanon, isFalse);
    final approved = RichNpcDialogueResponses.accept(
      proposal: plan, blueprint: world.blueprint,
      approvedDigest: plan.approvalDigest, userConfirmed: true,
    );
    expect(approved['entry'], hasLength(3));
    expect(RichNpcDialogueResponses.replyFor(
        {'scene_dialogue_responses': approved}, 'entry', 'help'),
        'Я выбираю решение help.');
    expect(plan.canModifyCampaign, isFalse);
  });

  testWidgets('skip is explicit and does not create AI or editor effects',
      (tester) async {
    final (world, origins, _) = _fixture();
    NpcResponsesReviewDecision? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => FilledButton(
        child: const Text('Войти'),
        onPressed: () async => result = await Navigator.of(context).push<
            NpcResponsesReviewDecision>(MaterialPageRoute(
          builder: (_) => NpcDialogueResponsesReviewPage(
            world: world, sceneOrigins: origins,
          ),
        )),
      )),
    )));
    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    final skip = find.byKey(const Key('npc-reply-skip'));
    final scrolling = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(skip, 180, scrollable: scrolling);
    // scrollUntilVisible only guarantees the lazily built element exists:
    // on a short page its center can still be below the root viewport.
    // Finish the scroll using a real drag, then tap the physical button.
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    if (tester.getCenter(skip).dy >=
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 24) {
      await tester.drag(scrolling, const Offset(0, -170));
      await tester.pumpAndSettle();
    }
    expect(tester.getCenter(skip).dy,
        lessThan(tester.view.physicalSize.height /
            tester.view.devicePixelRatio - 24));
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(result?.skipped, true);
    expect(result?.proposal, isNull);
  });

  testWidgets('compact Android-sized editor does not overflow at large text',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1280);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final (world, origins, _) = _fixture();
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640), textScaler: TextScaler.linear(1.6),
        ),
        child: NpcDialogueResponsesReviewPage(
          world: world, sceneOrigins: origins,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('npc-reply-select-entry'));
    final scrolling = find.byType(Scrollable).first;
    // The intro becomes taller at 160% text scale. The first source
    // scene is built lazily and must be reached by real user scrolling.
    await tester.scrollUntilVisible(entry, 140, scrollable: scrolling);
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    if (tester.getCenter(entry).dy >=
        tester.view.physicalSize.height / tester.view.devicePixelRatio - 24) {
      await tester.drag(scrolling, const Offset(0, -140));
      await tester.pumpAndSettle();
    }
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
