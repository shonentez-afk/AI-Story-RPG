import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/npc_editorial_page.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const book = ImportedBook(
    title: 'Роли и секреты', author: 'Автор',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. Дверь была открыта.',
      'Мария по прозвищу Лиса увидела дом. Дверь была закрыта.',
      'Артем встретил Мария.',
    ],
  );
  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceRelationReviewSession relations;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;
  late SourceCharacterDossierIndex dossiers;
  late SourceCharacterDossier artem;
  late MemorySourceAnalysisCheckpointRepository relationStore;
  late MemorySourceAnalysisCheckpointRepository noteStore;
  late MemorySourceAnalysisCheckpointRepository multiStore;

  setUp(() {
    index = BookSourceIndexer.index(book);
    final evidence = <SourceEvidence>[];
    for (final part in index.chunks) {
      evidence.addAll(SourceNarrativeExtractor.extractChunk(index, part));
    }
    graph = SourceEvidenceGraph.empty(index).addAll(index, evidence);
    for (final source in graph.records) {
      graph = graph.review(index, source.id, EvidenceStatus.confirmed);
    }
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    editorial = SemanticEditorialReviewSession.create(index, catalog);
    relations = SourceRelationReviewSession.create(index, graph);
    dossiers = SourceCharacterDossierIndex.build(index, graph,
        relations, catalog, editorial);
    artem = dossiers.dossiers.firstWhere((d) => d.labels.contains('Артем'));
    relationStore = MemorySourceAnalysisCheckpointRepository();
    noteStore = MemorySourceAnalysisCheckpointRepository();
    multiStore = MemorySourceAnalysisCheckpointRepository();
  });

  Widget screen() => MaterialApp(home: NpcEditorialPage(
    index: index, graph: graph, catalog: catalog, editorial: editorial,
    relationsRepository: relationStore,
    notebookRepository: noteStore,
    multiDraftRepository: multiStore,
    sessionBuilder: (i, g) async => SourceRelationReviewSession.create(i, g),
    sessionDecoder: (i, g, raw) async =>
        SourceRelationReviewSession.decode(i, g, raw),
    dossierBuilder: (i, g, r, c, e) async =>
        SourceCharacterDossierIndex.build(i, g, r, c, e),
  ));

  Future<void> selectArtem(WidgetTester tester) async {
    final finder = find.byKey(Key('npc-select-${artem.id}'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('npc-create-profile')), findsOneWidget);
  }

  Future<void> saveProfile(WidgetTester tester) async {
    await selectArtem(tester);
    await tester.ensureVisible(find.byKey(const Key('npc-create-profile')));
    await tester.tap(find.byKey(const Key('npc-create-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('npc-name-input')), 'Артем в моей адаптации');
    await tester.tap(find.byKey(const Key('npc-confirm-name')));
    await tester.pumpAndSettle();
  }

  testWidgets('profile and role save privately and resume on reopening',
      (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.textContaining('ИИ выключен'), findsOneWidget);
    expect(await noteStore.read(index.sourceFingerprint), isNull);
    await saveProfile(tester);
    expect(find.text('Имя адаптации: Артем в моей адаптации'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('npc-add-note')));
    await tester.tap(find.byKey(const Key('npc-add-note')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('npc-note-text')),
        'Охраняет дверь в альтернативной версии');
    await tester.tap(find.byKey(const Key('npc-note-confirm')));
    await tester.pumpAndSettle();
    final saved = NpcEditorialNotebook.decode(index, dossiers, graph, catalog,
        editorial, (await noteStore.read(index.sourceFingerprint))!);
    expect(saved.profiles.single.notes.single.field, NpcDraftField.role);
    expect(saved.profiles.single.notes.single.isAuthorial, true);
    expect(saved.profiles.single.displayName, 'Артем в моей адаптации');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(Key('npc-select-${artem.id}')));
    await tester.tap(find.byKey(Key('npc-select-${artem.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Охраняет дверь в альтернативной версии'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed write does not publish optimistic NPC profile',
      (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    noteStore.failNextWrite = true;
    await selectArtem(tester);
    await tester.ensureVisible(find.byKey(const Key('npc-create-profile')));
    await tester.tap(find.byKey(const Key('npc-create-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('npc-confirm-name')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Изменение не сохранено'), findsOneWidget);
    expect(await noteStore.read(index.sourceFingerprint), isNull);
    expect(find.byKey(const Key('npc-create-profile')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale SAME decision blocks old NPC edits without erasing data',
      (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await saveProfile(tester);
    final raw = (await noteStore.read(index.sourceFingerprint))!;
    final alias = relations.hints.firstWhere((edge) =>
        edge.kind == IdentityHintKind.explicitAlias &&
        (edge.firstId == artem.id || edge.secondId == artem.id));
    final decided = relations.decide(
        index, graph, alias.id, IdentityDecision.same);
    await relationStore.write(index.sourceFingerprint, decided.encode());
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.textContaining('Редактор NPC заблокирован'), findsOneWidget);
    expect(find.byKey(const Key('npc-create-profile')), findsNothing);
    expect(await noteStore.read(index.sourceFingerprint), raw);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt record stays intact until explicit confirmed reset',
      (tester) async {
    await noteStore.write(index.sourceFingerprint, '{"invalid":true}');
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('npc-retry-load')), findsOneWidget);
    expect(find.textContaining('Редактор NPC заблокирован'), findsOneWidget);
    await tester.tap(find.byKey(const Key('npc-reset-only')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await noteStore.read(index.sourceFingerprint), '{"invalid":true}');
    await tester.tap(find.byKey(const Key('npc-reset-only')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await tester.pumpAndSettle();
    expect(await noteStore.read(index.sourceFingerprint), isNull);
    expect(find.byKey(const Key('npc-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('broken independent scene draft warns without erasing NPC',
      (tester) async {
    final initial = NpcEditorialNotebook.empty(index).putProfile(
        NpcEditorialNotebook.freshProfile(artem));
    final raw = initial.encode();
    await noteStore.write(index.sourceFingerprint, raw);
    await multiStore.write(index.sourceFingerprint, '{"broken":true}');
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('npc-search')), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const Key('npc-continuity-panel')));
    await tester.tap(find.byKey(const Key('npc-continuity-panel')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Черновик сцен не проверен'), findsOneWidget);
    expect(await noteStore.read(index.sourceFingerprint), raw);
    expect(await multiStore.read(index.sourceFingerprint), '{"broken":true}');
    expect(tester.takeException(), isNull);
  });

}
