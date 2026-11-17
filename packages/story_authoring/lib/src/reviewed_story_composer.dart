import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'private_adaptation_preflight.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

/// A deliberately small, HUMAN-authored, source-bound CLASSIC scenario.
/// No model creates source truth and the two user-selected assertions must
/// have been confirmed both as exact passages AND as editorial canon candidates.
/// Full-novel automation and character/alias reconciliation remain a later
/// explicit review stage.
class ReviewedStoryComposer {
  const ReviewedStoryComposer._();

  static IntermediateStoryBlueprint compose({
    required BookSourceIndex index,
    required SourceEvidenceGraph evidence,
    required SourceSemanticCatalog catalog,
    required SemanticEditorialReviewSession editorial,
    required String openingAssertionId,
    required String endingAssertionId,
    required String openingText,
    required String endingText,
    required String alternateEndingText,
    required String followBookChoice,
    required String changeFateChoice,
  }) {
    if (!editorial.matches(index, catalog) ||
        openingAssertionId == endingAssertionId ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16) {
      throw const FormatException(
          'Не готовы исходные главы или редакторские решения');
    }
    final byClaim = {for (final a in catalog.assertions) a.id: a};
    final byEvidence = {for (final e in evidence.records) e.id: e};
    int confirmedChapter(String claimId) {
      final claim = byClaim[claimId];
      if (claim == null ||
          (claim.kind != SemanticAssertionKind.event &&
              claim.kind != SemanticAssertionKind.fact) ||
          editorial.verdicts[claimId] !=
              SemanticEditorialVerdict.canonCandidate ||
          claim.evidenceIds.isEmpty) {
        throw const FormatException(
            'Для сцены нужен выбранный подтверждённый факт книги');
      }
      var latest = 0;
      for (final id in claim.evidenceIds) {
        final source = byEvidence[id];
        if (source == null ||
            source.status != EvidenceStatus.confirmed ||
            source.spoilerGate != EvidenceSpoilerGate.chapter ||
            source.visibleAfterChapter != source.chapterIndex) {
          throw const FormatException(
              'Цитата ещё не подтверждена или содержит будущий спойлер');
        }
        source.validate(index);
        if (source.chapterIndex > latest) latest = source.chapterIndex;
      }
      return latest;
    }

    final openingChapter = confirmedChapter(openingAssertionId);
    final endingChapter = confirmedChapter(endingAssertionId);
    if (endingChapter < openingChapter) {
      throw const FormatException(
          'Финальная сцена не может предшествовать началу');
    }
    for (final value in [
      openingText, endingText, alternateEndingText,
      followBookChoice, changeFateChoice,
    ]) {
      if (value.trim().isEmpty || value.length > 6000 ||
          value.contains('\u0000')) {
        throw const FormatException('Некорректный текст игровой сцены');
      }
    }
    if (followBookChoice.length > 300 || changeFateChoice.length > 300) {
      throw const FormatException('Слишком длинная надпись действия');
    }
    final draft = IntermediateStoryBlueprint(
      sourceFingerprint: index.sourceFingerprint,
      title: index.title,
      entrySceneId: 'entry',
      rights: PreparationRights.privateUse,
      flags: const [],
      initialFlags: const [],
      scenes: [
        DraftScene(
          id: 'entry', chapterIndex: openingChapter,
          text: openingText.trim(),
          origin: DraftSceneOrigin.sourcePassage,
          assertionIds: [openingAssertionId],
          terminal: false,
          choices: [
            DraftChoice(id: 'follow_book',
                label: followBookChoice.trim(), nextSceneId: 'canon_end'),
            DraftChoice(id: 'change_fate',
                label: changeFateChoice.trim(), nextSceneId: 'alternate_end'),
          ],
        ),
        DraftScene(
          id: 'canon_end', chapterIndex: endingChapter,
          text: endingText.trim(),
          origin: DraftSceneOrigin.sourcePassage,
          assertionIds: [endingAssertionId],
          terminal: true, choices: const [],
        ),
        DraftScene(
          id: 'alternate_end', chapterIndex: openingChapter,
          text: alternateEndingText.trim(),
          origin: DraftSceneOrigin.explicitAdaptation,
          assertionIds: const [],
          terminal: true, choices: const [],
        ),
      ],
    );
    final acceptance = PrivateAdaptationPreflight.evaluate(
        index, evidence, catalog, editorial, draft);
    if (!acceptance.isStructurallyReady) {
      throw FormatException(
          'Сценарий не прошёл проверку: ' +
          acceptance.userFacingBlockers.join('; '));
    }
    return draft;
  }
}
