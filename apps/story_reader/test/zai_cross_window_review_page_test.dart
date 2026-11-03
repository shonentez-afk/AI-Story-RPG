import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_cross_window_review_page.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_preview_page.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _book() => BookSourceIndexer.index(const ImportedBook(
  title: 'Сказка о двух главах',
  author: 'ПРИВАТНЫЙ АВТОР',
  chapters: ['Кай вошёл в дом.', 'Кай открыл дверь.'],
  structuredChapters: [
    BookChapter(id: 'first', blocks: [
      BookBlock(kind: BookBlockKind.paragraph, text: 'Кай вошёл в дом.'),
    ]),
    BookChapter(id: 'second', blocks: [
      BookBlock(kind: BookBlockKind.paragraph, text: 'Кай открыл дверь.'),
    ]),
  ],
));

ZaiWindowReviewQueue _reviews(BookSourceIndex index) {
  var queue = ZaiWindowReviewQueue.empty(index);
  for (var window = 0; window < 2; window++) {
    final chunk = index.chunks[window];
    final person = SemanticCandidate.propose(index, chunk,
      category: SemanticCategory.character,
      startUtf16: chunk.startUtf16,
      endUtf16: chunk.startUtf16 + 3,
      label: 'Кай',
      uncertainty: 'Нужно проверить персонажа',
    );
    final action = SemanticCandidate.propose(index, chunk,
      category: SemanticCategory.event,
      startUtf16: chunk.startUtf16,
      endUtf16: chunk.endUtf16,
      label: window == 0 ? 'Кай вошёл' : 'Кай открыл дверь',
      uncertainty: 'Нужно подтвердить событие',
    );
    queue = queue.record(window, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [chunk.id],
        candidates: [person, action],
      ),
      totalSuggestions: 2,
      rejectedCount: 0,
      rejectedNonRussian: 0,
    ));
    queue = queue.decide(person.id, ZaiEditorialDecision.keepForReview)
        .decide(action.id, ZaiEditorialDecision.keepForReview);
  }
  return queue;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('review page shows cross-window evidence without cloud and '
      'consent protects manually proposed link', (tester) async {
    final index = _book();
    final queue = _reviews(index);
    final linksRepo = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(
      home: ZaiCrossWindowReviewPage(
        queue: queue, linksRepository: linksRepo,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('zai-graph-summary')), findsOneWidget);
    expect(find.textContaining('цитат на дальнейшую проверку 4'), findsOneWidget);
    expect(find.textContaining('Порядок цитат не обязательно'), findsOneWidget);
    expect(find.textContaining('Кай'), findsWidgets);
    final expansion = find.text('Кай').first;
    await tester.ensureVisible(expansion);
    await tester.tap(expansion);
    await tester.pumpAndSettle();

    final identityButton = find.byKey(
        Key('zai-graph-possible-identity-${queue.allCandidates.first.id}'));
    await tester.ensureVisible(identityButton);
    await tester.tap(identityButton);
    await tester.pumpAndSettle();
    expect(find.text('Отметить возможное совпадение?'), findsOneWidget);
    final submit = find.byKey(const Key('zai-link-confirm-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await linksRepo.read(index.sourceFingerprint), isNull);

    await tester.tap(identityButton);
    await tester.pumpAndSettle();
    final check = find.byKey(const Key('zai-link-confirm-checkbox'));
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Редакторских гипотез о связях: 1'), 150,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await tester.pumpAndSettle();
    expect(find.text('Редакторских гипотез о связях: 1'), findsOneWidget);
    final raw = await linksRepo.read(index.sourceFingerprint);
    expect(raw, isNotNull);
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
    final restored = ZaiCrossWindowLinkNotebook.decode(graph, raw!);
    expect(restored.links.length, 1);
    expect(restored.canPublishBookworld, false);
    expect(raw, isNot(contains('ПРИВАТНЫЙ АВТОР')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview provides a locally rendered cross-book overview even '
      'with no provider or network configured', (tester) async {
    final index = _book();
    final review = MemorySourceAnalysisCheckpointRepository();
    final links = MemorySourceAnalysisCheckpointRepository();
    await review.write(index.sourceFingerprint, _reviews(index).encode());
    await tester.pumpWidget(MaterialApp(
      home: ZaiSemanticPreviewPage(
        index: index,
        reviewRepository: review,
        linksRepository: links,
      ),
    ));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('zai-open-cross-window-review'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Сквозной анализ книги'), findsOneWidget);
    expect(find.byKey(const Key('zai-graph-summary')), findsOneWidget);
    // No cloud permission was requested, no network call made.
    expect(find.byKey(const Key('zai-consent-exact-checkbox')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
