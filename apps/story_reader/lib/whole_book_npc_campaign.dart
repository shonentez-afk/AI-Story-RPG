import 'dart:convert';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:story_core/story_core.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_source_encounters.dart';
import 'bookwide_storyplan_composer.dart';
import 'multi_act_trial_compiler.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';
import 'story_plan_trial_compiler.dart';

String _sha(String value) => sha256.convert(utf8.encode(value)).toString();

/// ALL eligible source events of the supplied act scenario are considered.
/// Nothing is silently truncated to an arbitrary first encounter or actor.
/// Missing acts/events remain an explicit coverage gap, never literary canon.
class WholeBookNpcSourcePlan {
  WholeBookNpcSourcePlan._({
    required this.index, required this.book, required this.bookMap,
    required this.draft, required this.plan,
    required Set<String> extraEventIds, required Set<String> reviewedEventIds,
    required this.coverage,
  }) : extraEventIds = Set.unmodifiable(extraEventIds),
       reviewedEventIds = Set.unmodifiable(reviewedEventIds),
       planDigest = _sha(plan.encode());

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final MultiActStoryPlanDraft draft;
  final StoryPlan plan;
  final Set<String> extraEventIds, reviewedEventIds;
  final BookwideStoryCoverage coverage;
  final String planDigest;
  bool get literaryMeaningVerified => false;

  factory WholeBookNpcSourcePlan.fromBook({
    required BookSourceIndex index, required NarrativeBookModel book,
    required BookwideActPlan bookMap, required MultiActStoryPlanDraft draft,
  }) {
    final extras = <String>{};
    for (var i = 0; i < draft.parts.length; i++) {
      final candidates = BookwideSourceEncounters.eligibleForAct(
          index: index, bookMap: bookMap, draft: draft, partIndex: i);
      if (candidates.length > BookwideSourceEncounters.maxReviewedEventsPerAct) {
        throw const FormatException(
            'Акт превышает вместимость. Нельзя молча отбросить события книги.');
      }
      extras.addAll(candidates.map((e) => e.id));
    }
    if (extras.length > BookwideSourceEncounters.remainingSceneCapacity(draft.plan)) {
      throw const FormatException(
          'Сценарий всей книги не помещается в текущий формат; события не обрезаны.');
    }
    final plan = BookwideSourceEncounters.attach(
      index: index, book: book, bookMap: bookMap, draft: draft,
      plan: draft.plan, reviewedEventIds: extras,
      userConfirmedPrivateAdaptation: true, // Local preview only, no bytes or API.
    );
    final reviewed = <String>{
      ...extras,
      for (final part in draft.parts) ...[part.setupEventId, part.outcomeEventId],
    };
    for (final event in book.events.where((e) => reviewed.contains(e.id))) {
      event.source.validate(index);
    }
    return WholeBookNpcSourcePlan._(
      index: index, book: book, bookMap: bookMap, draft: draft, plan: plan,
      extraEventIds: extras, reviewedEventIds: reviewed,
      coverage: BookwideActPlanner.compareWithStoryPlan(
          bookMap: bookMap, book: book, story: plan),
    );
  }

  /// The same production compiler and exact source consent as a manual game.
  Future<StoryPlanTrialCompilation> compileBase({
    required String approvedPlanDigest,
    required bool allShownQuotesReviewed,
    required bool privateFictionConfirmed,
  }) {
    if (!allShownQuotesReviewed || !privateFictionConfirmed ||
        approvedPlanDigest != planDigest || _sha(plan.encode()) != planDigest) {
      throw const FormatException('Согласие на цитаты всей кампании устарело.');
    }
    return MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: bookMap, draft: draft,
      sourceEventIdsReviewedByUser: reviewedEventIds,
      reviewedInteractiveEventIds: extraEventIds,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
  }
}

/// A source-backed opportunity, NOT an inferred literary conversation.
/// Pairing adjacent reviewed mentions is a writing suggestion; only execution
/// through the imported StoryWorld can prove its actual game chronology.
class BookwideNpcConversationCandidate {
  BookwideNpcConversationCandidate._({
    required this.id, required this.role,
    required this.firstSceneId, required this.responseSceneId,
    required this.firstExitChoiceId, required this.responseExitChoiceId,
    required this.firstEvent, required this.responseEvent,
  });
  final String id;
  final ReviewedHeroRole role;
  final String firstSceneId, responseSceneId;
  final String firstExitChoiceId, responseExitChoiceId;
  final NarrativeEvent firstEvent, responseEvent;
  bool get isCanonicalConversation => false;

  Map<String, dynamic> approvedRow(NpcCampaignDialogueDraft draft) => {
    'id': id, 'actor_id': role.characterId, 'display_name': role.displayName,
    'character_group_digest': role.groupDigest,
    'first_scene_id': firstSceneId, 'first_exit_choice_id': firstExitChoiceId,
    'response_scene_id': responseSceneId,
    'response_exit_choice_id': responseExitChoiceId,
    'source_event_id': firstEvent.id, 'response_event_id': responseEvent.id,
    'first_quote_sha256': _sha(firstEvent.source.quote),
    'response_quote_sha256': _sha(responseEvent.source.quote),
    'player_line': draft.playerLine, 'npc_line': draft.npcLine,
    'requires_episodes': draft.requiresCandidateIds.toList()..sort(),
  };
}

class NpcCampaignDialogueDraft {
  NpcCampaignDialogueDraft({
    required this.candidateId, required this.playerLine, required this.npcLine,
    Iterable<String> requiresCandidateIds = const [],
  }) : requiresCandidateIds = List.unmodifiable(requiresCandidateIds);
  final String candidateId, playerLine, npcLine;
  final List<String> requiresCandidateIds;
}

/// An immutable, exact review. Editing a word, dependency, identity or base
/// archive creates another approval digest and cannot overwrite an old save.
class ReviewedBookwideNpcCampaign {
  ReviewedBookwideNpcCampaign._({
    required this.reviewJson, required this.planDigest,
    required Uint8List baseArchive,
    required this.selectedDrafts, required this.actorCount,
  }) : _baseArchive = Uint8List.fromList(baseArchive),
       approvalDigest = ReviewedNpcCampaignBookworldWriter.digest(reviewJson);
  final String reviewJson, approvalDigest, planDigest;
  final Uint8List _baseArchive;
  final List<NpcCampaignDialogueDraft> selectedDrafts;
  final int actorCount;
  int get episodeCount => selectedDrafts.length;
  Map<String, dynamic> get shownReview =>
      Map<String, dynamic>.from(jsonDecode(reviewJson) as Map);
  bool get isLiteraryCanon => false;
}

class BookwideNpcCampaignBuild {
  const BookwideNpcCampaignBuild({
    required this.archive, required this.archiveSha256,
    required this.actorCount, required this.episodeCount,
    required this.sourceEventsRepresented, required this.sourceEventsTotal,
  });
  final Uint8List archive;
  final String archiveSha256;
  final int actorCount, episodeCount;
  final int sourceEventsRepresented, sourceEventsTotal;
  bool get requiresNetworkToPlay => false;
  bool get canonicalAdaptationVerified => false;
}

Uint8List _compileNpcCampaign(Map<String, dynamic> data) =>
    const ReviewedNpcCampaignBookworldWriter().build(
      verifiedBaseArchive: data['archive'] as Uint8List,
      sourceIndex: Map<String, dynamic>.from(data['source_index'] as Map),
      reviewJson: data['review_json'] as String,
      approvedDigest: data['approval_digest'] as String,
      userConfirmed: true,
    );

class BookwideNpcCampaignAuthoring {
  const BookwideNpcCampaignAuthoring._();

  static StoryDecision? _safePass(StorySituation scene) {
    for (final d in scene.decisions) {
      if (d.id.contains('_pass_source') && d.requires.isEmpty &&
          d.forbids.isEmpty && d.adds.isEmpty && d.removes.isEmpty) return d;
    }
    return null;
  }

  static List<BookwideNpcConversationCandidate> discover({
    required WholeBookNpcSourcePlan source,
    required List<ReviewedHeroRole> currentReviewedRoles,
  }) {
    if (source.planDigest != _sha(source.plan.encode())) {
      throw const FormatException('Сценарий изменился после просмотра цитат.');
    }
    final roles = [...currentReviewedRoles]
      ..sort((a, b) => a.characterId.compareTo(b.characterId));
    if (roles.map((r) => r.characterId).toSet().length != roles.length) {
      throw const FormatException('Один character_id повторён в карточках.');
    }
    final events = {for (final event in source.book.events) event.id: event};
    final result = <BookwideNpcConversationCandidate>[];
    for (final role in roles) {
      if (role.sourceFingerprint != source.index.sourceFingerprint ||
          !CharacterId.isValidNpc(role.characterId) ||
          role.confirmedMentions.isEmpty) {
        throw const FormatException('Карточка NPC относится к другой книге.');
      }
      final matching = <(StorySituation, StoryDecision, NarrativeEvent)>[];
      for (final scene in source.plan.situations) {
        final event = events[scene.sourceEventId];
        final exit = _safePass(scene);
        if (event == null || exit == null ||
            scene.route != StoryRoute.canonicalProposal) continue;
        event.source.validate(source.index);
        final mentioned = role.confirmedMentions.any((mention) {
          mention.validate(source.index);
          return mention.status == EvidenceStatus.confirmed &&
              mention.kind == EvidenceKind.character &&
              mention.chunkId == event.source.chunkId &&
              mention.startUtf16 < event.source.endUtf16 &&
              event.source.startUtf16 < mention.endUtf16;
        });
        if (mentioned) matching.add((scene, exit, event));
      }
      matching.sort((a, b) {
        final order = a.$3.narrativePosition.compareTo(b.$3.narrativePosition);
        return order != 0 ? order : a.$1.id.compareTo(b.$1.id);
      });
      for (var i = 1; i < matching.length; i++) {
        final first = matching[i - 1];
        final next = matching[i];
        if (first.$1.id == next.$1.id ||
            first.$3.source.chapterIndex > next.$3.source.chapterIndex) continue;
        final id = 'npc_arc_${_sha(canonicalJson({
          'source': source.index.sourceFingerprint,
          'actor': role.characterId, 'group': role.groupDigest,
          'first': first.$1.id, 'next': next.$1.id,
        })).substring(0, 16)}';
        result.add(BookwideNpcConversationCandidate._(
          id: id, role: role,
          firstSceneId: first.$1.id, responseSceneId: next.$1.id,
          firstExitChoiceId: first.$2.id, responseExitChoiceId: next.$2.id,
          firstEvent: first.$3, responseEvent: next.$3,
        ));
      }
    }
    result.sort((a, b) {
      final position = a.firstEvent.narrativePosition
          .compareTo(b.firstEvent.narrativePosition);
      return position != 0 ? position : a.id.compareTo(b.id);
    });
    return List.unmodifiable(result);
  }

  static ReviewedBookwideNpcCampaign review({
    required WholeBookNpcSourcePlan source,
    required Uint8List verifiedBaseArchive,
    required List<ReviewedHeroRole> currentReviewedRoles,
    required List<NpcCampaignDialogueDraft> selectedDrafts,
  }) {
    final base = const RichPrivateBookworldImporter().inspect(verifiedBaseArchive);
    if (base.sourceFingerprint != source.index.sourceFingerprint ||
        base.blueprint.scenes.length != source.plan.situations.length ||
        selectedDrafts.isEmpty ||
        selectedDrafts.length > ReviewedNpcCampaignBookworldWriter.maxEpisodes) {
      throw const FormatException('Неверный сценарий или число NPC-разговоров.');
    }
    final candidates = {
      for (final candidate in discover(
          source: source, currentReviewedRoles: currentReviewedRoles))
        candidate.id: candidate,
    };
    final chosen = <String>{};
    final rows = <Map<String, dynamic>>[];
    for (final draft in selectedDrafts) {
      final candidate = candidates[draft.candidateId];
      if (candidate == null || !chosen.add(draft.candidateId)) {
        throw const FormatException('NPC, цитата или встреча изменились после выбора.');
      }
      for (final text in [draft.playerLine, draft.npcLine]) {
        if (text.trim() != text || text.length < 4 || text.length > 400 ||
            RegExp(r'[\x00-\x1f\x7f«»]').hasMatch(text)) {
          throw const FormatException('Проверьте обе русские игровые реплики.');
        }
      }
      rows.add(candidate.approvedRow(draft));
    }
    if (selectedDrafts.any((d) =>
        d.requiresCandidateIds.any((id) => !chosen.contains(id)))) {
      throw const FormatException('Предшествующий разговор не включён в кампанию.');
    }
    rows.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final json = canonicalJson({
      'format': ReviewedNpcCampaignBookworldWriter.reviewFormat,
      'scope': ReviewedNpcCampaignBookworldWriter.scope,
      'source_fingerprint': base.sourceFingerprint,
      'base_archive_sha256': base.archiveSha256,
      'base_blueprint_sha256': base.blueprint.blueprintHash,
      'episodes': rows,
    });
    return ReviewedBookwideNpcCampaign._(
      reviewJson: json, planDigest: source.planDigest,
      baseArchive: verifiedBaseArchive,
      selectedDrafts: List.unmodifiable(selectedDrafts),
      actorCount: rows.map((r) => r['actor_id']).toSet().length,
    );
  }

  static Future<BookwideNpcCampaignBuild> compile({
    required WholeBookNpcSourcePlan source,
    required ReviewedBookwideNpcCampaign approval,
    required List<ReviewedHeroRole> freshReviewedRoles,
    required String approvedDigest,
    required bool explicitlyConfirmedPrivateFiction,
  }) async {
    if (!explicitlyConfirmedPrivateFiction ||
        approvedDigest != approval.approvalDigest ||
        source.planDigest != approval.planDigest) {
      throw const FormatException('Нет точного согласия на NPC-кампанию.');
    }
    // Reloaded identities/revoked quotes/changed dialogue cannot reuse consent.
    final fresh = review(source: source,
      verifiedBaseArchive: approval._baseArchive,
      currentReviewedRoles: freshReviewedRoles,
      selectedDrafts: approval.selectedDrafts,
    );
    if (fresh.approvalDigest != approvedDigest) {
      throw const FormatException('Карточки или реплики изменились: проверьте заново.');
    }
    final archive = await compute(_compileNpcCampaign, <String, dynamic>{
      'archive': approval._baseArchive,
      'source_index': source.index.toJson(),
      'review_json': approval.reviewJson,
      'approval_digest': approvedDigest,
    });
    final verified = const RichPrivateBookworldImporter().inspect(archive);
    if (verified.sourceFingerprint != source.index.sourceFingerprint ||
        verified.requiresNetwork || verified.canDistributePublicly ||
        verified.blueprint.actors.length != approval.actorCount + 1) {
      throw const FormatException('Собранный NPC-мир не соответствует принятой кампании.');
    }
    return BookwideNpcCampaignBuild(
      archive: archive, archiveSha256: verified.archiveSha256,
      actorCount: approval.actorCount, episodeCount: approval.episodeCount,
      sourceEventsRepresented: source.coverage.referencedEvents,
      sourceEventsTotal: source.coverage.allEvents,
    );
  }
}
