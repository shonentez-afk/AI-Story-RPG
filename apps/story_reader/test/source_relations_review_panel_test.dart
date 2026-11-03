import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_chronology.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_relations_review_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = ImportedBook(
    title: 'Хронология двух глав', author: 'Тест',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. Дверь была открыта.',
      'Артем встретил Анну. Дверь была закрыта.',
    ],
  );

  SourceEvidenceGraph sourceGraph(BookSourceIndex index,
      {bool confirm = true}) {
    final all = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      all.addAll(SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    var graph = SourceEvidenceGraph.empty(index).addAll(index, all);
    if (confirm) {
      for (final quote in graph.records) {
        graph = graph.review(index, quote.id, EvidenceStatus.confirmed);
      }
    }
    return graph;
  }

  Widget page(BookSourceIndex index, SourceEvidenceGraph graph,
      MemorySourceAnalysisCheckpointRepository store) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SourceRelationsReviewPanel(
                index: index,
                graph: graph,
                checkpointRepository: store,
                sessionBuilder: (i, g) async =>
                    SourceRelationReviewSession.create(i, g),
                sessionDecoder: (i, g, raw) async =>
                    SourceRelationReviewSession.decode(i, g, raw),
                checkpointEncoder: (session) async => session.encode(),
                chronologyBuilder: (i, g) async =>
                    SourceNarrativeChronology.build(i, g),
                relationDecider: (i, g, s, id, decision) async =>
                    s.decide(i, g, id, decision),
              ),
            ),
          ),
        ),
      );

  testWidgets('explicit opening, identity decision and resume are private',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final graph = sourceGraph(index);
    final store = MemorySourceAnalysisCheckpointRepository();

    await tester.pumpWidget(page(index, graph, store));
    await tester.pumpAndSettle();
    expect(find.text('Открыть связи и хронологию'), findsOneWidget);
    expect(find.textContaining('Артем — Волк'), findsNothing);
    expect(await store.read(index.sourceFingerprint), isNull);

    await tester.tap(find.text('Открыть связи и хронологию'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Артем — Волк'), findsOneWidget);
    expect(find.textContaining('Возможных пар: 1'), findsOneWidget);
    expect(find.text('Один'), findsOneWidget);
    await tester.ensureVisible(find.text('Один'));
    await tester.tap(find.text('Один'));
    await tester.pumpAndSettle();

    final saved = SourceRelationReviewSession.decode(index, graph,
        (await store.read(index.sourceFingerprint))!);
    expect(saved.unresolvedCount, 0);
    expect(saved.canPublishBookworld, false);
    expect(saved.decisionFor(saved.hints.single.id), IdentityDecision.same);

    final dropdown = find.byType(DropdownButton<ChapterTimeDecision>).first;
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Флешбэк').last);
    await tester.pumpAndSettle();
    final voted = SourceRelationReviewSession.decode(index, graph,
        (await store.read(index.sourceFingerprint))!);
    expect(voted.temporalDecision(0), ChapterTimeDecision.flashback);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(page(index, graph, store));
    await tester.pumpAndSettle();
    expect(find.textContaining('Артем — Волк'), findsNothing);
    await tester.tap(find.text('Открыть связи и хронологию'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Решение: Один персонаж'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long source exposes remaining identities and chronology '
      'without silently merging them', (tester) async {
    final longBook = ImportedBook(
      title: 'Много упоминаний', author: 'Автор',
      chapters: List.generate(9,
          (i) => 'Артем по прозвищу Волк открыл дверь. '
              'Дверь была открыта. Сцена $i.'),
    );
    final index = BookSourceIndexer.index(longBook);
    final graph = sourceGraph(index);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(page(index, graph, store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть связи и хронологию'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('relations-show-more')), findsOneWidget);
    expect(find.byKey(const Key('relations-show-more-chapters')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('relations-show-more')));
    await tester.tap(find.byKey(const Key('relations-show-more')));
    await tester.pumpAndSettle();
    final after = SourceRelationReviewSession.create(index, graph);
    expect(after.unresolvedCount, greaterThan(4));
    expect(await store.read(index.sourceFingerprint), isNull);
    await tester.ensureVisible(
        find.byKey(const Key('relations-show-more-chapters')));
    await tester.tap(find.byKey(const Key('relations-show-more-chapters')));
    await tester.pumpAndSettle();
    expect(find.text('Глава 4 → глава 5'), findsOneWidget);
    expect(find.byKey(const Key('relations-show-more-observations')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save shows error and does not publish identity',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final graph = sourceGraph(index);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(page(index, graph, store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть связи и хронологию'));
    await tester.pumpAndSettle();
    store.failNextWrite = true;
    await tester.ensureVisible(find.text('Один'));
    await tester.tap(find.text('Один'));
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), isNull);
    expect(find.textContaining('Решение: Не определено'), findsOneWidget);
    expect(find.textContaining('Решение не сохранено'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unverified source prevents unreviewed SAME and reset confirms',
      (tester) async {
    final index = BookSourceIndexer.index(book);
    final graph = sourceGraph(index, confirm: false);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(page(index, graph, store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть связи и хронологию'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сначала подтвердите обе цитаты'),
        findsOneWidget);
    final blocked = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Один'));
    expect(blocked.onPressed, isNull);
    await tester.ensureVisible(find.text('Сбросить связи'));
    await tester.tap(find.text('Сбросить связи'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить связи и хронологию?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
