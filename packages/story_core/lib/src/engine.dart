import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'blueprint.dart';
import 'codec.dart';
import 'world_state.dart';

enum DecisionStatus { applied, denied, duplicate }

class DecisionResult {
  const DecisionResult({
    required this.status,
    required this.state,
    this.reason,
    this.event,
  });

  final DecisionStatus status;
  final String? reason;
  final WorldState state;
  final WorldEvent? event;

  bool get applied => status == DecisionStatus.applied;
}

/// Deterministic, immutable record of a committed world action. Wall-clock
/// timestamps are intentionally absent: simulations must replay identically
/// on Windows, Android and machines with different time zones.
class WorldEvent {
  WorldEvent._({
    required this.sequence,
    required this.actionId,
    required this.actor,
    required this.sceneId,
    required this.choiceId,
    required this.nextSceneId,
    required this.previousHash,
    required this.beforeStateHash,
    required this.afterStateHash,
    required this.hash,
  });

  final int sequence;
  final String actionId;
  final String actor;
  final String sceneId;
  final String choiceId;
  final String nextSceneId;
  final String? previousHash;
  final String beforeStateHash;
  final String afterStateHash;
  final String hash;

  Map<String, dynamic> toJson() => {..._payload(), 'hash': hash};

  Map<String, dynamic> _payload() => {
    'sequence': sequence,
    'action_id': actionId,
    'actor': actor,
    'scene_id': sceneId,
    'choice_id': choiceId,
    'next_scene_id': nextSceneId,
    'previous_hash': previousHash,
    'before_state_hash': beforeStateHash,
    'after_state_hash': afterStateHash,
  };

  factory WorldEvent.create({
    required int sequence,
    required String actionId,
    required String actor,
    required String sceneId,
    required String choiceId,
    required String nextSceneId,
    required String? previousHash,
    required String beforeStateHash,
    required String afterStateHash,
  }) {
    final event = WorldEvent._(
      sequence: sequence,
      actionId: actionId,
      actor: actor,
      sceneId: sceneId,
      choiceId: choiceId,
      nextSceneId: nextSceneId,
      previousHash: previousHash,
      beforeStateHash: beforeStateHash,
      afterStateHash: afterStateHash,
      hash: '',
    );
    final hash = sha256.convert(
      utf8.encode(canonicalJson(event._payload())),
    ).toString();
    return WorldEvent._(
      sequence: sequence,
      actionId: actionId,
      actor: actor,
      sceneId: sceneId,
      choiceId: choiceId,
      nextSceneId: nextSceneId,
      previousHash: previousHash,
      beforeStateHash: beforeStateHash,
      afterStateHash: afterStateHash,
      hash: hash,
    );
  }

  factory WorldEvent.fromJson(Object? raw) {
    final data = jsonObject(raw, 'world_event');
    const keys = {
      'sequence', 'action_id', 'actor', 'scene_id', 'choice_id',
      'next_scene_id', 'previous_hash', 'before_state_hash',
      'after_state_hash', 'hash',
    };
    assertFields(data, 'world_event', keys, keys);
    if (data['sequence'] is! int || (data['sequence'] as int) < 1) {
      throw const FormatException('Invalid event sequence');
    }
    String verifiedHash(String field) {
      final value = data[field];
      if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
        throw FormatException('Invalid event $field');
      }
      return value;
    }
    final previous = data['previous_hash'];
    if (previous != null &&
        (previous is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(previous))) {
      throw const FormatException('Invalid previous hash');
    }
    return WorldEvent._(
      sequence: data['sequence'] as int,
      actionId: jsonId(data['action_id'], 'action_id'),
      actor: jsonId(data['actor'], 'actor'),
      sceneId: jsonId(data['scene_id'], 'scene_id'),
      choiceId: jsonId(data['choice_id'], 'choice_id'),
      nextSceneId: jsonId(data['next_scene_id'], 'next_scene_id'),
      previousHash: previous as String?,
      beforeStateHash: verifiedHash('before_state_hash'),
      afterStateHash: verifiedHash('after_state_hash'),
      hash: verifiedHash('hash'),
    );
  }
}

/// FR-CORE-01/04/05: offline world rules and confirmed events only.
/// No Flutter, network, LLM, Python or arbitrary user-supplied executable code.
/// Navigation presentation remains the responsibility of story_engine.
class StoryWorld {
  StoryWorld(this.blueprint) : _state = blueprint.initial;

  final StoryBlueprint blueprint;
  WorldState _state;
  final List<WorldEvent> _events = [];
  final Map<String, WorldEvent> _byAction = {};

  WorldState get state => _state;
  List<WorldEvent> get events => List.unmodifiable(_events);
  bool get isTerminal => blueprint.scenes[_state.sceneId]!.terminal;

  DecisionResult apply({
    required String actionId,
    required String choiceId,
    int? expectedRevision,
    String actor = 'player',
  }) {
    jsonId(actionId, 'action_id');
    jsonId(choiceId, 'choice_id');
    jsonId(actor, 'actor');
    final duplicate = _byAction[actionId];
    if (duplicate != null) {
      if (duplicate.choiceId != choiceId || duplicate.actor != actor) {
        throw const FormatException('Action ID reused for another operation');
      }
      return DecisionResult(
        status: DecisionStatus.duplicate, reason: 'already_committed',
        state: _state, event: duplicate,
      );
    }
    if (actor != 'player' || !blueprint.actors.contains(actor)) {
      return _denied('actor_not_supported');
    }
    if (expectedRevision != null && expectedRevision != _state.revision) {
      return _denied('stale_revision');
    }
    final scene = blueprint.scenes[_state.sceneId]!;
    if (scene.terminal) return _denied('terminal_scene');
    BlueprintChoice? choice;
    for (final option in scene.choices) {
      if (option.id == choiceId) {
        choice = option;
        break;
      }
    }
    if (choice == null) return _denied('choice_not_in_current_scene');
    for (final condition in choice.conditions) {
      if (!_matches(condition)) {
        return _denied('condition_not_met:${condition.op}');
      }
    }

    // Copy first, evaluate ALL effects and only then replace authoritative
    // state. A failed effect cannot partially spend a key or leak a fact.
    final stats = Map<String, int>.of(_state.stats);
    final items = Set<String>.of(_state.inventory);
    final flags = Map<String, bool>.of(_state.flags);
    final knowledge = _state.knowledge.map(
      (actor, facts) => MapEntry(actor, Set<String>.of(facts)),
    );
    var tick = _state.tick + 1;
    for (final effect in choice.effects) {
      switch (effect.op) {
        case 'grant_item':
          items.add(effect.id!);
        case 'consume_item':
          if (!items.remove(effect.id)) return _denied('missing_item');
        case 'set_flag':
          flags[effect.id!] = effect.value!;
        case 'stat_delta':
          final next = stats[effect.id!]! + effect.amount!;
          if (next < 0 || next > 1000000) return _denied('stat_out_of_range');
          stats[effect.id!] = next;
        case 'learn_fact':
          knowledge.putIfAbsent(effect.actor!, () => <String>{})
              .add(effect.id!);
        case 'advance_time':
          tick += effect.amount!;
        default:
          throw StateError('Validated effect is unknown: ${effect.op}');
      }
    }
    if (tick > 100000000) return _denied('time_out_of_range');
    final nextState = WorldState(
      sceneId: choice.nextSceneId,
      revision: _state.revision + 1,
      tick: tick,
      stats: stats,
      inventory: items,
      flags: flags,
      knowledge: knowledge,
    );
    final event = WorldEvent.create(
      sequence: nextState.revision,
      actionId: actionId,
      actor: actor,
      sceneId: _state.sceneId,
      choiceId: choice.id,
      nextSceneId: choice.nextSceneId,
      previousHash: _events.isEmpty ? null : _events.last.hash,
      beforeStateHash: _state.stateHash,
      afterStateHash: nextState.stateHash,
    );
    _state = nextState;
    _events.add(event);
    _byAction[actionId] = event;
    return DecisionResult(
      status: DecisionStatus.applied, state: _state, event: event,
    );
  }

  DecisionResult _denied(String reason) => DecisionResult(
    status: DecisionStatus.denied, reason: reason, state: _state,
  );

  bool _matches(TypedRule rule) {
    switch (rule.op) {
      case 'has_item':
        return _state.inventory.contains(rule.id);
      case 'flag_is':
        return _state.flags[rule.id!] == rule.value;
      case 'stat_at_least':
        return _state.stats[rule.id!]! >= rule.amount!;
      case 'knows_fact':
        return _state.knowledge[rule.actor!]?.contains(rule.id) ?? false;
      case 'tick_at_least':
        return _state.tick >= rule.amount!;
    }
    throw StateError('Validated condition is unknown: ${rule.op}');
  }

  /// A checkpoint is verified by deterministic replay. Caller-supplied
  /// state blobs are NOT trusted as an alternative source of truth.
  static StoryWorld replay(
    StoryBlueprint blueprint, Iterable<Object?> recordedEvents,
  ) {
    final world = StoryWorld(blueprint);
    for (final raw in recordedEvents) {
      final expected = WorldEvent.fromJson(raw);
      final result = world.apply(
        actionId: expected.actionId,
        choiceId: expected.choiceId,
        actor: expected.actor,
        expectedRevision: expected.sequence - 1,
      );
      if (!result.applied ||
          canonicalJson(result.event!.toJson()) !=
              canonicalJson(expected.toJson())) {
        throw const FormatException(
            'Event chain altered or incompatible with this BookWorld');
      }
    }
    return world;
  }
}
