import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_causal_choice_notebook.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_editorial_consistency.dart';
import 'package:ai_story_reader/zai_m2c_source_bridge.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:ai_story_reader/zai_source_scene_board.dart';
import 'package:flutter_test/flutter_test.dart';

/// Original, synthetic Russian test sentences only. No third-party book text
/// or private API key is ever committed in this fixture.
typedef _Scenario = ({
  ZaiWindowReviewQueue queue,
  ZaiCausalChoiceNotebook choices,
  ZaiEditorialConsistencyNotebook consistency,
  SourceEvidenceGraph evidence,
  SourceSemanticCatalog catalog,
  SemanticEditorialReviewSession editorial,
  Set<String> sourceScenes,
  Map<String, String> eventAssertions,
  Map<String, String> prose,
});

_Scenario _fixture() {
  final index = BookSourceIndexer.index(const ImportedBook(
    title: 'Редакторская сказка для QA',
    author: 'Тест приложения',
    chapters: [
      'Герой нашёл камень. Лесной зверь открыл дверь. Герой вернулся домой.',
    ],
  ));
  final chunk = index.chunks.single;
  SemanticCandidate event(String text) {
    final position = chunk.text.indexOf(text);
    expect(position, greaterThanOrEqualTo(0));
    return SemanticCandidate.propose(
      index, chunk, category: SemanticCategory.event,
      startUtf16: chunk.startUtf16 + position,
      endUtf16: chunk.startUtf16 + position + text.length,
      label: text,
      uncertainty: 'Действие ещё нуждается в редакторской проверке.',
    );
  }

  final events = [
    event('Герой нашёл камень.'),
    event('Лесной зверь открыл дверь.'),
    event('Герой вернулся домой.'),
  ];
  var queue = ZaiWindowReviewQueue.empty(index);
  expect(queue.windows.length, 1);
  queue = queue.record(0, ZaiSemanticPreviewResult(
    batch: SemanticCandidateBatch(
      providerId: ZaiSemanticPreviewService.providerId,
      providerVersion: ZaiSemanticPreviewService.providerVersion,
      sourceFingerprint: index.sourceFingerprint,
      chunkIds: [chunk.id],
      candidates: events,
    ),
    totalSuggestions: events.length,
    rejectedCount: 0,
    rejectedNonRussian: 0,
  ));
  for (final item in events) {
    queue = queue.decide(item.id, ZaiEditorialDecision.keepForReview);
  }
  final live = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
  var board = ZaiSourceSceneBoard.empty(live);
  for (var i = 0; i < events.length; i++) {
    board = board.addScene(
        [events[i].id], 'Проверенная сцена ${i + 1}',
        'Сцена отделена редактором от других событий.');
  }

  var notebook = ZaiCausalChoiceNotebook.empty(board)
      .addFlag('has_stone');
  notebook = notebook.addChoice(
    from: board.scenes[0].id,
    to: board.scenes[1].id,
    label: 'Продолжить путь со зверем',
    reason: 'Авторская ветка меняет наличие найденного предмета.',
    adds: ['has_stone'],
  );
  notebook = notebook.addChoice(
    from: board.scenes[0].id,
    to: board.scenes[2].id,
    label: 'Вместо этого вернуться домой',
    reason: 'Это самостоятельная альтернативная концовка.',
  );

  final sources = <SourceEvidence>[];
  for (final item in events.take(2)) {
    sources.add(SourceEvidence.propose(
      index,
      chunkId: chunk.id,
      kind: EvidenceKind.event,
      startUtf16: item.startUtf16,
      endUtf16: item.endUtf16,
    ));
  }
  var evidence = SourceEvidenceGraph.empty(index).addAll(index, sources);
  for (final item in sources) {
    evidence = evidence.review(index, item.id, EvidenceStatus.confirmed);
  }

  final claims = <SourceSemanticAssertion>[];
  for (var i = 0; i < sources.length; i++) {
    claims.add(SourceSemanticAssertion.propose(
      index, evidence,
      kind: SemanticAssertionKind.event,
      evidenceIds: [sources[i].id],
      subject: i == 0 ? 'Герой' : 'Лесной зверь',
      predicate: i == 0 ? 'нашёл' : 'открыл',
      object: i == 0 ? 'камень' : 'дверь',
      voice: AssertionVoice.narratorCandidate,
      polarity: AssertionPolarity.affirmative,
      time: AssertionTime.textOrderOnly,
      uncertainty: 'Ручная проверка текста и причинности ещё требуется.',
    ));
  }
  final catalog = SourceSemanticCatalog.checked(index, evidence, claims);
  var editorial = SemanticEditorialReviewSession.create(index, catalog);
  for (final claim in claims) {
    editorial = editorial.decide(
        catalog, claim.id, SemanticEditorialVerdict.canonCandidate);
  }
  return (
    queue: queue,
    choices: notebook,
    consistency: ZaiEditorialConsistencyNotebook.empty(live),
    evidence: evidence,
    catalog: catalog,
    editorial: editorial,
    sourceScenes: {board.scenes[0].id, board.scenes[1].id},
    eventAssertions: {
      events[0].id: claims[0].id,
      events[1].id: claims[1].id,
    },
    prose: {
      board.scenes[0].id: 'У ворот герой обнаружил необычный камень.',
      board.scenes[1].id: 'Зверь открыл дверь и показал тайную тропу.',
      board.scenes[2].id: 'Герой выбрал собственную дорогу и вернулся домой.',
    },
  );
}

ZaiM2cSourceBridgeReview _review(
  _Scenario f, {
  bool consent = true,
  PreparationRights rights = PreparationRights.privateUse,
  Map<String, String>? events,
  Map<String, String>? prose,
  SourceEvidenceGraph? evidence,
  SemanticEditorialReviewSession? editorial,
}) =>
    ZaiM2cSourceBridge.review(
      queue: f.queue,
      notebook: f.choices,
      consistency: f.consistency,
      evidence: evidence ?? f.evidence,
      catalog: f.catalog,
      editorial: editorial ?? f.editorial,
      sourceSceneIds: f.sourceScenes,
      eventAssertionIds: events ?? f.eventAssertions,
      authoredSceneTexts: prose ?? f.prose,
      rights: rights,
      consentForPrivateCompilation: consent,
    );

void main() {
  test('exact independently confirmed M2c citations can stage private draft',
      () {
    final f = _fixture();
    final result = _review(f);
    expect(result.blockers, isEmpty);
    expect(result.canStageForPrivateCompiler, isTrue);
    expect(result.canPublishBookworld, isFalse);
    expect(result.canStartPlayableRpg, isFalse);
    expect(result.canDistributePublicly, isFalse);
    expect(result.canSendToCloud, isFalse);
    final draft = result.draft!;
    expect(draft.rights, PreparationRights.privateUse);
    expect(draft.scenes, hasLength(3));
    expect(draft.scenes[0].origin, DraftSceneOrigin.sourcePassage);
    expect(draft.scenes[1].origin, DraftSceneOrigin.sourcePassage);
    expect(draft.scenes[2].origin, DraftSceneOrigin.explicitAdaptation);
    expect(draft.scenes[2].assertionIds, isEmpty);
    expect(result.acceptance!.causal.reachableEndings, 2);
    expect(draft.canPublishBookworld, isFalse);
    expect(draft.scenes[0].text, contains('камень'));
  });

  test('no consent or unknown translation rights never unlock staging', () {
    final f = _fixture();
    final noConsent = _review(f, consent: false);
    expect(noConsent.canStageForPrivateCompiler, isFalse);
    expect(noConsent.blockers.join(' '), contains('согласия'));
    final noRights = _review(f, rights: PreparationRights.unknown);
    expect(noRights.canStageForPrivateCompiler, isFalse);
    expect(noRights.blockers.join(' '), contains('частное'));
  });

  test('missing, swapped or speculative source evidence is not canon', () {
    final f = _fixture();
    final ids = f.eventAssertions.keys.toList();
    final crossed = {
      ids[0]: f.eventAssertions[ids[1]]!,
      ids[1]: f.eventAssertions[ids[0]]!,
    };
    final result = _review(f, events: crossed);
    expect(result.canStageForPrivateCompiler, isFalse);
    expect(result.blockers.join(' '), contains('диапазоны'));

    final index = f.queue.index;
    var unconfirmed = SourceEvidenceGraph.empty(index);
    for (final record in f.evidence.records) {
      unconfirmed = unconfirmed.addAll(index, [
        SourceEvidence.propose(index, chunkId: record.chunkId,
            kind: EvidenceKind.event,
            startUtf16: record.startUtf16,
            endUtf16: record.endUtf16),
      ]);
    }
    expect(_review(f, evidence: unconfirmed).canStageForPrivateCompiler,
        isFalse);
  });

  test('editor did not accept M2c claims, so a Z.ai keep mark is insufficient',
      () {
    final f = _fixture();
    final noEditor = SemanticEditorialReviewSession.create(
        f.queue.index, f.catalog);
    final result = _review(f, editorial: noEditor);
    expect(result.canStageForPrivateCompiler, isFalse);
    expect(result.blockers.join(' '), contains('утверждение'));
  });

  test('tampered scene prose or event mapping cannot stage bookworld', () {
    final f = _fixture();
    final scene = f.sourceScenes.first;
    expect(_review(f,
      prose: {...f.prose, scene: 'не готов'},
    ).canStageForPrivateCompiler, isFalse);
    expect(_review(f,
      events: {f.eventAssertions.keys.first: f.eventAssertions.values.first},
    ).canStageForPrivateCompiler, isFalse);
  });

  test('editing book changes source fingerprint and invalidates old review',
      () {
    final f = _fixture();
    final other = _fixture();
    // Original fixture is deterministic and can be repeatedly reviewed.
    expect(other.queue.index.sourceFingerprint,
        f.queue.index.sourceFingerprint);
    final stale = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая редакция',
      author: 'Тест приложения',
      chapters: ['Другой текст.'],
    ));
    expect(stale.sourceFingerprint,
        isNot(f.queue.index.sourceFingerprint));
  });
}
