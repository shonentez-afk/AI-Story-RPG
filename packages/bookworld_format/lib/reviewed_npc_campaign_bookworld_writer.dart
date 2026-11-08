import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'npc_dialogue_knowledge.dart';
import 'npc_social_contract.dart';
import 'private_bookworld_writer.dart';
import 'private_rich_bookworld.dart';
import 'rich_scene_dialogue.dart';
import 'src/zip_v1.dart';

/// Batch authoring of source-reviewed NPC conversations in ONE existing
/// rich-v3 or explicitly reviewed extended-v4 campaign. This is a translator into story_core, not a second runtime.
/// Consent covers the exact base archive, all actors, quotations, lines and
/// dependencies. No existing save, source text, or network is ever modified.
class ReviewedNpcCampaignBookworldWriter {
  const ReviewedNpcCampaignBookworldWriter();

  static const reviewFormat = 'ai_story_reviewed_npc_campaign_v1';
  static const scope = 'user_declared_private_game_fiction';
  static const maxReviewBytes = 256 * 1024;
  static const maxEpisodes = 32;
  static final _episodeId = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
  static final _sha = RegExp(r'^[0-9a-f]{64}$');
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');

  static String factId(String episodeId) => 'fact_$episodeId';
  static String memoryId(String episodeId) => 'memory_$episodeId';
  static String meetChoiceId(String episodeId) => '${episodeId}_meet';
  static String replyChoiceId(String episodeId) => '${episodeId}_reply';
  static String digest(String reviewJson) => sha256.convert(
      utf8.encode('reviewed-npc-campaign-v1\n$reviewJson')).toString();

  static void _fields(Map<String, dynamic> value, Set<String> expected) {
    if (value.length != expected.length ||
        !value.keys.toSet().containsAll(expected)) {
      throw const FormatException('Unknown or missing NPC campaign fields');
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('NPC campaign object expected');
    }
    return value;
  }

  static String _text(Object? value, int limit) {
    if (value is! String || value.isEmpty || value != value.trim() ||
        value.length > limit || _controls.hasMatch(value)) {
      throw const FormatException('Invalid reviewed NPC campaign text');
    }
    return value;
  }

  /// Importing the base first is mandatory. A hash-only check cannot validate
  /// its rules, provenance, source claims, or previously installed NPCs.
  Uint8List build({
    required Uint8List verifiedBaseArchive,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson,
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    if (!userConfirmed || approvedDigest != digest(reviewJson) ||
        utf8.encode(reviewJson).length > maxReviewBytes) {
      throw const FormatException('NPC campaign approval is absent or stale');
    }
    final review = _object(jsonDecode(reviewJson));
    _fields(review, {
      'format', 'scope', 'source_fingerprint', 'base_archive_sha256',
      'base_blueprint_sha256', 'episodes',
    });
    final base = const RichPrivateBookworldImporter()
        .inspect(verifiedBaseArchive);
    if (review['format'] != reviewFormat || review['scope'] != scope ||
        review['source_fingerprint'] != base.sourceFingerprint ||
        sourceIndex['source_fingerprint'] != base.sourceFingerprint ||
        review['base_archive_sha256'] != base.archiveSha256 ||
        review['base_blueprint_sha256'] != base.blueprint.blueprintHash ||
        base.blueprint.actors.length != 1 ||
        !base.blueprint.actors.contains('player') ||
        base.npcSocialRulebook != null) {
      throw const FormatException('NPC campaign is bound to another base world');
    }
    final rawEpisodes = review['episodes'];
    if (rawEpisodes is! List || rawEpisodes.isEmpty ||
        rawEpisodes.length > maxEpisodes) {
      throw const FormatException('Invalid NPC campaign size');
    }
    final episodes = <String, Map<String, dynamic>>{};
    final names = <String, String>{};
    for (final raw in rawEpisodes) {
      final row = _object(raw);
      _fields(row, {
        'id', 'actor_id', 'display_name', 'character_group_digest',
        'first_scene_id', 'first_exit_choice_id', 'response_scene_id',
        'response_exit_choice_id', 'source_event_id', 'response_event_id',
        'first_quote_sha256', 'response_quote_sha256', 'player_line',
        'npc_line', 'requires_episodes',
      });
      final id = _text(row['id'], 40);
      final actor = _text(row['actor_id'], 64);
      final name = _text(row['display_name'], 50);
      if (!_episodeId.hasMatch(id) || episodes.containsKey(id) ||
          !CharacterId.isValidNpc(actor) || name == 'Игрок' ||
          !RegExp(r'^[А-ЯЁA-Z][А-Яа-яЁёA-Za-z0-9 .-]{0,49}$',
              unicode: true).hasMatch(name) ||
          (names.containsKey(actor) && names[actor] != name)) {
        throw const FormatException('Duplicate episode or inconsistent NPC identity');
      }
      for (final key in ['character_group_digest', 'first_quote_sha256',
          'response_quote_sha256']) {
        if (row[key] is! String || !_sha.hasMatch(row[key] as String)) {
          throw const FormatException('Invalid NPC source digest');
        }
      }
      for (final key in ['first_scene_id', 'first_exit_choice_id',
          'response_scene_id', 'response_exit_choice_id',
          'source_event_id', 'response_event_id']) {
        _text(row[key], 128);
      }
      for (final key in ['player_line', 'npc_line']) {
        final line = _text(row[key], 400);
        if (line.contains('«') || line.contains('»')) {
          throw const FormatException('NPC line must not contain outer speech quotes');
        }
      }
      final dependencies = row['requires_episodes'];
      if (dependencies is! List || dependencies.length > 8 ||
          dependencies.any((d) => d is! String || d == id) ||
          dependencies.toSet().length != dependencies.length) {
        throw const FormatException('Invalid NPC episode prerequisites');
      }
      names[actor] = name;
      episodes[id] = row;
    }
    if (names.length > 15 ||
        base.blueprint.facts.length + episodes.length >
            (base.formatVersion == 4 ? 128 : 64)) {
      throw const FormatException('NPC campaign exceeds existing v3 catalogs');
    }
    // Reject dependency cycles BEFORE state exploration or ZIP construction.
    final visiting = <String>{};
    final visited = <String>{};
    void checkDependencies(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw const FormatException('Circular NPC episode prerequisite');
      }
      for (final dependency in episodes[id]!['requires_episodes'] as List) {
        if (!episodes.containsKey(dependency)) {
          throw const FormatException('Unknown prerequisite NPC episode');
        }
        checkDependencies(dependency as String);
      }
      visiting.remove(id);
      visited.add(id);
    }
    for (final id in episodes.keys) { checkDependencies(id); }

    final files = BworldZipV1.readPrivate(verifiedBaseArchive);
    final blueprint = _object(jsonDecode(
        utf8.decode(files['scenario/blueprint.json']!)));
    final provenance = _object(jsonDecode(
        utf8.decode(files['source/provenance.json']!)));
    final presentation = _object(provenance['presentation']);
    if (provenance.containsKey('npc_knowledge') ||
        provenance.containsKey('npc_social') ||
        (presentation['scene_dialogues'] is Map &&
         (presentation['scene_dialogues'] as Map).isNotEmpty)) {
      throw const FormatException(
          'Existing dialogue or NPC review must not be silently replaced');
    }
    final scenes = <String, Map<String, dynamic>>{
      for (final value in blueprint['scenes'] as List)
        _object(value)['id'] as String: _object(value),
    };
    final origins = <String, Map<String, dynamic>>{
      for (final value in provenance['scene_origins'] as List)
        _object(value)['scene_id'] as String: _object(value),
    };
    final choiceIds = <String>{
      for (final scene in scenes.values)
        for (final raw in scene['choices'] as List)
          _object(raw)['id'] as String,
    };
    final facts = <String>{...base.blueprint.facts};
    final grants = <Map<String, dynamic>>[];
    final witnesses = <String, Map<String, dynamic>>{};
    final memories = <Map<String, dynamic>>[];
    final gates = <Map<String, dynamic>>[];
    final responseRows = <String, List<Map<String, dynamic>>>{};
    final required = <String>[];

    Map<String, dynamic> sourceScene(String id, String quote) {
      final scene = scenes[id];
      final origin = origins[id];
      final refs = origin?['source_refs'];
      if (scene == null || scene['terminal'] != false ||
          origin?['origin'] != 'SOURCE_PASSAGE' || refs is! List ||
          !refs.any((ref) => ref is Map && ref['quote_sha256'] == quote &&
              ref['chapter_index'] == origin?['chapter_index'] &&
              ref['visible_after_chapter'] is int &&
              (ref['visible_after_chapter'] as int) <=
                  (origin!['chapter_index'] as int))) {
        throw const FormatException('NPC source scene has no exact reviewed citation');
      }
      return scene;
    }
    Map<String, dynamic> safeExit(Map<String, dynamic> scene, String id) {
      final found = (scene['choices'] as List).map(_object)
          .where((choice) => choice['id'] == id).toList();
      if (found.length != 1 ||
          (found.single['conditions'] as List).isNotEmpty ||
          (found.single['effects'] as List).isNotEmpty) {
        throw const FormatException('NPC action would bypass an existing causal gate');
      }
      return found.single;
    }
    final ordered = episodes.keys.toList()..sort();
    for (final id in ordered) {
      final row = episodes[id]!;
      final actor = row['actor_id'] as String;
      final firstId = row['first_scene_id'] as String;
      final secondId = row['response_scene_id'] as String;
      final quote = row['first_quote_sha256'] as String;
      final nextQuote = row['response_quote_sha256'] as String;
      final first = sourceScene(firstId, quote);
      final second = sourceScene(secondId, nextQuote);
      if (firstId == secondId ||
          (origins[firstId]!['chapter_index'] as int) >
              (origins[secondId]!['chapter_index'] as int)) {
        throw const FormatException('NPC response precedes its source encounter');
      }
      final firstExit = safeExit(first, row['first_exit_choice_id'] as String);
      final secondExit = safeExit(second, row['response_exit_choice_id'] as String);
      final fact = factId(id);
      final memory = memoryId(id);
      final meet = meetChoiceId(id);
      final reply = replyChoiceId(id);
      if (!facts.add(fact) || !choiceIds.add(meet) || !choiceIds.add(reply)) {
        throw const FormatException('NPC generated ID collides with the base world');
      }
      final prerequisites = <Map<String, dynamic>>[
        for (final dependency in row['requires_episodes'] as List)
          {'op': 'knows_fact', 'id': factId(dependency as String),
           'actor': episodes[dependency]!['actor_id']},
      ];
      (first['choices'] as List).add({
        'id': meet, 'label': 'Поговорить: ${row['display_name']}',
        'next_scene_id': firstExit['next_scene_id'],
        'conditions': prerequisites,
        'effects': [
          {'op': 'learn_fact', 'id': fact, 'actor': actor},
        ],
      });
      (second['choices'] as List).add({
        'id': reply, 'label': 'Продолжить разговор: ${row['display_name']}',
        'next_scene_id': secondExit['next_scene_id'],
        'conditions': [
          {'op': 'knows_fact', 'id': fact, 'actor': actor},
        ],
        'effects': <Map<String, dynamic>>[],
      });
      if ((first['choices'] as List).length > 16 ||
          (second['choices'] as List).length > 16) {
        throw const FormatException('Too many reviewed actions in one source scene');
      }
      grants.add({
        'scene_id': firstId, 'choice_id': meet, 'actor_id': actor,
        'fact_id': fact, 'source_quote_sha256': quote,
      });
      witnesses['$firstId|$actor'] = {
        'scene_id': firstId, 'actor_id': actor, 'mode': 'present',
        'source_quote_sha256': quote,
      };
      memories.add({
        'memory_id': memory, 'scene_id': firstId, 'choice_id': meet,
        'observer_id': actor, 'kind': 'witnessed',
        'related_actor_id': 'player', 'relationship_delta': 1,
        'max_triggers': 1, 'source_quote_sha256': quote,
      });
      gates.add({
        'scene_id': secondId, 'choice_id': reply, 'actor_id': actor,
        'required_memory_id': memory, 'minimum_trust_to_player': 1,
        'source_quote_sha256': nextQuote,
      });
      responseRows.putIfAbsent(secondId, () => []).add(row);
      required.addAll([meet, reply]);
    }
    blueprint['actors'] = ['player', ...(names.keys.toList()..sort())];
    blueprint['facts'] = facts.toList()..sort();
    final initial = _object(blueprint['initial_state']);
    final knowledge = _object(initial['knowledge']);
    for (final actor in names.keys) { knowledge[actor] = <String>[]; }
    final factNames = _object(presentation['fact_names']);
    for (final id in ordered) {
      factNames[factId(id)] = 'Игровая встреча: ${episodes[id]!['display_name']}';
    }
    provenance['npc_knowledge'] = {
      'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
      'review_scope': scope, 'source_fingerprint': base.sourceFingerprint,
      'user_confirmed': true, 'literary_canon_verified': false,
      'grants': grants,
    };
    provenance['npc_social'] = {
      'format': RichNpcSocialContract.choiceGateFormat,
      'review_scope': scope, 'source_fingerprint': base.sourceFingerprint,
      'user_confirmed': true, 'literary_canon_verified': false,
      'witnesses': witnesses.values.toList(), 'rules': memories,
      'choice_gates': gates,
    };
    final dialogues = <String, dynamic>{};
    final dialogueReview = <String, dynamic>{};
    for (final entry in responseRows.entries) {
      final scene = scenes[entry.key]!;
      final originalText = scene['text'] as String;
      final appended = <String>[
        'ЧАСТНЫЙ ИГРОВОЙ ДИАЛОГ, НЕ ДОСЛОВНЫЙ ТЕКСТ КНИГИ:',
        for (final row in entry.value) ...[
          'Игрок: «${row['player_line']}»',
          '${row['display_name']}: «${row['npc_line']}»',
        ],
      ].join('\n');
      scene['text'] = '$originalText\n\n$appended';
      final signed = RichSceneDialogue.presentationFor(scene['text'] as String);
      if (signed == null) {
        throw const FormatException('Reviewed NPC lines cannot be rendered safely');
      }
      final turns = RichSceneDialogue.parse(scene['text'] as String)!;
      final spoken = <int>[
        for (var i = 0; i < turns.length; i++)
          if (turns[i].speaker != null) i,
      ];
      if (spoken.length != entry.value.length * 2) {
        throw const FormatException('Original source speech needs separate identity review');
      }
      final reviewed = <Map<String, dynamic>>[];
      for (var i = 0; i < entry.value.length; i++) {
        final row = entry.value[i];
        final id = row['id'] as String;
        if (turns[spoken[i * 2]].speaker != 'Игрок' ||
            turns[spoken[i * 2 + 1]].speaker != row['display_name']) {
          throw const FormatException('Speaker order changed after NPC approval');
        }
        reviewed.add({
          'turn_index': spoken[i * 2], 'speaker': 'Игрок',
          'actor_id': 'player', 'required_fact_ids': <String>[],
        });
        reviewed.add({
          'turn_index': spoken[i * 2 + 1], 'speaker': row['display_name'],
          'actor_id': row['actor_id'], 'required_fact_ids': [factId(id)],
          'required_social_memory_id': memoryId(id),
          'minimum_trust_to_player': 1,
          'required_prior_choice_id': meetChoiceId(id),
          'source_quote_sha256': row['first_quote_sha256'],
          'private_fiction_confirmed': true,
        });
      }
      dialogues[entry.key] = signed;
      dialogueReview[entry.key] = reviewed;
    }
    presentation['scene_dialogues'] = dialogues;
    presentation['scene_dialogue_knowledge'] = dialogueReview;
    final worldId = 'npc_campaign_${sha256.convert(utf8.encode(
        '${base.archiveSha256}|$approvedDigest')).toString().substring(0, 24)}';
    blueprint['book_id'] = worldId;
    provenance['bookworld_id'] = worldId;
    final story = StoryBlueprint.fromJson(blueprint);
    final social = RichNpcSocialContract.inspect(provenance, {
      'npc_social_format': RichNpcSocialContract.choiceGateFormat,
    }, story)!;
    RichNpcDialogueKnowledge.validate(dialogueReview, story, dialogues,
        socialRules: social, sceneOrigins: Map<String, dynamic>.from(origins));
    RichNpcDialogueKnowledge.auditExecutableRoutes(dialogueReview, story,
        socialRules: social, maxMoves: base.formatVersion == 4 ? 2000 : 128,
        maxStates: base.formatVersion == 4 ? 8192 : 4096,
        projectDormantFlags: base.formatVersion == 4);
    final extended = base.formatVersion == 4;
    final baseProof = StoryCampaignCausalAudit.inspect(
      blueprint: base.blueprint, maxMoves: extended ? 2000 : 256,
      projectDormantFlags: extended,
    );
    if (!baseProof.playable || !baseProof.exhaustive) {
      throw const FormatException('Base campaign has no exhaustive causal acceptance');
    }
    final proof = StoryCampaignCausalAudit.inspect(
      blueprint: story, socialRulebook: social,
      requiredChoiceIds: [...baseProof.choiceWitnesses.keys, ...required],
      maxMoves: extended ? 2000 : 256,
      projectDormantFlags: extended,
    );
    if (!proof.playable || !proof.exhaustive) {
      throw const FormatException(
          'NPC campaign contains a blocked action, a trap, or exceeded the audit budget');
    }
    // The existing writer repeats source checks and independently imports its
    // ZIP and SQLite result. No new .bworld member or runtime capability.
    return const RichPrivateBookworldWriter().build(
        blueprint: blueprint, provenance: provenance, sourceIndex: sourceIndex,
        expanded: extended);
  }
}
