import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'blueprint.dart';
import 'codec.dart';
import 'engine.dart';

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
  });

  final String memoryId;
  final String sceneId;
  final String choiceId;
  final String observerId;
  final NpcMemoryKind kind;
  final String? relatedActorId;
  final int relationshipDelta;

  Map<String, Object?> toJson() => {
    'memory_id': memoryId,
    'scene_id': sceneId,
    'choice_id': choiceId,
    'observer_id': observerId,
    'kind': kind.name,
    'related_actor_id': relatedActorId,
    'relationship_delta': relationshipDelta,
  };
}

/// Bound to one exact, validated blueprint. A caller must separately
/// establish source provenance and editorial approval before using rules
/// to present a literary adaptation. Rules are not embedded in .bworld yet.
class NpcSocialRulebook {
  NpcSocialRulebook({
    required this.blueprintHash,
    required List<NpcSocialRule> rules,
  }) : rules = List.unmodifiable(rules);

  final String blueprintHash;
  final List<NpcSocialRule> rules;

  void validate(StoryBlueprint blueprint) {
    if (blueprintHash != blueprint.blueprintHash ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(blueprintHash) ||
        rules.length > 512) {
      throw const FormatException('NPC social rules not bound to blueprint');
    }
    final seen = <String>{};
    for (final rule in rules) {
      jsonId(rule.memoryId, 'npc.memory_id');
      jsonId(rule.sceneId, 'npc.scene_id');
      jsonId(rule.choiceId, 'npc.choice_id');
      jsonId(rule.observerId, 'npc.observer_id');
      if (!blueprint.actors.contains(rule.observerId)) {
        throw const FormatException('Unknown NPC memory observer');
      }
      final scene = blueprint.scenes[rule.sceneId];
      if (scene == null ||
          !scene.choices.any((choice) => choice.id == rule.choiceId)) {
        throw const FormatException('NPC memory references absent choice');
      }
      if (rule.relatedActorId != null) {
        jsonId(rule.relatedActorId!, 'npc.related_actor_id');
        if (!blueprint.actors.contains(rule.relatedActorId) ||
            rule.relatedActorId == rule.observerId) {
          throw const FormatException('Invalid directed NPC relationship');
        }
      }
      if (rule.relationshipDelta < -20 || rule.relationshipDelta > 20 ||
          (rule.relationshipDelta != 0 && rule.relatedActorId == null)) {
        throw const FormatException('Invalid NPC relationship change');
      }
      final identity = '${rule.observerId}|${rule.memoryId}';
      if (!seen.add(identity)) {
        throw const FormatException('Duplicate NPC event memory identity');
      }
    }
  }

  /// Digest is stable under rule order changes. The authoring client must
  /// persist and check it when this projection becomes a portable contract.
  String get digest {
    final entries = rules.map((rule) => rule.toJson()).toList()
      ..sort((a, b) =>
          ('${a['observer_id']}|${a['memory_id']}')
              .compareTo('${b['observer_id']}|${b['memory_id']}'));
    return sha256.convert(utf8.encode(canonicalJson({
      'blueprint_sha256': blueprintHash,
      'rules': entries,
    }))).toString();
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
  });

  final String observerId;
  final String memoryId;
  final NpcMemoryKind kind;
  /// The committed, hash-chained game event; never a prose citation.
  final WorldEvent event;
  final String? relatedActorId;
  final int relationshipDelta;
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
    required Map<String, List<NpcEventMemory>> memoryByActor,
    required Map<String, Map<String, int>> directedRelations,
  })  : _memoryByActor = Map.unmodifiable(
            memoryByActor.map((actor, memories) =>
                MapEntry(actor, List<NpcEventMemory>.unmodifiable(memories)))),
        _directedRelations = Map.unmodifiable(
            directedRelations.map((actor, targets) =>
                MapEntry(actor, Map<String, int>.unmodifiable(targets))));

  final String blueprintHash;
  final String rulebookDigest;
  final String worldStateHash;
  final String? eventHeadHash;
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
    return _memoryByActor[actorId] ?? List<NpcEventMemory>.unmodifiable([]);
  }

  bool hasMemory(String actorId, String memoryId) {
    jsonId(memoryId, 'memory_id');
    return memoriesFor(actorId).any((memory) => memory.memoryId == memoryId);
  }

  /// A -> B is not B -> A. Neutral/unspecified relationships return 0.
  int directedScore(String fromActorId, String toActorId) {
    jsonId(fromActorId, 'from_actor_id');
    jsonId(toActorId, 'to_actor_id');
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
    final relations = <String, Map<String, int>>{};
    for (final event in world.events) {
      for (final rule in byChoice[
              '${event.sceneId}|${event.choiceId}'] ??
          <NpcSocialRule>[]) {
        memory.putIfAbsent(rule.observerId, () => <NpcEventMemory>[]).add(
          NpcEventMemory(
            observerId: rule.observerId,
            memoryId: rule.memoryId,
            kind: rule.kind,
            event: event,
            relatedActorId: rule.relatedActorId,
            relationshipDelta: rule.relationshipDelta,
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
    return NpcSocialSnapshot._(
      blueprintHash: blueprint.blueprintHash,
      rulebookDigest: rulebook.digest,
      worldStateHash: world.state.stateHash,
      eventHeadHash: events.isEmpty ? null : events.last.hash,
      memoryByActor: memory,
      directedRelations: relations,
    );
  }
}
