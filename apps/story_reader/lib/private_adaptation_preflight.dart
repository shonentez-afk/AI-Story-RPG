import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

enum AdaptationGateIssue {
  rightsUnknown,
  noSourceScenes,
  noAlternativeScenes,
  unreviewedSourceClaim,
  disputedOrRejectedClaim,
  unconfirmedSourcePassage,
  futureSourceDisclosure,
  missingEditorialCatalog,
  productionBookworldNotImplemented,
}

/// M2d acceptance preflight. This does not build a ZIP and cannot weaken
/// original_demo v1 importer. A passed human review is still NOT independent
/// evidence of an event's objective truth, and no publisher rights are proven.
class PrivateAdaptationAcceptance {
  const PrivateAdaptationAcceptance({
    required this.causal,
    required this.issues,
    required this.reviewedSourceScenes,
    required this.explicitAdaptationScenes,
    required this.provenanceLinks,
  });

  final CausalPreflight causal;
  final List<AdaptationGateIssue> issues;
  final int reviewedSourceScenes;
  final int explicitAdaptationScenes;
  final int provenanceLinks;

  /// Plain Russian reasons that remain useful in the preparation report.
  /// A structural check passing never means this user book is playable.
  List<String> get userFacingBlockers => List.unmodifiable([
    for (final issue in issues)
      switch (issue) {
        AdaptationGateIssue.rightsUnknown =>
          'Не указан статус прав на личную адаптацию книги.',
        AdaptationGateIssue.noSourceScenes =>
          'Нет ни одной сцены с проверенной ссылкой на исходную книгу.',
        AdaptationGateIssue.noAlternativeScenes =>
          'Не создана отдельная альтернативная игровая сцена.',
        AdaptationGateIssue.unreviewedSourceClaim =>
          'Сцена использует ещё не проверенное утверждение из книги.',
        AdaptationGateIssue.disputedOrRejectedClaim =>
          'Сцена использует отклонённое или спорное утверждение.',
        AdaptationGateIssue.unconfirmedSourcePassage =>
          'Не подтверждено точное место цитаты в оригинале.',
        AdaptationGateIssue.futureSourceDisclosure =>
          'Сцена раскрывает сведения из будущей главы.',
        AdaptationGateIssue.missingEditorialCatalog =>
          'Решения редактора относятся к другой редакции книги.',
        AdaptationGateIssue.productionBookworldNotImplemented =>
          'Пакет этой книги ещё не создан и не проверен.',
      },
    ...causal.blockers,
  ]);

  bool get isStructurallyReady =>
      causal.isCausallyComplete &&
      issues.every((v) =>
          v == AdaptationGateIssue.productionBookworldNotImplemented);
  bool get canCompilePlayableBookworld => false;
  bool get canDistributePublicly => false;
  bool get canSendToCloud => false;
}

class PrivateAdaptationPreflight {
  const PrivateAdaptationPreflight._();

  static PrivateAdaptationAcceptance evaluate(
    BookSourceIndex index,
    SourceEvidenceGraph evidence,
    SourceSemanticCatalog catalog,
    SemanticEditorialReviewSession editorial,
    IntermediateStoryBlueprint draft,
  ) {
    if (index.sourceFingerprint != evidence.sourceFingerprint ||
        index.sourceFingerprint != catalog.sourceFingerprint ||
        index.sourceFingerprint != draft.sourceFingerprint) {
      throw const FormatException('Сценарий относится к другой книге');
    }
    final causal = draft.validate(index, evidence, catalog);
    final issues = <AdaptationGateIssue>{
      AdaptationGateIssue.productionBookworldNotImplemented,
    };
    if (draft.rights == PreparationRights.unknown) {
      issues.add(AdaptationGateIssue.rightsUnknown);
    }
    if (!editorial.matches(index, catalog)) {
      issues.add(AdaptationGateIssue.missingEditorialCatalog);
    }
    final byId = {for (final a in catalog.assertions) a.id: a};
    final byEvidence = {for (final e in evidence.records) e.id: e};

    var sourceCount = 0;
    var adaptationCount = 0;
    var references = 0;
    for (final scene in draft.scenes) {
      if (scene.origin == DraftSceneOrigin.explicitAdaptation) {
        adaptationCount++;
        continue;
      }
      sourceCount++;
      if (scene.assertionIds.isEmpty) {
        issues.add(AdaptationGateIssue.unreviewedSourceClaim);
      }
      for (final id in scene.assertionIds) {
        final claim = byId[id];
        if (claim == null) {
          throw const FormatException('Невозможное утверждение в сценарии');
        }
        final verdict = editorial.verdicts[id];
        if (verdict == null ||
            verdict == SemanticEditorialVerdict.passageOnly) {
          issues.add(AdaptationGateIssue.unreviewedSourceClaim);
        } else if (verdict != SemanticEditorialVerdict.canonCandidate) {
          issues.add(AdaptationGateIssue.disputedOrRejectedClaim);
        }
        for (final evidenceId in claim.evidenceIds) {
          final source = byEvidence[evidenceId];
          if (source == null) {
            throw const FormatException('Ссылка на отсутствующую цитату');
          }
          source.validate(index);
          references++;
          if (source.status != EvidenceStatus.confirmed) {
            issues.add(AdaptationGateIssue.unconfirmedSourcePassage);
          }
          if (source.visibleAfterChapter > scene.chapterIndex) {
            issues.add(AdaptationGateIssue.futureSourceDisclosure);
          }
        }
      }
    }
    if (sourceCount == 0) {
      issues.add(AdaptationGateIssue.noSourceScenes);
    }
    if (adaptationCount == 0) {
      issues.add(AdaptationGateIssue.noAlternativeScenes);
    }
    return PrivateAdaptationAcceptance(
      causal: causal,
      issues: List.unmodifiable(issues),
      reviewedSourceScenes: sourceCount,
      explicitAdaptationScenes: adaptationCount,
      provenanceLinks: references,
    );
  }
}
