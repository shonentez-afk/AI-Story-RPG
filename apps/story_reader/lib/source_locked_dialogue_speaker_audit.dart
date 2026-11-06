import 'package:bookworld_format/bookworld_format.dart';

import 'narrative_book_model.dart';
import 'npc_editorial_notebook.dart';

/// Source occurrence is NOT a statement that an NPC said the words or knew
/// the fact. Keep these categories separate from the game-world truth layer.
enum DialogueSpeakerEvidenceStatus {
  noMatchingSourceMention,
  ambiguousSameName,
  firstMentionAfterScene,
  sourceMentionIdentityUnresolved,
  sourceMentionGroupReviewed,
}

class DialogueSpeakerEvidence {
  const DialogueSpeakerEvidence({
    required this.speaker,
    required this.status,
    required this.dossierIds,
    required this.firstSourceChapter,
  });

  final String speaker;
  final DialogueSpeakerEvidenceStatus status;

  /// Stable source-only mention groups, never world actor IDs.
  final List<String> dossierIds;
  final int? firstSourceChapter;

  bool get provesSpokenWords => false;
  bool get provesNpcKnowledge => false;
  bool get provesBookCanon => false;

  String get description {
    switch (status) {
      case DialogueSpeakerEvidenceStatus.noMatchingSourceMention:
        return 'В проверенных карточках книги это имя не найдено. '
            'Реплика остаётся игровой выдумкой.';
      case DialogueSpeakerEvidenceStatus.ambiguousSameName:
        return 'Одинаковое имя относится к нескольким группам '
            'упоминаний. Личность говорящего не установлена.';
      case DialogueSpeakerEvidenceStatus.firstMentionAfterScene:
        return 'Первое упоминание имени найдено только в более '
            'поздней главе. Возможен преждевременный спойлер.';
      case DialogueSpeakerEvidenceStatus.sourceMentionIdentityUnresolved:
        return 'Имя упоминалось ранее, но тождественность персонажа '
            'не подтверждена. Знания и слова не доказаны.';
      case DialogueSpeakerEvidenceStatus.sourceMentionGroupReviewed:
        return 'Упоминания имени объединены проверенными решениями, '
            'но это всё ещё не доказательство сказанных слов или знаний.';
    }
  }
}

class SourceLockedDialogueSpeakerAudit {
  const SourceLockedDialogueSpeakerAudit._(this.speakers);

  final List<DialogueSpeakerEvidence> speakers;

  bool get hasStructuredDialogue => speakers.isNotEmpty;
  bool get hasLaterOnlyNames => speakers.any((e) =>
      e.status == DialogueSpeakerEvidenceStatus.firstMentionAfterScene);
  bool get allSpeakersProven => false;
  bool get knowsSourceFacts => false;
  bool get changesGameRules => false;
  bool get requiresNetwork => false;

  /// Resolve already-reviewed source-only names to persisted private NPC IDs.
  /// No line of dialogue, book claim, or NPC knowledge is thereby approved.
  /// All inputs must belong to one EXACT book revision. Ambiguous names,
  /// unresolved identity and future-only source appearances stay unbound.
  Map<String, String> bindReviewedCharacterIds({
    required NarrativeBookModel book,
    required NpcEditorialNotebook notebook,
  }) {
    if (notebook.sourceFingerprint != book.sourceFingerprint) {
      throw const FormatException(
          'Нельзя привязать диалог к карточкам другой редакции книги');
    }
    final groups = {
      for (final character in book.characters)
        character.mentionGroupId: character,
    };
    if (groups.length != book.characters.length) {
      throw const FormatException('Повторные группы персонажей книги');
    }
    final profiles = {
      for (final profile in notebook.profiles) profile.dossierId: profile,
    };
    if (profiles.length != notebook.profiles.length) {
      throw const FormatException('Дубли карточек редактора NPC');
    }
    final bindings = <String, String>{};
    final ownersById = <String, String>{};
    for (final evidence in speakers) {
      if (evidence.status !=
              DialogueSpeakerEvidenceStatus.sourceMentionGroupReviewed ||
          evidence.dossierIds.length != 1) continue;
      final dossierId = evidence.dossierIds.single;
      final source = groups[dossierId];
      final profile = profiles[dossierId];
      if (source == null || profile?.card == null ||
          !source.identityHintsResolved ||
          source.firstChapter > (evidence.firstSourceChapter ?? -1)) {
        continue;
      }
      final mentions = profile!.mentionIds;
      // Changing SAME/DIFFERENT group decisions must invalidate this binding.
      if (mentions.length != source.citationIds.length ||
          mentions.toSet().length != mentions.length ||
          mentions.toSet().difference(source.citationIds.toSet()).isNotEmpty) {
        continue;
      }
      profile.card!.validate();
      final characterId = profile.characterId!;
      final previousOwner = ownersById.putIfAbsent(
          characterId, () => dossierId);
      if (previousOwner != dossierId) {
        throw const FormatException(
            'Один character_id принадлежит разным персонажам');
      }
      bindings[evidence.speaker] = characterId;
    }
    return Map.unmodifiable(bindings);
  }

  /// Exact book character groups are optional: most full-book drafts still
  /// have zero reviewed characters. NEVER guess identity from prose or
  /// matching labels alone and never promote inferred NPC knowledge.
  static SourceLockedDialogueSpeakerAudit inspect({
    required String approvedSceneText,
    required int sceneChapterIndex,
    required List<NarrativeCharacter> sourceCharacters,
  }) {
    if (sceneChapterIndex < 0) {
      throw const FormatException('Отрицательный номер главы сценария.');
    }
    final turns = RichSceneDialogue.parse(approvedSceneText);
    if (turns == null) {
      return const SourceLockedDialogueSpeakerAudit._([]);
    }
    final names = <String>[];
    for (final turn in turns) {
      final label = turn.speaker;
      if (label != null && !names.contains(label)) names.add(label);
    }
    final result = <DialogueSpeakerEvidence>[];
    for (final name in names) {
      // Case-insensitive comparison is only a search HINT. Distinct
      // source groups never merge just because they share this label.
      final key = _normal(name);
      final matches = sourceCharacters.where((c) =>
          c.labels.any((label) => _normal(label) == key)).toList();
      final groups = <String, NarrativeCharacter>{
        for (final match in matches) match.mentionGroupId: match,
      };
      final unique = groups.values.toList()
        ..sort((a, b) => a.mentionGroupId.compareTo(b.mentionGroupId));
      final firstChapter = unique.isEmpty ? null
          : unique.map((c) => c.firstChapter)
              .reduce((a, b) => a < b ? a : b);
      DialogueSpeakerEvidenceStatus status;
      if (unique.isEmpty) {
        status = DialogueSpeakerEvidenceStatus.noMatchingSourceMention;
      } else if (unique.length > 1) {
        status = DialogueSpeakerEvidenceStatus.ambiguousSameName;
      } else if (unique.single.firstChapter > sceneChapterIndex) {
        status = DialogueSpeakerEvidenceStatus.firstMentionAfterScene;
      } else if (!unique.single.identityHintsResolved) {
        status = DialogueSpeakerEvidenceStatus.sourceMentionIdentityUnresolved;
      } else {
        status = DialogueSpeakerEvidenceStatus.sourceMentionGroupReviewed;
      }
      result.add(DialogueSpeakerEvidence(
        speaker: name,
        status: status,
        firstSourceChapter: firstChapter,
        dossierIds: List.unmodifiable(
            [for (final character in unique) character.mentionGroupId]),
      ));
    }
    return SourceLockedDialogueSpeakerAudit._(List.unmodifiable(result));
  }

  static String _normal(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
