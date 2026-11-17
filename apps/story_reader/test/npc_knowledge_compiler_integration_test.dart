import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:campaign_manager/campaign_manager.dart';

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
    final sqliteDirectory = Directory.systemTemp
        .createTempSync('npc_rich_campaign_acceptance_');
    try {
      late String campaignId;
      final firstStore = BookworldCampaignStore.openPrivateDirectory(
          sqliteDirectory.path);
      try {
        final installed = firstStore.installBookworld(richBytes);
        campaignId = firstStore.createCampaign(installed.archiveHash);
        final blockedSqlite = firstStore.commitChoice(
          campaignId, actionId: 'sqlite_blocked',
          choiceId: expandedEntry.choices.first.id, expectedRevision: 0);
        expect(blockedSqlite.applied, false);
        expect(firstStore.loadCampaign(campaignId).coordinator.state.revision, 0);
        final npcLearned = firstStore.commitChoice(
          campaignId, actionId: 'sqlite_npc_learned',
          choiceId: learnChoice.id, expectedRevision: 0);
        expect(npcLearned.applied, true);
        final saved = firstStore.loadCampaign(campaignId);
        expect(saved.coordinator.state.knowledge[richActor],
            contains(checked.blueprint.facts.single));
        expect(saved.coordinator.state.knowledge['player'], isEmpty);
      } finally {
        firstStore.close();
      }
      // This is a real SQLite close/reopen, not only StoryWorld.replay.
      final reopened = BookworldCampaignStore.openPrivateDirectory(
          sqliteDirectory.path);
      try {
        final restored = reopened.loadCampaign(campaignId);
        expect(restored.coordinator.state.revision, 1);
        expect(restored.coordinator.state.knowledge[richActor],
            contains(checked.blueprint.facts.single));
        expect(reopened.commitChoice(
          campaignId, actionId: 'sqlite_after_restart',
          choiceId: expandedEntry.choices.first.id,
          expectedRevision: 1).applied, true);
        expect(reopened.loadCampaign(campaignId).coordinator.state.revision, 2);
        expect(reopened.exportPortable(campaignId), isNotEmpty);
      } finally {
        reopened.close();
      }
    } finally {
      sqliteDirectory.deleteSync(recursive: true);
    }
    // The NORMAL book -> approved NPC -> rich-v3 pipeline now authors
    // actual typed book items, not just importing a prebuilt .bworld.
    var itemScenario = expanded;
    final itemChoiceIds = <String>[];
    for (final label in [
      'Взять найденный ключ',
      'Передать ключ Артему',
      'Получить ключ обратно',
    ]) {
      itemScenario = MultiSceneDraftWorkbench.addChoice(
          itemScenario, entry.id, entry.id);
      final added = itemScenario.scenes.first.choices.last;
      itemChoiceIds.add(added.id);
      itemScenario = MultiSceneDraftWorkbench.replaceChoice(
        itemScenario, entry.id,
        DraftChoice(id: added.id, label: label,
            nextSceneId: entry.id),
      );
    }
    final itemReview = <Map<String, dynamic>>[
      {
        'item_name': 'Ключ',
        'item_description': 'Найден у двери в первой главе',
        'actor_id': richActor,
        'acquire_choice_id': itemChoiceIds[0],
        'acquire_quote_sha256': quote,
        'give_choice_id': itemChoiceIds[1],
        'give_quote_sha256': quote,
        'return_choice_id': itemChoiceIds[2],
        'return_quote_sha256': quote,
        'personally_witnessed': true,
      },
    ];
    final itemBytes = await compileReviewedNpcRichPrivateBookworldInWorker(
      index, graph, catalog, editorial, itemScenario,
      npcRules: gatedRules, npcNotebook: permanent, npcDossiers: dossiers,
      sourceQuoteByRuleId: bound, userConfirmed: true,
      reviewedBookItems: itemReview,
    );
    final itemGame = const RichPrivateBookworldImporter().inspect(itemBytes);
    expect(itemGame.npcSocialRulebook, isNotNull);
    expect(itemGame.npcSocialRulebook!.itemTransfers, hasLength(2));
    expect(itemGame.blueprint.items, hasLength(1));
    expect(itemGame.blueprint.bookId, isNot(checked.blueprint.bookId));
    final itemId = itemGame.blueprint.items.single;
    expect((itemGame.presentation['item_names'] as Map)[itemId], 'Ключ');
    final itemWorld = StoryWorld(itemGame.blueprint,
        socialRulebook: itemGame.npcSocialRulebook);
    expect(itemWorld.apply(actionId: 'phantom', choiceId: itemChoiceIds[2])
        .applied, false);
    expect(itemWorld.apply(actionId: 'acquire', choiceId: itemChoiceIds[0])
        .applied, true);
    expect(itemWorld.apply(actionId: 'gift', choiceId: itemChoiceIds[1])
        .applied, true);
    expect(NpcSocialLedger.inspect(itemWorld, itemGame.npcSocialRulebook!)
        .itemOwner(itemId), richActor);
    expect(itemWorld.apply(actionId: 'counterfeit',
        choiceId: itemChoiceIds[0]).applied, false);
    final itemDir = Directory.systemTemp.createTempSync('book_item_native_');
    try {
      final store = BookworldCampaignStore.openPrivateDirectory(itemDir.path);
      late String itemCampaign;
      try {
        final installed = store.installBookworld(itemBytes);
        itemCampaign = store.createCampaign(installed.archiveHash);
        expect(store.commitChoice(itemCampaign,
            actionId: 'get_item', choiceId: itemChoiceIds[0],
            expectedRevision: 0).applied, true);
        expect(store.commitChoice(itemCampaign,
            actionId: 'give_item', choiceId: itemChoiceIds[1],
            expectedRevision: 1).applied, true);
      } finally {
        store.close();
      }
      final reopened = BookworldCampaignStore.openPrivateDirectory(
          itemDir.path);
      try {
        final campaign = reopened.loadCampaign(itemCampaign);
        final replay = StoryWorld.replay(itemGame.blueprint,
            campaign.coordinator.events.map((e) => e.toJson()),
            expectedSequence: campaign.coordinator.state.revision,
            expectedStateHash: campaign.coordinator.state.stateHash,
            socialRulebook: itemGame.npcSocialRulebook);
        expect(NpcSocialLedger.inspect(replay, itemGame.npcSocialRulebook!)
            .itemOwner(itemId), richActor);
        expect(reopened.commitChoice(itemCampaign,
            actionId: 'get_back', choiceId: itemChoiceIds[2],
            expectedRevision: 2).applied, true);
      } finally {
        reopened.close();
      }
    } finally {
      itemDir.deleteSync(recursive: true);
    }
    expect(utf8.decode(itemBytes, allowMalformed: true),
        isNot(contains(note.text)));

    // Real application path, not only a low-level importer fixture:
    // the reviewed prose is mapped to permanent character IDs, exact
    // learning events and author-approved dialogue turns, then compiled by
    // the SAME private native writer/SQLite/runtime pipeline.
    final dialogueEndId = expandedEntry.choices.first.nextSceneId;
    final dialogueEnd = expanded.scenes.singleWhere(
        (scene) => scene.id == dialogueEndId);
    final dialogueDraft = MultiSceneDraftWorkbench.replaceScene(
      expanded,
      MultiSceneDraftWorkbench.sceneCopy(dialogueEnd,
        text: 'Артем: «Я услышал твой рассказ.»\n'
            'Игрок: «Что ты теперь знаешь?»'),
    );
    final dialogueTranslation = PrivateClassicScenarioTranslator.translate(
      index, graph, catalog, editorial, dialogueDraft,
      npcRules: gatedRules, npcNotebook: permanent, npcDossiers: dossiers,
    );
    final dialogueBlueprint =
        StoryBlueprint.fromJson(dialogueTranslation.blueprintJson);
    final dialogueOrigins = <String, dynamic>{
      for (final origin in
          dialogueTranslation.provenanceJson['scene_origins'] as List)
        (origin as Map)['scene_id'] as String: origin,
    };
    final dialogueFact = dialogueBlueprint.facts.single;
    final names = {'Артем': richActor, 'Игрок': 'player'};
    final plannedDialogue = RichNpcDialogueAuthoring.propose(
      blueprint: dialogueBlueprint,
      sceneOrigins: dialogueOrigins,
      reviewedSpeakerActorIds: names,
      verifiedNpcFactGrants: [
        {
          'scene_id': expandedEntry.id,
          'choice_id': learnChoice.id,
          'actor_id': richActor,
          'fact_id': dialogueFact,
          'source_quote_sha256': quote,
        },
      ],
      reviewedNpcFactByTurn: {
        dialogueEndId: {0: dialogueFact},
      },
      reviewedSafeNpcTurns: const {},
      wholeDialogueTextReviewed: true,
      privateFictionAcknowledged: true,
    );
    Future<Uint8List> dialogueBuild(String digest) =>
        compileReviewedNpcRichPrivateBookworldInWorker(
      index, graph, catalog, editorial, dialogueDraft,
      npcRules: gatedRules, npcNotebook: permanent, npcDossiers: dossiers,
      sourceQuoteByRuleId: bound, userConfirmed: true,
      reviewedSpeakerBindings: names,
      reviewedDialogueProposal: plannedDialogue,
      approvedDialogueDigest: digest,
    );
    await expectLater(dialogueBuild(List.filled(64, '0').join()),
        throwsFormatException);
    final dialogueBytes = await dialogueBuild(plannedDialogue.approvalDigest);
    final dialogueWorld =
        const RichPrivateBookworldImporter().inspect(dialogueBytes);
    final dialogueScreen = RichSceneDialogue.verify(
      (dialogueWorld.presentation['scene_dialogues'] as Map)[dialogueEndId],
      dialogueWorld.blueprint.scenes[dialogueEndId]!.text,
    );
    final dialogueReviews =
        (dialogueWorld.presentation['scene_dialogue_knowledge'] as Map)
        [dialogueEndId] as List;
    final learnedDialogue = StoryWorld(dialogueWorld.blueprint);
    expect(learnedDialogue.apply(
        actionId: 'npc_learn_dialogue', choiceId: learnChoice.id).applied, true);
    expect(learnedDialogue.apply(
        actionId: 'enter_dialogue',
        choiceId: expandedEntry.choices.first.id).applied, true);
    expect(RichNpcDialogueKnowledge.redact(
      dialogueScreen, dialogueReviews, learnedDialogue.state.knowledge,
      committedEvents: learnedDialogue.events,
      sceneId: dialogueEndId,
    ).first.text, 'Я услышал твой рассказ.');
    final refusedDialogue = StoryWorld(dialogueWorld.blueprint);
    expect(refusedDialogue.apply(
        actionId: 'skip_npc',
        choiceId: expandedEntry.choices.first.id).applied, false);
    expect(refusedDialogue.state.knowledge[richActor], isEmpty);

    final text = utf8.decode(richBytes, allowMalformed: true);
    expect(text, isNot(contains(note.text)));
  });
}
