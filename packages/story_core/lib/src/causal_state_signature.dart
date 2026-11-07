import 'blueprint.dart';
import 'codec.dart';
import 'engine.dart';
import 'npc_social_ledger.dart';

/// Internal equivalence key for *future playable behavior*, not a checksum
/// of event history. Two hashed event chains can share this signature only
/// when every current typed condition and social gate sees the same state.
///
/// The optional prior-choice flag is necessary for source-locked dialogue
/// proofs. Campaign-wide terminal/trap audits omit that extra condition.
class CausalStateSignature {
  CausalStateSignature(this.blueprint, this.socialRulebook)
      : _latestTimeGate = _timeGate(blueprint),
        _npcActors = (
          blueprint.actors.where((id) => id != 'player').toList()..sort()
        ),
        _itemIds = (blueprint.items.toList()..sort());

  final StoryBlueprint blueprint;
  final NpcSocialRulebook? socialRulebook;
  final int _latestTimeGate;
  final List<String> _npcActors;
  final List<String> _itemIds;

  static int _timeGate(StoryBlueprint blueprint) {
    final thresholds = [
      for (final scene in blueprint.scenes.values)
        for (final choice in scene.choices)
          for (final rule in choice.conditions)
            if (rule.op == 'tick_at_least') rule.amount!,
    ];
    return thresholds.isEmpty
        ? 0 : thresholds.reduce((a, b) => a > b ? a : b);
  }

  String of(StoryWorld world, {String? requiredPriorChoiceId}) {
    final state = world.state;
    final priorSeen = requiredPriorChoiceId != null &&
        world.events.any((event) =>
            event.choiceId == requiredPriorChoiceId);
    Map<String, Object?>? socialState;
    if (socialRulebook != null) {
      final social = NpcSocialLedger.inspect(world, socialRulebook!);
      socialState = {
        // Memory multiplicity matters for rules with maxTriggers > 1.
        'memories': {
          for (final actor in _npcActors)
            actor: [
              for (final memory in social.memoriesFor(actor))
                memory.memoryId,
            ]..sort(),
        },
        // Only directed NPC -> player trust can be gated by this v3 DSL.
        'trust': {
          for (final actor in _npcActors)
            actor: social.directedScore(actor, 'player'),
        },
        'life': {
          for (final actor in _npcActors)
            actor: social.lifeState(actor).name,
        },
        'custody': {
          for (final item in _itemIds) item: social.itemOwner(item),
        },
      };
    }
    return canonicalJson({
      'scene': state.sceneId,
      // Ticks after the last authored threshold cannot change the
      // availability of a choice. This prevents false infinite loops.
      'time': _latestTimeGate == 0
          ? 0
          : (state.tick > _latestTimeGate ? _latestTimeGate : state.tick),
      'stats': state.stats,
      'flags': state.flags,
      'inventory': state.inventory.toList()..sort(),
      'knowledge': {
        for (final actor in blueprint.actors)
          actor: (state.knowledge[actor] ?? const <String>{})
              .toList()..sort(),
      },
      'prior': priorSeen,
      if (socialState != null) 'social': socialState,
    });
  }
}
