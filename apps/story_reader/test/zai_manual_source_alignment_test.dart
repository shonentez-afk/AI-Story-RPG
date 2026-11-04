import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_manual_source_alignment_page.dart';
import 'package:ai_story_reader/zai_source_scene_board.dart';
import 'package:flutter/material.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:ai_story_reader/zai_manual_source_alignment.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:flutter_test/flutter_test.dart';

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
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
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

Future<void> _moveTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)), 160,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 45,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('source citation is hidden until spoiler consent; '
      'both human checks precede a separate atomic checkpoint',
      (tester) async {
    final f = _source();
    final index = f.queue.index;
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(f.queue);
    final board = ZaiSourceSceneBoard.empty(graph).addScene(
      [f.candidate.id], 'Первая сцена', 'Частная редакторская заметка.',
    );
    final narrative = MemorySourceAnalysisCheckpointRepository();
    final catalog = MemorySourceAnalysisCheckpointRepository();
    final editorial = MemorySourceAnalysisCheckpointRepository();
    final alignment = MemorySourceAnalysisCheckpointRepository();
    await narrative.write(index.sourceFingerprint,
        f.baseline.narrative.encode());
    await catalog.write(index.sourceFingerprint,
        f.baseline.catalog.encode());
    await editorial.write(index.sourceFingerprint,
        f.baseline.editorial.encode());

    await tester.pumpWidget(MaterialApp(home: ZaiManualSourceAlignmentPage(
      queue: f.queue, board: board,
      narrativeRepository: narrative,
      catalogRepository: catalog,
      editorialRepository: editorial,
      alignmentRepository: alignment,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-align-title')), findsOneWidget);
    expect(find.byKey(const Key('zai-align-exact-quote')), findsNothing);
    expect(await alignment.read(index.sourceFingerprint), isNull);

    await tester.tap(find.byKey(const Key('zai-align-reveal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-align-exact-quote')), findsNothing);
    await tester.tap(find.byKey(const Key('zai-align-reveal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-align-reveal-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-align-exact-quote')), findsOneWidget);

    for (final item in [
      ('zai-align-subject', 'Саша'),
      ('zai-align-predicate', 'открыла'),
      ('zai-align-object', 'окно'),
    ]) {
      await _moveTo(tester, item.$1);
      await tester.enterText(find.byKey(Key(item.$1)), item.$2);
      await tester.pumpAndSettle();
    }
    await _moveTo(tester, 'zai-align-save');
    var save = tester.widget<FilledButton>(
        find.byKey(const Key('zai-align-save')));
    expect(save.onPressed, isNull);
    await _moveTo(tester, 'zai-align-confirm-quote');
    await tester.tap(find.byKey(const Key('zai-align-confirm-quote')));
    await tester.pumpAndSettle();
    await _moveTo(tester, 'zai-align-save');
    save = tester.widget<FilledButton>(
        find.byKey(const Key('zai-align-save')));
    expect(save.onPressed, isNull);
    await _moveTo(tester, 'zai-align-confirm-narrator');
    await tester.tap(find.byKey(const Key('zai-align-confirm-narrator')));
    await tester.pumpAndSettle();
    await _moveTo(tester, 'zai-align-save');
    save = tester.widget<FilledButton>(
        find.byKey(const Key('zai-align-save')));
    expect(save.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('zai-align-save')));
    await tester.pumpAndSettle();
    final raw = await alignment.read(index.sourceFingerprint);
    expect(raw, isNotNull);
    final restored = ZaiManualSourceAlignment.decode(
      queue: f.queue, baseline: f.baseline, raw: raw!);
    expect(restored.entries, hasLength(1));
    expect(await narrative.read(index.sourceFingerprint),
        f.baseline.narrative.encode());
    expect(await catalog.read(index.sourceFingerprint),
        f.baseline.catalog.encode());
    expect(await editorial.read(index.sourceFingerprint),
        f.baseline.editorial.encode());
    expect(tester.takeException(), isNull);
  });

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
