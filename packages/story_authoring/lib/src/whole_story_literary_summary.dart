import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'whole_story_literary_review.dart';

/// Read-only, deterministic cross-window diagnostic, never literary CANON.
class WholeStoryLiterarySummary {
  const WholeStoryLiterarySummary._({
    required this.manifestDigest,
    required this.reportDigest,
    required this.totalWindows,
    required this.totalTransitions,
    required this.totalFindings,
    required this.revisions,
    required this.insufficient,
    required this.uncoveredEvents,
    required this.crossWindowIssues,
    required this.findingsByKind,
  });

  static const format = 'ai_story_cross_window_literary_summary_m2h8g1c_v1';
  final String manifestDigest, reportDigest;
  final int totalWindows, totalTransitions, totalFindings;
  final int revisions, insufficient, uncoveredEvents;
  final List<Map<String, Object?>> crossWindowIssues;
  final Map<String, int> findingsByKind;

  bool get provesLiteraryCanon => false;
  bool get mayModifyBookWorld => false;
  bool get authorizesAutomaticRepair => false;
  bool get needsEditorialReview => totalFindings > 0 ||
      insufficient > 0 || crossWindowIssues.isNotEmpty || uncoveredEvents > 0;

  Map<String, Object?> toJson() => {
    'format': format,
    'status': 'UNVERIFIED_COMPLETE_AI_DIAGNOSTIC',
    'manifest_digest': manifestDigest,
    'report_digest': reportDigest,
    'total_windows': totalWindows,
    'total_transitions': totalTransitions,
    'total_findings': totalFindings,
    'windows_needing_revision': revisions,
    'windows_with_insufficient_evidence': insufficient,
    'uncovered_source_events': uncoveredEvents,
    'findings_by_kind': findingsByKind,
    'cross_window_issues': crossWindowIssues,
    'literary_canon_verified': false,
    'may_modify_bookworld': false,
    'may_repair_automatically': false,
  };

  /// Every saved report is reconstructed against its EXACT original window.
  /// Missing, extra, forged or obsolete reports reject the whole summary.
  static WholeStoryLiterarySummary compile({
    required WholeStoryLiteraryReviewManifest manifest,
    required List<WholeLiteraryReviewReport> reports,
  }) {
    manifest.verifyUnchanged();
    if (reports.length != manifest.totalWindows) {
      throw const FormatException('Нельзя собрать итог до завершения всех пакетов.');
    }
    final byKind = <String, int>{};
    final byChoice = <String, List<({int window, WholeLiteraryFinding finding})>>{};
    final allTransitions = <String>{};
    var findings = 0, revisions = 0, unknown = 0;
    for (var i = 0; i < reports.length; i++) {
      final window = manifest.windows[i];
      final report = WholeLiteraryReviewReport.fromJson(
          window, Map<String, dynamic>.from(reports[i].toJson()));
      if (report.verdict == WholeLiteraryVerdict.needsRevision) revisions++;
      if (report.verdict == WholeLiteraryVerdict.insufficientEvidence) unknown++;
      for (final step in window.transitions) {
        allTransitions.add(step['scene_id'].toString() + '/' +
            step['choice_id'].toString());
      }
      for (final f in report.findings) {
        findings++;
        byKind.update(f.kind.name, (n) => n + 1, ifAbsent: () => 1);
        final key = f.sceneId + '/' + f.choiceId + '/' + f.kind.name;
        byChoice.putIfAbsent(key, () => []).add((window: i, finding: f));
      }
    }
    final issues = <Map<String, Object?>>[];
    for (final entry in byChoice.entries) {
      final distinctWindows = entry.value.map((e) => e.window).toSet().toList()
        ..sort();
      if (distinctWindows.length < 2) continue;
      issues.add({
        'issue': 'CROSS_WINDOW_REVIEW_REQUIRED',
        'scene_choice_kind': entry.key,
        'windows': distinctWindows,
        'different_severity': entry.value.map(
            (e) => e.finding.severity).toSet().length > 1,
        'different_source_reference': entry.value.map(
            (e) => e.finding.sourceEventId).toSet().length > 1,
        'status': 'UNVERIFIED_AI_HYPOTHESES',
      });
    }
    issues.sort((a, b) => (a['scene_choice_kind'] as String)
        .compareTo(b['scene_choice_kind'] as String));
    final keys = byKind.keys.toList()..sort();
    final orderedCounts = <String, int>{
      for (final key in keys) key: byKind[key]!,
    };
    final payload = <String, Object?>{
      'manifest_digest': manifest.approvalDigest,
      'reports': [for (final report in reports) report.toJson()],
      'transition_count': allTransitions.length,
    };
    return WholeStoryLiterarySummary._(
      manifestDigest: manifest.approvalDigest,
      reportDigest: sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
      totalWindows: manifest.totalWindows,
      totalTransitions: manifest.totalTransitions,
      totalFindings: findings,
      revisions: revisions,
      insufficient: unknown,
      uncoveredEvents: manifest.notCoveredEvents,
      crossWindowIssues: List.unmodifiable(issues.map(
          (issue) => Map<String, Object?>.unmodifiable(issue))),
      findingsByKind: Map.unmodifiable(orderedCounts),
    );
  }
}
