import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'codec.dart';
import 'world_state.dart';

/// JSON-only adaptation contract (M1.7.1); not yet a ZIP .bworld package.
/// story_engine remains the selected scenario runtime per ADR-001.
class StoryBlueprint {
  StoryBlueprint._({
    required this.bookId,
    required this.title,
    required this.rightsStatus,
    required this.sourceFingerprint,
    required this.entrySceneId,
    required this.blueprintHash,
    required this.scenes,
    required this.items,
    required this.facts,
    required this.actors,
    required this.initial,
  });

  final String bookId;
  final String title;
  final String rightsStatus;
  final String? sourceFingerprint;
  final String entrySceneId;
  /// Exact canonical JSON blueprint SHA-256; not a source book fingerprint.
  final String blueprintHash;
  final Map<String, BlueprintScene> scenes;
  final Set<String> items;
  final Set<String> facts;
  final Set<String> actors;
  final WorldState initial;

  factory StoryBlueprint.fromJson(Object? value) {
    final root = jsonObject(value, 'story_blueprint');
    assertFields(root, 'story_blueprint', {
      'format', 'schema_version', 'book_id', 'title',
      'entry_scene_id', 'rights_status', 'source_fingerprint',
      'supported_modes', 'items', 'facts', 'actors',
      'initial_state', 'scenes',
    }, {
      'format', 'schema_version', 'book_id', 'title',
      'entry_scene_id', 'rights_status', 'source_fingerprint',
      'supported_modes', 'items', 'facts', 'actors',
      'initial_state', 'scenes',
    });
    // v1 demo stays strict; private books require an independently verified
    // v2 ZIP manifest and matching SHA256 source provenance at import time.
    final rights = root['rights_status'];
    final fingerprint = root['source_fingerprint'];
    final isOriginal = rights == 'original_demo' && fingerprint == null;
    final isPrivate = rights == 'private_adaptation' &&
        fingerprint is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint);
    if (root['format'] != 'ai_story_blueprint_v1' ||
        root['schema_version'] != 1 ||
        (!isOriginal && !isPrivate) ||
        root['title'] is! String ||
        (root['title'] as String).trim().isEmpty ||
        (root['title'] as String).length > 256) {
      throw const FormatException('Unsupported blueprint identity/version');
    }
    final modes = jsonObject(root['supported_modes'], 'supported_modes');
    assertFields(modes, 'supported_modes',
      {'roles', 'plots', 'interactions'},
      {'roles', 'plots', 'interactions'});
    final allowedModes = <String, Set<String>>{
      'roles': {'PROTAGONIST', 'CUSTOM', 'BOOK_CHARACTER'},
      'plots': {'CANON', 'ALTER_FATE', 'FREE_WORLD'},
      'interactions': {'CLASSIC', 'HYBRID', 'AI_FREEFORM'},
    };
    for (final entry in allowedModes.entries) {
      final enabled = jsonArray(modes[entry.key], entry.key);
      if (enabled.isEmpty || enabled.toSet().length != enabled.length ||
          enabled.any((value) => value is! String ||
              !entry.value.contains(value))) {
        throw FormatException('Invalid supported mode: ${entry.key}');
      }
    }
    // A declared mode must be truly executable by this prototype.
    if ((modes['roles'] as List).length != 1 ||
        (modes['roles'] as List).single != 'PROTAGONIST' ||
        (modes['plots'] as List).length != 1 ||
        (modes['plots'] as List).single !=
            (isOriginal ? 'CANON' : 'ALTER_FATE') ||
        (modes['interactions'] as List).length != 1 ||
        (modes['interactions'] as List).single != 'CLASSIC') {
      throw const FormatException('Unsupported M1.7 prototype modes');
    }
    final items = _readIdSet(root['items'], 'items');
    final facts = _readIdSet(root['facts'], 'facts');
    final actors = _readIdSet(root['actors'], 'actors');
    if (!actors.contains('player')) {
      throw const FormatException('A player actor is required');
    }
    final initial = WorldState.fromJson(root['initial_state']);
    final entry = jsonId(root['entry_scene_id'], 'entry_scene_id');
    if (initial.sceneId != entry) {
      throw const FormatException('Initial state does not match entry');
    }
    final list = jsonArray(root['scenes'], 'scenes');
    if (list.isEmpty || list.length > 5000) {
      throw const FormatException('Invalid scene count');
    }
    final scenes = <String, BlueprintScene>{};
    final choiceIds = <String>{};
    for (final raw in list) {
      final scene = BlueprintScene.fromJson(raw);
      if (scenes.containsKey(scene.id)) {
        throw FormatException('Duplicate scene ID: ${scene.id}');
      }
      if (scene.choices.length > 100) {
        throw const FormatException('Too many choices in scene');
      }
      for (final choice in scene.choices) {
        if (!choiceIds.add(choice.id)) {
          throw FormatException('Duplicate choice ID: ${choice.id}');
        }
      }
      scenes[scene.id] = scene;
    }
    if (!scenes.containsKey(entry) ||
        !scenes.values.any((scene) => scene.terminal)) {
      throw const FormatException('Missing entry or terminal scene');
    }
    if (initial.inventory.difference(items).isNotEmpty ||
        initial.knowledge.keys.any((actor) => !actors.contains(actor)) ||
        initial.knowledge.values.any((set) => set.difference(facts).isNotEmpty)) {
      throw const FormatException('Invalid initial catalog references');
    }
    for (final scene in scenes.values) {
      for (final choice in scene.choices) {
        if (!scenes.containsKey(choice.nextSceneId)) {
          throw FormatException('Missing destination: ${choice.nextSceneId}');
        }
        for (final rule in [...choice.conditions, ...choice.effects]) {
          if (rule.id != null) {
            final catalog = switch (rule.op) {
              'has_item' || 'grant_item' || 'consume_item' => items,
              'knows_fact' || 'learn_fact' => facts,
              'stat_at_least' || 'stat_delta' => initial.stats.keys.toSet(),
              'flag_is' || 'set_flag' => initial.flags.keys.toSet(),
              _ => <String>{},
            };
            if (!catalog.contains(rule.id)) {
              throw FormatException('Unknown referenced ID: ${rule.id}');
            }
          }
          if (rule.actor != null && !actors.contains(rule.actor)) {
            throw FormatException('Unknown knowledge actor: ${rule.actor}');
          }
        }
      }
    }
    final reachable = <String>{entry};
    final toVisit = <String>[entry];
    while (toVisit.isNotEmpty) {
      final scene = scenes[toVisit.removeLast()]!;
      for (final choice in scene.choices) {
        if (reachable.add(choice.nextSceneId)) {
          toVisit.add(choice.nextSceneId);
        }
      }
    }
    if (reachable.length != scenes.length ||
        !reachable.any((id) => scenes[id]!.terminal)) {
      throw const FormatException('Unreachable scene or ending');
    }
    return StoryBlueprint._(
      bookId: jsonId(root['book_id'], 'book_id'),
      title: root['title'] as String,
      rightsStatus: rights as String,
      sourceFingerprint: fingerprint as String?,
      entrySceneId: entry,
      blueprintHash: sha256.convert(utf8.encode(canonicalJson(root))).toString(),
      scenes: Map.unmodifiable(scenes),
      items: Set.unmodifiable(items),
      facts: Set.unmodifiable(facts),
      actors: Set.unmodifiable(actors),
      initial: initial,
    );
  }

  static Set<String> _readIdSet(Object? raw, String field) {
    final list = jsonArray(raw, field);
    if (list.length > 10000) throw FormatException('$field too large');
    final ids = list.map((value) => jsonId(value, field)).toList();
    if (ids.toSet().length != ids.length) {
      throw FormatException('Duplicate $field');
    }
    return ids.toSet();
  }
}

class BlueprintScene {
  BlueprintScene._(this.id, this.text, this.terminal, this.choices);

  final String id;
  final String text;
  final bool terminal;
  final List<BlueprintChoice> choices;

  factory BlueprintScene.fromJson(Object? value) {
    final json = jsonObject(value, 'scene');
    assertFields(json, 'scene',
      {'id', 'text', 'terminal', 'choices'},
      {'id', 'text', 'terminal', 'choices'});
    if (json['text'] is! String ||
        (json['text'] as String).length > 50000 ||
        json['terminal'] is! bool) {
      throw const FormatException('Invalid scene body or terminal flag');
    }
    final choices = jsonArray(json['choices'], 'scene.choices')
      .map(BlueprintChoice.fromJson).toList(growable: false);
    if (json['terminal'] == true && choices.isNotEmpty ||
        json['terminal'] == false && choices.isEmpty) {
      throw const FormatException('Terminal/choices mismatch');
    }
    return BlueprintScene._(
      jsonId(json['id'], 'scene.id'), json['text'] as String,
      json['terminal'] as bool, List.unmodifiable(choices),
    );
  }
}

class BlueprintChoice {
  BlueprintChoice._(
    this.id, this.label, this.nextSceneId, this.conditions, this.effects);

  final String id;
  final String label;
  final String nextSceneId;
  final List<TypedRule> conditions;
  final List<TypedRule> effects;

  factory BlueprintChoice.fromJson(Object? value) {
    final json = jsonObject(value, 'choice');
    assertFields(json, 'choice',
      {'id', 'label', 'next_scene_id', 'conditions', 'effects'},
      {'id', 'label', 'next_scene_id', 'conditions', 'effects'});
    if (json['label'] is! String ||
        (json['label'] as String).trim().isEmpty ||
        (json['label'] as String).length > 600) {
      throw const FormatException('Invalid choice label');
    }
    return BlueprintChoice._(
      jsonId(json['id'], 'choice.id'),
      json['label'] as String,
      jsonId(json['next_scene_id'], 'choice.next_scene_id'),
      List.unmodifiable(jsonArray(json['conditions'], 'conditions')
          .map((v) => TypedRule.fromJson(v, effect: false))),
      List.unmodifiable(jsonArray(json['effects'], 'effects')
          .map((v) => TypedRule.fromJson(v, effect: true))),
    );
  }
}

/// Typed, bounded DSL: never eval/source code/function calls from a book.
class TypedRule {
  const TypedRule._(this.op, this.id, this.actor, this.amount, this.value);

  final String op;
  final String? id;
  final String? actor;
  final int? amount;
  final bool? value;

  factory TypedRule.fromJson(Object? raw, {required bool effect}) {
    final json = jsonObject(raw, 'rule');
    final op = jsonId(json['op'], 'rule.op');
    Set<String> required;
    switch (op) {
      case 'has_item' when !effect:
        required = {'op', 'id'};
      case 'flag_is' when !effect:
        required = {'op', 'id', 'value'};
      case 'stat_at_least' when !effect:
        required = {'op', 'id', 'amount'};
      case 'knows_fact' when !effect:
        required = {'op', 'id', 'actor'};
      case 'tick_at_least' when !effect:
        required = {'op', 'amount'};
      case 'grant_item' || 'consume_item' when effect:
        required = {'op', 'id'};
      case 'set_flag' when effect:
        required = {'op', 'id', 'value'};
      case 'stat_delta' when effect:
        required = {'op', 'id', 'amount'};
      case 'learn_fact' when effect:
        required = {'op', 'id', 'actor'};
      case 'advance_time' when effect:
        required = {'op', 'amount'};
      default:
        throw FormatException('Unsupported rule operation: $op');
    }
    assertFields(json, 'rule.$op', required, required);
    final id = required.contains('id') ? jsonId(json['id'], 'rule.id') : null;
    final actor = required.contains('actor')
        ? jsonId(json['actor'], 'rule.actor') : null;
    final amount = required.contains('amount') ? json['amount'] : null;
    if (amount != null && (amount is! int ||
        (effect ? (amount == 0 || amount < -1000 || amount > 1000)
            : (amount < 0 || amount > 1000000)) ||
        (op == 'advance_time' && amount < 1))) {
      throw const FormatException('Invalid rule amount');
    }
    final value = required.contains('value') ? json['value'] : null;
    if (required.contains('value') && value is! bool) {
      throw const FormatException('Invalid boolean rule value');
    }
    return TypedRule._(op, id, actor, amount as int?, value as bool?);
  }
}
