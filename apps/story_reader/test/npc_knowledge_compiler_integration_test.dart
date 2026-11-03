import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/native_private_bookworld_compiler.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/multi_scene_draft_workbench.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/npc_knowledge_rulebook.dart';
import 'package:ai_story_reader/reviewed_story_composer.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('original compiler and opt-in NPC build produce separate safe worlds',
      () async {
    const book = ImportedBook(
      title: 'Дверь и Волк', author: 'Автор',
      chapters: [
        'Артем по прозвищу Волк открыл дверь. Дверь была закрыта.',
        'Артем встретил Марию. Дверь была открыта.',
      ],
    );
    final index = BookSourceIndexer.index(book);
    var review = StoryEvidenceReviewSession.create(index);
    while (review.scannedChunks < index.chunks.length) {
      review = review.scanNext(index);
    }
    for (final e in review.graph.records) {
      review = review.review(index, e.id, EvidenceStatus.confirmed);
    }
    final graph = review.graph;
    final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    final claims = catalog.assertions.where(
        (c) => c.kind == SemanticAssertionKind.event).toList();
    final byId = {for (final e in graph.records) e.id: e};
    final first = claims.firstWhere(
        (c) => byId[c.evidenceIds.first]!.chapterIndex == 0);
    final last = claims.firstWhere(
        (c) => byId[c.evidenceIds.first]!.chapterIndex == 1);
    final editorial = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, first.id, SemanticEditorialVerdict.canonCandidate)
        .decide(catalog, last.id, SemanticEditorialVerdict.canonCandidate);
    final scenario = ReviewedStoryComposer.compose(
      index: index, evidence: graph, catalog: catalog,
      editorial: editorial, openingAssertionId: first.id,
      endingAssertionId: last.id,
      openingText: 'Игрок стоит у запертой двери.',
      endingText: 'Игрок встречает друга.',
      alternateEndingText: 'Игрок уходит другой дорогой.',
      followBookChoice: 'Продолжить путь',
      changeFateChoice: 'Повернуть назад',
    );
    final relations = SourceRelationReviewSession.create(index, graph);
    final dossiers = SourceCharacterDossierIndex.build(
        index, graph, relations, catalog, editorial);
    final artem = dossiers.dossiers.firstWhere(
        (d) => d.labels.contains('Артем'));
    final profile = NpcEditorialNotebook.freshProfile(artem);
    const note = NpcDraftNote(
      id: 'npc_note_1', field: NpcDraftField.secret,
      text: 'Мой придуманный секрет, не принадлежащий оригиналу',
    );
    final notebook = NpcEditorialNotebook.empty(index).putProfile(
      NpcDraftProfile(
        dossierId: profile.dossierId, mentionIds: profile.mentionIds,
        displayName: profile.displayName, notes: const [note]),
    );
    final entry = scenario.scenes.first;
    final rule = NpcKnowledgeRulebook.compose(
      id: 'npc_rule_1', index: index, dossier: artem, note: note,
      scene: entry, choice: entry.choices.first,
      recipient: KnowledgeRecipient.player, playerApproval: true,
    );
    final rules = NpcKnowledgeRulebook.empty(index).withRule(rule);

    final originalBytes = await compileReviewedPrivateBookworldInWorker(
        index, graph, catalog, editorial, scenario);
    final privateBytes = await compileReviewedPrivateBookworldInWorker(
        index, graph, catalog, editorial, scenario,
        npcRules: rules, npcNotebook: notebook, npcDossiers: dossiers);
    final importer = const PrivateBookworldImporter();
    final original = importer.inspect(originalBytes);
    final enriched = importer.inspect(privateBytes);
    expect(original.blueprint.actors, {'player'});
    expect(original.blueprint.facts, isEmpty);
    expect(enriched.blueprint.actors.length, 2);
    expect(enriched.blueprint.facts.length, 1);
    expect(original.blueprint.bookId, isNot(enriched.blueprint.bookId));
    expect(original.blueprint.blueprintHash,
        isNot(enriched.blueprint.blueprintHash));
    expect(enriched.sourceFingerprint, index.sourceFingerprint);
    expect(utf8.decode(privateBytes, allowMalformed: true),
        isNot(contains(note.text)));
    final world = StoryWorld(enriched.blueprint);
    expect(world.state.knowledge['player'], isEmpty);
    expect(world.apply(
      actionId: 'confirmed', choiceId: entry.choices.first.id,
      expectedRevision: 0).applied, true);
    expect(world.state.knowledge['player'], containsAll(
        enriched.blueprint.facts));
    expect(world.state.knowledge[NpcKnowledgeRulebook.actorId(
        artem, index.sourceFingerprint)], isEmpty);

    // An explicit choice can grant knowledge before another choice checks it.
    // Build and re-import the actual ZIP/SQLite package, not only a preview.
    var expanded = MultiSceneDraftWorkbench.addChoice(
        scenario, entry.id, entry.id);
    final newChoice = expanded.scenes.first.choices.last;
    expanded = MultiSceneDraftWorkbench.replaceChoice(
      expanded, entry.id,
      DraftChoice(id: newChoice.id, label: 'Сначала поговорить с Артемом',
          nextSceneId: entry.id),
    );
    final expandedEntry = expanded.scenes.first;
    final learnChoice = expandedEntry.choices.last;
    final grant = NpcKnowledgeRulebook.compose(
      id: 'npc_rule_1', index: index, dossier: artem, note: note,
      scene: expandedEntry, choice: learnChoice,
      recipient: KnowledgeRecipient.ownerNpc, playerApproval: false,
    );
    final gate = NpcKnowledgeRulebook.composeGate(
      id: 'npc_gate_1', grant: grant, scene: expandedEntry,
      choice: expandedEntry.choices.first,
    );
    final gatedRules = NpcKnowledgeRulebook.empty(index)
        .withRule(grant).withGate(gate);
    final gatedBytes = await compileReviewedPrivateBookworldInWorker(
        index, graph, catalog, editorial, expanded,
        npcRules: gatedRules, npcNotebook: notebook, npcDossiers: dossiers);
    final gated = importer.inspect(gatedBytes);
    expect(gated.blueprint.bookId, isNot(enriched.blueprint.bookId));
    final gatedWorld = StoryWorld(gated.blueprint);
    final locked = gatedWorld.apply(
        actionId: 'before_meeting', choiceId: expandedEntry.choices.first.id);
    expect(locked.applied, isFalse);
    expect(gatedWorld.events, isEmpty);
    expect(gatedWorld.apply(
        actionId: 'talk', choiceId: learnChoice.id).applied, isTrue);
    expect(gatedWorld.apply(
        actionId: 'after_meeting', choiceId: expandedEntry.choices.first.id)
        .applied, isTrue);
    expect(gatedWorld.isTerminal, isTrue);
    expect(utf8.decode(gatedBytes, allowMalformed: true),
        isNot(contains(note.text)));
  });
}
