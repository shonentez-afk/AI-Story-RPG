import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'codec.dart';

/// A dynamically created, NONCANONICAL scene. The source-book cursor
/// remains at the last reached signed scene; a separate immutable overlay
/// carries an alternative story forward without forking the rule engine.
final class AlternateNarrativeScene {
  const AlternateNarrativeScene({
    required this.id, required this.text, this.terminal = false,
  });
  final String id;
  final String text;
  final bool terminal;

  Map<String, dynamic> toJson() => {
    'id': id, 'text': text, 'terminal': terminal,
  };

  factory AlternateNarrativeScene.fromJson(Object? source) {
    final raw = jsonObject(source, 'alternate_scene');
    assertFields(raw, 'alternate_scene',
        {'id', 'text', 'terminal'}, {'id', 'text', 'terminal'});
    final id = jsonId(raw['id'], 'alternate_scene.id');
    final text = raw['text'];
    if (!RegExp(r'^gm_scene_[1-9][0-9]{0,7}$').hasMatch(id) ||
        text is! String || text.trim() != text ||
        text.isEmpty || text.runes.length > 1200 ||
        RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e]').hasMatch(text) ||
        raw['terminal'] is! bool) {
      throw const FormatException('Invalid alternative narrative scene');
    }
    return AlternateNarrativeScene(
        id: id, text: text, terminal: raw['terminal'] as bool);
  }
}

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
    this.alternateScene,
  })  : stats = Map.unmodifiable(stats),
        inventory = Set.unmodifiable(inventory),
        flags = Map.unmodifiable(flags),
        knowledge = Map.unmodifiable(knowledge.map(
            (actor, facts) => MapEntry(actor, Set<String>.unmodifiable(facts)))) {
    jsonId(sceneId, 'scene_id');
    if (alternateScene != null && revision == 0) {
      throw const FormatException('Alternative scene cannot be initial state');
    }
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
  /// Absent for every historical save and for unaffected CANON play.
  final AlternateNarrativeScene? alternateScene;
  bool get plotDiverged => alternateScene != null;
  String get activeSceneId => alternateScene?.id ?? sceneId;

  Map<String, dynamic> toJson() => {
    'scene_id': sceneId,
    if (alternateScene != null) 'alternate_scene': alternateScene!.toJson(),
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
      {'scene_id', 'revision', 'tick', 'stats', 'inventory', 'flags', 'knowledge',
       'alternate_scene'});
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
      alternateScene: data.containsKey('alternate_scene')
          ? AlternateNarrativeScene.fromJson(data['alternate_scene'])
          : null,
    );
  }
}
