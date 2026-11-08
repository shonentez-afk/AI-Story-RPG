import 'dart:convert';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_npc_campaign_bookworld_writer.dart';
import 'package:crypto/crypto.dart';
import 'dart:isolate';
import 'package:story_core/story_core.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_source_encounters.dart';
import 'bookwide_storyplan_composer.dart';
import 'multi_act_trial_compiler.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'reviewed_hero_source_action.dart';
import 'reviewed_story_narrative.dart';
import 'source_evidence_graph.dart';
import 'story_plan.dart';
import 'story_plan_trial_compiler.dart';

String _sha(String value) => sha256.convert(utf8.encode(value)).toString();

/// Different explicit output contracts must NEVER reuse the same approval.
/// Keep the historical v3 digest bytes stable for old private reviews.
String _digestPlan(StoryPlan plan, bool expanded) => expanded
    ? _sha(canonicalJson({
        'scope': 'reviewed_bookwide_private_extended_v4',
        'plan': plan.encode(expanded: true),
      }))
    : _sha(plan.encode());

/// The selected protagonist and all NPC episodes share ONE source plan and
/// the existing compiler/runtime. Source coverage is not literary truth.
class WholeBookNpcSourcePlan {
  WholeBookNpcSourcePlan._({
    required this.index, required this.book, required this.bookMap,
    required this.draft, required this.plan,
    required Set<String> extraEventIds, required Set<String> reviewedEventIds,
    required this.coverage, required this.selectedHeroRole,
    required this.reviewedHeroSourceAction,
  }) : extraEventIds = Set.unmodifiable(extraEventIds),
       reviewedEventIds = Set.unmodifiable(reviewedEventIds),
       planDigest = _digestPlan(plan, draft.expanded);

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final MultiActStoryPlanDraft draft;
  final StoryPlan plan;
  final Set<String> extraEventIds, reviewedEventIds;
  final BookwideStoryCoverage coverage;
  final String planDigest;
  bool get expanded => draft.expanded;
  final ReviewedHeroRole? selectedHeroRole;
  final bool reviewedHeroSourceAction;
  bool get literaryMeaningVerified => false;
  String get heroName => selectedHeroRole?.displayName ?? 'Игрок';
  ReviewedStoryNarrative? get narrative =>
      draft is ReviewedStoryNarrative ? draft as ReviewedStoryNarrative : null;

  /// Local digest; the cloud receives only the separately displayed role.
  static String roleDigest(ReviewedHeroRole role) {
    final mentions = [...role.confirmedMentions]..sort((a, b) => a.id.compareTo(b.id));
    return _sha(canonicalJson({
      'source': role.sourceFingerprint, 'character_id': role.characterId,
      'name': role.displayName, 'dossier': role.dossierId, 'group': role.groupDigest,
      'first_chapter': role.firstSourceChapter,
      'mentions': [for (final m in mentions) {
        'id': m.id, 'chunk': m.chunkId, 'start': m.startUtf16,
        'end': m.endUtf16, 'status': m.status.name, 'kind': m.kind.name,
      }],
    }));
  }

  String get heroReviewDigest => _sha(canonicalJson({
    'role': selectedHeroRole == null ? null : roleDigest(selectedHeroRole!),
    'source_action': reviewedHeroSourceAction,
  }));

  Map<String, dynamic> get heroCloudContext => {
    'runtime_actor': 'player', 'character_id': selectedHeroRole?.characterId,
    'display_name': heroName, 'status': 'PRIVATE_PLAYER_ROLE_NOT_LITERARY_CANON',
    'imports_npc_knowledge': false, 'source_observation_enabled': reviewedHeroSourceAction,
  };

  void verifyCurrentHero(List<ReviewedHeroRole> currentRoles) {
    // An accepted story also binds the entire reviewed cast, not just the
    // player label. The old per-act path has no additional story binding.
    narrative?.verifyRoles(currentRoles);
    final hero = selectedHeroRole;
    if (hero == null) return;
    final matches = currentRoles.where((r) => r.characterId == hero.characterId).toList();
    if (matches.length != 1 || roleDigest(matches.single) != roleDigest(hero)) {
      throw const FormatException('Карточка выбранного героя изменена или отозвана. '
          'Выберите и подтвердите роль заново.');
    }
    for (final mention in matches.single.confirmedMentions) { mention.validate(index); }
  }

  void verifyArchiveHero(VerifiedRichPrivateBookworld world) {
    final hero = selectedHeroRole;
    final identity = world.blueprint.initial.flags.entries
        .where((e) => e.key.startsWith('player_is_npc_')).toList();
    final profile = world.presentation['hero'];
    if (world.sourceFingerprint != index.sourceFingerprint ||
        profile is! Map || profile['name'] != heroName ||
        (hero == null ? identity.isNotEmpty :
          identity.length != 1 || identity.single.key != hero.playerIdentityFlag ||
          identity.single.value != true || world.blueprint.actors.contains(hero.characterId))) {
      throw const FormatException('Роль героя в собранном мире не совпала с выбранной карточкой.');
    }
  }

  factory WholeBookNpcSourcePlan.fromBook({
    required BookSourceIndex index, required NarrativeBookModel book,
    required BookwideActPlan bookMap, required MultiActStoryPlanDraft draft,
    ReviewedHeroRole? selectedHeroRole,
    bool reviewedHeroSourceAction = false,
  }) {
    if (draft is ReviewedStoryNarrative &&
        (draft.context.index.sourceFingerprint != index.sourceFingerprint ||
         draft.context.book.sourceFingerprint != book.sourceFingerprint ||
         draft.context.book.title != book.title)) {
      throw const FormatException('Общий сюжет относится к другой исходной книге.');
    }
    if (reviewedHeroSourceAction && selectedHeroRole == null) {
      throw const FormatException('Ролевое действие требует выбранного героя.');
    }
    if (selectedHeroRole != null) {
      if (selectedHeroRole.sourceFingerprint != index.sourceFingerprint ||
          !CharacterId.isValidNpc(selectedHeroRole.characterId) ||
          selectedHeroRole.confirmedMentions.isEmpty) {
        throw const FormatException('Герой не подтверждён в этой редакции книги.');
      }
      for (final mention in selectedHeroRole.confirmedMentions) { mention.validate(index); }
    }
    final extras = <String>{};
    for (var i = 0; i < draft.parts.length; i++) {
      final candidates = BookwideSourceEncounters.eligibleForAct(
          index: index, bookMap: bookMap, draft: draft, partIndex: i);
      if (candidates.length > BookwideSourceEncounters.maxReviewedEventsPerAct) {
        throw const FormatException('Акт превышает вместимость. Нельзя молча отбросить события книги.');
      }
      extras.addAll(candidates.map((e) => e.id));
    }
    if (extras.length > BookwideSourceEncounters.remainingSceneCapacity(
        draft.plan, expanded: draft.expanded)) {
      throw const FormatException('Сценарий не помещается в текущий формат; события не обрезаны.');
    }
    final sourcePlan = BookwideSourceEncounters.attach(
      index: index, book: book, bookMap: bookMap, draft: draft,
      plan: draft.plan, reviewedEventIds: extras,
      userConfirmedPrivateAdaptation: true, // Local preview; no export or API.
      expanded: draft.expanded,
    );
    final rolePlan = selectedHeroRole?.bindTo(sourcePlan, book,
        expanded: draft.expanded) ?? sourcePlan;
    final plan = reviewedHeroSourceAction ? ReviewedHeroSourceAction.attach(
      index: index, book: book, plan: rolePlan, role: selectedHeroRole!,
      explicitlyConfirmedPrivateGameFiction: true,
      expanded: draft.expanded,
    ) : rolePlan;
    final reviewed = <String>{
      ...extras,
      for (final part in draft.parts) ...[part.setupEventId, part.outcomeEventId],
    };
    for (final event in book.events.where((e) => reviewed.contains(e.id))) { event.source.validate(index); }
    return WholeBookNpcSourcePlan._(
      index: index, book: book, bookMap: bookMap, draft: draft, plan: plan,
      selectedHeroRole: selectedHeroRole, reviewedHeroSourceAction: reviewedHeroSourceAction,
      extraEventIds: extras, reviewedEventIds: reviewed,
      coverage: BookwideActPlanner.compareWithStoryPlan(bookMap: bookMap,
          book: book, story: plan, expanded: draft.expanded),
    );
  }

  Future<StoryPlanTrialCompilation> compileBase({
    required String approvedPlanDigest, required bool allShownQuotesReviewed,
    required bool privateFictionConfirmed, String? approvedHeroDigest,
  }) {
    if (!allShownQuotesReviewed || !privateFictionConfirmed ||
        approvedPlanDigest != planDigest ||
        _digestPlan(plan, expanded) != planDigest ||
        (selectedHeroRole != null && approvedHeroDigest != heroReviewDigest)) {
      throw const FormatException('Согласие на цитаты или выбранного героя устарело.');
    }
    return MultiActTrialCompiler.compile(
      index: index, book: book, bookMap: bookMap, draft: draft,
      sourceEventIdsReviewedByUser: reviewedEventIds, reviewedInteractiveEventIds: extraEventIds,
      heroName: heroName, selectedHeroRole: selectedHeroRole,
      reviewedHeroSourceAction: reviewedHeroSourceAction,
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
      expanded: expanded,
    );
  }
}

class BookwideNpcConversationCandidate {
  BookwideNpcConversationCandidate._({required this.id, required this.role,
    required this.firstSceneId, required this.responseSceneId,
    required this.firstExitChoiceId, required this.responseExitChoiceId,
    required this.firstEvent, required this.responseEvent});
  final String id;
  final ReviewedHeroRole role;
  final String firstSceneId, responseSceneId, firstExitChoiceId, responseExitChoiceId;
  final NarrativeEvent firstEvent, responseEvent;
  bool get isCanonicalConversation => false;

  Map<String, dynamic> approvedRow(NpcCampaignDialogueDraft draft) => {
    'id': id, 'actor_id': role.characterId, 'display_name': role.displayName,
    'character_group_digest': role.groupDigest,
    'first_scene_id': firstSceneId, 'first_exit_choice_id': firstExitChoiceId,
    'response_scene_id': responseSceneId, 'response_exit_choice_id': responseExitChoiceId,
    'source_event_id': firstEvent.id, 'response_event_id': responseEvent.id,
    'first_quote_sha256': _sha(firstEvent.source.quote),
    'response_quote_sha256': _sha(responseEvent.source.quote),
    'player_line': draft.playerLine, 'npc_line': draft.npcLine,
    'requires_episodes': draft.requiresCandidateIds.toList()..sort(),
  };
}

class NpcCampaignDialogueDraft {
  NpcCampaignDialogueDraft({required this.candidateId, required this.playerLine,
    required this.npcLine, Iterable<String> requiresCandidateIds = const []})
      : requiresCandidateIds = List.unmodifiable(requiresCandidateIds);
  final String candidateId, playerLine, npcLine;
  final List<String> requiresCandidateIds;
}

class ReviewedBookwideNpcCampaign {
  ReviewedBookwideNpcCampaign._({
    required this.reviewJson, required this.planDigest, required this.heroReviewDigest,
    required this.storyReviewDigest,
    required Uint8List baseArchive, required this.selectedDrafts, required this.actorCount,
  }) : _baseArchive = Uint8List.fromList(baseArchive),
       // A motive-only edit may keep the exact same rules. It must still
       // revoke the author's approval; do not equate rules with the story.
       approvalDigest = storyReviewDigest == null
           ? ReviewedNpcCampaignBookworldWriter.digest(reviewJson)
           : _sha(canonicalJson({'scope': 'story_npc_author_approval_v1',
               'story': storyReviewDigest, 'review': reviewJson}));
  final String reviewJson, approvalDigest, planDigest, heroReviewDigest;
  final String? storyReviewDigest;
  final Uint8List _baseArchive;
  final List<NpcCampaignDialogueDraft> selectedDrafts;
  final int actorCount;
  int get episodeCount => selectedDrafts.length;
  Map<String, dynamic> get shownReview => Map<String, dynamic>.from(jsonDecode(reviewJson) as Map);
  bool get isLiteraryCanon => false;
}

class BookwideNpcCampaignBuild {
  const BookwideNpcCampaignBuild({required this.archive, required this.archiveSha256,
    required this.actorCount, required this.episodeCount,
    required this.sourceEventsRepresented, required this.sourceEventsTotal});
  final Uint8List archive;
  final String archiveSha256;
  final int actorCount, episodeCount, sourceEventsRepresented, sourceEventsTotal;
  bool get requiresNetworkToPlay => false;
  bool get canonicalAdaptationVerified => false;
}

Uint8List _compileNpcCampaign(Map<String, dynamic> data) =>
    const ReviewedNpcCampaignBookworldWriter().build(
      verifiedBaseArchive: data['archive'] as Uint8List,
      sourceIndex: Map<String, dynamic>.from(data['source_index'] as Map),
      reviewJson: data['review_json'] as String,
      approvedDigest: data['approval_digest'] as String, userConfirmed: true,
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
    required WholeBookNpcSourcePlan source, required List<ReviewedHeroRole> currentReviewedRoles,
  }) {
    if (source.planDigest != _digestPlan(source.plan, source.expanded)) {
      throw const FormatException('Сценарий изменился после просмотра цитат.');
    }
    source.verifyCurrentHero(currentReviewedRoles);
    final roles = [...currentReviewedRoles]..sort((a, b) => a.characterId.compareTo(b.characterId));
    if (roles.map((r) => r.characterId).toSet().length != roles.length) {
      throw const FormatException('Один character_id повторён в карточках.');
    }
    final events = {for (final event in source.book.events) event.id: event};
    final result = <BookwideNpcConversationCandidate>[];
    for (final role in roles) {
      if (role.sourceFingerprint != source.index.sourceFingerprint ||
          !CharacterId.isValidNpc(role.characterId) || role.confirmedMentions.isEmpty) {
        throw const FormatException('Карточка NPC относится к другой книге.');
      }
      if (role.characterId == source.selectedHeroRole?.characterId) continue;
      final matching = <(StorySituation, StoryDecision, NarrativeEvent)>[];
      for (final scene in source.plan.situations) {
        final event = events[scene.sourceEventId], exit = _safePass(scene);
        if (event == null || exit == null || scene.route != StoryRoute.canonicalProposal) continue;
        event.source.validate(source.index);
        final mentioned = role.confirmedMentions.any((mention) {
          mention.validate(source.index);
          return mention.status == EvidenceStatus.confirmed && mention.kind == EvidenceKind.character &&
              mention.chunkId == event.source.chunkId && mention.startUtf16 < event.source.endUtf16 &&
              event.source.startUtf16 < mention.endUtf16;
        });
        if (mentioned) matching.add((scene, exit, event));
      }
      matching.sort((a, b) {
        final order = a.$3.narrativePosition.compareTo(b.$3.narrativePosition);
        return order != 0 ? order : a.$1.id.compareTo(b.$1.id);
      });
      for (var i = 1; i < matching.length; i++) {
        final first = matching[i - 1], next = matching[i];
        if (first.$1.id == next.$1.id || first.$3.source.chapterIndex > next.$3.source.chapterIndex) continue;
        final id = 'npc_arc_${_sha(canonicalJson({
          'source': source.index.sourceFingerprint, 'actor': role.characterId,
          'group': role.groupDigest, 'first': first.$1.id, 'next': next.$1.id,
        })).substring(0, 16)}';
        result.add(BookwideNpcConversationCandidate._(
          id: id, role: role, firstSceneId: first.$1.id, responseSceneId: next.$1.id,
          firstExitChoiceId: first.$2.id, responseExitChoiceId: next.$2.id,
          firstEvent: first.$3, responseEvent: next.$3,
        ));
      }
    }
    result.sort((a, b) {
      final p = a.firstEvent.narrativePosition.compareTo(b.firstEvent.narrativePosition);
      return p != 0 ? p : a.id.compareTo(b.id);
    });
    return List.unmodifiable(result);
  }

  static ReviewedBookwideNpcCampaign review({required WholeBookNpcSourcePlan source,
    required Uint8List verifiedBaseArchive, required List<ReviewedHeroRole> currentReviewedRoles,
    required List<NpcCampaignDialogueDraft> selectedDrafts}) {
    final base = const RichPrivateBookworldImporter().inspect(verifiedBaseArchive);
    source.verifyCurrentHero(currentReviewedRoles); source.verifyArchiveHero(base);
    if (base.formatVersion != (source.expanded ? 4 : 3) ||
        base.blueprint.scenes.length != source.plan.situations.length ||
        selectedDrafts.isEmpty || selectedDrafts.length > ReviewedNpcCampaignBookworldWriter.maxEpisodes) {
      throw const FormatException('Неверный сценарий или число NPC-разговоров.');
    }
    final candidates = {for (final c in discover(source: source, currentReviewedRoles: currentReviewedRoles)) c.id: c};
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
    if (selectedDrafts.any((d) => d.requiresCandidateIds.any((id) => !chosen.contains(id)))) {
      throw const FormatException('Предшествующий разговор не включён в кампанию.');
    }
    rows.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final json = canonicalJson({
      'format': ReviewedNpcCampaignBookworldWriter.reviewFormat,
      'scope': ReviewedNpcCampaignBookworldWriter.scope,
      'source_fingerprint': base.sourceFingerprint, 'base_archive_sha256': base.archiveSha256,
      'base_blueprint_sha256': base.blueprint.blueprintHash, 'episodes': rows,
    });
    return ReviewedBookwideNpcCampaign._(
      reviewJson: json, planDigest: source.planDigest, heroReviewDigest: source.heroReviewDigest,
      storyReviewDigest: source.narrative?.reviewDigest,
      baseArchive: verifiedBaseArchive, selectedDrafts: List.unmodifiable(selectedDrafts),
      actorCount: rows.map((r) => r['actor_id']).toSet().length,
    );
  }

  static Future<BookwideNpcCampaignBuild> compile({required WholeBookNpcSourcePlan source,
    required ReviewedBookwideNpcCampaign approval, required List<ReviewedHeroRole> freshReviewedRoles,
    required String approvedDigest, required bool explicitlyConfirmedPrivateFiction}) async {
    if (!explicitlyConfirmedPrivateFiction || approvedDigest != approval.approvalDigest ||
        source.planDigest != approval.planDigest || source.heroReviewDigest != approval.heroReviewDigest ||
        source.narrative?.reviewDigest != approval.storyReviewDigest) {
      throw const FormatException('Нет точного согласия на героя, общий сюжет и NPC-кампанию.');
    }
    await source.narrative?.verifyLive();
    final fresh = review(source: source, verifiedBaseArchive: approval._baseArchive,
      currentReviewedRoles: freshReviewedRoles, selectedDrafts: approval.selectedDrafts);
    if (fresh.approvalDigest != approvedDigest) {
      throw const FormatException('Карточки или реплики изменились: проверьте заново.');
    }
    // The author-level digest also binds narrative. The existing worker still
    // receives ONLY its established strict v3 review and its own digest.
    final payload = <String, dynamic>{
      'archive': approval._baseArchive, 'source_index': source.index.toJson(),
      'review_json': approval.reviewJson,
      'approval_digest': ReviewedNpcCampaignBookworldWriter.digest(approval.reviewJson),
    };
    final archive = await Isolate.run(() => _compileNpcCampaign(payload));
    await source.narrative?.verifyLive();
    final verified = const RichPrivateBookworldImporter().inspect(archive);
    source.verifyArchiveHero(verified);
    if (verified.formatVersion != (source.expanded ? 4 : 3) ||
        verified.requiresNetwork || verified.canDistributePublicly ||
        verified.blueprint.actors.length != approval.actorCount + 1) {
      throw const FormatException('Собранный NPC-мир не соответствует принятой кампании.');
    }
    return BookwideNpcCampaignBuild(archive: archive, archiveSha256: verified.archiveSha256,
      actorCount: approval.actorCount, episodeCount: approval.episodeCount,
      sourceEventsRepresented: source.coverage.referencedEvents, sourceEventsTotal: source.coverage.allEvents);
  }
}
