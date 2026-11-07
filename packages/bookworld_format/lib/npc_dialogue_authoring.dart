import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'npc_dialogue_knowledge.dart';
import 'rich_scene_dialogue.dart';

/// A deterministic, offline REVIEW PROPOSAL for an already written
/// conversation, not a generator of literary truths or new engine effects.
///
/// Every speaker has an explicitly approved permanent actor ID. Every NPC
/// line is classified either as separately approved harmless game fiction
/// or as depending on a reviewed fact learned through a specific game choice.
/// No missing binding or semantic classification is silently inferred.
class ReviewedNpcDialoguePlan {
  ReviewedNpcDialoguePlan._({
    required this.blueprintHash,
    required this.sourceFingerprint,
    required this.approvalDigest,
    required this.speakerActorIds,
    required this.reviewedTurns,
    required this.npcLineCount,
    required this.causallyGuardedLineCount,
  });

  final String blueprintHash;
  final String? sourceFingerprint;
  final String approvalDigest;
  final Map<String, String> speakerActorIds;
  final Map<String, List<Map<String, dynamic>>> reviewedTurns;
  final int npcLineCount;
  final int causallyGuardedLineCount;

  bool get isLiteraryCanon => false;
  bool get needsFinalApproval => true;
  bool get requiresNetwork => false;
}

/// Reuses the ONE verified private rich-v3 dialogue format. All candidate
/// text lives in the signed StoryBlueprint; this tool only compiles the
/// explicit author reviews into the existing speaker/knowledge contract.
///
/// Source quote evidence proves only the origin of a game action, not that
/// the proposed line was literally uttered in the original book.
class RichNpcDialogueAuthoring {
  const RichNpcDialogueAuthoring._();

  static ReviewedNpcDialoguePlan propose({
    required StoryBlueprint blueprint,
    required Map<String, dynamic> sceneOrigins,
    required Map<String, String> reviewedSpeakerActorIds,
    required List<Map<String, String>> verifiedNpcFactGrants,
    required Map<String, Map<int, String>> reviewedNpcFactByTurn,
    required Map<String, Set<int>> reviewedSafeNpcTurns,
    required bool wholeDialogueTextReviewed,
    required bool privateFictionAcknowledged,
  }) {
    if (blueprint.rightsStatus != 'private_adaptation' ||
        blueprint.sourceFingerprint == null ||
        !wholeDialogueTextReviewed || !privateFictionAcknowledged) {
      throw const FormatException('NPC dialogue requires private review');
    }
    final signed = <String, dynamic>{};
    final reviews = <String, List<Map<String, dynamic>>>{};
    var npcCount = 0;
    var guardedCount = 0;
    for (final scene in blueprint.scenes.values) {
      final projection = RichSceneDialogue.presentationFor(scene.text);
      if (projection == null) continue;
      signed[scene.id] = projection;
      final turns = RichSceneDialogue.parse(scene.text)!;
      final factSelection =
          reviewedNpcFactByTurn[scene.id] ?? const <int, String>{};
      final safeSelection =
          reviewedSafeNpcTurns[scene.id] ?? const <int>{};
      final usedFactIndices = <int>{};
      final usedSafeIndices = <int>{};
      final entries = <Map<String, dynamic>>[];
      for (var i = 0; i < turns.length; i++) {
        final speaker = turns[i].speaker;
        if (speaker == null) continue;
        final actor = reviewedSpeakerActorIds[speaker];
        if (actor == null || !blueprint.actors.contains(actor) ||
            (actor != 'player' && !CharacterId.isValidNpc(actor))) {
          throw const FormatException(
              'Unresolved dialogue speaker character_id');
        }
        final factId = factSelection[i];
        final safe = safeSelection.contains(i);
        if (actor == 'player') {
          if (factId != null || safe) {
            throw const FormatException(
                'Player speech cannot inherit an NPC source grant');
          }
        } else {
          npcCount++;
          if ((factId == null && !safe) || (factId != null && safe)) {
            throw const FormatException(
                'NPC speech requires one explicit semantic classification');
          }
        }
        final review = <String, dynamic>{
          'turn_index': i,
          'speaker': speaker,
          'actor_id': actor,
          'required_fact_ids': factId == null ? <String>[] : <String>[factId],
        };
        if (factId != null) {
          usedFactIndices.add(i);
          final eligible = verifiedNpcFactGrants.where((grant) =>
              grant['actor_id'] == actor &&
              grant['fact_id'] == factId).toList();
          if (eligible.length != 1) {
            throw const FormatException(
                'Ambiguous or missing reviewed NPC learning action');
          }
          final grant = eligible.single;
          final prior = grant['choice_id'];
          final quote = grant['source_quote_sha256'];
          if (prior == null || quote == null || quote.isEmpty) {
            throw const FormatException(
                'NPC learning action has no exact source citation');
          }
          // The importer's exact-source, graph and effect checks run below.
          review.addAll({
            'required_prior_choice_id': prior,
            'source_quote_sha256': quote,
            'private_fiction_confirmed': true,
          });
          guardedCount++;
        }
        if (safe) usedSafeIndices.add(i);
        entries.add(review);
      }
      if (usedFactIndices.length != factSelection.length ||
          usedSafeIndices.length != safeSelection.length) {
        throw const FormatException(
            'Orphaned source/semantic approval for an NPC turn');
      }
      reviews[scene.id] = entries;
    }
    if (reviewedNpcFactByTurn.keys.any((id) => !signed.containsKey(id)) ||
        reviewedSafeNpcTurns.keys.any((id) => !signed.containsKey(id)) ||
        reviews.isEmpty || npcCount == 0) {
      throw const FormatException('No reviewable NPC conversation');
    }
    // Double-check every proposed turn through the actual strict importer
    // contract; no second semantic gate or engine is introduced.
    RichNpcDialogueKnowledge.validate(
      reviews, blueprint, signed, sceneOrigins: sceneOrigins);
    final frozen = <String, List<Map<String, dynamic>>>{
      for (final row in reviews.entries)
        row.key: List<Map<String, dynamic>>.unmodifiable([
          for (final review in row.value)
            Map<String, dynamic>.unmodifiable({
              ...review,
              'required_fact_ids':
                  List<String>.unmodifiable(review['required_fact_ids'] as List<String>),
            }),
        ]),
    };
    final boundSpeakers = Map<String, String>.unmodifiable(
        Map<String, String>.of(reviewedSpeakerActorIds));
    final digest = sha256.convert(utf8.encode(canonicalJson({
      'format': 'ai_story_npc_dialogue_authoring_review_v1',
      'blueprint_sha256': blueprint.blueprintHash,
      'source_fingerprint': blueprint.sourceFingerprint,
      'speaker_actor_ids': boundSpeakers,
      'scene_reviews': frozen,
      'npc_line_count': npcCount,
      'causal_line_count': guardedCount,
    }))).toString();
    return ReviewedNpcDialoguePlan._(
      blueprintHash: blueprint.blueprintHash,
      sourceFingerprint: blueprint.sourceFingerprint,
      approvalDigest: digest,
      speakerActorIds: boundSpeakers,
      reviewedTurns: Map<String, List<Map<String, dynamic>>>.unmodifiable(frozen),
      npcLineCount: npcCount,
      causallyGuardedLineCount: guardedCount,
    );
  }

  /// Only a second, exact-digest approval permits the proposal to become
  /// reviewed rich-v3 metadata. A different world or speaker map invalidates
  /// the approval. This never writes a campaign or performs any I/O.
  static Map<String, List<Map<String, dynamic>>> accept({
    required ReviewedNpcDialoguePlan proposal,
    required StoryBlueprint blueprint,
    required Map<String, String> reviewedSpeakerActorIds,
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    if (!userConfirmed ||
        approvedDigest != proposal.approvalDigest ||
        proposal.blueprintHash != blueprint.blueprintHash ||
        proposal.sourceFingerprint != blueprint.sourceFingerprint ||
        canonicalJson(proposal.speakerActorIds) !=
            canonicalJson(reviewedSpeakerActorIds)) {
      throw const FormatException('NPC dialogue approval is stale or missing');
    }
    return {
      for (final row in proposal.reviewedTurns.entries)
        row.key: [
          for (final review in row.value)
            Map<String, dynamic>.from(jsonDecode(jsonEncode(review)) as Map),
        ],
    };
  }
}
