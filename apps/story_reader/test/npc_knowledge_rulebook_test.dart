import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/npc_knowledge_rulebook.dart';
import 'package:ai_story_reader/npc_knowledge_world_bridge.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:story_core/story_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const novel = ImportedBook(
    title: 'Знание и тайна', author: 'Автор',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. Дверь была открыта.',
      'Мария по прозвищу Лиса увидела дом. Дверь была закрыта.',
      'Артем встретил Мария. Волк увидел Лиса.',
    ],
  );
  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;
  late SourceRelationReviewSession relations;
  late SourceCharacterDossierIndex dossiers;
  late SourceCharacterDossier artem;
  late NpcDraftNote secret;
  late NpcEditorialNotebook notebook;
  late IntermediateStoryBlueprint draft;

  setUp(() {
    index = BookSourceIndexer.index(novel);
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
    relations = SourceRelationReviewSession.create(index, graph);
    dossiers = SourceCharacterDossierIndex.build(
        index, graph, relations, catalog, editorial);
    artem = dossiers.dossiers.firstWhere(
        (d) => d.labels.contains('Артем'));
    secret = const NpcDraftNote(
      id: 'npc_note_1', field: NpcDraftField.secret,
      text: 'Знание, которого нет в оригинальном сценарии',
    );
    final profile = NpcEditorialNotebook.freshProfile(artem);
    notebook = NpcEditorialNotebook.empty(index).putProfile(
      NpcDraftProfile(
        dossierId: profile.dossierId, mentionIds: profile.mentionIds,
        displayName: 'Артем, авторская версия', notes: [secret],
      ),
    );
    draft = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint, title: index.title,
      entrySceneId: 'entry', rights: PreparationRights.privateUse,
      flags: const [], initialFlags: const [], scenes: [
        DraftScene(
          id: 'entry', chapterIndex: 0, text: 'Решение у ворот',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [], terminal: false,
          choices: [
            DraftChoice(id: 'repeat', label: 'Слушать снова',
                nextSceneId: 'entry'),
            DraftChoice(id: 'end_now', label: 'Покинуть ворота',
                nextSceneId: 'ending'),
          ],
        ),
        DraftScene(
          id: 'ending', chapterIndex: 0, text: 'Тихая развязка',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [], terminal: true, choices: const [],
        ),
      ],
    );
  });

  NpcKnowledgeRule makeRule({
    String id = 'npc_rule_1',
    String choiceId = 'repeat',
    KnowledgeRecipient recipient = KnowledgeRecipient.ownerNpc,
    bool approved = false,
  }) {
    final scene = draft.scenes.first;
    final choice = scene.choices.singleWhere((c) => c.id == choiceId);
    return NpcKnowledgeRulebook.compose(
      id: id, index: index, dossier: artem, note: secret,
      scene: scene, choice: choice,
      recipient: recipient, playerApproval: approved);
  }

  void check(NpcKnowledgeRulebook book) => book.validate(
    index: index, dossiers: dossiers, graph: graph,
    catalog: catalog, editorial: editorial,
    notebook: notebook, scenario: draft);

  Map<String, dynamic> base() => {
    'format': 'ai_story_blueprint_v1',
    'schema_version': 1,
    'book_id': 'book_private_test',
    'title': index.title,
    'entry_scene_id': 'entry',
    'rights_status': 'private_adaptation',
    'source_fingerprint': index.sourceFingerprint,
    'supported_modes': {
      'roles': ['PROTAGONIST'],
      'plots': ['ALTER_FATE'],
      'interactions': ['CLASSIC'],
    },
    'items': <String>[], 'facts': <String>[], 'actors': ['player'],
    'initial_state': {
      'scene_id': 'entry', 'revision': 0, 'tick': 0,
      'stats': <String, int>{}, 'inventory': <String>[],
      'flags': <String, bool>{}, 'knowledge': {'player': <String>[]},
    },
    'scenes': [
      {
        'id': 'entry', 'text': 'Решение у ворот',
        'terminal': false,
        'choices': [
          {
            'id': 'repeat', 'label': 'Слушать снова',
            'next_scene_id': 'entry',
            'conditions': <Object>[], 'effects': <Object>[],
          },
          {
            'id': 'end_now', 'label': 'Покинуть ворота',
            'next_scene_id': 'ending',
            'conditions': <Object>[], 'effects': <Object>[],
          },
        ],
      },
      {
        'id': 'ending', 'text': 'Тихая развязка',
        'terminal': true, 'choices': <Object>[],
      },
    ],
  };

  test('empty rules remain inert and standalone checkpoints roundtrip', () {
    final empty = NpcKnowledgeRulebook.empty(index);
    check(empty);
    expect(empty.rules, isEmpty);
    final saved = empty.withRule(makeRule());
    check(saved);
    final raw = saved.encode();
    final restored = NpcKnowledgeRulebook.decode(
      index: index, dossiers: dossiers, graph: graph,
      catalog: catalog, editorial: editorial, notebook: notebook,
      scenario: draft, raw: raw);
    expect(restored.encode(), raw);
    expect(restored.rules.single.recipient, KnowledgeRecipient.ownerNpc);
    expect(restored.nextRuleId(), 'npc_rule_2');
    expect(restored.withoutRule('npc_rule_1').rules, isEmpty);
    expect(saved.canSendToCloud, false);
  });

  test('owner learns opaque fact only after selected action', () {
    final rules = NpcKnowledgeRulebook.empty(index)
        .withRule(makeRule());
    final baseBlueprint = base();
    final unchanged = jsonEncode(baseBlueprint);
    final applied = NpcKnowledgeWorldBridge.preview(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook, scenario: draft,
      rulebook: rules, originalBlueprint: baseBlueprint,
    );
    expect(jsonEncode(baseBlueprint), unchanged);
    expect(applied.story.facts.length, 1);
    expect(applied.story.actors, contains('player'));
    expect(applied.story.actors.length, 2);
    expect(applied.story.bookId, isNot('book_private_test'));
    expect(jsonEncode(applied.blueprint), isNot(contains(secret.text)));
    expect(applied.containsOriginalNoteText, false);
    final world = StoryWorld(applied.story);
    final actor = applied.actorIds[artem.id]!;
    final fact = applied.factIds['${artem.id}|${secret.id}']!;
    expect(world.state.knowledge[actor], isEmpty);
    final result = world.apply(
      actionId: 'first', choiceId: 'repeat', expectedRevision: 0);
    expect(result.applied, true);
    expect(world.state.knowledge[actor], contains(fact));
    expect(world.state.knowledge['player'], isEmpty);
    expect(world.state.revision, 1);
  });

  test('explicit separate player consent is compulsory, not AI generated', () {
    final unapproved = NpcKnowledgeRulebook.empty(index).withRule(
      makeRule(recipient: KnowledgeRecipient.player));
    expect(() => check(unapproved), throwsFormatException);
    final approved = NpcKnowledgeRulebook.empty(index).withRule(
      makeRule(recipient: KnowledgeRecipient.player, approved: true));
    check(approved);
    final compiled = NpcKnowledgeWorldBridge.preview(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook, scenario: draft,
      rulebook: approved, originalBlueprint: base());
    final player = StoryWorld(compiled.story);
    final fact = compiled.factIds['${artem.id}|${secret.id}']!;
    expect(player.state.knowledge['player'], isEmpty);
    expect(player.apply(actionId: 'pick', choiceId: 'repeat').applied, true);
    expect(player.state.knowledge['player'], contains(fact));
    expect(jsonEncode(compiled.blueprint), isNot(contains(secret.text)));
  });

  test('135 moves replay exactly, checkpoint hash and NPC knowledge isolated',
      () {
    final rules = NpcKnowledgeRulebook.empty(index).withRule(makeRule());
    final worldData = NpcKnowledgeWorldBridge.preview(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook, scenario: draft,
      rulebook: rules, originalBlueprint: base());
    final world = StoryWorld(worldData.story);
    for (var i = 0; i < 134; i++) {
      final result = world.apply(
        actionId: 'step_$i', choiceId: 'repeat',
        expectedRevision: i);
      expect(result.applied, true, reason: 'step $i');
    }
    final finish = world.apply(
        actionId: 'finish', choiceId: 'end_now', expectedRevision: 134);
    expect(finish.applied, true);
    expect(world.isTerminal, true);
    expect(world.events.length, 135);
    final savedEvents = jsonDecode(jsonEncode([
      for (final event in world.events) event.toJson(),
    ])) as List;
    final replayed = StoryWorld.replay(
      worldData.story, savedEvents,
      expectedSequence: 135, expectedStateHash: world.state.stateHash);
    expect(replayed.state.stateHash, world.state.stateHash);
    expect(replayed.state.knowledge, world.state.knowledge);
    expect(replayed.state.knowledge['player'], isEmpty);
    expect(replayed.events.last.hash, world.events.last.hash);
    final tampered = jsonDecode(jsonEncode(savedEvents)) as List;
    (tampered[35] as Map)['choice_id'] = 'end_now';
    expect(() => StoryWorld.replay(worldData.story, tampered,
        expectedSequence: 135, expectedStateHash: world.state.stateHash),
        throwsFormatException);
  });

  test('source/group edits, moved choices and changed secret fail closed', () {
    final original = NpcKnowledgeRulebook.empty(index).withRule(makeRule());
    final movedDraft = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint, title: draft.title,
      entrySceneId: 'entry', rights: PreparationRights.privateUse,
      flags: const [], initialFlags: const [],
      scenes: [
        DraftScene(id: 'entry', chapterIndex: 1, text: 'Новая редакция',
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [], terminal: false,
          choices: draft.scenes.first.choices),
        draft.scenes.last,
      ]);
    expect(() => original.validate(
      index: index, dossiers: dossiers, graph: graph,
      catalog: catalog, editorial: editorial,
      notebook: notebook, scenario: movedDraft), throwsFormatException);
    final profile = notebook.profiles.single;
    final changed = NpcEditorialNotebook.empty(index).putProfile(
      NpcDraftProfile(
        dossierId: profile.dossierId,
        mentionIds: profile.mentionIds,
        displayName: profile.displayName,
        notes: const [NpcDraftNote(
          id: 'npc_note_1', field: NpcDraftField.secret,
          text: 'Другой секрет после редактирования',
        )],
      ));
    expect(() => original.validate(
      index: index, dossiers: dossiers, graph: graph,
      catalog: catalog, editorial: editorial,
      notebook: changed, scenario: draft), throwsFormatException);
    final alias = relations.hints.firstWhere((r) =>
        r.kind == IdentityHintKind.explicitAlias &&
        (r.firstId == artem.id || r.secondId == artem.id));
    final merged = SourceCharacterDossierIndex.build(index, graph,
      relations.decide(index, graph, alias.id, IdentityDecision.same),
      catalog, editorial);
    expect(() => original.validate(
      index: index, dossiers: merged, graph: graph,
      catalog: catalog, editorial: editorial,
      notebook: notebook, scenario: draft), throwsFormatException);
  });

  test('corrupt approval, digest and other edition cannot load', () {
    final saved = NpcKnowledgeRulebook.empty(index)
        .withRule(makeRule()).encode();
    expect(() => NpcKnowledgeRulebook.decode(
        index: index, dossiers: dossiers, graph: graph,
        catalog: catalog, editorial: editorial, notebook: notebook,
        scenario: draft,
        raw: saved.replaceFirst('"player_approval":false',
            '"player_approval":true')), throwsFormatException);
    expect(() => NpcKnowledgeRulebook.decode(
        index: index, dossiers: dossiers, graph: graph,
        catalog: catalog, editorial: editorial, notebook: notebook,
        scenario: draft, raw: saved.replaceFirst('npc_rule_1', 'npc_rule_9')),
        throwsFormatException);
    final other = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая книга', author: 'Автор', chapters: ['Чужой текст.']));
    expect(() => NpcKnowledgeRulebook.decode(
        index: other, dossiers: dossiers, graph: graph,
        catalog: catalog, editorial: editorial, notebook: notebook,
        scenario: draft, raw: saved), throwsFormatException);
  });

  test('v2 condition waits for the exact actor to learn a reviewed fact', () {
    final grant = makeRule();
    final scene = draft.scenes.first;
    final target = scene.choices.singleWhere((choice) => choice.id == 'end_now');
    final gate = NpcKnowledgeRulebook.composeGate(
      id: 'npc_gate_1', grant: grant, scene: scene, choice: target);
    final authored = NpcKnowledgeRulebook.empty(index)
        .withRule(grant).withGate(gate);
    check(authored);
    final raw = authored.encode();
    expect(raw, contains(NpcKnowledgeRulebook.gatedFormat));
    expect(raw, isNot(contains(secret.text)));
    final reopened = NpcKnowledgeRulebook.decode(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook, scenario: draft, raw: raw);
    expect(reopened.encode(), raw);
    expect(reopened.gates.single.choiceId, 'end_now');
    expect(reopened.nextGateId(), 'npc_gate_2');

    final translated = NpcKnowledgeWorldBridge.preview(
      index: index, dossiers: dossiers, graph: graph,
      catalog: catalog, editorial: editorial, notebook: notebook,
      scenario: draft, rulebook: reopened, originalBlueprint: base());
    final actor = translated.actorIds[artem.id]!;
    final fact = translated.factIds['${artem.id}|${secret.id}']!;
    final choice = translated.story.scenes['entry']!.choices
        .singleWhere((value) => value.id == 'end_now');
    expect(choice.conditions.single.op, 'knows_fact');
    expect(choice.conditions.single.actor, actor);
    expect(choice.conditions.single.id, fact);

    final world = StoryWorld(translated.story);
    final hash = world.state.stateHash;
    expect(world.apply(actionId: 'too_early', choiceId: 'end_now').applied,
        isFalse);
    expect(world.state.stateHash, hash);
    expect(world.events, isEmpty);
    expect(world.apply(actionId: 'learn', choiceId: 'repeat').applied, isTrue);
    expect(world.state.knowledge[actor], contains(fact));
    expect(world.state.knowledge['player'], isEmpty);
    expect(world.apply(actionId: 'finish', choiceId: 'end_now').applied, isTrue);
    expect(world.isTerminal, isTrue);
    final replay = StoryWorld.replay(
      translated.story,
      jsonDecode(jsonEncode(world.events.map((e) => e.toJson()).toList())) as List,
      expectedSequence: 2, expectedStateHash: world.state.stateHash);
    expect(replay.state.knowledge[actor], contains(fact));
    expect(replay.state.stateHash, world.state.stateHash);
  });

  test('old v1 remains identical, changed rule and tampered gate fail closed', () {
    final grant = makeRule();
    final legacy = NpcKnowledgeRulebook.empty(index).withRule(grant);
    final oldJson = legacy.encode();
    expect(oldJson, contains(NpcKnowledgeRulebook.format));
    expect(oldJson, isNot(contains('"gates"')));
    expect(NpcKnowledgeRulebook.decode(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook, scenario: draft,
      raw: oldJson).encode(), oldJson);

    final gate = NpcKnowledgeRulebook.composeGate(
      id: 'npc_gate_1', grant: grant, scene: draft.scenes.first,
      choice: draft.scenes.first.choices.last);
    final gated = legacy.withGate(gate);
    check(gated);
    expect(() => check(gated.withoutRule(grant.id)), throwsFormatException);
    expect(() => check(gated.withRule(makeRule(
      recipient: KnowledgeRecipient.player, approved: true))),
      throwsFormatException);
    final raw = gated.encode();
    expect(() => NpcKnowledgeRulebook.decode(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook, scenario: draft,
      raw: raw.replaceFirst('npc_gate_1', 'npc_gate_9')),
      throwsFormatException);
    final missing = gated.withoutGate(gate.id);
    expect(missing.encode(), oldJson);
  });

  test('short note text is never silently copied into world catalog', () {
    // A user must not unknowingly serialize a note verbatim into a scene
    // while simultaneously claiming the note is opaque.
    final badBlueprint = base();
    final scenes = badBlueprint['scenes'] as List;
    (scenes.first as Map)['text'] = secret.text;
    expect(() => NpcKnowledgeWorldBridge.preview(
      index: index, dossiers: dossiers, graph: graph, catalog: catalog,
      editorial: editorial, notebook: notebook, scenario: draft,
      rulebook: NpcKnowledgeRulebook.empty(index).withRule(makeRule()),
      originalBlueprint: badBlueprint), throwsFormatException);
  });
}
