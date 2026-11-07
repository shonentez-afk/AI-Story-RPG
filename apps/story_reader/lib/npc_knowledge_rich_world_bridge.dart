import 'dart:convert';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'npc_editorial_notebook.dart';
import 'npc_knowledge_rulebook.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// One local, source-reviewed bridge to the existing rich-v3 writer.
/// This never guesses which quote proves an NPC fact or grants consent.
class NpcKnowledgeRichWorldBridge {
  const NpcKnowledgeRichWorldBridge._();

  static Map<String, dynamic> prepare({
    required BookSourceIndex index,
    required SourceCharacterDossierIndex dossiers,
    required SourceEvidenceGraph graph,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required NpcEditorialNotebook notebook,
    required IntermediateStoryBlueprint scenario,
    required NpcKnowledgeRulebook rulebook,
    required Map<String, dynamic> blueprint,
    required Map<String, dynamic> provenance,
    required Map<String, String> sourceQuoteByRuleId,
    required bool userConfirmed,
    Map<String, dynamic>? reviewedNpcSocial,
    Map<String, List<Map<String, dynamic>>> reviewedDialogueTurns = const {},
    Map<String, String> reviewedSpeakerBindings = const {},
    String heroName = 'Игрок',
    String heroDescription =
        'Герой частной игровой адаптации. Решения сохраняются в журнале.',
  }) {
    if (!userConfirmed) {
      throw const FormatException('Нужно явное подтверждение знаний NPC');
    }
    rulebook.validate(
      index: index, dossiers: dossiers, graph: graph,
      catalog: catalog, editorial: editorial,
      notebook: notebook, scenario: scenario,
    );
    if (provenance['bookworld_id'] != blueprint['book_id'] ||
        provenance['source_fingerprint'] != index.sourceFingerprint ||
        blueprint['source_fingerprint'] != index.sourceFingerprint ||
        blueprint['rights_status'] != 'private_adaptation' ||
        provenance['rights_status'] != 'private_use_only' ||
        provenance['publication_authorized'] != false ||
        heroName.trim().isEmpty || heroName.length > 120 ||
        heroDescription.trim().isEmpty || heroDescription.length > 1200) {
      throw const FormatException('Чужой источник, права или герой');
    }
    final world = StoryBlueprint.fromJson(blueprint);
    final npcs = world.actors.difference({'player'});
    if (npcs.isEmpty || npcs.length > 15 ||
        npcs.any((id) => !CharacterId.isValidNpc(id)) ||
        world.initial.knowledge.keys.toSet().difference(world.actors).isNotEmpty ||
        world.initial.knowledge.values.any((facts) => facts.isNotEmpty)) {
      throw const FormatException('Требуются постоянные character_id NPC');
    }
    final profiles = {for (final p in notebook.profiles) p.dossierId: p};
    final origins = <String, Map<String, dynamic>>{};
    final originValues = provenance['scene_origins'];
    if (originValues is! List) {
      throw const FormatException('Нет литературных источников сцен');
    }
    for (final value in originValues) {
      if (value is! Map<String, dynamic> ||
          value['scene_id'] is! String ||
          origins.containsKey(value['scene_id'])) {
        throw const FormatException('Подмена источника сцены NPC');
      }
      origins[value['scene_id'] as String] = value;
    }
    final choices = <String, (String, Map<String, dynamic>)>{};
    for (final raw in blueprint['scenes'] as List) {
      final scene = raw as Map<String, dynamic>;
      for (final item in scene['choices'] as List) {
        final choice = item as Map<String, dynamic>;
        final id = choice['id'] as String;
        if (choices.containsKey(id)) {
          throw const FormatException('Повтор ID игрового решения');
        }
        choices[id] = (scene['id'] as String, choice);
      }
    }
    final npcRules = rulebook.rules
        .where((r) => r.recipient == KnowledgeRecipient.ownerNpc)
        .toList();
    if (npcRules.isEmpty || npcRules.length > 128 ||
        sourceQuoteByRuleId.length != npcRules.length ||
        sourceQuoteByRuleId.keys.toSet().difference(
            npcRules.map((r) => r.id).toSet()).isNotEmpty) {
      throw const FormatException('Нет точных цитат для всех знаний NPC');
    }
    final assertions = {for (final a in catalog.assertions) a.id: a};
    final evidence = {for (final e in graph.records) e.id: e};
    final grants = <Map<String, String>>[];
    final unique = <String>{};
    for (final rule in npcRules) {
      final profile = profiles[rule.dossierId];
      if (profile?.characterId == null ||
          !npcs.contains(profile!.characterId)) {
        throw const FormatException('Непостоянный character_id NPC');
      }
      final note = profile.notes.singleWhere((n) => n.id == rule.noteId);
      final fact = NpcKnowledgeRulebook.factId(
          index.sourceFingerprint, rule.groupDigest, note);
      final compiled = choices[rule.choiceId];
      if (compiled == null || (compiled.$2['effects'] as List)
          .where((value) => value is Map &&
              value['op'] == 'learn_fact' && value['id'] == fact &&
              value['actor'] == profile.characterId).length != 1) {
        throw const FormatException('Нет проверенного эффекта NPC');
      }
      final sceneId = compiled.$1;
      final origin = origins[sceneId];
      final quote = sourceQuoteByRuleId[rule.id];
      final references = origin?['source_refs'];
      if (origin?['origin'] != 'SOURCE_PASSAGE' ||
          quote == null || references is! List ||
          !references.any((value) => value is Map &&
              value['quote_sha256'] == quote &&
              value['visible_after_chapter'] is int &&
              origin!['chapter_index'] is int &&
              value['visible_after_chapter'] <= origin['chapter_index'])) {
        throw const FormatException('Цитата не относится к этой сцене');
      }
      if (note.sourceAssertionId != null) {
        final assertion = assertions[note.sourceAssertionId];
        if (assertion == null || !assertion.evidenceIds.any(
            (id) => evidence[id]?.evidenceSha256 == quote)) {
          throw const FormatException('Цитата не подтверждает заметку NPC');
        }
      }
      final key = [sceneId, rule.choiceId, profile.characterId!, fact].join('|');
      if (!unique.add(key)) {
        throw const FormatException('Повтор источника NPC');
      }
      grants.add({
        'scene_id': sceneId, 'choice_id': rule.choiceId,
        'actor_id': profile.characterId!, 'fact_id': fact,
        'source_quote_sha256': quote,
      });
    }
    final actual = <String>{};
    for (final scene in world.scenes.values) {
      for (final choice in scene.choices) {
        for (final effect in choice.effects) {
          if (effect.op == 'learn_fact' && effect.actor != 'player') {
            actual.add([scene.id, choice.id, effect.actor, effect.id].join('|'));
          }
        }
      }
    }
    if (actual.length != unique.length || !actual.containsAll(unique)) {
      throw const FormatException('Остались непроверенные эффекты NPC');
    }
    final result = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(provenance)) as Map);
    result['format'] = 'ai_story_private_provenance_v2';
    result['model_provenance'] = {
      'provider': 'unknown', 'model_id': null,
      'model_id_status': 'not_attested',
      'tool': 'AI Story RPG', 'method': 'reviewed_local_compilation',
    };
    final sceneNames = <String, String>{};
    final dialogues = <String, Map<String, Object?>>{};
    final scenes = blueprint['scenes'] as List;
    for (var i = 0; i < scenes.length; i++) {
      final scene = scenes[i] as Map<String, dynamic>;
      final id = scene['id'] as String;
      sceneNames[id] = 'Сцена ' + (i + 1).toString();
      final turns = RichSceneDialogue.presentationFor(scene['text'] as String);
      if (turns != null) dialogues[id] = turns;
    }
    if (dialogues.keys.toSet().difference(
            reviewedDialogueTurns.keys.toSet()).isNotEmpty ||
        reviewedDialogueTurns.keys.toSet().difference(
            dialogues.keys.toSet()).isNotEmpty) {
      throw const FormatException('Нужна проверка всех реплик NPC');
    }
    for (final entries in reviewedDialogueTurns.values) {
      for (final entry in entries) {
        final speaker = entry['speaker'];
        final actor = entry['actor_id'];
        if (actor != 'player' &&
            (speaker is! String ||
             reviewedSpeakerBindings[speaker] != actor)) {
          throw const FormatException(
              'У говорящего нет подтверждённого character_id');
        }
      }
    }
    final socialRules = reviewedNpcSocial == null ? null :
        RichNpcSocialContract.inspect(
          {...provenance, 'npc_social': reviewedNpcSocial},
          {'npc_social_format': reviewedNpcSocial['format']},
          world,
        );
    RichNpcDialogueKnowledge.validate(
      reviewedDialogueTurns.isEmpty ? null :
          <String, dynamic>{...reviewedDialogueTurns},
      world, <String, dynamic>{...dialogues},
      socialRules: socialRules,
    );
    final facts = world.facts.toList()..sort();
    result['presentation'] = {
      'hero': {'name': heroName.trim(), 'description': heroDescription.trim()},
      'item_names': <String, String>{}, 'item_descriptions': <String, String>{},
      'stat_names': <String, String>{},
      // Never serialize the private original note or secret text.
      'fact_names': {
        for (var i = 0; i < facts.length; i++)
          facts[i]: 'Сведения ' + (i + 1).toString(),
      },
      'scene_names': sceneNames,
      'scene_dialogues': dialogues,
      if (reviewedDialogueTurns.isNotEmpty)
        'scene_dialogue_knowledge': reviewedDialogueTurns,
    };
    if (reviewedNpcSocial != null) {
      // The model/presentation are already assembled at this point.
      // Never invent the author's presence, rumor or consent flags.
      result['npc_social'] =
          jsonDecode(jsonEncode(reviewedNpcSocial));
      // All quotes, actions and actor identities were preflight checked.
      // The strict ZIP writer and importer independently repeat this check.
    }
    result['npc_knowledge'] = {
      'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': index.sourceFingerprint,
      'user_confirmed': true,
      'literary_canon_verified': false,
      'grants': grants,
    };
    return result;
  }
}
