import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_cross_window_review_page.dart';
import 'package:ai_story_reader/zai_editorial_consistency.dart';
import 'package:ai_story_reader/zai_editorial_consistency_page.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _book() => BookSourceIndexer.index(const ImportedBook(
  title: 'Две версии',
  author: 'ПРИВАТНЫЙ АВТОР',
  chapters: [
    'Кай живёт в деревне. Кай открыл дверь.',
    'Кай не живёт в деревне. Кай ушёл.',
  ],
  structuredChapters: [
    BookChapter(id: 'one', blocks: [
      BookBlock(kind: BookBlockKind.paragraph,
          text: 'Кай живёт в деревне. Кай открыл дверь.'),
    ]),
    BookChapter(id: 'two', blocks: [
      BookBlock(kind: BookBlockKind.paragraph,
          text: 'Кай не живёт в деревне. Кай ушёл.'),
    ]),
  ],
));

ZaiWindowReviewQueue _queue(BookSourceIndex index) {
  var queue = ZaiWindowReviewQueue.empty(index);
  for (var i = 0; i < 2; i++) {
    final chunk = index.chunks[i];
    final text = i == 0 ? 'Кай живёт в деревне.' :
        'Кай не живёт в деревне.';
    final action = i == 0 ? 'Кай открыл дверь.' : 'Кай ушёл.';
    SemanticCandidate candidate(SemanticCategory category, String quote) {
      final offset = chunk.text.indexOf(quote);
      return SemanticCandidate.propose(index, chunk,
        category: category,
        startUtf16: chunk.startUtf16 + offset,
        endUtf16: chunk.startUtf16 + offset + quote.length,
        label: quote,
        uncertainty: 'Проверка контекста',
      );
    }
    final proposed = <SemanticCandidate>[
      candidate(SemanticCategory.fact, text),
      candidate(SemanticCategory.event, action),
    ];
    queue = queue.record(i, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [chunk.id],
        candidates: proposed,
      ),
      totalSuggestions: 2,
      rejectedCount: 0,
      rejectedNonRussian: 0,
    ));
    for (final item in proposed) {
      queue = queue.decide(item.id, ZaiEditorialDecision.keepForReview);
    }
  }
  return queue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('possible discrepancy shows EXACT two quotes, cannot save '
      'without explicit checkbox, cancellation never writes', (tester) async {
    final index = _book();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(_queue(index));
    final repo = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(
      home: ZaiEditorialConsistencyPage(graph: graph, repository: repo),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-consistency-title')), findsOneWidget);
    expect(find.textContaining('возможных противоречий по формулировке: 1'),
        findsOneWidget);

    final hint = find.text('Сравнить эти цитаты вручную');
    await tester.ensureVisible(hint);
    await tester.tap(hint);
    await tester.pumpAndSettle();
    final propose = find.byKey(const Key('zai-consistency-propose'));
    await tester.scrollUntilVisible(propose, 180,
      scrollable: find.byType(Scrollable).first, maxScrolls: 35);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(propose).onPressed, isNotNull);
    await tester.tap(propose);
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('zai-consistency-confirm-save'));
    expect(submit, findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.textContaining('Кай живёт в деревне.'), findsWidgets);
    expect(find.textContaining('Кай не живёт в деревне.'), findsWidgets);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await repo.read(index.sourceFingerprint), isNull);

    await tester.tap(propose);
    await tester.pumpAndSettle();
    final checkbox = find.byKey(const Key('zai-consistency-confirm-check'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final raw = await repo.read(index.sourceFingerprint);
    expect(raw, isNotNull);
    expect(raw, isNot(contains('ПРИВАТНЫЙ АВТОР')));
    final restored = ZaiEditorialConsistencyNotebook.decode(graph, raw!);
    expect(restored.questions, hasLength(1));
    expect(restored.questions.single.kind,
        ZaiConsistencyKind.possibleDiscrepancy);
    expect(restored.questions.single.proven, false);
    expect(restored.canPublishBookworld, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupted notebook remains read-only until explicitly '
      'reset, other graph evidence is not deleted', (tester) async {
    final index = _book();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(_queue(index));
    final repo = MemorySourceAnalysisCheckpointRepository();
    await repo.write(index.sourceFingerprint, '{invalid');
    await tester.pumpWidget(MaterialApp(
      home: ZaiEditorialConsistencyPage(graph: graph, repository: repo),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zai-consistency-error')), findsOneWidget);
    final button = find.byKey(const Key('zai-consistency-reset'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Сбросить вопросы согласованности?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await repo.read(index.sourceFingerprint), '{invalid');
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const Key('zai-consistency-reset-confirm')));
    await tester.pumpAndSettle();
    expect(await repo.read(index.sourceFingerprint), isNull);
    expect(find.byKey(const Key('zai-consistency-error')), findsNothing);
    expect(graph.reviewed, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cross-window overview opens consistency without '
      'sending book text and preserves source navigation', (tester) async {
    final index = _book();
    final repo = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(
      home: ZaiCrossWindowReviewPage(
        queue: _queue(index),
        linksRepository: MemorySourceAnalysisCheckpointRepository(),
        consistencyRepository: repo,
      ),
    ));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('zai-open-editorial-consistency'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Алиасы, противоречия и хронология'), findsOneWidget);
    expect(find.byKey(const Key('zai-consistency-summary')), findsOneWidget);
    expect(find.byKey(const Key('zai-consistency-confirm-save')), findsNothing);
    expect(await repo.read(index.sourceFingerprint), isNull);
    expect(tester.takeException(), isNull);
  });
}
