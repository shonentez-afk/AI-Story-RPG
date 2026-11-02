import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';

void main() {
  const book = ImportedBook(title: 'Авторский тестовый рассказ', author: 'Тест',
      chapters: [
        'Дверь была закрыта. Мария открыла дверь.',
        'Дверь была открыта. Мария встретила Ивана.',
      ]);

  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceSemanticCatalog catalog;

  setUp(() {
    index = BookSourceIndexer.index(book);
    graph = SourceEvidenceGraph.empty(index);
    for (final chunk in index.chunks) {
      graph = graph.addAll(
          index, SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
  });

  test('M2b4b offline meaning proposals retain exact quotations and uncertainty',
      () {
    expect(catalog.assertions.length, greaterThanOrEqualTo(4));
    expect(catalog.assertions.any(
        (x) => x.kind == SemanticAssertionKind.event), true);
    expect(catalog.assertions.any(
        (x) => x.kind == SemanticAssertionKind.fact), true);
    expect(catalog.assertions.every(
        (x) => x.evidenceIds.isNotEmpty && !x.isVerifiedWorldTruth &&
            !x.establishesIdentity && !x.canPublishBookworld), true);
    expect(catalog.possibleDiscrepancies, isNotEmpty);
    expect(catalog.possibleDiscrepancies.every(
        (x) => !x.isProvenContradiction), true);
    expect(catalog.canPublishBookworld, false);
    final decoded = SourceSemanticCatalog.decode(index, graph, catalog.encode());
    expect(decoded.encode(), catalog.encode());
  });

  test('semantic assertions reject forged citations, unrelated categories '
      'and fake confirmation', () {
    final a = catalog.assertions.first;
    final bogus = Map<String, dynamic>.from(a.toJson());
    bogus['evidence_ids'] = ['nonexistent_id'];
    expect(() => SourceSemanticAssertion.fromJson(index, graph, bogus),
        throwsFormatException);
    final spoof = Map<String, dynamic>.from(a.toJson());
    spoof['status'] = 'CONFIRMED';
    expect(() => SourceSemanticAssertion.fromJson(index, graph, spoof),
        throwsFormatException);
    final wrongMeaning = Map<String, dynamic>.from(a.toJson());
    wrongMeaning['subject'] = 'выдуманный герой';
    expect(() => SourceSemanticAssertion.fromJson(index, graph, wrongMeaning),
        throwsFormatException);
    final altered = jsonDecode(catalog.encode()) as Map<String, dynamic>;
    final payload = altered['payload'] as Map<String, dynamic>;
    payload['can_publish_bookworld'] = true;
    expect(() => SourceSemanticCatalog.decode(index, graph, jsonEncode(altered)),
        throwsFormatException);
    final other = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая редакция', author: 'Автор',
      chapters: ['Дверь была закрыта.'],
    ));
    expect(() => SourceSemanticCatalog.decode(other, graph, catalog.encode()),
        throwsFormatException);
  });

  IntermediateStoryBlueprint goodDraft() {
    final claims = catalog.assertions;
    final first = claims.firstWhere((c) =>
        c.evidenceIds.any((id) => graph.records.any(
            (e) => e.id == id && e.chapterIndex == 0)));
    final last = claims.firstWhere((c) =>
        c.evidenceIds.any((id) => graph.records.any(
            (e) => e.id == id && e.chapterIndex == 1)));
    return IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: 'Тестовая адаптация',
      entrySceneId: 'entry',
      rights: PreparationRights.privateUse,
      flags: ['saved_hero'],
      initialFlags: const [],
      scenes: [
        DraftScene(
          id: 'entry', chapterIndex: 0,
          text: 'Мария стоит перед дверью.',
          origin: DraftSceneOrigin.sourcePassage,
          assertionIds: [first.id], terminal: false,
          choices: [
            DraftChoice(
              id: 'save', label: 'Помочь Марии',
              nextSceneId: 'junction', adds: ['saved_hero'],
            ),
            DraftChoice(
              id: 'leave', label: 'Не помогать',
              nextSceneId: 'junction', removes: ['saved_hero'],
            ),
          ],
        ),
        DraftScene(
          id: 'junction', chapterIndex: 0,
          text: 'После выбора приходится жить с последствиями.',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: [first.id], terminal: false,
          choices: [
            DraftChoice(id: 'helped', label: 'Встретиться с героем',
                nextSceneId: 'happy_end', requires: ['saved_hero']),
            DraftChoice(id: 'alone', label: 'Уйти одному',
                nextSceneId: 'alternate_end', forbids: ['saved_hero']),
          ],
        ),
        DraftScene(
          id: 'happy_end', chapterIndex: 1,
          text: 'Мария встретила Ивана.',
          origin: DraftSceneOrigin.sourcePassage,
          assertionIds: [last.id], terminal: true, choices: const [],
        ),
        DraftScene(
          id: 'alternate_end', chapterIndex: 0,
          text: 'Вы ушли в другую сторону.',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: [first.id], terminal: true, choices: const [],
        ),
      ],
    );
  }

  test('M2c causal explorer verifies changed history and two reachable endings',
      () {
    final draft = goodDraft();
    final result = draft.validate(index, graph, catalog);
    expect(result.reachableScenes, 4);
    expect(result.reachableEndings, 2);
    expect(result.reachableStates, greaterThanOrEqualTo(5));
    expect(result.canExportPublic, false);
    expect(result.canPublishBookworld, false);
    expect(result.blockers, isNotEmpty);
    expect(draft.canPublishBookworld, false);
    expect(IntermediateStoryBlueprint.decode(draft.encode()).encode(),
        draft.encode());
  });

  test('M2c fails closed on impossible alternative and broken causal graph',
      () {
    final draft = goodDraft();
    final junction = draft.scenes[1];
    final blocked = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint, title: draft.title,
      entrySceneId: draft.entrySceneId, rights: draft.rights,
      flags: draft.flags, initialFlags: draft.initialFlags,
      scenes: [
        draft.scenes[0],
        DraftScene(id: junction.id, chapterIndex: junction.chapterIndex,
          text: junction.text, origin: junction.origin,
          assertionIds: junction.assertionIds, terminal: false,
          choices: [
            DraftChoice(id: 'helped', label: 'Только если спасён',
                nextSceneId: 'happy_end', requires: ['saved_hero']),
            DraftChoice(id: 'alone', label: 'Тоже только если спасён',
                nextSceneId: 'alternate_end', requires: ['saved_hero']),
          ],
        ),
        ...draft.scenes.skip(2),
      ],
    );
    expect(() => blocked.validate(index, graph, catalog),
        throwsFormatException);
    final missing = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint, title: draft.title,
      entrySceneId: draft.entrySceneId, rights: draft.rights,
      flags: draft.flags, initialFlags: draft.initialFlags,
      scenes: [
        DraftScene(
          id: 'entry', chapterIndex: 0, text: 'Вход',
          origin: DraftSceneOrigin.sourcePassage,
          assertionIds: ['forged_semantic_assertion'],
          terminal: false,
          choices: [DraftChoice(
              id: 'go', label: 'Идти', nextSceneId: 'happy_end')],
        ),
        ...draft.scenes.skip(1),
      ],
    );
    expect(() => missing.validate(index, graph, catalog),
        throwsFormatException);
  });

  test('M2c prevents early spoilers, fake ready flags and missing edition',
      () {
    final draft = goodDraft();
    final future = draft.scenes[2].assertionIds.first;
    final spoiled = IntermediateStoryBlueprint(
      sourceFingerprint: draft.sourceFingerprint,
      title: draft.title, entrySceneId: draft.entrySceneId,
      rights: draft.rights, flags: draft.flags,
      initialFlags: draft.initialFlags,
      scenes: [
        DraftScene(id: 'entry', chapterIndex: 0, text: 'Тайна финала',
          origin: DraftSceneOrigin.sourcePassage,
          assertionIds: [future], terminal: false,
          choices: draft.scenes.first.choices),
        ...draft.scenes.skip(1),
      ],
    );
    expect(() => spoiled.validate(index, graph, catalog),
        throwsFormatException);
    final forged = jsonDecode(draft.encode()) as Map<String, dynamic>;
    forged['can_publish_bookworld'] = true;
    expect(() => IntermediateStoryBlueprint.fromJson(forged),
        throwsFormatException);
    final other = BookSourceIndexer.index(const ImportedBook(
        title: 'Другое издание', author: 'Тест',
        chapters: ['Совершенно другая книга.']));
    expect(() => draft.validate(other, graph, catalog),
        throwsFormatException);
  });

  test('rights remain unresolved for publication even after causality passes',
      () {
    final draft = goodDraft();
    final unknown = IntermediateStoryBlueprint(
      sourceFingerprint: draft.sourceFingerprint, title: draft.title,
      entrySceneId: draft.entrySceneId, rights: PreparationRights.unknown,
      flags: draft.flags, initialFlags: draft.initialFlags,
      scenes: draft.scenes,
    );
    final result = unknown.validate(index, graph, catalog);
    expect(result.blockers.any((s) => s.contains('права')), true);
    expect(result.canExportPublic, false);
  });
  test('M2c rejects unknown flags, duplicated choices and forged schema fields',
      () {
    final draft = goodDraft();
    final wrongFlags = IntermediateStoryBlueprint(
      sourceFingerprint: draft.sourceFingerprint, title: draft.title,
      entrySceneId: draft.entrySceneId, rights: draft.rights,
      flags: ['saved_hero'], initialFlags: draft.initialFlags,
      scenes: [
        DraftScene(id: 'entry', chapterIndex: 0, text: 'Вход',
          origin: DraftSceneOrigin.sourcePassage,
          assertionIds: draft.scenes[0].assertionIds, terminal: false,
          choices: [
            DraftChoice(id: 'unknown_flag', label: 'Идти',
              nextSceneId: 'junction', requires: ['magic']),
          ]),
        ...draft.scenes.skip(1),
      ],
    );
    expect(() => wrongFlags.validate(index, graph, catalog),
        throwsFormatException);
    final duplicate = IntermediateStoryBlueprint(
      sourceFingerprint: draft.sourceFingerprint, title: draft.title,
      entrySceneId: draft.entrySceneId, rights: draft.rights,
      flags: draft.flags, initialFlags: draft.initialFlags,
      scenes: [draft.scenes.first, draft.scenes.first, ...draft.scenes.skip(1)],
    );
    expect(() => duplicate.validate(index, graph, catalog),
        throwsFormatException);
    final json = jsonDecode(draft.encode()) as Map<String, dynamic>;
    expect(() => IntermediateStoryBlueprint.fromJson(
        {...json, 'network_enabled': true}), throwsFormatException);
    expect(() => IntermediateStoryBlueprint.fromJson(
        {...json, 'status': 'PLAYABLE'}), throwsFormatException);
  });

  test('model text cannot promote a single verified quotation to world truth',
      () {
    final assertion = catalog.assertions.first;
    final fake = Map<String, dynamic>.from(assertion.toJson());
    fake['status'] = 'CONFIRMED';
    fake['can_publish_bookworld'] = true;
    expect(() => SourceSemanticAssertion.fromJson(index, graph, fake),
        throwsFormatException);
    expect(catalog.canPublishBookworld, false);
    expect(goodDraft().canPublishBookworld, false);
  });

}
