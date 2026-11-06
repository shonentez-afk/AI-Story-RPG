import 'dart:io';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';

/// Independent Dart importer of a Python-built, source-reviewed NPC rich-v3.
/// Exercises the actual typed game rules and event replay, not only ZIP JSON.
void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Expected Python-built NPC .bworld path');
  }
  final archive = File(args.single).readAsBytesSync();
  final verified = const RichPrivateBookworldImporter().inspect(archive);
  final npcIds = verified.blueprint.actors
      .where(CharacterId.isValidNpc).toList();
  if (npcIds.length != 1 ||
      verified.blueprint.facts.length != 1) {
    throw StateError('Python NPC fixture missing actor or fact');
  }
  final npc = npcIds.single;
  final fact = verified.blueprint.facts.single;
  final world = StoryWorld(verified.blueprint);
  final before = world.apply(actionId: 'early', choiceId: 'help');
  if (before.applied ||
      before.reason != 'condition_not_met:knows_fact' ||
      world.actorKnowsFact(npc, fact)) {
    throw StateError('NPC learned a fact before its committed event');
  }
  if (!world.apply(actionId: 'teach_npc', choiceId: 'wait').applied ||
      !world.actorKnowsFact(npc, fact) ||
      world.actorKnowsFact('player', fact)) {
    throw StateError('NPC knowledge is not actor scoped');
  }
  if (!world.apply(actionId: 'help_later', choiceId: 'help').applied) {
    throw StateError('Confirmed NPC knowledge did not unlock the choice');
  }
  final restored = StoryWorld.replay(
    verified.blueprint,
    world.events.map((event) => event.toJson()),
    expectedSequence: world.state.revision,
    expectedStateHash: world.state.stateHash,
  );
  if (!restored.actorKnowsFact(npc, fact) ||
      restored.factLearningEvents(npc, fact).single.hash !=
          world.events.first.hash) {
    throw StateError('NPC provenance did not survive deterministic replay');
  }
  final socialRules = verified.npcSocialRulebook;
  if (socialRules != null) {
    if (!socialRules.requireReviewedWitnesses) {
      throw StateError('Python-built social contract was not reviewed');
    }
    final social = NpcSocialLedger.inspect(world, socialRules);
    final saved = NpcSocialLedger.inspect(restored, socialRules);
    if (social.directedScore(npc, 'player') != 7 ||
        social.directedScore('player', npc) != 0 ||
        social.memoriesFor(npc).length != 1 ||
        social.memoriesFor(npc).single.witnessMode != NpcWitnessMode.present ||
        social.snapshotHash != saved.snapshotHash) {
      throw StateError('Python social witness/replay parity mismatch');
    }
  }
  stdout.writeln('Python-built NPC rich-v3 passed independent Dart replay.');
}
