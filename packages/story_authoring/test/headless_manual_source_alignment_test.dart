import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

/// Only our original synthetic Russian sentences; no private Grimm text
/// and no provider response or secret is embedded in version control.
typedef _TestCase = ({
  ZaiWindowReviewQueue queue,
  ZaiSourceAlignmentBaseline baseline,
  SemanticCandidate candidate,
});

_TestCase _source({String text = 'Саша открыла окно. Миша нашёл ключ.'}) {
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Синтетический источник QA',
    author: 'Тестовый автор',
    chapters: [text],
  ));
  var queue = ZaiWindowReviewQueue.empty(index);
  final chunk = index.chunks.single;
  final quote = text.substring(0, text.indexOf('.') + 1);
  final start = chunk.text.indexOf(quote);
  expect(start, greaterThanOrEqualTo(0));
  final candidate = SemanticCandidate.propose(
    index, chunk,
    category: SemanticCategory.event,
    startUtf16: chunk.startUtf16 + start,
    endUtf16: chunk.startUtf16 + start + quote.length,
    label: 'Открытие окна',
    uncertainty: 'Сначала только модельная гипотеза.',
  );
  for (var i = 0; i < queue.windows.length; i++) {
    final window = queue.windows[i];
    final matches = window.chunks.any((c) => c.id == chunk.id)
        ? [candidate] : <SemanticCandidate>[];
    queue = queue.record(i, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: SemanticPreviewWireContract.providerId,
        providerVersion: SemanticPreviewWireContract.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [for (final c in window.chunks) c.id],
        candidates: matches,
      ),
      totalSuggestions: matches.length,
      rejectedCount: 0,
      rejectedNonRussian: 0,
    ));
  }
  queue = queue.decide(
      candidate.id, ZaiEditorialDecision.keepForReview);

  var narrative = StoryEvidenceReviewSession.create(index);
  while (narrative.scannedChunks < index.chunks.length) {
    narrative = narrative.scanNext(index, limit: 24);
  }
  final catalog = SourceSemanticCatalog.fromLocalEvidence(
      index, narrative.graph);
  final editorial = SemanticEditorialReviewSession.create(index, catalog);
  return (
    queue: queue,
    candidate: candidate,
    baseline: ZaiSourceAlignmentBaseline(
      narrative: narrative, catalog: catalog, editorial: editorial),
  );
}

ZaiManualSourceAlignment _accept(_TestCase f, {
  bool quote = true,
  bool narrator = true,
}) => ZaiManualSourceAlignment.empty(f.queue.index, f.baseline).accept(
  queue: f.queue, baseline: f.baseline, findingId: f.candidate.id,
  subject: 'Саша', predicate: 'открыла', object: 'окно',
  quoteConfirmedByReader: quote,
  narratorAssertionConfirmedByReader: narrator,
);

void main() {

  test('two independent human approvals add exact source and M2c canon '
      'candidate without changing original independent checkpoints', () {
    final f = _source();
    final unchangedSource = f.baseline.narrative.encode();
    final unchangedCatalog = f.baseline.catalog.encode();
    final unchangedEditorial = f.baseline.editorial.encode();
    final journal = _accept(f);
    expect(journal.canPublishBookworld, false);
    expect(journal.canSendToCloud, false);
    expect(journal.isAutomaticCanon, false);
    final saved = journal.encode(queue: f.queue, baseline: f.baseline);
    final decoded = ZaiManualSourceAlignment.decode(
      queue: f.queue, baseline: f.baseline, raw: saved);
    expect(decoded.encode(queue: f.queue, baseline: f.baseline), saved);
    final applied = decoded.apply(queue: f.queue, baseline: f.baseline);
    expect(applied.canPublishBookworld, false);
    expect(applied.provesNpcKnowledge, false);
    final linked = applied.assertionByFinding[f.candidate.id];
    expect(linked, isNotNull);
    final assertion = applied.catalog.assertions
        .singleWhere((a) => a.id == linked);
    expect(assertion.kind, SemanticAssertionKind.event);
    expect(assertion.subject, 'Саша');
    expect(assertion.predicate, 'открыла');
    expect(assertion.object, 'окно');
    expect(applied.editorial.verdicts[linked],
        SemanticEditorialVerdict.canonCandidate);
    final source = applied.evidence.records.singleWhere(
        (e) => e.id == assertion.evidenceIds.single);
    expect(source.status, EvidenceStatus.confirmed);
    expect(source.label, f.candidate.quote);
    expect(source.chunkId, f.candidate.chunkId);
    expect(source.startUtf16, f.candidate.startUtf16);
    expect(source.endUtf16, f.candidate.endUtf16);
    expect(source.evidenceSha256, f.candidate.quoteSha256);
    // The baseline independent M2c editorial is unchanged on disk.
    expect(f.baseline.narrative.encode(), unchangedSource);
    expect(f.baseline.catalog.encode(), unchangedCatalog);
    expect(f.baseline.editorial.encode(), unchangedEditorial);
    final withdrawn = decoded.remove(
        queue: f.queue, baseline: f.baseline,
        findingId: f.candidate.id);
    expect(withdrawn.entries, isEmpty);
    expect(withdrawn.apply(queue: f.queue, baseline: f.baseline)
        .assertionByFinding, isEmpty);
  });

  test('keepForReview and a forged true flag do not replace human approval',
      () {
    final f = _source();
    expect(() => _accept(f, quote: false), throwsFormatException);
    expect(() => _accept(f, narrator: false), throwsFormatException);
    expect(() => ZaiManualSourceAlignment.empty(f.queue.index, f.baseline)
        .accept(
          queue: f.queue, baseline: f.baseline,
          findingId: 'not-an-event',
          subject: 'Саша', predicate: 'открыла', object: 'окно',
          quoteConfirmedByReader: true,
          narratorAssertionConfirmedByReader: true,
        ), throwsFormatException);
    final accepted = _accept(f);
    final raw = accepted.encode(queue: f.queue, baseline: f.baseline);
    expect(() => ZaiManualSourceAlignment.decode(
      queue: f.queue, baseline: f.baseline,
      raw: raw.replaceFirst('открыла', 'подменила'),
    ), throwsFormatException);
  });

  test('changed edition, removed keep mark and changed independent M2c '
      'invalidate saved manual citation without losing the original', () {
    final f = _source();
    final stored = _accept(f).encode(queue: f.queue, baseline: f.baseline);
    final another = _source(text: 'Саша открыла окно. Миша нашёл другой ключ.');
    expect(() => ZaiManualSourceAlignment.decode(
      queue: another.queue, baseline: another.baseline, raw: stored,
    ), throwsFormatException);
    final notKept = f.queue.decide(
        f.candidate.id, ZaiEditorialDecision.rejected);
    expect(() => ZaiManualSourceAlignment.decode(
      queue: notKept, baseline: f.baseline, raw: stored,
    ), throwsFormatException);
    final added = ZaiSourceAlignmentBaseline(
      narrative: f.baseline.narrative,
      catalog: f.baseline.catalog,
      editorial: f.baseline.editorial,
    );
    expect(ZaiManualSourceAlignment.decode(
      queue: f.queue, baseline: added, raw: stored,
    ).entries, hasLength(1));
  });

  test('one exact quote cannot be silently promoted over disputed M2c '
      'source evidence', () {
    final f = _source();
    // Propose and classify this very quotation independently as disputed.
    final source = SourceEvidence.propose(
      f.queue.index,
      chunkId: f.candidate.chunkId,
      kind: EvidenceKind.event,
      startUtf16: f.candidate.startUtf16,
      endUtf16: f.candidate.endUtf16,
    );
    final baselineNarrative = f.baseline.narrative;
    final hasOriginal = baselineNarrative.graph.records
        .any((item) => item.id == source.id);
    // An incompatible old review must not be repaired silently.
    if (hasOriginal) {
      final disputedGraph = baselineNarrative.graph.review(
          f.queue.index, source.id, EvidenceStatus.conflicted);
      expect(disputedGraph.records.singleWhere(
          (e) => e.id == source.id).status, EvidenceStatus.conflicted);
    }
    expect(_accept(f).apply(queue: f.queue, baseline: f.baseline)
        .assertionByFinding.containsKey(f.candidate.id), isTrue);
  });
}
