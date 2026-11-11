import 'dart:convert';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:bookworld_format/reviewed_campaign_prose_writer.dart';
import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'book_to_rpg_workflow.dart';
import 'rpg_creation_contract.dart';
import 'campaign_prose_contract.dart';
import 'npc_campaign_consequences.dart';
import 'reviewed_hero_role.dart';
import 'source_locked_gameplay_candidates.dart';
import 'whole_book_npc_campaign.dart';
import 'whole_plan_gameplay_manifest.dart';

/// An ordered, source-locked authoring process, never a second game engine.
enum ReviewedCampaignStage { base, gameplay, dialogue, complete }

final class ReviewedCampaignState {
  ReviewedCampaignState._(this.source, Uint8List archive, this.stage,
      this.effectsCount, this.npcEpisodeCount, this.hasNewNarration)
      : _archive = Uint8List.fromList(archive),
        archiveSha256 = sha256.convert(archive).toString(),
        sourceFingerprint = source.index.sourceFingerprint,
        planDigest = source.planDigest,
        heroDigest = source.heroReviewDigest,
        storyDigest = source.narrative?.reviewDigest;

  final WholeBookNpcSourcePlan source;
  final Uint8List _archive;
  final ReviewedCampaignStage stage;
  final String sourceFingerprint, planDigest, heroDigest, archiveSha256;
  final String? storyDigest;
  final int effectsCount, npcEpisodeCount;
  final bool hasNewNarration;

  Uint8List get archive => Uint8List.fromList(_archive);
  bool get isLiteraryCanon => false;
  bool get isPubliclyDistributable => false;
  bool get canPlayOffline => stage == ReviewedCampaignStage.complete;

  Map<String, Object?> get status => {
    'format': 'reviewed_campaign_workflow_v1',
    'stage': stage.name,
    'source_fingerprint': sourceFingerprint,
    'plan_digest': planDigest,
    'hero_digest': heroDigest,
    'story_digest': storyDigest,
    'archive_sha256': archiveSha256,
    'item_effects': effectsCount,
    'npc_episodes': npcEpisodeCount,
    'narration_added': hasNewNarration,
    'can_play_offline': canPlayOffline,
    'literary_canon_verified': false,
    'public_distribution_allowed': false,
  };
}

/// Reuses the signed BookWorld, effect, NPC and prose compilers. The caller
/// provides human approvals, live reviewed roles, and optional checkpoint IO.
/// No Flutter, provider keys, network, file paths or installed saves here.
class ReviewedCampaignWorkflow {
  const ReviewedCampaignWorkflow();
  static const _importer = RichPrivateBookworldImporter();

  static String _planDigest(WholeBookNpcSourcePlan s) {
    final encoded = s.plan.encode(expanded: s.expanded);
    return s.expanded
        ? campaignProseHash({'scope': 'reviewed_bookwide_private_extended_v4',
            'plan': encoded})
        : sha256.convert(utf8.encode(encoded)).toString();
  }

  static void _stage(ReviewedCampaignState state, ReviewedCampaignStage needed) {
    if (state.stage != needed) {
      throw const FormatException('Нельзя пропустить этап подтверждения RPG.');
    }
  }

  Future<void> _verify(
      ReviewedCampaignState state, List<ReviewedHeroRole> roles) async {
    final s = state.source;
    await s.narrative?.verifyLive();
    s.verifyCurrentHero(roles);
    if (s.index.sourceFingerprint != state.sourceFingerprint ||
        s.planDigest != state.planDigest || s.planDigest != _planDigest(s) ||
        s.heroReviewDigest != state.heroDigest ||
        s.narrative?.reviewDigest != state.storyDigest ||
        sha256.convert(state._archive).toString() != state.archiveSha256) {
      throw const FormatException('Изменилась редакция, роль или архив игры.');
    }
    final world = _importer.inspect(state._archive);
    s.verifyArchiveHero(world);
    if (world.archiveSha256 != state.archiveSha256 ||
        world.requiresNetwork || world.canDistributePublicly ||
        world.formatVersion != (s.expanded ? 4 : 3) ||
        !world.blueprint.scenes.keys.toSet().containsAll(
            s.plan.situations.map((v) => v.id))) {
      throw const FormatException('Собранный мир не соответствует плану.');
    }
  }

  Future<ReviewedCampaignState> compileBase({
    required WholeBookNpcSourcePlan source,
    required List<ReviewedHeroRole> reviewedRoles,
    required String approvedPlanDigest,
    required String approvedHeroDigest,
    required bool allShownQuotesReviewed,
    required bool privateFictionConfirmed,
  }) async {
    RpgCreationPolicy.inspect(
      RpgCreationIntent.reviewedAlterFate(
        hero: source.selectedHeroRole == null
            ? RpgCreationHero.freePlayer
            : RpgCreationHero.reviewedCharacterIdentity),
      sourceFingerprint: source.index.sourceFingerprint,
      reviewedHero: source.selectedHeroRole,
    ).requireSupported();
    if (!allShownQuotesReviewed || !privateFictionConfirmed ||
        approvedPlanDigest != source.planDigest ||
        approvedHeroDigest != source.heroReviewDigest) {
      throw const FormatException('Нет согласия на план, цитаты и роль.');
    }
    source.verifyCurrentHero(reviewedRoles);
    final compiled = await source.compileBase(
      approvedPlanDigest: approvedPlanDigest,
      approvedHeroDigest: approvedHeroDigest,
      allShownQuotesReviewed: allShownQuotesReviewed,
      privateFictionConfirmed: privateFictionConfirmed,
    );
    final state = ReviewedCampaignState._(
        source, compiled.archive, ReviewedCampaignStage.base, 0, 0, false);
    await _verify(state, reviewedRoles);
    return state;
  }

  NpcCampaignConsequencePreview previewEffects({
    required ReviewedCampaignState base,
    required List<ReviewedHeroRole> reviewedRoles,
    required WholePlanGameplayBatchManifest manifest,
    required List<GameplayCandidateDraft> proposals,
    required Map<String, String> reviewNotes,
  }) {
    _stage(base, ReviewedCampaignStage.base);
    return NpcCampaignConsequences.preview(
      source: base.source, originalArchive: base.archive,
      currentReviewedRoles: reviewedRoles, manifest: manifest,
      proposals: proposals, selectedUserReviewNotes: reviewNotes);
  }

  Future<ReviewedCampaignState> acceptEffects({
    required ReviewedCampaignState base,
    required List<ReviewedHeroRole> reviewedRoles,
    required NpcCampaignConsequencePreview review,
    required String approvedDigest,
    required bool explicitlyConfirmedPrivateFiction,
  }) async {
    _stage(base, ReviewedCampaignStage.base);
    await _verify(base, reviewedRoles);
    final effects = await NpcCampaignConsequences.accept(
      source: base.source, preview: review, originalArchive: base.archive,
      freshReviewedRoles: reviewedRoles, approvedDigest: approvedDigest,
      explicitlyConfirmedPrivateFiction: explicitlyConfirmedPrivateFiction);
    final next = ReviewedCampaignState._(
      base.source,
      effects.archiveFor(source: base.source, originalArchive: base.archive),
      ReviewedCampaignStage.gameplay, effects.effectCount, 0, false);
    await _verify(next, reviewedRoles);
    return next;
  }

  /// Explicitly permit games with no model-proposed item/fact changes.
  Future<ReviewedCampaignState> skipEffects({
    required ReviewedCampaignState base,
    required List<ReviewedHeroRole> reviewedRoles,
    required bool explicitlyConfirmedNoEffects,
  }) async {
    _stage(base, ReviewedCampaignStage.base);
    if (!explicitlyConfirmedNoEffects) {
      throw const FormatException('Не подтверждено отсутствие эффектов.');
    }
    await _verify(base, reviewedRoles);
    return ReviewedCampaignState._(
      base.source, base.archive, ReviewedCampaignStage.gameplay, 0, 0, false);
  }

  ReviewedBookwideNpcCampaign reviewNpc({
    required ReviewedCampaignState gameplay,
    required List<ReviewedHeroRole> reviewedRoles,
    required List<NpcCampaignDialogueDraft> drafts,
  }) {
    _stage(gameplay, ReviewedCampaignStage.gameplay);
    return BookwideNpcCampaignAuthoring.review(
      source: gameplay.source, verifiedBaseArchive: gameplay.archive,
      currentReviewedRoles: reviewedRoles, selectedDrafts: drafts);
  }

  Future<ReviewedCampaignState> acceptNpc({
    required ReviewedCampaignState gameplay,
    required List<ReviewedHeroRole> reviewedRoles,
    required ReviewedBookwideNpcCampaign review,
    required String approvedDigest,
    required bool explicitlyConfirmedPrivateFiction,
  }) async {
    _stage(gameplay, ReviewedCampaignStage.gameplay);
    await _verify(gameplay, reviewedRoles);
    if (review.shownReview['base_archive_sha256'] != gameplay.archiveSha256) {
      throw const FormatException('Диалоги относятся к другому миру.');
    }
    final npc = await BookwideNpcCampaignAuthoring.compile(
      source: gameplay.source, approval: review,
      freshReviewedRoles: reviewedRoles, approvedDigest: approvedDigest,
      explicitlyConfirmedPrivateFiction: explicitlyConfirmedPrivateFiction);
    final next = ReviewedCampaignState._(
        gameplay.source, npc.archive, ReviewedCampaignStage.dialogue,
        gameplay.effectsCount, npc.episodeCount, false);
    await _verify(next, reviewedRoles);
    return next;
  }

  /// No NPC is a supported game configuration, not a synthetic NPC.
  Future<ReviewedCampaignState> skipNpc({
    required ReviewedCampaignState gameplay,
    required List<ReviewedHeroRole> reviewedRoles,
    required bool explicitlyConfirmedNoNpcDialogues,
  }) async {
    _stage(gameplay, ReviewedCampaignStage.gameplay);
    if (!explicitlyConfirmedNoNpcDialogues) {
      throw const FormatException('Не подтверждено отсутствие NPC-реплик.');
    }
    await _verify(gameplay, reviewedRoles);
    return ReviewedCampaignState._(
      gameplay.source, gameplay.archive, ReviewedCampaignStage.dialogue,
      gameplay.effectsCount, 0, false);
  }

  Future<CampaignProseManifest> prepareNarration({
    required ReviewedCampaignState dialogue,
    required List<ReviewedHeroRole> reviewedRoles,
    required Future<void> Function() verifyCurrent,
  }) async {
    _stage(dialogue, ReviewedCampaignStage.dialogue);
    await _verify(dialogue, reviewedRoles);
    return const BookToRpgWorkflow().prepareCampaignNarration(
      source: dialogue.source, finalArchive: dialogue.archive,
      verifyCurrent: verifyCurrent);
  }

  Future<ReviewedCampaignState> _complete(
      ReviewedCampaignState dialogue, Uint8List archive,
      List<ReviewedHeroRole> roles, bool narrated) async {
    final done = ReviewedCampaignState._(
      dialogue.source, archive, ReviewedCampaignStage.complete,
      dialogue.effectsCount, dialogue.npcEpisodeCount, narrated);
    await _verify(done, roles);
    final world = _importer.inspect(done._archive);
    final proof = StoryCampaignCausalAudit.inspect(
      blueprint: world.blueprint, socialRulebook: world.npcSocialRulebook);
    if (!proof.playable || !proof.exhaustive) {
      throw const FormatException('Кампания не прошла причинный аудит.');
    }
    return done;
  }

  Future<ReviewedCampaignState> completeWithoutNarration({
    required ReviewedCampaignState dialogue,
    required List<ReviewedHeroRole> reviewedRoles,
    required bool explicitlyAcceptedExistingSceneText,
  }) async {
    _stage(dialogue, ReviewedCampaignStage.dialogue);
    if (!explicitlyAcceptedExistingSceneText) {
      throw const FormatException('Подтвердите существующий текст сцен.');
    }
    await _verify(dialogue, reviewedRoles);
    return _complete(dialogue, dialogue.archive, reviewedRoles, false);
  }

  Future<ReviewedCampaignState> completeWithNarration({
    required ReviewedCampaignState dialogue,
    required List<ReviewedHeroRole> reviewedRoles,
    required CampaignProseManifest manifest,
    required CampaignProseSession session,
    required Future<CampaignProseSession> Function() readLatest,
    required String approvedDigest,
    required bool fullTextReviewed,
    required bool privateFictionConfirmed,
  }) async {
    _stage(dialogue, ReviewedCampaignStage.dialogue);
    await _verify(dialogue, reviewedRoles);
    if (manifest.archiveSha256 != dialogue.archiveSha256 ||
        manifest.source.index.sourceFingerprint != dialogue.sourceFingerprint ||
        manifest.source.planDigest != dialogue.planDigest ||
        manifest.source.heroReviewDigest != dialogue.heroDigest) {
      throw const FormatException('Черновик для другой редакции игры.');
    }
    final reviewed = CampaignProseFinalizer.review(manifest, session);
    if (!fullTextReviewed || !privateFictionConfirmed ||
        approvedDigest != ReviewedCampaignProseWriter.digest(reviewed)) {
      throw const FormatException('Текст не подтверждён для этой игры.');
    }
    Future<void> guard() async {
      await manifest.verifyCurrent();
      await _verify(dialogue, reviewedRoles);
      final current = await readLatest();
      if (current.revision != session.revision ||
          current.recordHash != session.recordHash) {
        throw const FormatException('Черновик изменён в другом клиенте.');
      }
    }
    await guard();
    final archive = CampaignProseFinalizer.compile(
      verifiedArchive: manifest.originalArchive,
      sourceIndex: dialogue.source.index.toJson(),
      reviewJson: reviewed, approvedDigest: approvedDigest,
      fullTextReviewed: fullTextReviewed,
      privateFictionConfirmed: privateFictionConfirmed);
    await guard();
    return _complete(dialogue, archive, reviewedRoles, true);
  }
}
