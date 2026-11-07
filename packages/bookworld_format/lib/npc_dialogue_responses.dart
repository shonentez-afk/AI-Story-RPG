import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'rich_scene_dialogue.dart';

/// Signed, author-reviewed PLAYER reply options for a source-locked NPC scene.
/// Only the existing StoryBlueprint choice can change the world; no second
/// dialogue engine, UI effects, or inferential book-canon assertions.
class RichNpcDialogueResponses {
  const RichNpcDialogueResponses._();

  static final _sha = RegExp(r'^[0-9a-f]{64}$');
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');

  static String? replyFor(
      Map<String, dynamic> presentation, String sceneId, String choiceId) {
    final groups = presentation['scene_dialogue_responses'];
    if (groups is! Map<String, dynamic>) return null;
    final rows = groups[sceneId];
    if (rows is! List) return null;
    for (final row in rows) {
      if (row is Map<String, dynamic> && row['choice_id'] == choiceId) {
        return row['player_line'] as String;
      }
    }
    return null;
  }

  /// Called by authoring AND strict ZIP importer, including for rebuilt
  /// checksums. Missing optional metadata preserves legacy rich-v3 worlds.
  static void validate(
    Map<String, dynamic>? responses, StoryBlueprint blueprint,
    Map<String, dynamic>? dialogues,
    Map<String, dynamic>? speakerReview,
    Map<String, dynamic> origins, {
    NpcSocialRulebook? socialRules,
  }) {
    if (responses == null) return;
    if (responses.isEmpty || responses.length > 48 ||
        blueprint.rightsStatus != 'private_adaptation' ||
        dialogues == null || speakerReview == null) {
      throw const FormatException('Unreviewed NPC response metadata');
    }
    for (final group in responses.entries) {
      final scene = blueprint.scenes[group.key];
      final speakers = speakerReview[group.key];
      final origin = origins[group.key];
      if (scene == null || !dialogues.containsKey(group.key) ||
          speakers is! List || origin is! Map<String, dynamic> ||
          origin['origin'] != 'SOURCE_PASSAGE' ||
          origin['chapter_index'] is! int ||
          origin['source_refs'] is! List ||
          scene.terminal || scene.choices.length < 2 ||
          scene.choices.length > 16 || group.value is! List ||
          (group.value as List).length != scene.choices.length) {
        throw const FormatException(
            'NPC responses need signed dialogue and two real choices');
      }
      final turns = RichSceneDialogue.verify(
          dialogues[group.key], scene.text);
      final npcs = <String>{};
      for (final raw in speakers) {
        if (raw is! Map<String, dynamic> ||
            raw['turn_index'] is! int ||
            raw['actor_id'] is! String) {
          throw const FormatException('Invalid NPC speaker review');
        }
        final i = raw['turn_index'] as int;
        if (i < 0 || i >= turns.length ||
            turns[i].speaker != raw['speaker']) {
          throw const FormatException('NPC speaker/turn mismatch');
        }
        if (raw['actor_id'] != 'player') {
          npcs.add(raw['actor_id'] as String);
        }
      }
      if (npcs.isEmpty) {
        throw const FormatException('No approved NPC interlocutor');
      }
      final outcomes = <String>{};
      for (final choice in scene.choices) {
        final memories = socialRules?.rules.where((r) =>
            r.sceneId == scene.id && r.choiceId == choice.id).map((r) =>
                [r.observerId, r.memoryId, r.relationshipDelta,
                 r.relatedActorId]).toList() ?? [];
        outcomes.add(canonicalJson({
          'next': choice.nextSceneId,
          'effects': [for (final e in choice.effects)
            [e.op, e.id, e.actor, e.amount, e.value]],
          'npc_memories': memories,
        }));
      }
      if (outcomes.length < 2) {
        throw const FormatException('NPC answers have no different outcomes');
      }
      final used = <String>{};
      for (final raw in group.value as List) {
        if (raw is! Map<String, dynamic> ||
            raw.keys.toSet().length != 5 ||
            !raw.keys.toSet().containsAll({
              'choice_id', 'interlocutor_id', 'player_line',
              'source_quote_sha256', 'private_fiction_confirmed',
            })) {
          throw const FormatException('Unknown NPC response review fields');
        }
        final choice = raw['choice_id'];
        final actor = raw['interlocutor_id'];
        final line = raw['player_line'];
        final quote = raw['source_quote_sha256'];
        if (choice is! String || !used.add(choice) ||
            !scene.choices.any((c) => c.id == choice) ||
            actor is! String || !npcs.contains(actor) ||
            !CharacterId.isValidNpc(actor) ||
            line is! String || line.trim() != line ||
            line.length < 4 || line.length > 220 ||
            _controls.hasMatch(line) || line.contains('«') ||
            line.contains('»') || line.contains('"') ||
            quote is! String || !_sha.hasMatch(quote) ||
            raw['private_fiction_confirmed'] != true) {
          throw const FormatException('Unapproved NPC response');
        }
        final chapter = origin['chapter_index'] as int;
        if (!(origin['source_refs'] as List).any((ref) => ref is Map &&
            ref['quote_sha256'] == quote &&
            ref['chapter_index'] is int &&
            (ref['chapter_index'] as int) <= chapter &&
            ref['visible_after_chapter'] is int &&
            (ref['visible_after_chapter'] as int) <= chapter)) {
          throw const FormatException('Response has no source-bound quote');
        }
        if (socialRules?.requireReviewedWitnesses == true &&
            !socialRules!.witnesses.any((w) =>
                w.sceneId == scene.id && w.actorId == actor &&
                w.mode == NpcWitnessMode.present)) {
          throw const FormatException(
              'NPC reply requires verified personal scene presence');
        }
        if (socialRules != null &&
            socialRules.lifeTransitions.any((life) =>
                life.actorId == actor) &&
            !socialRules.choiceGates.any((gate) =>
                gate.sceneId == scene.id && gate.choiceId == choice &&
                gate.actorId == actor)) {
          throw const FormatException(
              'NPC life state must be enforced by story_core choice gate');
        }
      }
      if (used.length != scene.choices.length ||
          !used.containsAll(scene.choices.map((c) => c.id))) {
        throw const FormatException('Missing one or more reviewed NPC answers');
      }
    }
  }

  /// One coherent approval proposal for every reply in each reviewed scene.
  static ReviewedNpcResponsePlan propose({
    required StoryBlueprint blueprint,
    required Map<String, dynamic> sceneOrigins,
    required Map<String, dynamic> signedDialogues,
    required Map<String, dynamic> reviewedSpeakerTurns,
    required Map<String, Map<String, String>> playerLinesByScene,
    required Map<String, String> interlocutorByScene,
    required Map<String, String> sourceQuoteByScene,
    required bool wholeDialogueReviewed,
    required bool privateFictionAcknowledged,
    NpcSocialRulebook? socialRules,
  }) {
    if (!wholeDialogueReviewed || !privateFictionAcknowledged ||
        playerLinesByScene.isEmpty ||
        playerLinesByScene.keys.toSet().difference(
            interlocutorByScene.keys.toSet()).isNotEmpty ||
        playerLinesByScene.keys.toSet().difference(
            sourceQuoteByScene.keys.toSet()).isNotEmpty ||
        interlocutorByScene.keys.toSet().length != playerLinesByScene.length ||
        sourceQuoteByScene.keys.toSet().length != playerLinesByScene.length) {
      throw const FormatException('Incomplete NPC response review');
    }
    final responses = <String, dynamic>{};
    for (final group in playerLinesByScene.entries) {
      final scene = blueprint.scenes[group.key];
      if (scene == null) {
        throw const FormatException('Unknown NPC answer scene');
      }
      responses[group.key] = [
        for (final choice in scene.choices)
          {
            'choice_id': choice.id,
            'interlocutor_id': interlocutorByScene[group.key],
            'player_line': group.value[choice.id],
            'source_quote_sha256': sourceQuoteByScene[group.key],
            'private_fiction_confirmed': true,
          },
      ];
    }
    validate(responses, blueprint, signedDialogues, reviewedSpeakerTurns,
        sceneOrigins, socialRules: socialRules);
    final digest = sha256.convert(utf8.encode(canonicalJson({
      'format': 'ai_story_reviewed_npc_responses_v1',
      'blueprint_sha256': blueprint.blueprintHash,
      'social_digest': socialRules?.digest,
      'responses': responses,
    }))).toString();
    return ReviewedNpcResponsePlan._(blueprint.blueprintHash,
        socialRules?.digest, digest,
        Map<String, dynamic>.unmodifiable(
            jsonDecode(jsonEncode(responses)) as Map<String, dynamic>));
  }

  static Map<String, dynamic> accept({
    required ReviewedNpcResponsePlan proposal,
    required StoryBlueprint blueprint,
    required String approvedDigest,
    required bool userConfirmed,
    NpcSocialRulebook? socialRules,
  }) {
    if (!userConfirmed || approvedDigest != proposal.approvalDigest ||
        proposal.blueprintHash != blueprint.blueprintHash ||
        proposal.socialRulebookDigest != socialRules?.digest) {
      throw const FormatException('NPC reply approval is stale');
    }
    return jsonDecode(jsonEncode(proposal.reviewedResponses))
        as Map<String, dynamic>;
  }
}

class ReviewedNpcResponsePlan {
  const ReviewedNpcResponsePlan._(this.blueprintHash,
      this.socialRulebookDigest, this.approvalDigest, this.reviewedResponses);

  final String blueprintHash;
  final String? socialRulebookDigest;
  final String approvalDigest;
  final Map<String, dynamic> reviewedResponses;
  bool get isLiteraryCanon => false;
  bool get canModifyCampaign => false;
  bool get needsFinalApproval => true;
}
