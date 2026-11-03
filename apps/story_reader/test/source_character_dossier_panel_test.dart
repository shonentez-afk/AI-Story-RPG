import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossier_panel.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_chronology.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_relations_review_panel.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const story = ImportedBook(
    title: 'Персонажи двух глав', author: 'Автор',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. Дверь была открыта.',
      'Артем встретил Анну. Дверь была закрыта.',
    ],
  );
  (BookSourceIndex, SourceEvidenceGraph, SourceSemanticCatalog,
      SemanticEditorialReviewSession) fixture(ImportedBook book) {
    final index = BookSourceIndexer.index(book);
    final evidence = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      evidence.addAll(SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    var graph = SourceEvidenceGraph.empty(index).addAll(index, evidence);
    for (final entry in graph.records) {
      graph = graph.review(index, entry.id, EvidenceStatus.confirmed);
    }
    final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    final editorial = SemanticEditorialReviewSession.create(index, catalog);
    return (index, graph, catalog, editorial);
  }

  Widget screen(BookSourceIndex index, SourceEvidenceGraph graph,
      SourceSemanticCatalog catalog,
      SemanticEditorialReviewSession editorial,
      MemorySourceAnalysisCheckpointRepository store,
      {int revision = 0}) => MaterialApp(home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SourceCharacterDossierPanel(
        index: index, graph: graph, catalog: catalog,
        editorial: editorial, checkpointRepository: store,
        refreshRevision: revision,
        sessionBuilder: (i, g) async =>
            SourceRelationReviewSession.create(i, g),
        sessionDecoder: (i, g, raw) async =>
            SourceRelationReviewSession.decode(i, g, raw),
        dossierBuilder: (i, g, s, c, e) async =>
            SourceCharacterDossierIndex.build(i, g, s, c, e),
      ),
    ),
  ));

  testWidgets('no spoilers or extra checkpoint on first render',
      (tester) async {
    final (index, graph, catalog, editorial) = fixture(story);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(screen(index, graph, catalog, editorial, store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dossier-open')), findsOneWidget);
    expect(find.textContaining('Упоминаний:'), findsNothing);
    expect(await store.read(index.sourceFingerprint), isNull);
    await tester.tap(find.byKey(const Key('dossier-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dossier-search')), findsOneWidget);
    expect(find.textContaining('Группы не равны числу персонажей'),
        findsOneWidget);
    expect(find.textContaining('Артем'), findsWidgets);
    expect(await store.read(index.sourceFingerprint), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved SAME refreshes only derived cards', (tester) async {
    final (index, graph, catalog, editorial) = fixture(story);
    final store = MemorySourceAnalysisCheckpointRepository();
    final review = SourceRelationReviewSession.create(index, graph);
    final alias = review.hints.firstWhere(
        (h) => h.kind == IdentityHintKind.explicitAlias &&
            h.sourceKind == EvidenceKind.character);
    await tester.pumpWidget(screen(index, graph, catalog, editorial, store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier-open')));
    await tester.pumpAndSettle();
    final total = graph.records.where(
        (e) => e.kind == EvidenceKind.character).length;
    expect(find.textContaining('${total} отдельных групп'), findsOneWidget);
    final same = review.decide(index, graph, alias.id, IdentityDecision.same);
    await store.write(index.sourceFingerprint, same.encode());
    await tester.pumpWidget(screen(
        index, graph, catalog, editorial, store, revision: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('${total - 1} отдельных групп'), findsOneWidget);
    expect(find.textContaining('Артем / Волк'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt saved decisions block cards without reset',
      (tester) async {
    final (index, graph, catalog, editorial) = fixture(story);
    final store = MemorySourceAnalysisCheckpointRepository();
    await store.write(index.sourceFingerprint, '{"invalid":true}');
    await tester.pumpWidget(screen(index, graph, catalog, editorial, store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Карточки не открыты'), findsOneWidget);
    expect(find.byKey(const Key('dossier-search')), findsNothing);
    expect(await store.read(index.sourceFingerprint), '{"invalid":true}');
  });

  testWidgets('long book exposes every separate name across pages',
      (tester) async {
    final book = ImportedBook(
      title: 'Двенадцать глав', author: 'Автор',
      chapters: List.generate(12,
          (i) => 'Артем открыл дверь. Дверь была закрыта. Глава $i.'),
    );
    final (index, graph, catalog, editorial) = fixture(book);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(screen(index, graph, catalog, editorial, store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dossier-next')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('dossier-next')));
    await tester.tap(find.byKey(const Key('dossier-next')));
    await tester.pumpAndSettle();
    expect(find.text('Страница 2 из 2'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('dossier-search')), 'другое имя');
    await tester.pumpAndSettle();
    expect(find.text('По выбранному имени карточек нет.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing identity reviewer saves and refreshes dossiers',
      (tester) async {
    final (index, graph, catalog, editorial) = fixture(story);
    final store = MemorySourceAnalysisCheckpointRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: SingleChildScrollView(child: _ConnectedDossiers(
          index: index, graph: graph, catalog: catalog,
          editorial: editorial, store: store,
        )))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dossier-open')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Открыть связи и хронологию'));
    await tester.tap(find.text('Открыть связи и хронологию'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Один').first);
    await tester.tap(find.text('Один').first);
    await tester.pumpAndSettle();
    final saved = SourceRelationReviewSession.decode(index, graph,
        (await store.read(index.sourceFingerprint))!);
    expect(saved.proposedRelations.any(
        (r) => r.decision == IdentityDecision.same), true);
    expect(find.textContaining('Один персонаж (решение редактора)'),
        findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _ConnectedDossiers extends StatefulWidget {
  const _ConnectedDossiers({
    required this.index, required this.graph, required this.catalog,
    required this.editorial, required this.store,
  });
  final BookSourceIndex index;
  final SourceEvidenceGraph graph;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
  final MemorySourceAnalysisCheckpointRepository store;
  @override
  State<_ConnectedDossiers> createState() => _ConnectedDossiersState();
}

class _ConnectedDossiersState extends State<_ConnectedDossiers> {
  int revision = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
    SourceCharacterDossierPanel(
      index: widget.index, graph: widget.graph,
      catalog: widget.catalog, editorial: widget.editorial,
      checkpointRepository: widget.store, refreshRevision: revision,
      sessionBuilder: (i, g) async => SourceRelationReviewSession.create(i, g),
      sessionDecoder: (i, g, raw) async =>
          SourceRelationReviewSession.decode(i, g, raw),
      dossierBuilder: (i, g, s, c, e) async =>
          SourceCharacterDossierIndex.build(i, g, s, c, e),
    ),
    SourceRelationsReviewPanel(
      index: widget.index, graph: widget.graph,
      checkpointRepository: widget.store,
      sessionBuilder: (i, g) async => SourceRelationReviewSession.create(i, g),
      sessionDecoder: (i, g, raw) async =>
          SourceRelationReviewSession.decode(i, g, raw),
      checkpointEncoder: (session) async => session.encode(),
      chronologyBuilder: (i, g) async =>
          SourceNarrativeChronology.build(i, g),
      relationDecider: (i, g, session, id, decision) async =>
          session.decide(i, g, id, decision),
      onReviewSaved: () => setState(() => revision++),
    ),
  ]);
}
