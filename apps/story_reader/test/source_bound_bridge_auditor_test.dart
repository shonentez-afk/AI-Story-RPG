import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_bound_bridge_auditor.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  const _Fixture(this.index, this.events, this.graph, this.catalog,
      this.editorial, this.claimId);
  final BookSourceIndex index;
  final List<NarrativeEvent> events;
  final SourceEvidenceGraph graph;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
  final String claimId;

  SourceBoundBridgeAudit inspect(SourceBoundBridge bridge, {
    BookSourceIndex? source,
    List<NarrativeEvent>? sourceEvents,
  }) => SourceBoundBridgeAuditor.audit(
    index: source ?? index,
    evidence: graph,
    catalog: catalog,
    editorial: editorial,
    events: sourceEvents ?? events,
    bridges: [bridge],
  );

  SourceBoundBridge candidate({
    String id = 'causal_bridge',
    String first = 'first_event',
    String second = 'second_event',
    List<String>? claimIds,
    SourceBridgeKind kind = SourceBridgeKind.causalCandidate,
  }) => SourceBoundBridge(
    id: id,
    fromEventId: first,
    toEventId: second,
    sourceClaimIds: claimIds ?? [claimId],
    kind: kind,
    rationale: 'Проверить связь действий героя в разных частях текста.',
  );
}

_Fixture _fixture({
  AssertionVoice voice = AssertionVoice.narratorCandidate,
  bool confirmedWords = true,
  bool reviewedMeaningCandidate = true,
}) {
  final index = BookSourceIndexer.index(const ImportedBook(
    title: 'Два акта — независимый тест',
    author: 'Тест',
    chapters: [
      'Путник увидел закрытую дверь и не дал обещаний. '
          'Он спросил о свободной дороге и запомнил ответ.',
      'Позже путник оказался у ворот. Рассказчик сообщил, '
          'что рядом есть обходная тропа и открыт второй путь.',
    ],
  ));
  final firstChunk = index.chunks.firstWhere((c) => c.chapterIndex == 0);
  final secondChunk = index.chunks.firstWhere((c) => c.chapterIndex == 1);
  NarrativeCitation cite(SourceChunk c) {
    final len = c.text.length < 52 ? c.text.length : 52;
    return NarrativeCitation(
      chunkId: c.id,
      chapterIndex: c.chapterIndex,
      blockIndex: c.blockIndex,
      startUtf16: c.startUtf16,
      endUtf16: c.startUtf16 + len,
      quote: c.text.substring(0, len),
    );
  }
  final first = cite(firstChunk);
  final second = cite(secondChunk);
  final events = [
    NarrativeEvent(id: 'first_event', suggestedLabel: 'Решение у двери',
      source: first, narrativePosition: 0),
    NarrativeEvent(id: 'second_event', suggestedLabel: 'Решение у ворот',
      source: second, narrativePosition: 1),
  ];

  SourceEvidence proposal(NarrativeCitation q) =>
      SourceEvidence.propose(index, chunkId: q.chunkId,
        kind: EvidenceKind.fact,
        startUtf16: q.startUtf16, endUtf16: q.endUtf16);
  final proofA = proposal(first);
  final proofB = proposal(second);
  var graph = SourceEvidenceGraph.empty(index).addAll(index, [
    proofA, proofB,
  ]);
  if (confirmedWords) {
    graph = graph.review(index, proofA.id, EvidenceStatus.confirmed);
    graph = graph.review(index, proofB.id, EvidenceStatus.confirmed);
  }
  final claim = SourceSemanticAssertion.propose(index, graph,
    kind: SemanticAssertionKind.relation,
    evidenceIds: [proofA.id, proofB.id],
    subject: 'Путник',
    predicate: 'выбирает следующий путь',
    object: 'Обходная дорога',
    voice: voice,
    polarity: AssertionPolarity.affirmative,
    time: AssertionTime.textOrderOnly,
    uncertainty: 'Цитаты точны, но причинность и порядок мира не доказаны.',
  );
  final catalog = SourceSemanticCatalog.checked(index, graph, [claim]);
  var editorial = SemanticEditorialReviewSession.create(index, catalog);
  if (reviewedMeaningCandidate) {
    editorial = editorial.decide(
        catalog, claim.id, SemanticEditorialVerdict.canonCandidate);
  }
  return _Fixture(index, events, graph, catalog, editorial, claim.id);
}

void main() {
  test('exact evidence on BOTH sides yields literary review candidate, '
      'never automatic world canon', () {
    final f = _fixture();
    final audit = f.inspect(f.candidate());
    expect(audit.rejectedCount, 0);
    expect(audit.candidatesForLiteraryReview, 1);
    expect(audit.findings.single.disposition,
        SourceBridgeDisposition.literaryReviewRequired);
    expect(audit.findings.single.establishesWorldTruth, false);
    expect(audit.findings.single.establishesNPCWorldKnowledge, false);
    expect(audit.findings.single.establishesWorldChronology, false);
    expect(audit.canDeclareLiteraryCausality, false);
    expect(audit.canDeclareCanonicalRpg, false);
    expect(audit.toDiagnosticJson()['canonical_rpg_ready'], false);
  });

  test('an NPC report is NOT a narrator-established world fact', () {
    final f = _fixture(voice: AssertionVoice.reported);
    final audit = f.inspect(f.candidate());
    expect(audit.rejectedCount, 1);
    expect(audit.findings.single.blockers.join(' '), contains('персонажа'));
    expect(audit.canDeclareLiteraryCausality, false);
  });

  test('no editorial meaning review or unconfirmed words fail closed', () {
    final notReviewed = _fixture(reviewedMeaningCandidate: false);
    expect(notReviewed.inspect(notReviewed.candidate()).rejectedCount, 1);
    final notConfirmed = _fixture(confirmedWords: false);
    expect(notConfirmed.inspect(notConfirmed.candidate()).rejectedCount, 1);
    expect(notConfirmed.inspect(notConfirmed.candidate())
        .findings.single.blockers.join(' '), contains('цитат'));
  });

  test('unknown assertion, invented event and alien edition rejected', () {
    final f = _fixture();
    expect(f.inspect(f.candidate(claimIds: ['invented'])).rejectedCount, 1);
    expect(f.inspect(f.candidate(second: 'unseen_event')).rejectedCount, 1);

    final alienIndex = BookSourceIndexer.index(const ImportedBook(
      title: 'Совсем другая книга',
      author: 'Тест',
      chapters: ['Другой текст этой редакции.'],
    ));
    expect(() => f.inspect(f.candidate(), source: alienIndex),
        throwsFormatException);
  });

  test('moved or corrupted literal quote fails before semantic audit', () {
    final f = _fixture();
    final real = f.events.first;
    final forged = NarrativeEvent(
      id: real.id,
      suggestedLabel: real.suggestedLabel,
      narrativePosition: real.narrativePosition,
      source: NarrativeCitation(
        chunkId: real.source.chunkId,
        chapterIndex: real.source.chapterIndex,
        blockIndex: real.source.blockIndex,
        startUtf16: real.source.startUtf16,
        endUtf16: real.source.endUtf16,
        quote: 'Подменённая цитата',
      ),
    );
    expect(() => f.inspect(f.candidate(),
        sourceEvents: [forged, f.events.last]), throwsFormatException);
  });

  test('source order reverse remains a warning, not invented world time', () {
    final f = _fixture();
    final audit = f.inspect(f.candidate(
      first: 'second_event', second: 'first_event'));
    expect(audit.findings.single.textOrderReversed, true);
    expect(audit.findings.single.establishesWorldChronology, false);
    expect(audit.canDeclareCanonicalRpg, false);
  });

  test('explicit fictional bridge is not misrepresented as literary proof', () {
    final f = _fixture();
    final allowed = f.inspect(f.candidate(
      kind: SourceBridgeKind.explicitGameFiction, claimIds: []));
    expect(allowed.fictionalCount, 1);
    expect(allowed.rejectedCount, 0);
    expect(allowed.canDeclareLiteraryCausality, false);
    final fakingProof = f.inspect(f.candidate(
      kind: SourceBridgeKind.explicitGameFiction));
    expect(fakingProof.rejectedCount, 1);
  });

  test('duplicate ids and invalid disclosure notes cannot bypass auditing', () {
    final f = _fixture();
    final b = f.candidate();
    expect(() => SourceBoundBridgeAuditor.audit(
      index: f.index, evidence: f.graph, catalog: f.catalog,
      editorial: f.editorial, events: f.events, bridges: [b, b],
    ), throwsFormatException);
    expect(() => f.inspect(SourceBoundBridge(
      id: 'bad id', fromEventId: 'first_event', toEventId: 'second_event',
      kind: SourceBridgeKind.causalCandidate, sourceClaimIds: [f.claimId],
      rationale: 'Нарушен формат идентификатора.',
    )), throwsFormatException);
  });
}
