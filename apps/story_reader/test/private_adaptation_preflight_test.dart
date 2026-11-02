import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/private_adaptation_preflight.dart';
import 'package:ai_story_reader/private_classic_scenario_translator.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';

void main() {
  const book = ImportedBook(
    title: 'Первое испытание', author: 'Собственный текст',
    chapters: [
      'Дверь была закрыта. Мария открыла дверь.',
      'Дверь была открыта. Мария встретила Ивана.',
    ],
  );

  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceSemanticCatalog catalog;
  late SourceSemanticAssertion firstClaim;
  late SourceSemanticAssertion lastClaim;

  setUp(() {
    index = BookSourceIndexer.index(book);
    var review = StoryEvidenceReviewSession.create(index)
        .scanNext(index);
    for (final item in review.graph.records) {
      review = review.review(index, item.id, EvidenceStatus.confirmed);
    }
    graph = review.graph;
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    firstClaim = catalog.assertions.firstWhere((c) =>
        c.evidenceIds.any((id) => graph.records.any(
            (e) => e.id == id && e.chapterIndex == 0)));
    lastClaim = catalog.assertions.firstWhere((c) =>
        c.evidenceIds.any((id) => graph.records.any(
            (e) => e.id == id && e.chapterIndex == 1)));
  });

  IntermediateStoryBlueprint shortDraft({
    PreparationRights rights = PreparationRights.privateUse,
    List<String>? firstAssertionIds,
  }) => IntermediateStoryBlueprint(
    sourceFingerprint: index.sourceFingerprint, title: book.title,
    entrySceneId: 'entry', rights: rights,
    flags: const [], initialFlags: const [],
    scenes: [
      DraftScene(
        id: 'entry', chapterIndex: 0, text: 'Перед закрытой дверью',
        origin: DraftSceneOrigin.sourcePassage,
        assertionIds: firstAssertionIds ?? [firstClaim.id],
        terminal: false,
        choices: [
          DraftChoice(id: 'follow_book',
              label: 'Следовать событиям книги',
              nextSceneId: 'canon_end'),
          DraftChoice(id: 'depart',
              label: 'Изменить судьбу',
              nextSceneId: 'alternate_end'),
        ],
      ),
      DraftScene(
        id: 'canon_end', chapterIndex: 1, text: 'Мария встретила Ивана',
        origin: DraftSceneOrigin.sourcePassage,
        assertionIds: [lastClaim.id],
        terminal: true, choices: const [],
      ),
      DraftScene(
        id: 'alternate_end', chapterIndex: 0,
        text: 'Мария решает не идти к двери',
        origin: DraftSceneOrigin.explicitAdaptation,
        assertionIds: const [], terminal: true, choices: const [],
      ),
    ],
  );

  test('explicit manual review allows only structural acceptance, not game',
      () {
    var editor = SemanticEditorialReviewSession.create(index, catalog);
    editor = editor.decide(
        catalog, firstClaim.id, SemanticEditorialVerdict.canonCandidate);
    editor = editor.decide(
        catalog, lastClaim.id, SemanticEditorialVerdict.canonCandidate);
    final status = PrivateAdaptationPreflight.evaluate(
        index, graph, catalog, editor, shortDraft());
    expect(status.causal.isCausallyComplete, true);
    expect(status.reviewedSourceScenes, 2);
    expect(status.explicitAdaptationScenes, 1);
    expect(status.provenanceLinks, greaterThanOrEqualTo(2));
    expect(status.issues,
        [AdaptationGateIssue.productionBookworldNotImplemented]);
    expect(status.isStructurallyReady, true);
    expect(status.canCompilePlayableBookworld, false);
    expect(status.canDistributePublicly, false);
    expect(status.canSendToCloud, false);
  });

  test('preflight shows human-facing reasons before any model is connected',
      () {
    final blank = SemanticEditorialReviewSession.create(index, catalog);
    final status = PrivateAdaptationPreflight.evaluate(
        index, graph, catalog, blank,
        shortDraft(rights: PreparationRights.unknown));
    expect(status.userFacingBlockers,
        contains('Не указан статус прав на личную адаптацию книги.'));
    expect(status.userFacingBlockers,
        contains('Компилятор пользовательских .bworld ещё не реализован.'));
    expect(status.isStructurallyReady, false);
    expect(status.canSendToCloud, false);
  });

  test('M2d translates validated scenes and causality into inert rules',
      () {
    final editorial = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, firstClaim.id, SemanticEditorialVerdict.canonCandidate)
        .decide(catalog, lastClaim.id, SemanticEditorialVerdict.canonCandidate);
    final compiled = PrivateClassicScenarioTranslator.translate(
        index, graph, catalog, editorial, shortDraft());
    final again = PrivateClassicScenarioTranslator.translate(
        index, graph, catalog, editorial, shortDraft());

    final payload = compiled.blueprintJson;
    final provenance = compiled.provenanceJson;
    expect(compiled.blueprintSha256, again.blueprintSha256);
    expect(compiled.provenanceSha256, again.provenanceSha256);
    expect(payload['rights_status'], 'private_adaptation');
    expect(payload['source_fingerprint'], index.sourceFingerprint);
    expect(payload['supported_modes']['interactions'], ['CLASSIC']);
    expect(payload['supported_modes']['plots'], ['ALTER_FATE']);
    expect(payload['initial_state']['scene_id'], 'entry');
    expect(payload['initial_state']['flags'], isEmpty);
    expect((payload['scenes'] as List).length, 3);
    final start = (payload['scenes'] as List).first as Map;
    expect((start['choices'] as List).length, 2);
    expect((start['choices'] as List).first['effects'], isEmpty);
    expect(provenance['source_chapters_total'], 2);
    expect(provenance['model_provenance']['provider'], 'none');
    expect(provenance['publication_authorized'], false);
    final refs = (provenance['scene_origins'] as List).first['source_refs'] as List;
    expect(refs, isNotEmpty);
    expect(refs.first['quote_sha256'], hasLength(64));
    expect(compiled.provenanceSource, isNot(contains('Дверь была закрыта')));
    expect(compiled.isPackageBuilt, false);
    expect(compiled.canDistributePublicly, false);
    expect(compiled.canPublishBookworld, false);
    payload['rights_status'] = 'hacked';
    expect(compiled.blueprintJson['rights_status'], 'private_adaptation');
  });

  test('M2d translates truth-valued flags into typed conditions/effects',
      () {
    final editor = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, firstClaim.id, SemanticEditorialVerdict.canonCandidate)
        .decide(catalog, lastClaim.id, SemanticEditorialVerdict.canonCandidate);
    final base = shortDraft();
    final first = base.scenes.first;
    final withFlags = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint, title: base.title,
      entrySceneId: base.entrySceneId, rights: base.rights,
      flags: const ['friend_saved'], initialFlags: const [],
      scenes: [
        DraftScene(
          id: first.id, chapterIndex: first.chapterIndex,
          text: first.text, origin: first.origin,
          assertionIds: first.assertionIds, terminal: false,
          choices: [
            DraftChoice(id: 'follow_book', label: 'Вместе',
                nextSceneId: 'canon_end', adds: ['friend_saved']),
            DraftChoice(id: 'depart', label: 'Врозь',
                nextSceneId: 'alternate_end', removes: ['friend_saved']),
          ],
        ),
        ...base.scenes.skip(1),
      ],
    );
    final translated = PrivateClassicScenarioTranslator.translate(
        index, graph, catalog, editor, withFlags);
    final blueprint = translated.blueprintJson;
    expect(blueprint['initial_state']['flags'], {'friend_saved': false});
    final choices = (blueprint['scenes'] as List).first['choices'] as List;
    expect(choices.first['effects'], [
      {'op': 'set_flag', 'id': 'friend_saved', 'value': true},
    ]);
    expect(choices.last['effects'], [
      {'op': 'set_flag', 'id': 'friend_saved', 'value': false},
    ]);
  });

  test('M2d translation refuses missing editorial review and unknown rights',
      () {
    final blank = SemanticEditorialReviewSession.create(index, catalog);
    expect(() => PrivateClassicScenarioTranslator.translate(
        index, graph, catalog, blank, shortDraft()), throwsFormatException);
    final accepted = blank
        .decide(catalog, firstClaim.id, SemanticEditorialVerdict.canonCandidate)
        .decide(catalog, lastClaim.id, SemanticEditorialVerdict.canonCandidate);
    expect(() => PrivateClassicScenarioTranslator.translate(
        index, graph, catalog, accepted,
        shortDraft(rights: PreparationRights.unknown)), throwsFormatException);
    // Even a user's assertion that text is public-domain is insufficient
    // for distribution without an independently audited rights record.
    expect(() => PrivateClassicScenarioTranslator.translate(
        index, graph, catalog, accepted,
        shortDraft(rights: PreparationRights.publicDomain)), throwsFormatException);
  });

  test('missing decisions and rights are blockers even with valid quotes', () {
    final blank = SemanticEditorialReviewSession.create(index, catalog);
    final status = PrivateAdaptationPreflight.evaluate(
        index, graph, catalog, blank,
        shortDraft(rights: PreparationRights.unknown));
    expect(status.isStructurallyReady, false);
    expect(status.issues.contains(AdaptationGateIssue.rightsUnknown), true);
    expect(status.issues.contains(
        AdaptationGateIssue.unreviewedSourceClaim), true);
  });

  test('disputed source passage cannot enter canonical scenes', () {
    final editor = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, firstClaim.id, SemanticEditorialVerdict.disputed)
        .decide(catalog, lastClaim.id, SemanticEditorialVerdict.canonCandidate);
    final status = PrivateAdaptationPreflight.evaluate(
        index, graph, catalog, editor, shortDraft());
    expect(status.issues.contains(
        AdaptationGateIssue.disputedOrRejectedClaim), true);
    expect(status.isStructurallyReady, false);
  });

  test('source edition mismatch is rejected before any game export', () {
    final editor = SemanticEditorialReviewSession.create(index, catalog);
    final other = BookSourceIndexer.index(const ImportedBook(
        title: 'Новая редакция', author: 'Собственный текст',
        chapters: ['Совсем другая версия']));
    expect(() => PrivateAdaptationPreflight.evaluate(
        other, graph, catalog, editor, shortDraft()),
        throwsFormatException);
  });

  test('future quotation in the first scene is a hard spoiler block', () {
    final editor = SemanticEditorialReviewSession.create(index, catalog);
    expect(() => PrivateAdaptationPreflight.evaluate(
        index, graph, catalog, editor,
        shortDraft(firstAssertionIds: [lastClaim.id])),
        throwsFormatException);
  });

  test('source evidence confirmed only as text, never enough to build game',
      () {
    var editor = SemanticEditorialReviewSession.create(index, catalog);
    editor = editor.decide(
        catalog, firstClaim.id, SemanticEditorialVerdict.passageOnly);
    editor = editor.decide(
        catalog, lastClaim.id, SemanticEditorialVerdict.passageOnly);
    final status = PrivateAdaptationPreflight.evaluate(
        index, graph, catalog, editor, shortDraft());
    expect(status.issues.contains(
        AdaptationGateIssue.unreviewedSourceClaim), true);
    expect(status.canCompilePlayableBookworld, false);
  });
}
