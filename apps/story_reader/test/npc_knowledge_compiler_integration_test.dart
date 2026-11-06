import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/native_private_bookworld_compiler.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/multi_scene_draft_workbench.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/npc_character_card.dart';
import 'package:ai_story_reader/private_classic_scenario_translator.dart';
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

    // Complete source-locked NPC → rich-v3 → real runtime → replay pipeline.
    // A legacy citation-hash actor is valid in old v2, NOT in new rich NPC.
    final permanent = notebook.putProfile(
      notebook.profiles.single.copyWith(card: NpcCharacterCard.fresh()),
    );
    final translation = PrivateClassicScenarioTranslator.translate(
      index, graph, catalog, editorial, expanded,
      npcRules: gatedRules, npcNotebook: permanent, npcDossiers: dossiers,
    );
    final entryOrigin = (translation.provenanceJson['scene_origins'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((origin) => origin['scene_id'] == expandedEntry.id);
    final refs = entryOrigin['source_refs'] as List;
    final quote = (refs.first as Map)['quote_sha256'] as String;
    final bound = {'npc_rule_1': quote};
    Future<Uint8List> richBuild({
      required bool confirmed, required Map<String, String> quotes,
    }) => compileReviewedNpcRichPrivateBookworldInWorker(
      index, graph, catalog, editorial, expanded,
      npcRules: gatedRules, npcNotebook: permanent, npcDossiers: dossiers,
      sourceQuoteByRuleId: quotes, userConfirmed: confirmed,
    );
    await expectLater(
      richBuild(confirmed: false, quotes: bound), throwsFormatException,
    );
    await expectLater(
      richBuild(confirmed: true, quotes: {'npc_rule_1': List.filled(64, 'f').join()}),
      throwsFormatException,
    );
    await expectLater(
      richBuild(confirmed: true, quotes: const {}),
      throwsFormatException,
    );
    final richBytes = await richBuild(confirmed: true, quotes: bound);
    final checked = const RichPrivateBookworldImporter().inspect(richBytes);
    expect(checked.blueprint.actors, contains(permanent.profiles.single.characterId));
    final richActor = permanent.profiles.single.characterId!;
    final richWorld = StoryWorld(checked.blueprint);
    expect(richWorld.actorKnowsFact(richActor,
        checked.blueprint.facts.single), false);
    expect(richWorld.apply(
      actionId: 'rich_before_meeting',
      choiceId: expandedEntry.choices.first.id).applied, false);
    expect(richWorld.apply(
      actionId: 'rich_talk', choiceId: learnChoice.id).applied, true);
    expect(richWorld.actorKnowsFact(
        richActor, checked.blueprint.facts.single), true);
    expect(richWorld.actorKnowsFact(
        'player', checked.blueprint.facts.single), false);
    expect(richWorld.apply(
      actionId: 'rich_after_meeting',
      choiceId: expandedEntry.choices.first.id).applied, true);
    final replay = StoryWorld.replay(
      checked.blueprint,
      richWorld.events.map((event) => event.toJson()),
      expectedSequence: richWorld.state.revision,
      expectedStateHash: richWorld.state.stateHash,
    );
    expect(replay.state.stateHash, richWorld.state.stateHash);
    expect(replay.factLearningEvents(
        richActor, checked.blueprint.facts.single).single.actionId,
        'rich_talk');
    final text = utf8.decode(richBytes, allowMalformed: true);
    expect(text, isNot(contains(note.text)));
  });
}
