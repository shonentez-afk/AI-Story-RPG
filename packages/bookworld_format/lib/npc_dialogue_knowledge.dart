import 'package:story_core/story_core.dart';

import 'rich_scene_dialogue.dart';

/// Review of named spoken turns, not an assertion of literary canon.
/// It is embedded in the already signed private rich-v3 presentation.
class RichNpcDialogueKnowledge {
  const RichNpcDialogueKnowledge._();

  static const unavailableLine =
      'Реплика пока недоступна: ещё не выполнены условия разговора.';

  /// A rich world with NPC actors cannot present unreviewed speaker turns.
  /// Every named turn has an explicit, exact actor ID and fact prerequisites.
  /// No name-based identity inference or free-text understanding happens here.
  static void validate(
    Map<String, dynamic>? review,
    StoryBlueprint blueprint,
    Map<String, dynamic>? signedDialogues, {
    NpcSocialRulebook? socialRules,
  }) {
    final hasNpcs = blueprint.actors.any((id) => id != 'player');
    final signed = signedDialogues ?? const <String, dynamic>{};
    if (!hasNpcs) {
      if (review != null) {
        throw const FormatException('Unexpected NPC dialogue review');
      }
      return;
    }
    // A rich world cannot remove the signed presentation and then rely
    // on the UI's legacy scene-text parser to reveal unreviewed words.
    for (final scene in blueprint.scenes.values) {
      if (RichSceneDialogue.parse(scene.text) != null &&
          !signed.containsKey(scene.id)) {
        throw const FormatException(
            'Structured NPC speech must be signed and source-reviewed');
      }
    }
    if (signed.isEmpty) {
      if (review != null && review.isNotEmpty) {
        throw const FormatException('NPC dialogue review has no scene');
      }
      return;
    }
    if (review == null ||
        review.keys.toSet().difference(signed.keys.toSet()).isNotEmpty ||
        signed.keys.toSet().difference(review.keys.toSet()).isNotEmpty) {
      throw const FormatException('Every NPC dialogue needs complete review');
    }
    for (final sceneId in signed.keys) {
      final scene = blueprint.scenes[sceneId];
      if (scene == null) {
        throw const FormatException('NPC dialogue references missing scene');
      }
      final turns = RichSceneDialogue.verify(signed[sceneId], scene.text);
      final expected = <int>{
        for (var i = 0; i < turns.length; i++)
          if (turns[i].speaker != null) i,
      };
      final entries = review[sceneId];
      if (entries is! List || entries.length != expected.length) {
        throw const FormatException('Unreviewed spoken NPC dialogue turn');
      }
      final seen = <int>{};
      for (final raw in entries) {
        if (raw is! Map<String, dynamic> ||
            raw.keys.toSet().difference({
              'turn_index', 'speaker', 'actor_id', 'required_fact_ids',
              'required_social_memory_id', 'minimum_trust_to_player',
            }).isNotEmpty ||
            !raw.keys.toSet().containsAll({
              'turn_index', 'speaker', 'actor_id', 'required_fact_ids',
            })) {
          throw const FormatException('Unknown NPC dialogue review fields');
        }
        final index = raw['turn_index'];
        final speaker = raw['speaker'];
        final actor = raw['actor_id'];
        final facts = raw['required_fact_ids'];
        if (index is! int || !expected.contains(index) ||
            !seen.add(index) || speaker != turns[index].speaker ||
            actor is! String || !blueprint.actors.contains(actor) ||
            (actor != 'player' && !CharacterId.isValidNpc(actor)) ||
            facts is! List || facts.length > 16 ||
            facts.any((fact) => fact is! String ||
                !blueprint.facts.contains(fact)) ||
            facts.toSet().length != facts.length ||
            facts.join('|') != ([...facts]..sort()).join('|')) {
          throw const FormatException(
              'NPC dialogue has wrong actor, facts or turn order');
        }
        final memoryId = raw['required_social_memory_id'];
        final minTrust = raw['minimum_trust_to_player'];
        if (raw.containsKey('required_social_memory_id') &&
            (actor == 'player' ||
             memoryId is! String ||
             socialRules == null ||
             !socialRules.rules.any((r) =>
                 r.observerId == actor && r.memoryId == memoryId))) {
          throw const FormatException(
              'Unreviewed NPC social memory prerequisite');
        }
        if (raw.containsKey('minimum_trust_to_player') &&
            (actor == 'player' || socialRules == null ||
             minTrust is! int || minTrust < 1 || minTrust > 100 ||
             !socialRules.rules.any((r) => r.observerId == actor &&
                 r.relatedActorId == 'player' &&
                 r.relationshipDelta > 0))) {
          throw const FormatException(
              'Unreviewed NPC directed relationship prerequisite');
        }
      }
      if (!seen.containsAll(expected)) {
        throw const FormatException('Incomplete NPC dialogue speaker review');
      }
    }
  }

  /// Applied ONLY AFTER importer verification and successful SQLite replay.
  /// Never exposes the forbidden words to Flutter, history or local caching.
  /// No mutation of the world or dialogue position is required.
  static List<RichDialogueTurn> redact(
    List<RichDialogueTurn> turns,
    List<dynamic> reviewedTurns,
    Map<String, Set<String>> knowledge, {
    NpcSocialSnapshot? social,
  }) {
    final byIndex = <int, Map<String, dynamic>>{};
    for (final item in reviewedTurns) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Unverified dialogue review');
      }
      final index = item['turn_index'];
      if (index is! int || index < 0 || index >= turns.length ||
          turns[index].speaker != item['speaker'] ||
          byIndex.containsKey(index)) {
        throw const FormatException('Invalid dialogue review index');
      }
      byIndex[index] = item;
    }
    return List<RichDialogueTurn>.unmodifiable([
      for (var i = 0; i < turns.length; i++)
        if (turns[i].speaker == null)
          turns[i]
        else
          (() {
            final review = byIndex[i];
            if (review == null ||
                review['actor_id'] is! String ||
                review['required_fact_ids'] is! List) {
              throw const FormatException('Unreviewed NPC line at runtime');
            }
            final actor = review['actor_id'] as String;
            final required = review['required_fact_ids'] as List;
            final known = knowledge[actor] ?? const <String>{};
            final memoryId = review['required_social_memory_id'];
            final threshold = review['minimum_trust_to_player'];
            final allowed = required.every((fact) => known.contains(fact)) &&
                (memoryId == null ||
                 (memoryId is String && social != null &&
                  social.hasMemory(actor, memoryId))) &&
                (threshold == null ||
                 (threshold is int && social != null &&
                  social.directedScore(actor, 'player') >= threshold));
            return allowed ? turns[i] : RichDialogueTurn(
              speaker: turns[i].speaker, text: unavailableLine,
            );
          })(),
    ]);
  }
}
