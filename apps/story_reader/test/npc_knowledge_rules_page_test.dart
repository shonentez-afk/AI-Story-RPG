import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/npc_knowledge_rulebook.dart';
import 'package:ai_story_reader/npc_knowledge_rules_page.dart';
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
  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;
  late SourceCharacterDossierIndex dossiers;
  late NpcEditorialNotebook notebook;
  late IntermediateStoryBlueprint scenario;
  late MemorySourceAnalysisCheckpointRepository store;

  setUp(() {
    index = BookSourceIndexer.index(const ImportedBook(
      title: 'Условия знаний NPC', author: 'Автор',
      chapters: [
        'Артем по прозвищу Волк открыл дверь. Дверь открыта.',
        'Мария по прозвищу Лиса увидела дом. Дверь закрыта.',
      ],
    ));
    final refs = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      refs.addAll(SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    graph = SourceEvidenceGraph.empty(index).addAll(index, refs);
    for (final ref in graph.records) {
      graph = graph.review(index, ref.id, EvidenceStatus.confirmed);
    }
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    editorial = SemanticEditorialReviewSession.create(index, catalog);
    final relations = SourceRelationReviewSession.create(index, graph);
    dossiers = SourceCharacterDossierIndex.build(
        index, graph, relations, catalog, editorial);
    final artem = dossiers.dossiers.firstWhere(
        (d) => d.labels.contains('Артем'));
    final initial = NpcEditorialNotebook.freshProfile(artem);
    notebook = NpcEditorialNotebook.empty(index).putProfile(
        NpcDraftProfile(
          dossierId: initial.dossierId, mentionIds: initial.mentionIds,
          displayName: initial.displayName,
          notes: const [
            NpcDraftNote(
              id: 'npc_note_1', field: NpcDraftField.secret,
              text: 'Мой авторский секрет',
            ),
          ],
        ),
    );
    scenario = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: index.title, entrySceneId: 'first',
      rights: PreparationRights.privateUse,
      flags: const [], initialFlags: const [],
      scenes: [
        DraftScene(
          id: 'first', chapterIndex: 0, text: 'Начало',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [], terminal: false,
          choices: [
            DraftChoice(id: 'wait', label: 'Выслушать NPC',
                nextSceneId: 'first'),
            DraftChoice(id: 'open', label: 'Открыть дверь',
                nextSceneId: 'end'),
          ],
        ),
        DraftScene(
          id: 'end', chapterIndex: 0, text: 'Финал',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [], terminal: true, choices: const [],
        ),
      ],
    );
    store = MemorySourceAnalysisCheckpointRepository();
  });

  Widget screen() => MaterialApp(home: NpcKnowledgeRulesPage(
    index: index, dossiers: dossiers, graph: graph,
    catalog: catalog, editorial: editorial, notebook: notebook,
    scenario: scenario, repository: store,
  ));

  testWidgets('authoring NPC rule persists and editing resumes', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), isNull);
    await tester.tap(find.byKey(const Key('knowledge-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-confirm')));
    await tester.pumpAndSettle();
    final raw = (await store.read(index.sourceFingerprint))!;
    final saved = NpcKnowledgeRulebook.decode(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook,
      scenario: scenario, raw: raw);
    expect(saved.rules.single.recipient, KnowledgeRecipient.ownerNpc);
    expect(saved.rules.single.playerApproval, false);
    expect(raw, isNot(contains('Мой авторский секрет')));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-rule-npc_rule_1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-edit-npc_rule_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-choice-select')), findsOneWidget);
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), raw);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialogue gate persists, reloads and cannot orphan its grant',
      (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('knowledge-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('knowledge-confirm')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('knowledge-gate-add')));
    await tester.tap(find.byKey(const Key('knowledge-gate-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-gate-grant')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-gate-choice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-gate-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Добавить условие к игровому выбору?'), findsOneWidget);
    await tester.tap(find.text('Подтвердить').last);
    await tester.pumpAndSettle();

    final raw = (await store.read(index.sourceFingerprint))!;
    final saved = NpcKnowledgeRulebook.decode(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook,
      scenario: scenario, raw: raw);
    expect(saved.rules.single.choiceId, 'wait');
    expect(saved.gates.single.choiceId, 'open');
    expect(saved.gates.single.grantRuleId, saved.rules.single.id);
    expect(raw, isNot(contains('Мой авторский секрет')));
    expect(find.byKey(const Key('knowledge-gate-npc_gate_1')), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(
        const Key('knowledge-gate-edit-npc_gate_1')));
    expect(find.byKey(const Key('knowledge-gate-npc_gate_1')), findsOneWidget);

    await tester.ensureVisible(find.byKey(
        const Key('knowledge-delete-npc_rule_1')));
    await tester.tap(find.byKey(const Key('knowledge-delete-npc_rule_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Не сохранено'), findsOneWidget);
    expect(await store.read(index.sourceFingerprint), raw);

    await tester.ensureVisible(find.byKey(
        const Key('knowledge-gate-delete-npc_gate_1')));
    await tester.tap(find.byKey(
        const Key('knowledge-gate-delete-npc_gate_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить').last);
    await tester.pumpAndSettle();
    final remaining = NpcKnowledgeRulebook.decode(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook,
      scenario: scenario,
      raw: (await store.read(index.sourceFingerprint))!);
    expect(remaining.gates, isEmpty);
    expect(remaining.rules.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player knowledge requires checkbox and explicit second approval',
      (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('knowledge-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('knowledge-recipient')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Игроку (с отдельным согласием)').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('knowledge-confirm'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('knowledge-player-approval')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('knowledge-confirm'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('knowledge-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Разрешить знание игроку?'), findsOneWidget);
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('write failure never creates false saved rule', (tester) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    store.failNextWrite = true;
    await tester.tap(find.byKey(const Key('knowledge-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('knowledge-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не сохранено'), findsOneWidget);
    expect(await store.read(index.sourceFingerprint), isNull);
    expect(find.byKey(const Key('knowledge-rule-npc_rule_1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corruption requires explicit two-step reset', (tester) async {
    await store.write(index.sourceFingerprint, '{"invalid":true}');
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), '{"invalid":true}');
    await tester.tap(find.byKey(const Key('knowledge-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить').last);
    await tester.pumpAndSettle();
    expect(await store.read(index.sourceFingerprint), isNull);
    expect(find.byKey(const Key('knowledge-add')), findsOneWidget);
  });

  testWidgets('narrow screen with large text renders editor safely',
      (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(640, 1280);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 640), textScaler: TextScaler.linear(2)),
      child: screen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('knowledge-add')));
    await tester.tap(find.byKey(const Key('knowledge-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('knowledge-confirm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
