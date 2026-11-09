import 'package:story_core/story_core.dart';

/// Import-time verification of human-reviewed causal witnesses for a
/// source-literal v5 book. An LLM cannot grant NPC identity, eyewitness
/// presence, canonical obligations or permission to contradict the book.
final class CanonCausalContract {
  const CanonCausalContract._();

  static const format = 'ai_story_source_causal_review_v1';
  static const graphFormat = 'ai_story_source_causal_review_v2';
  static final _sha = RegExp(r'^[0-9a-f]{64}$');
  static final _gm = RegExp(r'^gm_[a-z0-9_]{1,59}$');

  static Map<String, dynamic> _map(Object? raw, String field) {
    if (raw is! Map<String, dynamic>) {
      throw FormatException('Malformed source causal $field');
    }
    return raw;
  }

  static void _fields(Map<String, dynamic> value,
      Set<String> expected, String field) {
    if (value.keys.toSet().length != expected.length ||
        !value.keys.toSet().containsAll(expected)) {
      throw FormatException('Unknown or missing source causal $field field');
    }
  }

  static bool _cited(Map<String, Map<String, dynamic>> origins,
      String sceneId, String quote) {
    final row = origins[sceneId];
    if (row == null || row['origin'] != 'SOURCE_PASSAGE' ||
        row['chapter_index'] is! int ||
        row['source_refs'] is! List) return false;
    final chapter = row['chapter_index'] as int;
    return (row['source_refs'] as List).any((raw) =>
      raw is Map<String, dynamic> &&
      raw['quote_sha256'] == quote &&
      raw['chapter_index'] == chapter &&
      raw['visible_after_chapter'] is int &&
      raw['visible_after_chapter'] <= chapter);
  }

  /// Returns null for unchanged old literal v5 games. All additions use the
  /// SAME stored hash-verified scenario and versioned signed provenance.
  static ({
    NpcSocialRulebook rulebook, Map<String, String> names,
  })? inspect(Map<String, dynamic> source,
      Map<String, dynamic> manifest, StoryBlueprint blueprint) {
    final raw = source['canon_causality'];
    final marker = manifest['canon_causality_format'];
    if (raw == null && marker == null) return null;
    if (!{format, graphFormat}.contains(marker) || !blueprint.isReviewedCanon ||
        !blueprint.supportsFreeform || !manifest.containsKey('canon_review_format')) {
      throw const FormatException('Missing source-causal v5 authorization');
    }
    final review = _map(raw, 'review');
    final graphReview = review['format'] == graphFormat;
    _fields(review, {
      'format', 'review_scope', 'source_fingerprint',
      'base_archive_sha256', 'user_confirmed',
      'semantic_canon_automatically_verified',
      'witnesses', 'invariants',
      if (graphReview) 'event_graph',
      if (graphReview && review.containsKey('npc_reactions')) 'npc_reactions',
    }, 'review');
    if (review['format'] != marker ||
        review['review_scope'] != 'human_reviewed_private_story_causality' ||
        review['source_fingerprint'] != blueprint.sourceFingerprint ||
        review['base_archive_sha256'] is! String ||
        !_sha.hasMatch(review['base_archive_sha256'] as String) ||
        review['user_confirmed'] != true ||
        review['semantic_canon_automatically_verified'] != false) {
      throw const FormatException('Source-causal consent is absent or stale');
    }
    final sourceOrigins = source['scene_origins'];
    if (sourceOrigins is! List) {
      throw const FormatException('Missing literal source citations');
    }
    final origins = <String, Map<String, dynamic>>{};
    for (final raw in sourceOrigins) {
      final o = _map(raw, 'origin');
      final id = o['scene_id'];
      if (id is! String || origins.containsKey(id)) {
        throw const FormatException('Untrusted causal source origin');
      }
      origins[id] = o;
    }
    final witnesses = review['witnesses'], invariants = review['invariants'];
    if (witnesses is! List || witnesses.isEmpty || witnesses.length > 128 ||
        invariants is! List || invariants.isEmpty ||
        invariants.length > 256) {
      throw const FormatException('Causal review has no bounded NPC history');
    }
    final names = <String, String>{};
    final modes = <String>{};
    final verifiedWitnesses = <NpcSceneWitness>[];
    for (final raw in witnesses) {
      final row = _map(raw, 'NPC witness');
      _fields(row, {
        'scene_id', 'actor_id', 'display_name',
        'source_quote_sha256', 'mode',
      }, 'witness');
      final actor = row['actor_id'], scene = row['scene_id'];
      final label = row['display_name'], quote = row['source_quote_sha256'];
      if (actor is! String || !CharacterId.isValidNpc(actor) ||
          !blueprint.actors.contains(actor) ||
          scene is! String || !blueprint.scenes.containsKey(scene) ||
          label is! String || label.trim() != label ||
          label.isEmpty || label.runes.length > 85 ||
          quote is! String || !_sha.hasMatch(quote) ||
          !_cited(origins, scene, quote) ||
          !blueprint.scenes[scene]!.text.contains(label) ||
          !modes.add(scene + '|' + actor) ||
          (names[actor] != null && names[actor] != label)) {
        throw const FormatException(
            'NPC identity/presence is not an exact source witness');
      }
      final mode = switch (row['mode']) {
        'present' => NpcWitnessMode.present,
        'reported' => NpcWitnessMode.reported,
        _ => throw const FormatException('Unknown NPC witness type'),
      };
      names[actor] = label;
      verifiedWitnesses.add(NpcSceneWitness(
        sceneId: scene, actorId: actor, mode: mode));
    }
    if (names.keys.toSet().length != blueprint.actors.length - 1 ||
        !names.keys.toSet().containsAll(
            blueprint.actors.difference({'player'}))) {
      throw const FormatException('NPC actor catalog is not source reviewed');
    }
    final gates = <NpcCanonInvariant>[];
    for (final raw in invariants) {
      final row = _map(raw, 'causal invariant');
      _fields(row, {
        'scene_id', 'actor_id', 'forbidden_memory_id',
        'minimum_trust', 'maximum_trust', 'source_quote_sha256',
      }, 'invariant');
      final scene = row['scene_id'], actor = row['actor_id'];
      final memory = row['forbidden_memory_id'];
      final quote = row['source_quote_sha256'];
      if (scene is! String || scene == blueprint.entrySceneId ||
          !blueprint.scenes.containsKey(scene) ||
          actor is! String || !names.containsKey(actor) ||
          memory is! String || !_gm.hasMatch(memory) ||
          quote is! String || !_sha.hasMatch(quote) ||
          !_cited(origins, scene, quote)) {
        throw const FormatException('Future canonical obligation lacks source');
      }
      final min = row['minimum_trust'], max = row['maximum_trust'];
      if ((min != null && min is! int) ||
          (max != null && max is! int)) {
        throw const FormatException('Invalid NPC trust prerequisite');
      }
      gates.add(NpcCanonInvariant(
        sceneId: scene, actorId: actor, forbiddenMemoryId: memory,
        minimumTrust: min as int?, maximumTrust: max as int?,
      ));
    }
    BookCausalGraph? bookGraph;
    final reactions = <NpcAutomaticReaction>[];
    if (graphReview && review.containsKey('npc_reactions')) {
      final rows = review['npc_reactions'];
      if (rows is! List || rows.length > 256) {
        throw const FormatException('Invalid automatic NPC reaction catalog');
      }
      for (final raw in rows) {
        final row = _map(raw, 'npc reaction');
        _fields(row, {
          'scene_id', 'source_quote_sha256', 'actor_id',
          'trigger_memory_id', 'minimum_trust', 'response_memory_id',
          'next_goal_id', 'relay_fact_id', 'relay_to_actor_id',
        }, 'npc reaction');
        final scene = row['scene_id'], quote = row['source_quote_sha256'];
        if (scene is! String || quote is! String ||
            !_cited(origins, scene, quote) ||
            row['actor_id'] is! String ||
            row['trigger_memory_id'] is! String ||
            row['minimum_trust'] is! int ||
            row['response_memory_id'] is! String ||
            row['next_goal_id'] is! String ||
            (row['relay_fact_id'] != null &&
                row['relay_fact_id'] is! String) ||
            (row['relay_to_actor_id'] != null &&
                row['relay_to_actor_id'] is! String)) {
          throw const FormatException('NPC reaction lacks reviewed evidence');
        }
        reactions.add(NpcAutomaticReaction(
          sceneId: scene,
          actorId: row['actor_id'] as String,
          triggerMemoryId: row['trigger_memory_id'] as String,
          minimumTrust: row['minimum_trust'] as int,
          responseMemoryId: row['response_memory_id'] as String,
          nextGoalId: row['next_goal_id'] as String,
          relayFactId: row['relay_fact_id'] as String?,
          relayToActorId: row['relay_to_actor_id'] as String?,
        ));
      }
    }
    if (graphReview) {
      final rawEvents = review['event_graph'];
      if (rawEvents is! List) {
        throw const FormatException('Missing reviewed full-book causes');
      }
      for (final raw in rawEvents) {
        final row = _map(raw, 'causal event');
        _fields(row, {'scene_id', 'source_quote_sha256',
            'depends_on', 'preconditions', 'effects'}, 'causal event');
        if (row['scene_id'] is! String ||
            row['source_quote_sha256'] is! String ||
            !_cited(origins, row['scene_id'] as String,
                row['source_quote_sha256'] as String)) {
          throw const FormatException('Causal event lacks signed book quote');
        }
      }
      bookGraph = BookCausalGraph.fromReview([
        for (final raw in rawEvents)
          {...(raw as Map<String, dynamic>)}..remove('source_quote_sha256'),
      ], blueprint);
    }
    final rulebook = NpcSocialRulebook(
      blueprintHash: blueprint.blueprintHash,
      rules: const [], witnesses: verifiedWitnesses,
      canonInvariants: gates,
      requireReviewedWitnesses: true,
      dynamicInteractionsEnabled: true,
      bookCausality: bookGraph,
      automaticReactions: reactions,
    );
    rulebook.validate(blueprint);
    return (rulebook: rulebook, names: Map.unmodifiable(names));
  }
}
