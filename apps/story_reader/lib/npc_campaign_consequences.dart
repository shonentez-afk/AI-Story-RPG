import 'dart:convert';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'reviewed_gameplay_compiler.dart';
import 'reviewed_hero_role.dart';
import 'whole_book_npc_campaign.dart';
import 'whole_plan_gameplay_candidate_batch.dart';
import 'zai_source_locked_gameplay_candidates.dart';

String _planHash(WholeBookNpcSourcePlan source) =>
    sha256.convert(utf8.encode(source.plan.encode())).toString();

class NpcCampaignConsequencePreview {
  NpcCampaignConsequencePreview._({
    required this.gameplay, required this.planDigest,
    required this.heroDigest, required Uint8List baseArchive,
  }) : _baseArchive = Uint8List.fromList(baseArchive);
  final ReviewedGameplayApprovalPreview gameplay;
  final String planDigest, heroDigest;
  final Uint8List _baseArchive;
  String get approvalDigest => gameplay.approvalDigest;
  Map<String, dynamic> get shownReview => gameplay.shownReview;
  int get effectCount => (shownReview['effects'] as List).length;
  bool get literaryMeaningVerified => false;
}

/// Exact source/role/base binding. The variant is built before NPC authoring;
/// neither the base nor an installed campaign is modified by this service.
class NpcCampaignConsequences {
  NpcCampaignConsequences._({
    required Uint8List archive, required this.planDigest,
    required this.heroDigest, required this.originalArchiveSha256,
    required this.approvalDigest, required this.effectCount,
  }) : _archive = Uint8List.fromList(archive);
  final Uint8List _archive;
  final String planDigest, heroDigest, originalArchiveSha256, approvalDigest;
  final int effectCount;
  bool get isInstalled => false;
  bool get literaryCanonVerified => false;

  Uint8List archiveFor({
    required WholeBookNpcSourcePlan source,
    required Uint8List originalArchive,
  }) {
    if (source.planDigest != planDigest || _planHash(source) != planDigest ||
        source.heroReviewDigest != heroDigest ||
        sha256.convert(originalArchive).toString() != originalArchiveSha256) {
      throw const FormatException(
          'Предметы согласованы для другой роли или редакции сценария.');
    }
    return Uint8List.fromList(_archive);
  }

  static NpcCampaignConsequencePreview preview({
    required WholeBookNpcSourcePlan source,
    required Uint8List originalArchive,
    required List<ReviewedHeroRole> currentReviewedRoles,
    required WholePlanGameplayBatchManifest manifest,
    required List<GameplayCandidateDraft> proposals,
    required Map<String, String> selectedUserReviewNotes,
  }) {
    source.verifyCurrentHero(currentReviewedRoles);
    source.verifyArchiveHero(
        const RichPrivateBookworldImporter().inspect(originalArchive));
    if (_planHash(source) != source.planDigest ||
        manifest.plan.encode() != source.plan.encode()) {
      throw const FormatException('Изменён план последствий выбранного героя.');
    }
    final gameplay = ReviewedGameplayCompiler.previewAcrossBatches(
      currentRichBookworld: originalArchive,
      index: source.index, book: source.book, plan: source.plan,
      manifest: manifest, proposals: proposals,
      selectedUserReviewNotes: selectedUserReviewNotes,
    );
    return NpcCampaignConsequencePreview._(
      gameplay: gameplay, planDigest: source.planDigest,
      heroDigest: source.heroReviewDigest, baseArchive: originalArchive,
    );
  }

  static Future<NpcCampaignConsequences> accept({
    required WholeBookNpcSourcePlan source,
    required NpcCampaignConsequencePreview preview,
    required Uint8List originalArchive,
    required List<ReviewedHeroRole> freshReviewedRoles,
    required String approvedDigest,
    required bool explicitlyConfirmedPrivateFiction,
  }) async {
    if (!explicitlyConfirmedPrivateFiction ||
        approvedDigest != preview.approvalDigest ||
        source.planDigest != preview.planDigest ||
        _planHash(source) != preview.planDigest ||
        source.heroReviewDigest != preview.heroDigest ||
        sha256.convert(originalArchive).toString() !=
            preview.gameplay.baseArchiveSha256) {
      throw const FormatException(
          'Нужно отдельное согласие на показанные предметы и последствия.');
    }
    source.verifyCurrentHero(freshReviewedRoles);
    final base = const RichPrivateBookworldImporter().inspect(preview._baseArchive);
    source.verifyArchiveHero(base);
    final bytes = await ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: preview.gameplay, currentRichBookworld: preview._baseArchive,
      index: source.index, explicitlyConfirmedPrivateGameFiction: true,
      approvedReviewDigest: approvedDigest,
    );
    final world = const RichPrivateBookworldImporter().inspect(bytes);
    source.verifyArchiveHero(world);
    if (world.blueprint.actors.length != 1 ||
        !world.blueprint.actors.contains('player') ||
        world.npcSocialRulebook != null ||
        world.blueprint.scenes.keys.toSet().difference(
            base.blueprint.scenes.keys.toSet()).isNotEmpty ||
        base.blueprint.scenes.keys.toSet().difference(
            world.blueprint.scenes.keys.toSet()).isNotEmpty) {
      throw const FormatException('Последствия изменили личности или состав сцен.');
    }
    final originalProof = StoryCampaignCausalAudit.inspect(blueprint: base.blueprint);
    if (!originalProof.playable || !originalProof.exhaustive) {
      throw const FormatException('Исходная кампания не прошла полный обход.');
    }
    final combinedProof = StoryCampaignCausalAudit.inspect(
      blueprint: world.blueprint,
      requiredChoiceIds: originalProof.choiceWitnesses.keys,
    );
    if (!combinedProof.playable || !combinedProof.exhaustive) {
      // Fail closed, but report real replayable reasons rather than making
      // a missing action and a resource limit indistinguishable to authors.
      throw FormatException('Последствия не прошли причинную проверку: ' +
          canonicalJson({
            'status': combinedProof.status.name,
            'states': combinedProof.exploredStates,
            'exhaustive': combinedProof.exhaustive,
            'unproven_choices': combinedProof.unprovenRequiredChoiceIds,
            'unproven_endings': combinedProof.unprovenTerminalIds,
            'traps': [for (final trap in combinedProof.traps) {
              'scene': trap.sceneId,
              'path': trap.choiceIds,
              'reasons': trap.choiceLockReasons,
            }],
            'cycles': combinedProof.cycleCount,
          }));
    }
    return NpcCampaignConsequences._(
      archive: bytes, planDigest: source.planDigest,
      heroDigest: source.heroReviewDigest,
      originalArchiveSha256: base.archiveSha256,
      approvalDigest: approvedDigest, effectCount: preview.effectCount,
    );
  }
}
