import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'whole_story_literary_review.dart';
import 'whole_story_literary_summary.dart';

/// A source-/plan-SHA-locked receipt for a COMPLETE independent review that
/// found no actionable defects in the UNMODIFIED draft. This is NOT a claim
/// that the model proved book semantics or the literary CANON.
///
/// Unlike g2b's repaired-plan receipt, there is no change of graph here.
/// Uncovered source events and model uncertainty are deliberately retained
/// as explicit counts, and this receipt can authorize only a PRIVATE trial.
class WholeStoryLiteraryUnchangedApproval {
  WholeStoryLiteraryUnchangedApproval._({
    required this.manifest,
    required List<WholeLiteraryReviewReport> reports,
    required this.summaryDigest,
    required this.planSha256,
    required this.unresolvedWindows,
    required this.uncoveredSourceEvents,
  }) : reports = List.unmodifiable(reports);

  final WholeStoryLiteraryReviewManifest manifest;
  final List<WholeLiteraryReviewReport> reports;
  final String summaryDigest;
  final String planSha256;
  final int unresolvedWindows;
  final int uncoveredSourceEvents;

  bool get approvedForPrivateTrial => true;
  bool get provesBookCanon => false;
  bool get canDistributePublicly => false;
  bool get allBookEventsReviewed => uncoveredSourceEvents == 0;
  bool get meaningStillUncertain =>
      unresolvedWindows > 0 || uncoveredSourceEvents > 0;

  static WholeStoryLiteraryUnchangedApproval accept({
    required WholeStoryLiteraryReviewManifest manifest,
    required List<WholeLiteraryReviewReport> reports,
    required bool userReviewedAllReports,
    required bool explicitlyAcceptedPrivateFiction,
  }) {
    if (!userReviewedAllReports || !explicitlyAcceptedPrivateFiction) {
      throw const FormatException(
          'Нужно отдельно подтвердить изучение заключений и частную '
          'игровую выдумку. Автоматического подтверждения нет.');
    }
    final summary = WholeStoryLiterarySummary.compile(
        manifest: manifest, reports: reports);
    if (summary.totalFindings != 0 ||
        summary.revisions != 0 ||
        summary.crossWindowIssues.isNotEmpty ||
        summary.totalWindows <= 0 ||
        summary.totalTransitions <= 0) {
      throw const FormatException(
          'Замечания к исходному сценарию не устранены. '
          'Нельзя принять его без проверки или исправления.');
    }
    // "Insufficient evidence" can be accepted only as an explicitly
    // disclosed PRIVATE FICTIONAL trial, never a complete literary game.
    // A plan with no uncovered events is still not automatically CANON.
    final planSha = sha256.convert(
        utf8.encode(manifest.plan.encode())).toString();
    if (planSha != manifest.evidence.planSha256) {
      throw const FormatException(
          'Точная редакция сценарного плана изменилась.');
    }
    return WholeStoryLiteraryUnchangedApproval._(
      manifest: manifest,
      reports: reports,
      summaryDigest: summary.reportDigest,
      planSha256: planSha,
      unresolvedWindows: summary.insufficient,
      uncoveredSourceEvents: summary.uncoveredEvents,
    );
  }

  /// Compiler replays the complete report through the exact CURRENT index,
  /// BookModel and StoryPlan. A changed quote, scene, choice, edition or
  /// missing/forged report fails before installing any game.
  void verifyForCompiler({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
  }) {
    if (index.sourceFingerprint != manifest.index.sourceFingerprint ||
        book.sourceFingerprint != index.sourceFingerprint ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        book.title != index.title ||
        plan.title != book.title ||
        plan.encode() != manifest.plan.encode() ||
        planSha256 != sha256.convert(
            utf8.encode(plan.encode())).toString()) {
      throw const FormatException(
          'Литературное заключение относится к другой книге или версии игры.');
    }
    manifest.evidence.verifyUnchanged(
        index: index, book: book, plan: plan,
        claimEvidence: manifest.claimEvidence);
    final summary = WholeStoryLiterarySummary.compile(
        manifest: manifest, reports: reports);
    if (summary.reportDigest != summaryDigest ||
        summary.totalFindings != 0 ||
        summary.revisions != 0 ||
        summary.crossWindowIssues.isNotEmpty ||
        summary.insufficient != unresolvedWindows ||
        summary.uncoveredEvents != uncoveredSourceEvents) {
      throw const FormatException(
          'Литературная проверка неполна, изменена или содержит замечания.');
    }
  }
}
