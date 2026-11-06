import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'story_plan.dart';
import 'story_plan_bounded_repair.dart';
import 'story_plan_causal_audit.dart';
import 'whole_story_literary_evidence_manifest.dart';
import 'whole_story_literary_review.dart';
import 'whole_story_literary_summary.dart';

/// A read-only repair proposal. A repaired StoryPlan is still a DRAFT,
/// not a BookWorld, not a literary CANON and not a SQLite campaign.
class WholeStoryLiteraryRepairResult {
  const WholeStoryLiteraryRepairResult({
    required this.formal,
    required this.previousReportDigest,
    required this.originalPlanSha,
    required this.revisedPlanSha,
    required this.findingKeys,
    required this.newReviewManifest,
  });

  final StoryRepairResult formal;
  final String previousReportDigest, originalPlanSha, revisedPlanSha;
  final List<String> findingKeys;
  final WholeStoryLiteraryReviewManifest? newReviewManifest;

  StoryPlan get draft => formal.draft;
  bool get changed => formal.appliedChanges.isNotEmpty;
  bool get requiresFreshLiteraryConsent => changed;
  bool get oldLiteraryApprovalRevoked => changed;
  bool get provesBookCanon => false;
  bool get mayChangeGameOrSave => false;
  bool get canPublish => false;
  bool get isReadyToPlay => false;

  Map<String, Object?> toJson() => {
    'status': changed ? 'NEW_DRAFT_REVIEW_REQUIRED'
        : 'NO_SAFE_LOCAL_CORRECTION',
    'previous_report_digest': previousReportDigest,
    'previous_plan_sha': originalPlanSha,
    'draft_plan_sha': revisedPlanSha,
    'new_review_manifest_digest': newReviewManifest?.approvalDigest,
    'requires_new_literary_consent': requiresFreshLiteraryConsent,
    'unresolved_ai_findings': findingKeys,
    'changes': [
      for (final change in formal.appliedChanges) {
        'rule_id': change.invariantId,
        'choice_id': change.decisionId,
        'new_requires': change.addedRequires,
        'new_forbids': change.addedForbids,
      },
    ],
    'blockers': formal.blockers,
    'is_canon': false,
    'may_change_game_or_save': false,
  };
}

/// M2h8g2a. Reuses the EXISTING proven shortest-path causal auditor and
/// StoryPlanBoundedRepair instead of making a second game rules engine.
/// Only approved pre-existing causal rules may be enforced automatically.
/// The model's problem text NEVER becomes executable state or literary fact.
class WholeStoryLiteraryBoundedRepair {
  const WholeStoryLiteraryBoundedRepair._();

  static String _key(WholeLiteraryFinding f) =>
      f.sceneId + '/' + f.choiceId + '/' + f.kind.name + '/' +
      (f.sourceEventId ?? 'UNKNOWN');

  static WholeStoryLiteraryRepairResult propose({
    required WholeStoryLiteraryReviewManifest manifest,
    required List<WholeLiteraryReviewReport> reports,
    required String expectedReportDigest,
    required StoryCausalContract approvedRules,
    required bool explicitRuleReview,
    int maxPatches = 3,
  }) {
    // Revalidate EVERY report and the exact edition and plan before editing.
    final summary = WholeStoryLiterarySummary.compile(
        manifest: manifest, reports: reports);
    if (!explicitRuleReview ||
        expectedReportDigest != summary.reportDigest) {
      throw const FormatException(
          'Нужно подтвердить правила для этой точной литературной рецензии.');
    }
    final findings = [
      for (final report in reports)
        for (final finding in report.findings) finding,
    ];
    final relevant = <String, Set<WholeLiteraryFindingKind>>{};
    for (final f in findings) {
      relevant.putIfAbsent(f.choiceId, () => <WholeLiteraryFindingKind>{})
          .add(f.kind);
    }
    if (approvedRules.decisionInvariants.isEmpty &&
        approvedRules.knowledgeGates.isEmpty) {
      throw const FormatException('Нет подтверждённых причинных правил.');
    }
    const causalKinds = {
      WholeLiteraryFindingKind.promise,
      WholeLiteraryFindingKind.actorKnowledge,
      WholeLiteraryFindingKind.causalLink,
      WholeLiteraryFindingKind.routeState,
    };
    // Each rule needs an actual anchored finding, not a generic model guess.
    for (final rule in approvedRules.decisionInvariants) {
      if (!(relevant[rule.decisionId] ?? <WholeLiteraryFindingKind>{})
          .any(causalKinds.contains)) {
        throw const FormatException(
            'Причинное правило не связано с замечанием исходной рецензии.');
      }
    }
    for (final rule in approvedRules.knowledgeGates) {
      if (rule.protectedDecisionIds.isEmpty ||
          rule.protectedDecisionIds.any((id) =>
              !(relevant[id] ?? <WholeLiteraryFindingKind>{})
                  .contains(WholeLiteraryFindingKind.actorKnowledge))) {
        throw const FormatException(
            'Правило знаний не связано с конкретным замечанием об NPC.');
      }
    }
    final original = manifest.plan.encode();
    final formal = StoryPlanBoundedRepair.attempt(
      book: manifest.book, plan: manifest.plan,
      contract: approvedRules, maxPatches: maxPatches,
    );
    if (manifest.plan.encode() != original) {
      throw const FormatException('Исходный StoryPlan был изменён.');
    }
    WholeStoryLiteraryReviewManifest? newReview;
    if (formal.appliedChanges.isNotEmpty) {
      // Replay ALL reachable gameplay paths and rebuild approval digests.
      final evidence = WholeStoryLiteraryEvidenceManifest.build(
        index: manifest.index, book: manifest.book, plan: formal.draft,
        claimEvidence: manifest.claimEvidence,
      );
      newReview = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: manifest.index, book: manifest.book, plan: formal.draft,
        evidence: evidence, claimEvidence: manifest.claimEvidence,
        maxNewRequestsPerRun: manifest.maxNewRequestsPerRun,
      );
      if (newReview.approvalDigest == manifest.approvalDigest ||
          evidence.planSha256 == manifest.evidence.planSha256) {
        throw const FormatException('Результат не изменил редакцию сценария.');
      }
    }
    final keys = findings.map(_key).toSet().toList()..sort();
    return WholeStoryLiteraryRepairResult(
      formal: formal,
      previousReportDigest: summary.reportDigest,
      originalPlanSha: sha256.convert(utf8.encode(original)).toString(),
      revisedPlanSha:
          sha256.convert(utf8.encode(formal.draft.encode())).toString(),
      findingKeys: List.unmodifiable(keys),
      newReviewManifest: newReview,
    );
  }
}
