import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'zai_source_locked_gameplay_candidates.dart';

/// Offline, deterministic, source-bound PLAYER reading memory proposal.
/// It NEVER claims the fictional protagonist knew a literary fact before
/// the player's explicit role-observe action. The only content remembered is
/// a verbatim span of text the player has elected to examine. The proposal
/// still needs a separate author review note and final exact-digest consent
/// through the EXISTING ReviewedGameplayCompiler.
class ReviewedHeroReadingCandidate {
  const ReviewedHeroReadingCandidate._();

  static bool hasEligibleChoice(SourceLockedGameplayContext context) =>
      context.choices.any((choice) =>
          choice.choiceId.endsWith('_hero_observe'));

  static GameplayCandidateDraft? fromContext({
    required BookSourceIndex index,
    required SourceLockedGameplayContext context,
  }) {
    if (context.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Память героя относится к другой книге.');
    }
    final choices = [
      for (final anchor in context.choices)
        if (anchor.choiceId.endsWith('_hero_observe')) anchor,
    ];
    if (choices.isEmpty) return null;
    if (choices.length != 1) {
      throw const FormatException(
          'Для локальной памяти требуется одно ролевое наблюдение.');
    }
    final choice = choices.single;
    final matching = [
      for (final e in context.excerpts)
        if (e.id == choice.sourceEventId) e,
    ];
    if (matching.length != 1) {
      throw const FormatException('Не найден проверенный отрывок героя.');
    }
    final excerpt = matching.single;
    excerpt.source.validate(index);
    // Keep the displayed knowledge a LITERAL substring, not a paraphrase
    // or unsupported model conclusion. Never cut a UTF-16 surrogate pair.
    final firstLine = excerpt.source.quote
        .split(RegExp(r'[\r\n]')).first.trim();
    final literal = String.fromCharCodes(firstLine.runes.take(110)).trim();
    if (literal.length < 2 || literal.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(literal)) {
      throw const FormatException('Нет безопасного дословного знания.');
    }
    final material = jsonEncode({
      'scope': 'reader_observed_literal_source_v1',
      'edition': index.sourceFingerprint,
      'event_id': excerpt.id,
      'choice_id': choice.choiceId,
      'quote': excerpt.source.quote,
    });
    final fingerprint = sha256.convert(utf8.encode(material)).toString();
    final candidate = GameplayCandidate(
      kind: 'fact',
      id: 'hero_read_' + fingerprint.substring(0, 20),
      label: literal,
      op: 'learn_fact',
      sceneId: choice.sceneId,
      choiceId: choice.choiceId,
      sourceEventId: choice.sourceEventId,
      uncertainty: 'Игровое знание только о прочитанных словах книги. '
          'Это не подтверждает знания литературного героя, '
          'правдивость реплики NPC или канон событий.',
    );
    return GameplayCandidateDraft(
      sourceFingerprint: context.sourceFingerprint,
      approvalDigest: context.approvalDigest,
      candidates: List.unmodifiable([candidate]),
    );
  }
}
