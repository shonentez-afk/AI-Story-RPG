import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'source_locked_prose_models.dart';

/// M2h7c3. Explicit, session-local human acceptance of ONE private,
/// source-locked AI prose draft. The approval cannot certify book-world
/// causality, narrator reliability, NPC knowledge, ownership or chronology.
class ReviewedProseSceneApproval {
  ReviewedProseSceneApproval._({
    required this.sourceFingerprint,
    required this.situationId,
    required this.contextDigest,
    required this.proseSha256,
    required this.prose,
    required this.route,
  });

  final String sourceFingerprint;
  final String situationId;
  final String contextDigest;
  final String proseSha256;
  final String prose;
  final StoryRoute route;

  static final RegExp _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static void _validateProse(String prose, String uncertainty) {
    if (prose.trim() != prose ||
        prose.length < 80 || prose.length > 2600 ||
        _controls.hasMatch(prose) ||
        uncertainty.trim() != uncertainty ||
        uncertainty.length < 10 || uncertainty.length > 300 ||
        _controls.hasMatch(uncertainty)) {
      throw const FormatException(
          'Невозможно принять повреждённый художественный текст.');
    }
  }

  /// Caller must obtain BOTH confirmations through a real user action.
  /// Generating or restoring a draft alone never produces approval.
  static ReviewedProseSceneApproval accept({
    required SourceLockedProseContext context,
    required SourceLockedProseDraft draft,
    required bool fullTextReviewedByUser,
    required bool privateFictionAcknowledged,
  }) {
    if (!fullTextReviewedByUser || !privateFictionAcknowledged) {
      throw const FormatException(
          'Художественный текст и его вымышленный статус не подтверждены.');
    }
    if (draft.situationId != context.situation.id ||
        draft.sourceFingerprint != context.index.sourceFingerprint ||
        draft.approvalDigest != context.approvalDigest ||
        draft.route != context.situation.route) {
      throw const FormatException(
          'Черновик относится к другой сцене, книге или версии сценария.');
    }
    _validateProse(draft.text, draft.uncertainty);
    return ReviewedProseSceneApproval._(
      sourceFingerprint: draft.sourceFingerprint,
      situationId: draft.situationId,
      contextDigest: draft.approvalDigest,
      proseSha256: sha256.convert(utf8.encode(draft.text)).toString(),
      prose: draft.text,
      route: draft.route,
    );
  }

  bool get establishesBookWorldTruth => false;
  bool get canPublishAsCanon => false;
  bool get changesGameRules => false;
}

/// Checks the exact approved payload against the FINAL scenario at the
/// point of compilation. Existing flags, choices and source refs stay the
/// authority; this overlay can change only the visible scene description.
class ReviewedProseSceneOverlay {
  const ReviewedProseSceneOverlay._();

  static Map<String, String> validate({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan finalPlan,
    required List<ReviewedProseSceneApproval> approvals,
  }) {
    if (approvals.isEmpty) return const {};
    if (approvals.length > 64 ||
        index.sourceFingerprint != book.sourceFingerprint ||
        finalPlan.sourceFingerprint != index.sourceFingerprint ||
        finalPlan.title != book.title ||
        !finalPlan.validate(book).isStructurallySound) {
      throw const FormatException(
          'Художественные сцены относятся к чужому игровому плану.');
    }
    final result = <String, String>{};
    for (final approval in approvals) {
      if (result.containsKey(approval.situationId)) {
        throw const FormatException(
            'Повторное или противоречивое подтверждение одной сцены.');
      }
      final context = SourceLockedProseContext.forSituation(
        index: index,
        book: book,
        plan: finalPlan,
        situationId: approval.situationId,
      );
      if (approval.sourceFingerprint != context.index.sourceFingerprint ||
          approval.contextDigest != context.approvalDigest ||
          approval.route != context.situation.route ||
          approval.proseSha256 !=
              sha256.convert(utf8.encode(approval.prose)).toString()) {
        throw const FormatException(
            'Отменено согласие: редакция, правила, контекст '
            'или литературный текст сцены изменились.');
      }
      ReviewedProseSceneApproval._validateProse(
          approval.prose, 'Вымышленная адаптация, не проверенный канон.');
      result[approval.situationId] = approval.prose;
    }
    return Map.unmodifiable(result);
  }
}
