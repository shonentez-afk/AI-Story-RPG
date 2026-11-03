import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_editorial_review_page.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const novel = ImportedBook(
    title: 'Рукописная история', author: 'Автор',
    chapters: [
      'Дверь была закрыта. Мария открыла дверь.',
      'Дверь была открыта. Мария встретила Ивана.',
    ],
  );

  Future<(BookSourceIndex, StoryEvidenceReviewSession,
      SourceSemanticCatalog)> indexed({bool confirm = true,
      ImportedBook book = novel}) async {
    final index = BookSourceIndexer.index(book);
    var session = StoryEvidenceReviewSession.create(index);
    while (session.scannedChunks < index.chunks.length) {
      session = session.scanNext(index);
    }
    if (confirm) {
      for (final citation in session.graph.records) {
        session = session.review(index, citation.id, EvidenceStatus.confirmed);
      }
    }
    final catalog = SourceSemanticCatalog.fromLocalEvidence(
        index, session.graph);
    return (index, session, catalog);
  }

  Widget page(
    BookSourceIndex index,
    MemorySourceAnalysisCheckpointRepository evidence,
    MemorySourceAnalysisCheckpointRepository catalog,
    MemorySourceAnalysisCheckpointRepository editorial,
  ) => MaterialApp(
    home: SourceEditorialReviewPage(
      index: index,
      narrativeRepository: evidence,
      catalogRepository: catalog,
      editorialRepository: editorial,
      relationsRepository: MemorySourceAnalysisCheckpointRepository(),
    ),
  );

  testWidgets('missing semantic checkpoints show blocker without edits',
      (tester) async {
    final index = BookSourceIndexer.index(novel);
    await tester.pumpWidget(page(
        index,
        MemorySourceAnalysisCheckpointRepository(),
        MemorySourceAnalysisCheckpointRepository(),
        MemorySourceAnalysisCheckpointRepository()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Данные редактора не открыты'), findsOneWidget);
    expect(find.byKey(const Key('source-editor-show-spoilers')), findsNothing);
    expect(find.text('Перепроверить подготовку'), findsOneWidget);
  });

  testWidgets('spoilers are opt-in and verified source decision persists',
      (tester) async {
    final (index, session, catalog) = await indexed();
    expect(catalog.assertions, isNotEmpty);
    final narrative = MemorySourceAnalysisCheckpointRepository();
    final semantic = MemorySourceAnalysisCheckpointRepository();
    final editorial = MemorySourceAnalysisCheckpointRepository();
    await narrative.write(index.sourceFingerprint, session.encode());
    await semantic.write(index.sourceFingerprint, catalog.encode());
    await tester.pumpWidget(page(index, narrative, semantic, editorial));
    await tester.pumpAndSettle();
    expect(find.textContaining('из ${catalog.assertions.length} утверждений'),
        findsOneWidget);
    expect(find.textContaining('Мария открыла дверь'), findsNothing);
    await tester.tap(find.byKey(const Key('source-editor-show-spoilers')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-editor-search')), findsOneWidget);
    final id = catalog.assertions.first.id;
    final button = find.byKey(Key('source-verdict-$id-canonCandidate'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final saved = SemanticEditorialReviewSession.decode(
        index, session.graph, catalog,
        (await editorial.read(index.sourceFingerprint))!);
    expect(saved.verdicts[id], SemanticEditorialVerdict.canonCandidate);
    expect(saved.isWorldCanon, false);
    expect(saved.canPublishBookworld, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfirmed citations block canon, failed write stays private',
      (tester) async {
    final (index, pending, catalog) = await indexed(confirm: false);
    final narrative = MemorySourceAnalysisCheckpointRepository();
    final semantic = MemorySourceAnalysisCheckpointRepository();
    final editorial = MemorySourceAnalysisCheckpointRepository();
    await narrative.write(index.sourceFingerprint, pending.encode());
    await semantic.write(index.sourceFingerprint, catalog.encode());
    await tester.pumpWidget(page(index, narrative, semantic, editorial));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-editor-show-spoilers')));
    await tester.pumpAndSettle();
    final id = catalog.assertions.first.id;
    final blocked = tester.widget<OutlinedButton>(
        find.byKey(Key('source-verdict-$id-canonCandidate')));
    expect(blocked.onPressed, isNull);
    editorial.failNextWrite = true;
    final disputed = find.byKey(Key('source-verdict-$id-disputed'));
    await tester.ensureVisible(disputed);
    await tester.tap(disputed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Решение не сохранено'), findsOneWidget);
    expect(await editorial.read(index.sourceFingerprint), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog of many chapters is searchable and paginated',
      (tester) async {
    final many = ImportedBook(
      title: 'Пятнадцать событий', author: 'Автор',
      chapters: List.generate(16, (i) =>
          'Дверь была закрыта. Мария открыла дверь. Глава номер $i.'),
    );
    final (index, session, catalog) = await indexed(book: many);
    expect(catalog.assertions.length, greaterThan(12));
    final narrative = MemorySourceAnalysisCheckpointRepository();
    final semantic = MemorySourceAnalysisCheckpointRepository();
    await narrative.write(index.sourceFingerprint, session.encode());
    await semantic.write(index.sourceFingerprint, catalog.encode());
    await tester.pumpWidget(page(index, narrative, semantic,
        MemorySourceAnalysisCheckpointRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source-editor-show-spoilers')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('source-editor-next')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('source-editor-next')));
    await tester.tap(find.byKey(const Key('source-editor-next')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Страница 2 из'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('source-editor-search')), 'неизвестное');
    await tester.pumpAndSettle();
    expect(find.text('Для выбранного фильтра записей нет.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrative reset preserves editor decisions but revokes '
      'unverified canon readiness until citations are reapproved',
      (tester) async {
    final (index, verified, catalog) = await indexed();
    final fp = index.sourceFingerprint;
    final narrative = MemorySourceAnalysisCheckpointRepository();
    final semantics = MemorySourceAnalysisCheckpointRepository();
    final editorial = MemorySourceAnalysisCheckpointRepository();
    final first = catalog.assertions.first.id;
    final decision = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, first, SemanticEditorialVerdict.canonCandidate);
    await narrative.write(fp, verified.encode());
    await semantics.write(fp, catalog.encode());
    await editorial.write(fp, decision.encode());

    Future<void> reopen() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(page(index, narrative, semantics, editorial));
      await tester.pumpAndSettle();
    }

    await reopen();
    expect(find.textContaining(
        'с действующими подтверждёнными цитатами: 1'), findsOneWidget);

    // An explicit reset of narrative evidence deletes only its own scope.
    // The editor must block while source evidence is missing.
    await narrative.delete(fp);
    await reopen();
    expect(find.textContaining('Данные редактора не открыты'),
        findsOneWidget);
    expect(find.byKey(const Key('source-editor-show-spoilers')),
        findsNothing);
    expect(await semantics.read(fp), catalog.encode());
    expect(await editorial.read(fp), decision.encode());

    // Re-analysis recreates identical source passages but does not
    // automatically restore the old human confirmations.
    final pending = StoryEvidenceReviewSession.create(index).scanNext(index);
    expect(pending.scannedChunks, index.chunks.length);
    expect(pending.graph.records.any(
        (e) => e.status == EvidenceStatus.confirmed), isFalse);
    await narrative.write(fp, pending.encode());
    await reopen();
    expect(find.textContaining(
        'с действующими подтверждёнными цитатами: 0'), findsOneWidget);
    expect(find.textContaining('Повторная проверка обязательна'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('source-editor-show-spoilers')));
    await tester.pumpAndSettle();
    final blocked = tester.widget<OutlinedButton>(
        find.byKey(Key('source-verdict-$first-canonCandidate')));
    expect(blocked.onPressed, isNull);
    expect(await editorial.read(fp), decision.encode());

    // A safe full re-confirmation restores validity, not by deleting
    // historical decisions or silently changing independent checkpoints.
    await narrative.write(fp, verified.encode());
    await reopen();
    expect(find.textContaining('Повторная проверка обязательна'),
        findsNothing);
    expect(find.textContaining(
        'с действующими подтверждёнными цитатами: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
