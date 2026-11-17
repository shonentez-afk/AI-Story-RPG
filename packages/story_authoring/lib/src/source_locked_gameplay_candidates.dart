import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';

/// One decision and exactly ONE existing source citation allowed for this
/// proposal. Nearby text and the decision's label are NOT literary evidence.
class GameplayChoiceAnchor {
  const GameplayChoiceAnchor({
    required this.sceneId,
    required this.choiceId,
    required this.sourceEventId,
    required this.intent,
  });

  final String sceneId, choiceId, sourceEventId, intent;

  Map<String, Object> toJson() => {
    'scene_id': sceneId,
    'choice_id': choiceId,
    'source_event_id': sourceEventId,
    'intent': intent,
  };
}

/// M2h8d1: exact, user-visible, bounded request payload. No model request
/// happens here and no original book, edition fingerprint, title or key is
/// uploaded automatically. In particular, a quoted noun is not proof that
/// the hero owns it or can use it.
class SourceLockedGameplayContext {
  SourceLockedGameplayContext._({
    required this.sourceFingerprint,
    required this.planSha256,
    required this.excerpts,
    required this.choices,
    required this.payloadJson,
    required this.approvalDigest,
  });

  static const format = 'ai_story_gameplay_candidates_m2h8d1_v1';
  /// Provider model bound into the exact user-approved request digest.
  static const defaultModelId = 'glm-4.7-flash';
  static const maxExcerpts = 6;
  static const maxChoices = 16;
  static const maxProposals = 6;
  static const maxSentBytes = 8 * 1024;

  final String sourceFingerprint, planSha256, approvalDigest;
  final List<NarrativeEvent> excerpts;
  final List<GameplayChoiceAnchor> choices;
  // Keep the precise consented bytes immutable, even if the UI mutates a
  // map returned by the public preview accessor.
  final String payloadJson;
  Map<String, Object> get consentPreview =>
      Map<String, Object>.from(jsonDecode(payloadJson) as Map);

  static SourceLockedGameplayContext forPlan({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required List<String> exactEventIds,
  }) {
    if (!book.analysisComplete ||
        index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        plan.title != index.title ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        !plan.validate(book).isStructurallySound) {
      throw const FormatException(
          'Нужна полностью проверенная редакция книги и её StoryPlan.');
    }
    if (exactEventIds.isEmpty ||
        exactEventIds.length > maxExcerpts ||
        exactEventIds.length != exactEventIds.toSet().length) {
      throw const FormatException(
          'Выберите от 1 до 6 разных проверенных отрывков.');
    }
    final byId = {for (final e in book.events) e.id: e};
    final selected = <NarrativeEvent>[];
    var previous = -1;
    for (final id in exactEventIds) {
      final e = byId[id];
      if (e == null || e.narrativePosition <= previous) {
        throw const FormatException(
            'Отрывки относятся к другой редакции или переставлены.');
      }
      e.source.validate(index);
      selected.add(e);
      previous = e.narrativePosition;
    }
    final selectedIds = exactEventIds.toSet();
    final anchors = <GameplayChoiceAnchor>[];
    for (final scene in plan.situations) {
      for (final choice in scene.decisions) {
        // A player who PASSES a source encounter cannot receive a new
        // item/fact merely because the enclosing scene has a quote. Only
        // the explicit "examine_source" decision is eligible for a
        // separately reviewed source-locked gameplay effect.
        if (scene.id.contains('_source_encounter') &&
            choice.id.contains('_pass_source')) continue;
        // A decision's explicit source takes precedence over its parent
        // scene. A fictional decision is never silently relabeled CANON.
        final sourceId = choice.sourceEventId ?? scene.sourceEventId;
        if (sourceId != null && selectedIds.contains(sourceId)) {
          anchors.add(GameplayChoiceAnchor(
            sceneId: scene.id,
            choiceId: choice.id,
            sourceEventId: sourceId,
            intent: choice.intent,
          ));
        }
      }
    }
    if (anchors.isEmpty || anchors.length > maxChoices) {
      throw const FormatException(
          'Нужны связанные с цитатами игровые решения (до 16).');
    }
    final payload = <String, Object>{
      'review_kind': 'UNVERIFIED_TYPED_GAMEPLAY_SUGGESTIONS_ONLY',
      'source_excerpts': [
        for (final e in selected)
          {
            'event_id': e.id,
            'chapter_index': e.source.chapterIndex,
            'quote': e.source.quote,
          },
      ],
      'allowed_choices': [for (final anchor in anchors) anchor.toJson()],
      'max_proposals': maxProposals,
      'allowed_ops': ['grant_item', 'consume_item', 'learn_fact'],
      'literary_meaning': 'NOT_ATTESTED',
      'item_ownership': 'NOT_PROVEN_BY_WORD_MATCH',
    };
    final payloadJson = jsonEncode(payload);
    if (utf8.encode(payloadJson).length > maxSentBytes) {
      throw const FormatException(
          'Фрагменты и решения превышают размер одного запроса.');
    }
    final planSha = sha256.convert(utf8.encode(plan.encode())).toString();
    final digest = sha256.convert(utf8.encode(jsonEncode({
      'format': format,
      'edition': index.sourceFingerprint,
      'plan_sha256': planSha,
      'shown_payload': payload,
      'model': defaultModelId,
    }))).toString();
    return SourceLockedGameplayContext._(
      sourceFingerprint: index.sourceFingerprint,
      planSha256: planSha,
      excerpts: List.unmodifiable(selected),
      choices: List.unmodifiable(anchors),
      payloadJson: payloadJson,
      approvalDigest: digest,
    );
  }

  bool get independentlyConfirmsOwnership => false;
  bool get independentlyConfirmsKnowledge => false;
  bool get canModifyBookworld => false;
}

/// A syntactically checked AI SUGGESTION. It has no runtime rights and cannot
/// be handed to the BookWorld compiler as an accepted gameplay effect.
class GameplayCandidate {
  const GameplayCandidate({
    required this.kind,
    required this.id,
    required this.label,
    required this.op,
    required this.sceneId,
    required this.choiceId,
    required this.sourceEventId,
    required this.uncertainty,
  });

  final String kind, id, label, op, sceneId, choiceId, sourceEventId;
  final String uncertainty;
  bool get isReviewed => false;
  bool get mayChangeGameState => false;
  bool get isLiteraryCanon => false;
}

class GameplayCandidateDraft {
  const GameplayCandidateDraft({
    required this.sourceFingerprint,
    required this.approvalDigest,
    required this.candidates,
  });

  final String sourceFingerprint, approvalDigest;
  final List<GameplayCandidate> candidates;
  bool get hasCandidate => candidates.isNotEmpty;
  bool get isAcceptedIntoGame => false;
  bool get mayChangeGameState => false;
  bool get provesLiteraryMeaning => false;
}

