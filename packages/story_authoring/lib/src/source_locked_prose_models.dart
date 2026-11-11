import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';

/// M2h7c1: source-locked prose preview for ONE game situation.
///
/// This is deliberately not a scene compiler. Exact source text can be
/// quoted, but a model-written interpretation is still GAME FICTION.
class SourceLockedProseContext {
  SourceLockedProseContext._(
      this.index, this.book, this.plan, this.situation, this.sourceEvent);

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final StorySituation situation;
  final NarrativeEvent? sourceEvent;

  static SourceLockedProseContext forSituation({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required String situationId,
  }) {
    if (!book.analysisComplete ||
        index.sourceFingerprint != book.sourceFingerprint ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        index.title != book.title || plan.title != book.title ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        !plan.validate(book).isStructurallySound) {
      throw const FormatException('Сцена относится к другой или '
          'неполностью проверенной редакции книги.');
    }
    final matches = plan.situations.where((s) => s.id == situationId).toList();
    if (matches.length != 1) {
      throw const FormatException('Ситуация не найдена в StoryPlan.');
    }
    final situation = matches.single;
    NarrativeEvent? event;
    if (situation.sourceEventId != null) {
      final matching = book.events.where(
          (e) => e.id == situation.sourceEventId).toList();
      if (matching.length != 1) {
        throw const FormatException('Непроверенный источник сцены.');
      }
      event = matching.single;
      event.source.validate(index);
      if (event.source.chapterIndex != situation.chapterIndex) {
        throw const FormatException('Сцена перенесена в чужую главу.');
      }
    }
    if (situation.route == StoryRoute.canonicalProposal && event == null) {
      throw const FormatException(
          'Предполагаемая исходная сцена не имеет исходной цитаты.');
    }
    return SourceLockedProseContext._(
        index, book, plan, situation, event);
  }

  /// Exactly what the user must be shown BEFORE consent. Private source
  /// text is never sent outside this per-situation payload.
  Map<String, Object> get consentPreview => {
    'scene_id': situation.id,
    'route': situation.route.name,
    'goal': situation.goal,
    'conflict': situation.conflict,
    if (sourceEvent != null)
      'source_excerpt': {
        'event_id': sourceEvent!.id,
        'quote': sourceEvent!.source.quote,
      },
    'allowed_choices': [
      for (final choice in situation.decisions)
        {
          'id': choice.id,
          'intent': choice.intent,
          'requires': choice.requires,
          'forbids': choice.forbids,
          'adds': choice.adds,
          'removes': choice.removes,
        },
    ],
    'narrative_status': 'GAME_FICTION_OR_UNVERIFIED_INTERPRETATION',
  };

  /// Includes the book's exact edition and the whole plan revision locally.
  /// The digest, edition fingerprint, title and author are NOT sent to Z.ai.
  String get approvalDigest =>
      sha256.convert(utf8.encode(jsonEncode({
        'format': 'ai_story_prose_scene_consent_m2h7c1_v1',
        'source_fingerprint': index.sourceFingerprint,
        'plan_sha256':
            sha256.convert(utf8.encode(plan.encode())).toString(),
        'preview': consentPreview,
      }))).toString();

  bool get hasLiteraryMeaningVerification => false;
  bool get mayPublish => false;
}

/// An untrusted model-written prose candidate. Its words never add/remove
/// flags or invent an NPC's knowledge in the game engine.
class SourceLockedProseDraft {
  const SourceLockedProseDraft({
    required this.sourceFingerprint,
    required this.situationId,
    required this.approvalDigest,
    required this.text,
    required this.uncertainty,
    required this.route,
  });

  final String sourceFingerprint, situationId, approvalDigest;
  final String text, uncertainty;
  final StoryRoute route;

  bool get isHumanReviewed => false;
  bool get hasVerifiedLiteraryMeaning => false;
  bool get canPublish => false;
  bool get canInstallDirectly => false;
  bool get canMutateCampaign => false;

  Map<String, Object> toDiagnosticJson() => {
    'format': 'ai_story_prose_draft_m2h7c1_v1',
    'scene_id': situationId,
    'route': route.name,
    'status': 'PROSE_DRAFT_REVIEW_REQUIRED',
    'quote_not_world_truth': true,
    'literary_meaning_verified': false,
    'can_install': false,
  };
}

