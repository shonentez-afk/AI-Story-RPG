import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'blueprint.dart';
import 'codec.dart';
import 'world_state.dart';
import 'npc_social_ledger.dart';

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
    required this.blueprintHash,
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
  /// Prevents applying this event log to another version of the rules.
  final String blueprintHash;
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
    'blueprint_sha256': blueprintHash,
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
    required String blueprintHash,
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
      blueprintHash: blueprintHash,
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
      blueprintHash: blueprintHash,
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
      'next_scene_id', 'blueprint_sha256', 'previous_hash',
      'before_state_hash',
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
      blueprintHash: verifiedHash('blueprint_sha256'),
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
  StoryWorld(this.blueprint, {this.socialRulebook})
      : _state = blueprint.initial {
    socialRulebook?.validate(blueprint);
  }

  final StoryBlueprint blueprint;
  /// Optional signed social decision contract, never inferred from scene text.
  final NpcSocialRulebook? socialRulebook;
  WorldState _state;
  final List<WorldEvent> _events = [];
  final Map<String, WorldEvent> _byAction = {};

  WorldState get state => _state;
  List<WorldEvent> get events => List.unmodifiable(_events);
  bool get isTerminal => blueprint.scenes[_state.sceneId]!.terminal;

  /// Committed decisions that explicitly taught [factId] to [actorId].
  ///
  /// This is derived from the verified event chain and the exact blueprint,
  /// never from the chronological order of chapters or NPC display names.
  /// Initial knowledge has no learning event. Failed, speculative and
  /// unvisited choices are excluded; replay produces identical evidence.
  List<WorldEvent> factLearningEvents(String actorId, String factId) {
    jsonId(actorId, 'actor_id');
    jsonId(factId, 'fact_id');
    if (!blueprint.actors.contains(actorId) ||
        !blueprint.facts.contains(factId)) {
      throw const FormatException('Unknown actor or fact');
    }
    final evidence = <WorldEvent>[];
    for (final event in _events) {
      final scene = blueprint.scenes[event.sceneId]!;
      final choice = scene.choices.singleWhere((c) => c.id == event.choiceId);
      if (choice.effects.any((effect) =>
          effect.op == 'learn_fact' &&
          effect.actor == actorId &&
          effect.id == factId)) {
        evidence.add(event);
      }
    }
    return List<WorldEvent>.unmodifiable(evidence);
  }

  /// Does the current campaign actually know this fact? Unlike a source
  /// dossier mention, this reflects only initial state and committed effects.
  bool actorKnowsFact(String actorId, String factId) {
    jsonId(actorId, 'actor_id');
    jsonId(factId, 'fact_id');
    if (!blueprint.actors.contains(actorId) ||
        !blueprint.facts.contains(factId)) {
      throw const FormatException('Unknown actor or fact');
    }
    return _state.knowledge[actorId]?.contains(factId) ?? false;
  }


  /// Missing prerequisites for a *reviewed* dialogue turn or action.
  ///
  /// The caller must supply exact fact IDs from a validated source/review
  /// contract. Free-form dialogue text is never searched or trusted here.
  /// Unknown actors/facts fail closed, even if their display names match.
  /// This method does not prove that the words were spoken in the book.
  List<String> missingKnowledgeForActor(
      String actorId, Iterable<String> requiredFactIds) {
    jsonId(actorId, 'actor_id');
    if (!blueprint.actors.contains(actorId)) {
      throw const FormatException('Unknown knowledge actor');
    }
    final missing = <String>{};
    for (final factId in requiredFactIds) {
      jsonId(factId, 'fact_id');
      if (!blueprint.facts.contains(factId)) {
        throw const FormatException('Unknown required fact');
      }
      if (!(_state.knowledge[actorId]?.contains(factId) ?? false)) {
        missing.add(factId);
      }
    }
    return List<String>.unmodifiable(missing.toList()..sort());
  }

  /// An isolated tentative world for coordinating with the scenario runtime.
  /// No I/O occurs here; a rejected proposal never mutates the live world.
  StoryWorld fork() {
    final draft = StoryWorld(blueprint, socialRulebook: socialRulebook);
    draft._state = _state;
    draft._events.addAll(_events);
    draft._byAction.addAll(_byAction);
    return draft;
  }

  /// Reason that an action is currently not available. The source of truth
  /// is the world-state rule interpreter, not the scenario presentation.
  String? choiceLockReason(String choiceId) {
    if (isTerminal) return 'terminal_scene';
    final scene = blueprint.scenes[_state.sceneId]!;
    BlueprintChoice? selected;
    for (final choice in scene.choices) {
      if (choice.id == choiceId) {
        selected = choice;
        break;
      }
    }
    if (selected == null) return 'choice_not_in_current_scene';
    for (final condition in selected.conditions) {
      if (!_matches(condition)) {
        return 'condition_not_met:${condition.op}';
      }
    }
    if (socialRulebook != null && socialRulebook!.choiceGates.isNotEmpty) {
      for (final gate in socialRulebook!.choiceGates) {
        if (gate.sceneId != _state.sceneId || gate.choiceId != choiceId) {
          continue;
        }
        final social = NpcSocialLedger.inspect(this, socialRulebook!);
        if (gate.requiredMemoryId != null &&
            !social.hasMemory(gate.actorId, gate.requiredMemoryId!)) {
          return 'condition_not_met:npc_memory';
        }
        if (gate.minimumTrustToPlayer != null &&
            social.directedScore(gate.actorId, 'player') <
                gate.minimumTrustToPlayer!) {
          return 'condition_not_met:npc_trust';
        }
      }
    }
    if (socialRulebook != null && socialRulebook!.itemTransfers.isNotEmpty) {
      final custody = NpcSocialLedger.inspect(this, socialRulebook!);
      final matching = socialRulebook!.itemTransfers.where((transfer) =>
          transfer.sceneId == _state.sceneId &&
          transfer.choiceId == choiceId).toList();
      for (final transfer in matching) {
        if (custody.itemOwner(transfer.itemId) != transfer.fromActorId) {
          return 'condition_not_met:npc_item_owner';
        }
      }
      for (final effect in selected.effects) {
        if (effect.op != 'grant_item') continue;
        final isReviewedReturn = matching.any((transfer) =>
            transfer.itemId == effect.id &&
            transfer.toActorId == 'player');
        if (!isReviewedReturn) {
          final actualOwner = custody.itemOwner(effect.id!);
          if (actualOwner != null && actualOwner != 'player') {
            return 'condition_not_met:npc_item_custody';
          }
        }
      }
    }
    return null;
  }

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
    final lockReason = choiceLockReason(choiceId);
    if (lockReason != null) return _denied(lockReason);
    // The choice exists because choiceLockReason validated its scene and
    // predicates. Keep the actual definition from this exact blueprint.
    final choice = blueprint.scenes[_state.sceneId]!.choices
        .firstWhere((option) => option.id == choiceId);

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
      blueprintHash: blueprint.blueprintHash,
      previousHash: _events.isEmpty ? null : _events.last.hash,
      beforeStateHash: _state.stateHash,
      afterStateHash: nextState.stateHash,
    );
    if (socialRulebook != null && socialRulebook!.itemTransfers.isNotEmpty) {
      // Pre-commit verification must never let a partial transfer reach the
      // durable SQLite event chain. No world state is published on failure.
      final draft = fork();
      draft._state = nextState;
      draft._events.add(event);
      draft._byAction[actionId] = event;
      try {
        NpcSocialLedger.inspect(draft, socialRulebook!);
      } on FormatException {
        return _denied('npc_item_custody_conflict');
      }
    }
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
    StoryBlueprint blueprint, Iterable<Object?> recordedEvents, {
    int? expectedSequence,
    String? expectedStateHash,
    NpcSocialRulebook? socialRulebook,
  }) {
    final world = StoryWorld(blueprint, socialRulebook: socialRulebook);
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
    // Without an expected head, a shortened valid prefix looks like a
    // legitimate earlier checkpoint. Callers must bind the expected head.
    if ((expectedSequence != null &&
            world.state.revision != expectedSequence) ||
        (expectedStateHash != null &&
            world.state.stateHash != expectedStateHash)) {
      throw const FormatException('Incomplete or mismatched event log head');
    }
    return world;
  }
}
