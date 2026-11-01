import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'codec.dart';

/// Only committed campaign data; no executable BookWorld code and no UI.
/// The authoritative state is never exposed as a mutable collection.
class WorldState {
  WorldState({
    required this.sceneId,
    this.revision = 0,
    this.tick = 0,
    Map<String, int> stats = const {},
    Set<String> inventory = const {},
    Map<String, bool> flags = const {},
    Map<String, Set<String>> knowledge = const {},
  })  : stats = Map.unmodifiable(stats),
        inventory = Set.unmodifiable(inventory),
        flags = Map.unmodifiable(flags),
        knowledge = Map.unmodifiable(knowledge.map(
            (actor, facts) => MapEntry(actor, Set<String>.unmodifiable(facts)))) {
    jsonId(sceneId, 'scene_id');
    if (revision < 0 || tick < 0 || tick > 100000000 ||
        stats.values.any((value) => value < 0 || value > 1000000)) {
      throw const FormatException('Invalid world counters');
    }
  }

  final String sceneId;
  final int revision;
  final int tick;
  final Map<String, int> stats;
  final Set<String> inventory;
  final Map<String, bool> flags;
  /// Individual knowledge sets, never a global shared secrets list.
  final Map<String, Set<String>> knowledge;

  Map<String, dynamic> toJson() => {
    'scene_id': sceneId,
    'revision': revision,
    'tick': tick,
    'stats': SplayTreeMap<String, int>.of(stats),
    'inventory': (inventory.toList()..sort()),
    'flags': SplayTreeMap<String, bool>.of(flags),
    'knowledge': SplayTreeMap<String, List<String>>.of(
      knowledge.map((actor, facts) =>
          MapEntry(actor, facts.toList()..sort())),
    ),
  };

  String get stateHash =>
      sha256.convert(utf8.encode(canonicalJson(toJson()))).toString();

  factory WorldState.fromJson(Object? raw) {
    final data = jsonObject(raw, 'world_state');
    assertFields(data, 'world_state',
      {'scene_id', 'revision', 'tick', 'stats', 'inventory', 'flags', 'knowledge'},
      {'scene_id', 'revision', 'tick', 'stats', 'inventory', 'flags', 'knowledge'});
    final stats = jsonObject(data['stats'], 'stats');
    final flags = jsonObject(data['flags'], 'flags');
    final knowledge = jsonObject(data['knowledge'], 'knowledge');
    final items = jsonArray(data['inventory'], 'inventory');
    if (data['revision'] is! int || data['tick'] is! int ||
        stats.values.any((v) => v is! int) ||
        flags.values.any((v) => v is! bool) ||
        items.any((v) => v is! String)) {
      throw const FormatException('Invalid world value types');
    }
    final itemIds = items.map((v) => jsonId(v, 'inventory item')).toList();
    if (itemIds.length != itemIds.toSet().length) {
      throw const FormatException('Duplicate inventory item');
    }
    final actorFacts = <String, Set<String>>{};
    for (final entry in knowledge.entries) {
      final actor = jsonId(entry.key, 'actor');
      final rawFacts = jsonArray(entry.value, 'knowledge');
      final facts = rawFacts.map((v) => jsonId(v, 'fact')).toList();
      if (facts.length != facts.toSet().length) {
        throw const FormatException('Duplicate known fact');
      }
      actorFacts[actor] = facts.toSet();
    }
    return WorldState(
      sceneId: jsonId(data['scene_id'], 'scene_id'),
      revision: data['revision'] as int,
      tick: data['tick'] as int,
      stats: stats.map((k, v) =>
          MapEntry(jsonId(k, 'stat'), v as int)),
      inventory: itemIds.toSet(),
      flags: flags.map((k, v) =>
          MapEntry(jsonId(k, 'flag'), v as bool)),
      knowledge: actorFacts,
    );
  }
}
