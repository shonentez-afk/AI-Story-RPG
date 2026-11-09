import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'blueprint.dart';
import 'character_id.dart';
import 'codec.dart';
import 'engine.dart';
import 'freeform_action.dart';
import 'book_causality.dart';

/// A reviewed *classification* of one committed game action, not a claim
/// inferred from prose or from an actor's displayed name.
enum NpcMemoryKind {
  witnessed,
  promiseReceived,
  promiseBroken,
  helped,
  betrayed,
  rumorHeard,
}

/// Witnessed in person and learned second-hand are NOT interchangeable.
/// Reviewed source citations live in bookworld_format, not in story_core.
enum NpcWitnessMode { present, reported }

/// Projected exclusively from committed events. Death cannot be reversed.
enum NpcLifeState { present, absent, dead }

class NpcLifeTransition {
  const NpcLifeTransition({
    required this.sceneId, required this.choiceId,
    required this.actorId, required this.nextState,
  });
  final String sceneId;
  final String choiceId;
  final String actorId;
  final NpcLifeState nextState;

  Map<String, Object?> toJson() => {
    'scene_id': sceneId, 'choice_id': choiceId,
    'actor_id': actorId, 'next_state': nextState.name,
  };
}

/// Presence in a precise scene, approved by the private author. This is
/// NOT inferred from a character's name or from their appearance in prose.
class NpcSceneWitness {
  const NpcSceneWitness({
    required this.sceneId,
    required this.actorId,
    required this.mode,
  });

  final String sceneId;
  final String actorId;
  final NpcWitnessMode mode;

  Map<String, Object?> toJson() => {
    'scene_id': sceneId,
    'actor_id': actorId,
    'mode': mode.name,
  };
}

/// A reviewed, *authoritative* prerequisite on one real game decision.
/// It never changes the stored WorldState; it is evaluated from committed
/// hash-chained events by StoryWorld before an action can be accepted.
/// Without an exact signed, source-locked rulebook, the gate cannot be used.
class NpcSocialChoiceGate {
  const NpcSocialChoiceGate({
    required this.sceneId,
    required this.choiceId,
    required this.actorId,
    this.requiredMemoryId,
    this.minimumTrustToPlayer,
  });

  final String sceneId;
  final String choiceId;
  final String actorId;
  final String? requiredMemoryId;
  final int? minimumTrustToPlayer;

  Map<String, Object?> toJson() => {
    'scene_id': sceneId,
    'choice_id': choiceId,
    'actor_id': actorId,
    'required_memory_id': requiredMemoryId,
    'minimum_trust_to_player': minimumTrustToPlayer,
  };
}

/// One source-reviewed custody transfer. Player inventory still changes
/// through the existing typed grant_item/consume_item effects. NPC custody
/// is recomputed from the SAME hash-chained committed game actions.
class NpcItemTransfer {
  const NpcItemTransfer({
    required this.sceneId,
    required this.choiceId,
    required this.itemId,
    required this.fromActorId,
    required this.toActorId,
  });

  final String sceneId;
  final String choiceId;
  final String itemId;
  final String fromActorId;
  final String toActorId;

  Map<String, Object?> toJson() => {
    'scene_id': sceneId,
    'choice_id': choiceId,
    'item_id': itemId,
    'from_actor_id': fromActorId,
    'to_actor_id': toActorId,
  };
}

/// A declarative, source-reviewable event annotation. It has no runtime
/// effect by itself; the optional relationship delta is a read-only
/// projection, NOT a hidden world mutation or a new blueprint DSL operation.
class NpcSocialRule {
  const NpcSocialRule({
    required this.memoryId,
    required this.sceneId,
    required this.choiceId,
    required this.observerId,
    required this.kind,
    this.relatedActorId,
    this.relationshipDelta = 0,
    this.maxTriggers = 1,
  });

  final String memoryId;
  final String sceneId;
  final String choiceId;
  final String observerId;
  final NpcMemoryKind kind;
  final String? relatedActorId;
  final int relationshipDelta;
  /// One event can be revisited: relationship farming is disallowed by default.
  final int maxTriggers;

  Map<String, Object?> toJson() => {
    'memory_id': memoryId,
    'scene_id': sceneId,
    'choice_id': choiceId,
    'observer_id': observerId,
    'kind': kind.name,
    'related_actor_id': relatedActorId,
    'relationship_delta': relationshipDelta,
    'max_triggers': maxTriggers,
  };
}

/// Reviewed source expectation for one future canonical book scene.
/// It cannot be inferred from a model's narrative proposal.
final class NpcCanonInvariant {
  const NpcCanonInvariant({
    required this.sceneId, required this.actorId,
    required this.forbiddenMemoryId,
    this.minimumTrust, this.maximumTrust,
  });
  final String sceneId, actorId, forbiddenMemoryId;
  final int? minimumTrust, maximumTrust;
  Map<String, Object?> toJson() => {
    'scene_id': sceneId, 'actor_id': actorId,
    'forbidden_memory_id': forbiddenMemoryId,
    'minimum_trust': minimumTrust,
    'maximum_trust': maximumTrust,
  };
}

/// A deterministic NPC response to source-reviewed contact, not model prose.
final class NpcAutomaticReaction {
  const NpcAutomaticReaction({
    required this.sceneId,
    required this.actorId,
    required this.triggerMemoryId,
    required this.minimumTrust,
    required this.responseMemoryId,
    required this.nextGoalId,
    this.relayFactId,
    this.relayToActorId,
  });

  final String sceneId, actorId, triggerMemoryId, responseMemoryId;
  final int minimumTrust;
  final String nextGoalId;
  final String? relayFactId, relayToActorId;

  Map<String, Object?> toJson() => {
    'scene_id': sceneId,
    'actor_id': actorId,
    'trigger_memory_id': triggerMemoryId,
    'minimum_trust': minimumTrust,
    'response_memory_id': responseMemoryId,
    'next_goal_id': nextGoalId,
    'relay_fact_id': relayFactId,
    'relay_to_actor_id': relayToActorId,
  };

  bool activated(FreeformNpcInteraction contact, int trust) =>
      contact.actorId == actorId &&
      contact.memoryId == triggerMemoryId &&
      trust >= minimumTrust &&
      (relayFactId == null || contact.learnFactId == relayFactId);
}

/// Bound to one exact, validated blueprint. A caller must separately
/// establish source provenance and editorial approval before using rules
/// to present a literary adaptation. Rules are not embedded in .bworld yet.
class NpcSocialRulebook {
  NpcSocialRulebook({
    required this.blueprintHash,
    required List<NpcSocialRule> rules,
    List<NpcSceneWitness> witnesses = const [],
    List<NpcSocialChoiceGate> choiceGates = const [],
    List<NpcItemTransfer> itemTransfers = const [],
    List<NpcLifeTransition> lifeTransitions = const [],
    this.requireReviewedWitnesses = false,
    this.dynamicInteractionsEnabled = false,
    List<NpcCanonInvariant> canonInvariants = const [],
    this.bookCausality,
    List<NpcAutomaticReaction> automaticReactions = const [],
  }) : automaticReactions = List.unmodifiable(automaticReactions),
       canonInvariants = List.unmodifiable(canonInvariants),
       rules = List.unmodifiable(rules),
       witnesses = List.unmodifiable(witnesses),
       choiceGates = List.unmodifiable(choiceGates),
       itemTransfers = List.unmodifiable(itemTransfers),
       lifeTransitions = List.unmodifiable(lifeTransitions);

  final String blueprintHash;
  final List<NpcSocialRule> rules;
  final List<NpcSceneWitness> witnesses;
  final List<NpcSocialChoiceGate> choiceGates;
  final List<NpcItemTransfer> itemTransfers;
  final List<NpcLifeTransition> lifeTransitions;
  final List<NpcCanonInvariant> canonInvariants;
  final BookCausalGraph? bookCausality;
  final List<NpcAutomaticReaction> automaticReactions;
  final bool dynamicInteractionsEnabled;
  /// Strict portable social rules must prove how each observer learned
  /// about the event. Old local preview rulebooks keep legacy semantics.
  final bool requireReviewedWitnesses;

  void validate(StoryBlueprint blueprint) {
    if (bookCausality != null &&
        (!blueprint.isReviewedCanon || !dynamicInteractionsEnabled)) {
      throw const FormatException('Causal graph requires source-reviewed CANON');
    }
    if (blueprintHash != blueprint.blueprintHash ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(blueprintHash) ||
        rules.length > 512 || canonInvariants.length > 256 ||
        (canonInvariants.isNotEmpty && !dynamicInteractionsEnabled) ||
        (dynamicInteractionsEnabled && !requireReviewedWitnesses) ||
        automaticReactions.length > 256 ||
        (automaticReactions.isNotEmpty && !dynamicInteractionsEnabled)) {
      throw const FormatException('NPC social rules not bound to blueprint');
    }
    if (witnesses.length > 512 || choiceGates.length > 128 ||
        itemTransfers.length > 128 || lifeTransitions.length > 128 ||
        ((witnesses.isNotEmpty || choiceGates.isNotEmpty ||
          itemTransfers.isNotEmpty || lifeTransitions.isNotEmpty) &&
         !requireReviewedWitnesses)) {
      throw const FormatException('NPC witness review must be explicit');
    }
    final presence = <String, NpcWitnessMode>{};
    for (final witness in witnesses) {
      jsonId(witness.sceneId, 'npc.presence.scene_id');
      jsonId(witness.actorId, 'npc.presence.actor_id');
      if (!blueprint.scenes.containsKey(witness.sceneId) ||
          !blueprint.actors.contains(witness.actorId) ||
          witness.actorId == 'player' ||
          (blueprint.rightsStatus == 'private_adaptation' &&
              !CharacterId.isValidNpc(witness.actorId)) ||
          presence.containsKey('${witness.sceneId}|${witness.actorId}')) {
        throw const FormatException('Invalid or duplicate NPC scene witness');
      }
      presence['${witness.sceneId}|${witness.actorId}'] = witness.mode;
    }
    final reactionKeys = <String>{};
    final gmId = RegExp(r'^gm_[a-z0-9_]{1,59}$');
    for (final reaction in automaticReactions) {
      if (!blueprint.scenes.containsKey(reaction.sceneId) ||
          !blueprint.actors.contains(reaction.actorId) ||
          reaction.actorId == 'player' ||
          !CharacterId.isValidNpc(reaction.actorId) ||
          !gmId.hasMatch(reaction.triggerMemoryId) ||
          !gmId.hasMatch(reaction.responseMemoryId) ||
          reaction.triggerMemoryId == reaction.responseMemoryId ||
          !gmId.hasMatch(reaction.nextGoalId) ||
          reaction.minimumTrust < -100 || reaction.minimumTrust > 100 ||
          presence['${reaction.sceneId}|${reaction.actorId}'] !=
              NpcWitnessMode.present ||
          !reactionKeys.add(
              '${reaction.actorId}|${reaction.triggerMemoryId}')) {
        throw const FormatException('Unreviewed or ambiguous NPC reaction');
      }
      final relay = reaction.relayToActorId, fact = reaction.relayFactId;
      if ((relay == null) != (fact == null) ||
          (relay != null && (!blueprint.actors.contains(relay) ||
              relay == 'player' || relay == reaction.actorId ||
              presence['${reaction.sceneId}|$relay'] !=
                  NpcWitnessMode.present)) ||
          (fact != null &&
              !(blueprint.facts.contains(fact) || gmId.hasMatch(fact)))) {
        throw const FormatException('NPC rumor lacks source-reviewed witness');
      }
    }
    final invariantKeys = <String>{};
    for (final invariant in canonInvariants) {
      jsonId(invariant.sceneId, 'canon.invariant.scene_id');
      jsonId(invariant.actorId, 'canon.invariant.actor_id');
      jsonId(invariant.forbiddenMemoryId, 'canon.invariant.memory_id');
      final low = invariant.minimumTrust, high = invariant.maximumTrust;
      if (!blueprint.isReviewedCanon ||
          !blueprint.scenes.containsKey(invariant.sceneId) ||
          invariant.sceneId == blueprint.entrySceneId ||
          !blueprint.actors.contains(invariant.actorId) ||
          invariant.actorId == 'player' ||
          !CharacterId.isValidNpc(invariant.actorId) ||
          !RegExp(r'^gm_[a-z0-9_]{1,59}$')
              .hasMatch(invariant.forbiddenMemoryId) ||
          (low != null && (low < -100 || low > 100)) ||
          (high != null && (high < -100 || high > 100)) ||
          (low != null && high != null && low > high) ||
          !invariantKeys.add(invariant.sceneId + '|' +
              invariant.actorId + '|' + invariant.forbiddenMemoryId)) {
        throw const FormatException('Invalid reviewed canonical prerequisite');
      }
    }
    final seen = <String>{};
    final usedWitnesses = <String>{};
    for (final rule in rules) {
      jsonId(rule.memoryId, 'npc.memory_id');
      jsonId(rule.sceneId, 'npc.scene_id');
      jsonId(rule.choiceId, 'npc.choice_id');
      jsonId(rule.observerId, 'npc.observer_id');
      if (!blueprint.actors.contains(rule.observerId)) {
        throw const FormatException('Unknown NPC memory observer');
      }
      if (blueprint.rightsStatus == 'private_adaptation' &&
          rule.observerId != 'player' &&
          !CharacterId.isValidNpc(rule.observerId)) {
        throw const FormatException(
            'Private NPC memory requires permanent character_id');
      }
      final scene = blueprint.scenes[rule.sceneId];
      if (scene == null ||
          !scene.choices.any((choice) => choice.id == rule.choiceId)) {
        throw const FormatException('NPC memory references absent choice');
      }
      if (rule.relatedActorId != null) {
        jsonId(rule.relatedActorId!, 'npc.related_actor_id');
        if (!blueprint.actors.contains(rule.relatedActorId) ||
            rule.relatedActorId == rule.observerId ||
            (blueprint.rightsStatus == 'private_adaptation' &&
                rule.relatedActorId != 'player' &&
                !CharacterId.isValidNpc(rule.relatedActorId!))) {
          throw const FormatException('Invalid directed NPC relationship');
        }
      }
      if (rule.maxTriggers < 1 || rule.maxTriggers > 10 ||
          rule.relationshipDelta < -20 || rule.relationshipDelta > 20 ||
          (rule.relationshipDelta != 0 && rule.relatedActorId == null)) {
        throw const FormatException('Invalid NPC relationship change');
      }
      if (requireReviewedWitnesses && rule.observerId != 'player') {
        final witness = presence['${rule.sceneId}|${rule.observerId}'];
        if (witness == null) {
          throw const FormatException(
              'NPC cannot remember an event without an approved witness');
        }
        if (witness == NpcWitnessMode.reported &&
            (rule.kind != NpcMemoryKind.rumorHeard ||
                rule.relationshipDelta != 0)) {
          throw const FormatException(
              'Second-hand rumor is not eyewitness proof or earned trust');
        }
        usedWitnesses.add('${rule.sceneId}|${rule.observerId}');
      }
      final identity = '${rule.observerId}|${rule.memoryId}';
      if (!seen.add(identity)) {
        throw const FormatException('Duplicate NPC event memory identity');
      }
    }
    final lifeActions = <String>{};
    for (final change in lifeTransitions) {
      jsonId(change.sceneId, 'npc.life.scene_id');
      jsonId(change.choiceId, 'npc.life.choice_id');
      jsonId(change.actorId, 'npc.life.actor_id');
      final scene = blueprint.scenes[change.sceneId];
      if (scene == null ||
          !scene.choices.any((choice) => choice.id == change.choiceId) ||
          !blueprint.actors.contains(change.actorId) ||
          change.actorId == 'player' ||
          (blueprint.rightsStatus == 'private_adaptation' &&
              !CharacterId.isValidNpc(change.actorId)) ||
          !lifeActions.add('${change.sceneId}|${change.choiceId}|${change.actorId}')) {
        throw const FormatException('Invalid or duplicate NPC life event');
      }
    }
    final transfers = <String>{};
    for (final transfer in itemTransfers) {
      jsonId(transfer.sceneId, 'npc.transfer.scene_id');
      jsonId(transfer.choiceId, 'npc.transfer.choice_id');
      jsonId(transfer.itemId, 'npc.transfer.item_id');
      jsonId(transfer.fromActorId, 'npc.transfer.from_actor_id');
      jsonId(transfer.toActorId, 'npc.transfer.to_actor_id');
      final scene = blueprint.scenes[transfer.sceneId];
      final choices = scene?.choices
          .where((choice) => choice.id == transfer.choiceId).toList();
      if (choices == null || choices.length != 1 ||
          !blueprint.items.contains(transfer.itemId) ||
          !blueprint.actors.contains(transfer.fromActorId) ||
          !blueprint.actors.contains(transfer.toActorId) ||
          transfer.fromActorId == transfer.toActorId ||
          !transfers.add(
              '${transfer.sceneId}|${transfer.choiceId}|${transfer.itemId}')) {
        throw const FormatException('Invalid NPC item transfer reference');
      }
      final fromPlayer = transfer.fromActorId == 'player';
      final toPlayer = transfer.toActorId == 'player';
      if (fromPlayer == toPlayer) {
        throw const FormatException('NPC transfer must involve the hero');
      }
      final npc = fromPlayer ? transfer.toActorId : transfer.fromActorId;
      if ((blueprint.rightsStatus == 'private_adaptation' &&
           !CharacterId.isValidNpc(npc)) ||
          presence['${transfer.sceneId}|$npc'] != NpcWitnessMode.present) {
        throw const FormatException(
            'NPC item transfer requires approved personal presence');
      }
      usedWitnesses.add('${transfer.sceneId}|$npc');
      final expectedEffect = fromPlayer ? 'consume_item' : 'grant_item';
      if (choices.single.effects.where((effect) =>
          effect.op == expectedEffect &&
          effect.id == transfer.itemId).length != 1) {
        throw const FormatException(
            'NPC item custody does not match typed world effect');
      }
    }
    if (requireReviewedWitnesses && !dynamicInteractionsEnabled &&
        (presence.length != usedWitnesses.length ||
         !usedWitnesses.containsAll(presence.keys))) {
      throw const FormatException('Orphaned NPC witness evidence');
    }
    final gated = <String>{};
    for (final gate in choiceGates) {
      jsonId(gate.sceneId, 'npc.choice_gate.scene_id');
      jsonId(gate.choiceId, 'npc.choice_gate.choice_id');
      jsonId(gate.actorId, 'npc.choice_gate.actor_id');
      if (gate.requiredMemoryId != null) {
        jsonId(gate.requiredMemoryId!, 'npc.choice_gate.required_memory_id');
      }
      final scene = blueprint.scenes[gate.sceneId];
      if (scene == null ||
          !scene.choices.any((choice) => choice.id == gate.choiceId) ||
          !blueprint.actors.contains(gate.actorId) ||
          gate.actorId == 'player' ||
          (blueprint.rightsStatus == 'private_adaptation' &&
              !CharacterId.isValidNpc(gate.actorId)) ||
          !gated.add('${gate.sceneId}|${gate.choiceId}') ||
          (gate.requiredMemoryId == null &&
              gate.minimumTrustToPlayer == null) ||
          (gate.minimumTrustToPlayer != null &&
              (gate.minimumTrustToPlayer! < 1 ||
               gate.minimumTrustToPlayer! > 100))) {
        throw const FormatException('Invalid or duplicate NPC choice gate');
      }
      if (gate.requiredMemoryId != null &&
          !rules.any((rule) =>
              rule.observerId == gate.actorId &&
              rule.memoryId == gate.requiredMemoryId &&
              !(rule.sceneId == gate.sceneId &&
                rule.choiceId == gate.choiceId))) {
        throw const FormatException(
            'NPC choice requires unreviewed or self-granted memory');
      }
      if (gate.minimumTrustToPlayer != null &&
          !rules.any((rule) =>
              rule.observerId == gate.actorId &&
              rule.relatedActorId == 'player' &&
              rule.relationshipDelta > 0 &&
              !(rule.sceneId == gate.sceneId &&
                rule.choiceId == gate.choiceId))) {
        throw const FormatException(
            'NPC choice requires unearned or self-granted trust');
      }
    }
    // A->B->A "remember this first" cycles would make both game
    // decisions impossible. Reject them at authoring/import time rather
    // than presenting a dead-end to the player.
    final gatedChoices = {
      for (final gate in choiceGates)
        '${gate.sceneId}|${gate.choiceId}': gate,
    };
    final visiting = <String>{};
    final visited = <String>{};
    void checkChain(String key) {
      if (visited.contains(key)) return;
      if (!visiting.add(key)) {
        throw const FormatException('Circular NPC memory choice dependency');
      }
      final gate = gatedChoices[key]!;
      if (gate.requiredMemoryId != null) {
        final producer = rules.singleWhere((rule) =>
            rule.observerId == gate.actorId &&
            rule.memoryId == gate.requiredMemoryId);
        final source = '${producer.sceneId}|${producer.choiceId}';
        if (gatedChoices.containsKey(source)) checkChain(source);
      }
      visiting.remove(key);
      visited.add(key);
    }
    for (final key in gatedChoices.keys) {
      checkChain(key);
    }
  }

  /// Digest is stable under rule order changes. The authoring client must
  /// persist and check it when this projection becomes a portable contract.
  bool breaksCanon(String nextSceneId, NpcSocialSnapshot snapshot) {
    for (final rule in canonInvariants) {
      if (rule.sceneId != nextSceneId) continue;
      if (snapshot.hasMemory(rule.actorId, rule.forbiddenMemoryId)) return true;
      final trust = snapshot.directedScore(rule.actorId, 'player');
      if ((rule.minimumTrust != null && trust < rule.minimumTrust!) ||
          (rule.maximumTrust != null && trust > rule.maximumTrust!)) {
        return true;
      }
    }
    return false;
  }

  String get digest {
    final entries = rules.map((rule) => rule.toJson()).toList()
      ..sort((a, b) =>
          ('${a['observer_id']}|${a['memory_id']}')
              .compareTo('${b['observer_id']}|${b['memory_id']}'));
    final signed = <String, Object?>{
      'blueprint_sha256': blueprintHash,
      'rules': entries,
    };
    if (requireReviewedWitnesses) {
      final sortedWitnesses = witnesses.map((e) => e.toJson()).toList()
        ..sort((a, b) =>
            ('${a['scene_id']}|${a['actor_id']}')
                .compareTo('${b['scene_id']}|${b['actor_id']}'));
      signed['witnesses'] = sortedWitnesses;
      signed['require_reviewed_witnesses'] = true;
    }
    if (choiceGates.isNotEmpty) {
      final gates = choiceGates.map((gate) => gate.toJson()).toList()
        ..sort((a, b) =>
            ('${a['scene_id']}|${a['choice_id']}')
                .compareTo('${b['scene_id']}|${b['choice_id']}'));
      signed['choice_gates'] = gates;
    }
    if (itemTransfers.isNotEmpty) {
      final transfers = itemTransfers.map((rule) => rule.toJson()).toList()
        ..sort((a, b) =>
            ('${a['scene_id']}|${a['choice_id']}|${a['item_id']}')
                .compareTo('${b['scene_id']}|${b['choice_id']}|${b['item_id']}'));
      signed['item_transfers'] = transfers;
    }
    if (dynamicInteractionsEnabled) {
      signed['dynamic_interactions'] = true;
      signed['canon_invariants'] = (canonInvariants
          .map((gate) => gate.toJson()).toList()
          ..sort((a, b) => (a['scene_id'].toString() +
              a['actor_id'].toString())
              .compareTo(b['scene_id'].toString() +
                  b['actor_id'].toString())));
    }
    if (bookCausality != null) {
      signed['book_causal_graph'] = bookCausality!.toJson();
    }
    if (automaticReactions.isNotEmpty) {
      signed['automatic_npc_reactions'] = (
          automaticReactions.map((reaction) => reaction.toJson()).toList()
            ..sort((a, b) =>
                (a['actor_id'].toString() + a['trigger_memory_id'].toString())
                    .compareTo(b['actor_id'].toString() +
                        b['trigger_memory_id'].toString())));
    }
    if (lifeTransitions.isNotEmpty) {
      final changes = lifeTransitions.map((change) => change.toJson()).toList()
        ..sort((a, b) =>
            ('${a['scene_id']}|${a['choice_id']}|${a['actor_id']}')
                .compareTo('${b['scene_id']}|${b['choice_id']}|${b['actor_id']}'));
      signed['life_transitions'] = changes;
    }
    return sha256.convert(utf8.encode(canonicalJson(signed))).toString();
  }
}

class NpcEventMemory {
  const NpcEventMemory({
    required this.observerId,
    required this.memoryId,
    required this.kind,
    required this.event,
    required this.relatedActorId,
    required this.relationshipDelta,
    this.witnessMode,
    this.goalId,
  });

  final String observerId;
  final String memoryId;
  final NpcMemoryKind kind;
  /// The committed, hash-chained game event; never a prose citation.
  final WorldEvent event;
  final String? relatedActorId;
  final int relationshipDelta;
  /// Null for the player (whose action is already committed), present or
  /// reported for separately verified NPC observers.
  final NpcWitnessMode? witnessMode;
  final String? goalId;
}

/// Safe read-only projection of *actual* committed events onto authored
/// witnesses and directed relationships. Does not grant a fact, validate
/// claimed eyewitness presence, or authorize a spoken line.
class NpcSocialSnapshot {
  NpcSocialSnapshot._({
    required this.blueprintHash,
    required this.rulebookDigest,
    required this.worldStateHash,
    required this.eventHeadHash,
    required Set<String> actorIds,
    required Set<String> itemIds,
    required Map<String, String> itemOwners,
    required Map<String, NpcLifeState> lifeByActor,
    required Map<String, List<NpcEventMemory>> memoryByActor,
    required Map<String, Map<String, int>> directedRelations,
  })  : _actorIds = Set<String>.unmodifiable(actorIds),
        _itemIds = Set<String>.unmodifiable(itemIds),
        _itemOwners = Map<String, String>.unmodifiable(itemOwners),
        _lifeByActor = Map<String, NpcLifeState>.unmodifiable(lifeByActor),
        _memoryByActor = Map.unmodifiable(
            memoryByActor.map((actor, memories) =>
                MapEntry(actor, List<NpcEventMemory>.unmodifiable(memories)))),
        _directedRelations = Map.unmodifiable(
            directedRelations.map((actor, targets) =>
                MapEntry(actor, Map<String, int>.unmodifiable(targets))));

  final String blueprintHash;
  final String rulebookDigest;
  final String worldStateHash;
  final String? eventHeadHash;
  final Set<String> _actorIds;
  final Set<String> _itemIds;
  final Map<String, String> _itemOwners;
  final Map<String, NpcLifeState> _lifeByActor;
  final Map<String, List<NpcEventMemory>> _memoryByActor;
  final Map<String, Map<String, int>> _directedRelations;

  String get snapshotHash => sha256.convert(utf8.encode(canonicalJson({
    'blueprint_sha256': blueprintHash,
    'rulebook_sha256': rulebookDigest,
    'state_sha256': worldStateHash,
    'event_head_sha256': eventHeadHash,
  }))).toString();

  List<NpcEventMemory> memoriesFor(String actorId) {
    jsonId(actorId, 'observer_id');
    if (!_actorIds.contains(actorId)) {
      throw const FormatException('Unknown NPC memory actor');
    }
    return _memoryByActor[actorId] ?? List<NpcEventMemory>.unmodifiable([]);
  }

  /// Last committed private goal, not a source-book personality assertion.
  String? currentGoal(String actorId) {
    final memories = memoriesFor(actorId);
    for (var i = memories.length - 1; i >= 0; i--) {
      if (memories[i].goalId != null) return memories[i].goalId;
    }
    return null;
  }

  bool hasMemory(String actorId, String memoryId) {
    jsonId(memoryId, 'memory_id');
    return memoriesFor(actorId).any((memory) => memory.memoryId == memoryId);
  }

  /// Unknown actors fail closed; old archives default NPCs to available.
  NpcLifeState lifeState(String actorId) {
    jsonId(actorId, 'npc_life_actor_id');
    if (!_actorIds.contains(actorId)) {
      throw const FormatException('Unknown NPC life actor');
    }
    return actorId == 'player' ? NpcLifeState.present :
        (_lifeByActor[actorId] ?? NpcLifeState.present);
  }

  /// Null means nobody currently possesses this item. Unknown catalog IDs
  /// fail closed. Player ownership must equal the authoritative inventory.
  String? itemOwner(String itemId) {
    jsonId(itemId, 'item_id');
    if (!_itemIds.contains(itemId)) {
      throw const FormatException('Unknown item custody reference');
    }
    return _itemOwners[itemId];
  }

  List<String> itemsHeldBy(String actorId) {
    jsonId(actorId, 'actor_id');
    if (!_actorIds.contains(actorId)) {
      throw const FormatException('Unknown item owner');
    }
    return List<String>.unmodifiable((_itemOwners.entries
        .where((entry) => entry.value == actorId)
        .map((entry) => entry.key).toList()..sort()));
  }

  /// A -> B is not B -> A. Neutral/unspecified relationships return 0.
  int directedScore(String fromActorId, String toActorId) {
    jsonId(fromActorId, 'from_actor_id');
    jsonId(toActorId, 'to_actor_id');
    if (!_actorIds.contains(fromActorId) || !_actorIds.contains(toActorId)) {
      throw const FormatException('Unknown directed relationship actors');
    }
    return _directedRelations[fromActorId]?[toActorId] ?? 0;
  }
}

class NpcSocialLedger {
  const NpcSocialLedger._();

  /// Deterministically builds a private preview from an authoritative
  /// StoryWorld, not from unverified, caller-supplied event JSON.
  static NpcSocialSnapshot inspect(
      StoryWorld world, NpcSocialRulebook rulebook) {
    final blueprint = world.blueprint;
    rulebook.validate(blueprint);
    final byChoice = <String, List<NpcSocialRule>>{};
    for (final rule in rulebook.rules) {
      byChoice.putIfAbsent('${rule.sceneId}|${rule.choiceId}',
          () => <NpcSocialRule>[]).add(rule);
    }
    final memory = <String, List<NpcEventMemory>>{};
    final witnessModes = {
      for (final witness in rulebook.witnesses)
        '${witness.sceneId}|${witness.actorId}': witness.mode,
    };
    final triggersByRule = <String, int>{};
    final relations = <String, Map<String, int>>{};
    final life = <String, NpcLifeState>{
      for (final actor in blueprint.actors)
        if (actor != 'player') actor: NpcLifeState.present,
    };
    final lifeByChoice = <String, List<NpcLifeTransition>>{};
    for (final change in rulebook.lifeTransitions) {
      lifeByChoice.putIfAbsent('${change.sceneId}|${change.choiceId}',
          () => <NpcLifeTransition>[]).add(change);
    }
    for (final event in world.events) {
      final key = '${event.sceneId}|${event.choiceId}';
      if (rulebook.lifeTransitions.isNotEmpty) {
        for (final rule in byChoice[key] ?? <NpcSocialRule>[]) {
          if (rule.observerId != 'player' &&
              (life[rule.observerId] == NpcLifeState.dead ||
               (witnessModes['${event.sceneId}|${rule.observerId}'] ==
                    NpcWitnessMode.present &&
                life[rule.observerId] != NpcLifeState.present))) {
            throw const FormatException('Absent/dead NPC witnessed an event');
          }
        }
        for (final change in lifeByChoice[key] ?? <NpcLifeTransition>[]) {
          final previous = life[change.actorId]!;
          final valid = switch (change.nextState) {
            NpcLifeState.absent => previous == NpcLifeState.present,
            NpcLifeState.present => previous == NpcLifeState.absent,
            NpcLifeState.dead => previous != NpcLifeState.dead,
          };
          if (!valid) {
            throw const FormatException(
                'NPC life transition contradicts committed event history');
          }
          life[change.actorId] = change.nextState;
        }
      }
      final intervention = event.freeform?.npcInteraction;
      if (intervention != null) {
        if (!rulebook.dynamicInteractionsEnabled ||
            !blueprint.actors.contains(intervention.actorId) ||
            life[intervention.actorId] != NpcLifeState.present) {
          throw const FormatException('Unreviewed or absent NPC');
        }
        final key = event.sceneId + '|' + intervention.actorId;
        final witness = witnessModes[key];
        final previousContact =
            memory[intervention.actorId]?.isNotEmpty ?? false;
        if (witness != NpcWitnessMode.present &&
            !(previousContact && world.state.plotDiverged)) {
          throw const FormatException('NPC is not present and source-reviewed');
        }
        final actorMemories =
            memory.putIfAbsent(intervention.actorId, () => <NpcEventMemory>[]);
        if (actorMemories.any((v) => v.memoryId == intervention.memoryId) ||
            actorMemories.length >= 64) {
          throw const FormatException('Repeated NPC memory or overflow');
        }
        final kind = switch (intervention.kind) {
          'helped' => NpcMemoryKind.helped,
          'betrayed' => NpcMemoryKind.betrayed,
          'promise_received' => NpcMemoryKind.promiseReceived,
          'promise_broken' => NpcMemoryKind.promiseBroken,
          'rumor_heard' => NpcMemoryKind.rumorHeard,
          _ => NpcMemoryKind.witnessed,
        };
        final relation = relations.putIfAbsent(
            intervention.actorId, () => <String, int>{});
        final trust = (relation['player'] ?? 0) + intervention.trustDelta;
        if (trust < -100 || trust > 100) {
          throw const FormatException('NPC trust outside approved bounds');
        }
        relation['player'] = trust;
        actorMemories.add(NpcEventMemory(
          observerId: intervention.actorId,
          memoryId: intervention.memoryId,
          kind: kind, event: event,
          relatedActorId: 'player',
          relationshipDelta: intervention.trustDelta,
          witnessMode: witness, goalId: intervention.goalId,
        ));
        for (final reaction in rulebook.automaticReactions) {
          if (reaction.sceneId != event.sceneId ||
              !reaction.activated(intervention, trust)) continue;
          if (actorMemories.any((m) => m.memoryId == reaction.responseMemoryId) ||
              actorMemories.length >= 64) {
            throw const FormatException('NPC automatic memory repeats');
          }
          actorMemories.add(NpcEventMemory(
            observerId: intervention.actorId,
            memoryId: reaction.responseMemoryId,
            kind: NpcMemoryKind.witnessed, event: event,
            relatedActorId: 'player', relationshipDelta: 0,
            witnessMode: NpcWitnessMode.present,
            goalId: reaction.nextGoalId,
          ));
          if (reaction.relayToActorId != null) {
            if (life[reaction.relayToActorId] != NpcLifeState.present) {
              throw const FormatException('Absent NPC cannot receive rumor');
            }
            final recipient = memory.putIfAbsent(
                reaction.relayToActorId!, () => <NpcEventMemory>[]);
            if (recipient.any((m) => m.memoryId == reaction.responseMemoryId) ||
                recipient.length >= 64) {
              throw const FormatException('NPC rumor already received');
            }
            recipient.add(NpcEventMemory(
              observerId: reaction.relayToActorId!,
              memoryId: reaction.responseMemoryId,
              kind: NpcMemoryKind.rumorHeard, event: event,
              relatedActorId: intervention.actorId,
              relationshipDelta: 0,
              witnessMode: NpcWitnessMode.present,
            ));
          }
        }
      }
      for (final rule in byChoice[
              '${event.sceneId}|${event.choiceId}'] ??
          <NpcSocialRule>[]) {
        final key = '${rule.observerId}|${rule.memoryId}';
        final previousTriggers = triggersByRule[key] ?? 0;
        if (previousTriggers >= rule.maxTriggers) continue;
        triggersByRule[key] = previousTriggers + 1;
        memory.putIfAbsent(rule.observerId, () => <NpcEventMemory>[]).add(
          NpcEventMemory(
            observerId: rule.observerId,
            memoryId: rule.memoryId,
            kind: rule.kind,
            event: event,
            relatedActorId: rule.relatedActorId,
            relationshipDelta: rule.relationshipDelta,
            witnessMode:
                witnessModes['${rule.sceneId}|${rule.observerId}'],
          ),
        );
        if (rule.relatedActorId != null && rule.relationshipDelta != 0) {
          final targets = relations.putIfAbsent(
              rule.observerId, () => <String, int>{});
          final next =
              (targets[rule.relatedActorId] ?? 0) + rule.relationshipDelta;
          if (next < -100 || next > 100) {
            throw const FormatException(
                'Reviewed NPC relationship exceeds permitted range');
          }
          targets[rule.relatedActorId!] = next;
        }
      }
    }
    final events = world.events;

    // Recompute custody from typed effects and actual committed decisions.
    // A forged prose note cannot give an NPC an item. Every player transfer
    // must agree with the player's exact inventory effects.
    final owners = <String, String>{
      for (final item in blueprint.initial.inventory) item: 'player',
    };
    final transferByAction = {
      for (final transfer in rulebook.itemTransfers)
        '${transfer.sceneId}|${transfer.choiceId}|${transfer.itemId}':
            transfer,
    };
    for (final event in events) {
      final effects = event.freeform?.effects ?? [
          ...blueprint.scenes[event.sceneId]!.choices
              .singleWhere((candidate) => candidate.id == event.choiceId)
              .effects,
          ...world.sourceEffectsFor(event.sceneId),
      ];
      for (final effect in effects) {
        if (effect.op != 'grant_item' && effect.op != 'consume_item') continue;
        final itemId = effect.id!;
        final transfer = transferByAction[
            '${event.sceneId}|${event.choiceId}|$itemId'];
        final current = owners[itemId];
        if (effect.op == 'consume_item') {
          if (current != 'player' ||
              (transfer != null && transfer.fromActorId != 'player')) {
            throw const FormatException('NPC custody spent an unowned item');
          }
          if (transfer != null) {
            owners[itemId] = transfer.toActorId;
          } else {
            owners.remove(itemId);
          }
        } else {
          if (transfer != null) {
            if (transfer.toActorId != 'player' ||
                current != transfer.fromActorId) {
              throw const FormatException(
                  'NPC custody returned an unowned item');
            }
          } else if (current != null && current != 'player') {
            throw const FormatException(
                'World item duplicated while carried by NPC');
          }
          owners[itemId] = 'player';
        }
      }
      final interaction = event.freeform?.npcInteraction;
      if (interaction != null) {
        final give = interaction.giveItemId;
        final take = interaction.takeItemId;
        if (give != null) {
          if (owners[give] != 'player') {
            throw const FormatException('Unowned gift to NPC');
          }
          owners[give] = interaction.actorId;
        }
        if (take != null) {
          if (owners[take] != interaction.actorId) {
            throw const FormatException('NPC gave an unowned item');
          }
          owners[take] = 'player';
        }
      }
    }
    for (final item in {
      ...blueprint.items,
      ...world.state.inventory.where((id) => id.startsWith('gm_')),
    }) {
      if ((owners[item] == 'player') != world.state.inventory.contains(item)) {
        throw const FormatException('NPC custody conflicts with world inventory');
      }
    }
    return NpcSocialSnapshot._(
      blueprintHash: blueprint.blueprintHash,
      rulebookDigest: rulebook.digest,
      worldStateHash: world.state.stateHash,
      eventHeadHash: events.isEmpty ? null : events.last.hash,
      actorIds: blueprint.actors,
      itemIds: {...blueprint.items,
          ...world.state.inventory.where((id) => id.startsWith('gm_'))},
      itemOwners: owners,
      lifeByActor: life,
      memoryByActor: memory,
      directedRelations: relations,
    );
  }
}
