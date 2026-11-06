import 'package:story_core/story_core.dart';

/// Optional, exact, private-only source review of NPC presence and
/// event-derived relationships. This lives outside the independent core:
/// scene citations are literary *witnesses*, not world-state effects.
class RichNpcSocialContract {
  const RichNpcSocialContract._();

  static const format = 'ai_story_npc_social_witness_v1';
  /// V2 adds verifiable conditions on authoritative game decisions. V1
  /// archives keep their exact meaning and continue to open unchanged.
  static const choiceGateFormat = 'ai_story_npc_social_witness_v2';
  /// V3 additionally binds player/NPC item custody transfers to the EXACT
  /// typed world effect, committed choice, active witness and source quote.
  static const itemTransferFormat = 'ai_story_npc_social_witness_v3';
  static final _sha = RegExp(r'^[0-9a-f]{64}$');
  static final _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  static void _fields(Map<String, dynamic> input,
      Set<String> expected, String label) {
    if (input.length != expected.length ||
        !input.keys.toSet().containsAll(expected)) {
      throw FormatException('NPC social $label has unknown/missing fields');
    }
  }

  static String _checkedId(Object? raw, String label) {
    if (raw is! String || !_id.hasMatch(raw)) {
      throw FormatException('Invalid NPC social $label');
    }
    return raw;
  }

  static String _checkedQuote(Object? raw) {
    if (raw is! String || !_sha.hasMatch(raw)) {
      throw const FormatException('Invalid NPC social quote digest');
    }
    return raw;
  }

  /// Every annotation is bound to a quoted, *already visible* passage of the
  /// exact source scene. It does not magically prove the literary assertion;
  /// the author must independently review whether the quote supports it.
  static bool _cited(String sceneId, String quote,
      Map<String, Map<String, dynamic>> origins) {
    final origin = origins[sceneId];
    final refs = origin?['source_refs'];
    final chapter = origin?['chapter_index'];
    return origin?['origin'] == 'SOURCE_PASSAGE' &&
        chapter is int && refs is List && refs.any((raw) =>
            raw is Map &&
            raw['quote_sha256'] == quote &&
            raw['chapter_index'] is int &&
            raw['visible_after_chapter'] is int &&
            raw['chapter_index'] <= chapter &&
            raw['visible_after_chapter'] <= chapter);
  }

  /// Fail closed: absent metadata means no social authority. Both marker and
  /// reviewed source payload must appear together. Old v3 remains compatible.
  static NpcSocialRulebook? inspect(Map<String, dynamic> source,
      Map<String, dynamic> manifest, StoryBlueprint blueprint) {
    final raw = source['npc_social'];
    final marker = manifest['npc_social_format'];
    if (raw == null && marker == null) return null;
    if ((marker != format && marker != choiceGateFormat &&
         marker != itemTransferFormat) ||
        raw is! Map<String, dynamic> ||
        blueprint.rightsStatus != 'private_adaptation') {
      throw const FormatException('NPC social version/capability mismatch');
    }
    _fields(raw, {
      'format', 'review_scope', 'source_fingerprint',
      'user_confirmed', 'literary_canon_verified', 'witnesses', 'rules',
      if (marker == choiceGateFormat ||
          marker == itemTransferFormat) 'choice_gates',
      if (marker == itemTransferFormat) 'item_transfers',
    }, 'source review');
    if (raw['format'] != marker ||
        raw['review_scope'] != 'user_declared_private_game_fiction' ||
        raw['source_fingerprint'] != blueprint.sourceFingerprint ||
        raw['user_confirmed'] != true ||
        raw['literary_canon_verified'] != false) {
      throw const FormatException('Unapproved NPC social game annotations');
    }
    final rawWitnesses = raw['witnesses'];
    final rawRules = raw['rules'];
    if (rawWitnesses is! List || rawRules is! List ||
        rawWitnesses.isEmpty || rawWitnesses.length > 128 ||
        rawRules.isEmpty || rawRules.length > 128) {
      throw const FormatException('NPC social review must be bounded');
    }
    final sourceOrigins = source['scene_origins'];
    if (sourceOrigins is! List) {
      throw const FormatException('Missing NPC social source scenes');
    }
    final origins = <String, Map<String, dynamic>>{};
    for (final origin in sourceOrigins) {
      if (origin is! Map<String, dynamic> ||
          origin['scene_id'] is! String ||
          origins.containsKey(origin['scene_id'])) {
        throw const FormatException('Duplicate NPC social source scene');
      }
      origins[origin['scene_id'] as String] = origin;
    }

    final witnesses = <NpcSceneWitness>[];
    for (final entry in rawWitnesses) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Malformed NPC scene witness');
      }
      _fields(entry, {
        'scene_id', 'actor_id', 'mode', 'source_quote_sha256',
      }, 'witness');
      final sceneId = _checkedId(entry['scene_id'], 'scene');
      final actorId = _checkedId(entry['actor_id'], 'actor');
      final quote = _checkedQuote(entry['source_quote_sha256']);
      if (!_cited(sceneId, quote, origins)) {
        throw const FormatException('NPC witness lacks scene source');
      }
      final NpcWitnessMode mode;
      switch (entry['mode']) {
        case 'present':
          mode = NpcWitnessMode.present;
        case 'reported':
          mode = NpcWitnessMode.reported;
        default:
          throw const FormatException('Unknown NPC witness channel');
      }
      witnesses.add(NpcSceneWitness(
        sceneId: sceneId, actorId: actorId, mode: mode,
      ));
    }

    final rules = <NpcSocialRule>[];
    for (final entry in rawRules) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Malformed NPC event memory rule');
      }
      _fields(entry, {
        'memory_id', 'scene_id', 'choice_id', 'observer_id', 'kind',
        'related_actor_id', 'relationship_delta', 'max_triggers',
        'source_quote_sha256',
      }, 'memory');
      final id = _checkedId(entry['memory_id'], 'memory');
      final sceneId = _checkedId(entry['scene_id'], 'scene');
      final choiceId = _checkedId(entry['choice_id'], 'choice');
      final observer = _checkedId(entry['observer_id'], 'observer');
      final quote = _checkedQuote(entry['source_quote_sha256']);
      if (!_cited(sceneId, quote, origins)) {
        throw const FormatException('NPC memory lacks scene source');
      }
      final related = entry['related_actor_id'];
      if (related != null) _checkedId(related, 'related actor');
      if (entry['relationship_delta'] is! int ||
          entry['max_triggers'] is! int) {
        throw const FormatException('Invalid NPC social numeric bounds');
      }
      final kindName = entry['kind'];
      NpcMemoryKind? kind;
      for (final value in NpcMemoryKind.values) {
        if (value.name == kindName) { kind = value; break; }
      }
      if (kind == null) {
        throw const FormatException('Unrecognized NPC memory kind');
      }
      rules.add(NpcSocialRule(
        memoryId: id, sceneId: sceneId, choiceId: choiceId,
        observerId: observer, kind: kind,
        relatedActorId: related as String?,
        relationshipDelta: entry['relationship_delta'] as int,
        maxTriggers: entry['max_triggers'] as int,
      ));
    }
    final choiceGates = <NpcSocialChoiceGate>[];
    if (marker == choiceGateFormat || marker == itemTransferFormat) {
      final rawGates = raw['choice_gates'];
      if (rawGates is! List ||
          (marker == choiceGateFormat && rawGates.isEmpty) ||
          rawGates.length > 128) {
        throw const FormatException('Invalid NPC social decision gates');
      }
      for (final entry in rawGates) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Malformed NPC decision review');
        }
        _fields(entry, {
          'scene_id', 'choice_id', 'actor_id', 'required_memory_id',
          'minimum_trust_to_player', 'source_quote_sha256',
        }, 'choice gate');
        final sceneId = _checkedId(entry['scene_id'], 'choice scene');
        final choiceId = _checkedId(entry['choice_id'], 'choice');
        final actorId = _checkedId(entry['actor_id'], 'choice actor');
        final memory = entry['required_memory_id'];
        final trust = entry['minimum_trust_to_player'];
        if (memory != null) _checkedId(memory, 'required memory');
        if (trust != null && trust is! int) {
          throw const FormatException('Invalid NPC trust condition');
        }
        final quote = _checkedQuote(entry['source_quote_sha256']);
        if (!_cited(sceneId, quote, origins)) {
          throw const FormatException('NPC choice gate lacks scene source');
        }
        final targetChapter = origins[sceneId]?['chapter_index'];
        if (targetChapter is! int) {
          throw const FormatException('Unknown chapter for NPC choice gate');
        }
        if (memory != null) {
          final relevant = rules.where((rule) =>
              rule.observerId == actorId &&
              rule.memoryId == memory).toList();
          if (relevant.length != 1 ||
              (origins[relevant.single.sceneId]?['chapter_index'] as int) >
                  targetChapter) {
            throw const FormatException(
                'NPC choice requires an event from a future chapter');
          }
        }
        if (trust != null && !rules.any((rule) =>
            rule.observerId == actorId &&
            rule.relatedActorId == 'player' &&
            rule.relationshipDelta > 0 &&
            origins[rule.sceneId]?['chapter_index'] is int &&
            (origins[rule.sceneId]!['chapter_index'] as int) <= targetChapter)) {
          throw const FormatException(
              'NPC choice trust cannot precede its source event');
        }
        choiceGates.add(NpcSocialChoiceGate(
          sceneId: sceneId, choiceId: choiceId, actorId: actorId,
          requiredMemoryId: memory as String?,
          minimumTrustToPlayer: trust as int?,
        ));
      }
    }
    final itemTransfers = <NpcItemTransfer>[];
    if (marker == itemTransferFormat) {
      final rawTransfers = raw['item_transfers'];
      if (rawTransfers is! List || rawTransfers.isEmpty ||
          rawTransfers.length > 128) {
        throw const FormatException('Invalid reviewed NPC item transfers');
      }
      for (final entry in rawTransfers) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Malformed NPC item transfer');
        }
        _fields(entry, {
          'scene_id', 'choice_id', 'item_id', 'from_actor_id',
          'to_actor_id', 'source_quote_sha256',
        }, 'item custody');
        final scene = _checkedId(entry['scene_id'], 'item scene');
        final choice = _checkedId(entry['choice_id'], 'item choice');
        final item = _checkedId(entry['item_id'], 'item');
        final from = _checkedId(entry['from_actor_id'], 'item sender');
        final to = _checkedId(entry['to_actor_id'], 'item recipient');
        if (!_cited(scene,
            _checkedQuote(entry['source_quote_sha256']), origins)) {
          throw const FormatException('NPC item transfer lacks scene source');
        }
        itemTransfers.add(NpcItemTransfer(
          sceneId: scene, choiceId: choice, itemId: item,
          fromActorId: from, toActorId: to,
        ));
      }
    }
    final book = NpcSocialRulebook(
      blueprintHash: blueprint.blueprintHash,
      witnesses: witnesses,
      rules: rules,
      choiceGates: choiceGates,
      itemTransfers: itemTransfers,
      requireReviewedWitnesses: true,
    );
    book.validate(blueprint);
    return book;
  }
}
