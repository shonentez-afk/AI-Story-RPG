import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

void main() {
  const engine = BookAuthoringEngine();
  const compiler = PortableReviewedDraftCompiler();

  ({SourceLockedBook source, Map<String, dynamic> review})
      reviewedSyntheticBook() {
    const book = ImportedBook(
      title: 'Дверь и Волк', author: 'Автор',
      chapters: [
        'Артем по прозвищу Волк открыл дверь. Дверь была закрыта.',
        'Артем встретил Марию. Дверь была открыта.',
      ],
    );
    final source = engine.indexImported(book);
    final index = source.index;
    var evidence = StoryEvidenceReviewSession.create(index);
    while (evidence.scannedChunks < index.chunks.length) {
      evidence = evidence.scanNext(index);
    }
    for (final item in evidence.graph.records) {
      evidence = evidence.review(index, item.id, EvidenceStatus.confirmed);
    }
    final graph = evidence.graph;
    final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    final events = catalog.assertions.where(
        (c) => c.kind == SemanticAssertionKind.event).toList();
    final byId = {for (final e in graph.records) e.id: e};
    final first = events.firstWhere(
        (c) => byId[c.evidenceIds.first]!.chapterIndex == 0);
    final last = events.firstWhere(
        (c) => byId[c.evidenceIds.first]!.chapterIndex == 1);
    final editorial = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, first.id, SemanticEditorialVerdict.canonCandidate)
        .decide(catalog, last.id, SemanticEditorialVerdict.canonCandidate);
    final draft = ReviewedStoryComposer.compose(
      index: index, evidence: graph, catalog: catalog,
      editorial: editorial, openingAssertionId: first.id,
      endingAssertionId: last.id,
      openingText: 'Игрок стоит у запертой двери.',
      endingText: 'Игрок встречает друга.',
      alternateEndingText: 'Игрок уходит другой дорогой.',
      followBookChoice: 'Продолжить путь',
      changeFateChoice: 'Повернуть назад',
    );
    return (
      source: source,
      review: <String, dynamic>{
        'format': PortableReviewedDraftCompiler.format,
        'source_fingerprint': index.sourceFingerprint,
        'evidence': evidence.encode(),
        'catalog': catalog.encode(),
        'editorial': editorial.encode(),
        'draft': draft.encode(),
        'hero_name': 'Игрок',
      },
    );
  }

  test('source + reviewed checkpoints -> offline v3 without Flutter or model',
      () async {
    final fixture = reviewedSyntheticBook();
    final archive = await compiler.build(
        source: fixture.source, review: fixture.review);
    final inspected = const RichPrivateBookworldImporter().inspect(archive);
    expect(inspected.sourceFingerprint, fixture.source.index.sourceFingerprint);
    expect(inspected.blueprint.actors, {'player'});
    expect(inspected.blueprint.scenes.length, 3);
    expect(inspected.canDistributePublicly, false);
    expect(inspected.requiresNetwork, false);
    final out = File(
        '../../artifacts/bookworld/story_authoring_review_bundle_fixture.bworld');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(archive);
  });

  test('203 reviewed scenes -> source-locked v4 -> real 201-step SQLite '
      'world and deterministic event replay without Flutter/AI', () async {
    final fixture = reviewedSyntheticBook();
    final base = IntermediateStoryBlueprint.decode(
        fixture.review['draft'] as String);
    final first = base.scenes.first;
    expect(first.terminal, false);
    final canonChoice = first.choices.first;
    final path = [
      for (var i = 0; i < 200; i++)
        'long_' + i.toString().padLeft(4, '0'),
    ];
    final entry = DraftScene(
      id: first.id,
      chapterIndex: first.chapterIndex,
      text: first.text,
      origin: first.origin,
      assertionIds: first.assertionIds,
      terminal: false,
      choices: [
        DraftChoice(
          id: canonChoice.id,
          label: canonChoice.label,
          nextSceneId: path.first,
          requires: canonChoice.requires,
          forbids: canonChoice.forbids,
          adds: canonChoice.adds,
          removes: canonChoice.removes,
        ),
        ...first.choices.skip(1),
      ],
    );
    final extended = IntermediateStoryBlueprint(
      sourceFingerprint: base.sourceFingerprint,
      title: base.title,
      entrySceneId: base.entrySceneId,
      rights: base.rights,
      flags: base.flags,
      initialFlags: base.initialFlags,
      scenes: [
        entry,
        for (var i = 0; i < path.length; i++)
          DraftScene(
            id: path[i],
            chapterIndex: 0,
            text: 'Частная игровая сцена номер ' + (i + 1).toString(),
            origin: DraftSceneOrigin.explicitAdaptation,
            assertionIds: const [],
            terminal: false,
            choices: [
              DraftChoice(
                id: 'long_choice_' + i.toString().padLeft(4, '0'),
                label: 'Продолжить путешествие',
                nextSceneId: i + 1 == path.length
                    ? canonChoice.nextSceneId : path[i + 1],
              ),
            ],
          ),
        ...base.scenes.skip(1),
      ],
    );
    final checkpoints = Map<String, dynamic>.from(fixture.review)
      ..['draft'] = extended.encode();
    await expectLater(compiler.build(
      source: fixture.source, review: checkpoints,
    ), throwsFormatException);
    final bytes = await compiler.build(
        source: fixture.source, review: checkpoints, expanded: true);
    final verified = const RichPrivateBookworldImporter().inspect(bytes);
    expect(verified.formatVersion, 4);
    expect(verified.blueprint.scenes.length, 203);
    expect(verified.sourceFingerprint,
        fixture.source.index.sourceFingerprint);
    expect(verified.canDistributePublicly, false);
    expect(verified.requiresNetwork, false);
    final world = StoryWorld(verified.blueprint);
    expect(world.apply(
        actionId: 'open_0', choiceId: canonChoice.id).applied, true);
    for (var i = 0; i < path.length; i++) {
      expect(world.apply(
        actionId: 'open_' + (i + 1).toString(),
        choiceId: 'long_choice_' + i.toString().padLeft(4, '0'),
      ).applied, true);
    }
    expect(world.isTerminal, true);
    expect(world.state.revision, 201);
    final restored = StoryWorld.replay(
      verified.blueprint,
      world.events.map((event) => event.toJson()),
      expectedSequence: world.state.revision,
      expectedStateHash: world.state.stateHash,
    );
    expect(restored.state.stateHash, world.state.stateHash);
    final output = File(
      '../../artifacts/bookworld/story_authoring_extended_review_fixture.bworld');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes);
  });

  test('edition mismatch, missing review and fabricated NPC consent fail closed',
      () async {
    final fixture = reviewedSyntheticBook();
    final foreign = engine.parseAndIndex('other.txt',
        Uint8List.fromList(utf8.encode('Другой текст')));
    await expectLater(compiler.build(
        source: foreign, review: fixture.review), throwsFormatException);
    final missing = Map<String, dynamic>.from(fixture.review)
      ..remove('editorial');
    await expectLater(compiler.build(
        source: fixture.source, review: missing), throwsFormatException);
    final fakeNpc = Map<String, dynamic>.from(fixture.review)
      ..['npc'] = {
        'notebook': 'not-reviewed',
        'rules': 'not-reviewed',
        'source_quotes_by_rule_id': <String, String>{},
        'user_confirmed': false,
      };
    await expectLater(compiler.build(
        source: fixture.source, review: fakeNpc), throwsFormatException);
    expect(jsonDecode(fixture.review['draft'] as String), isA<Map>());
  });
}
