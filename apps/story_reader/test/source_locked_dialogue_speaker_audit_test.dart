import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_locked_dialogue_speaker_audit.dart';
import 'package:flutter_test/flutter_test.dart';

const _scene = 'Дверь была закрыта, и путники остановились.\n'
    'Лена: «Посмотри на замок, но не рассказывай чужие секреты».\n'
    'Страж: «Я ещё не знаю, как открыть эту дверь».\n'
    'Тень: «Мне неизвестна история замка».\n'
    'Незнакомец: «Что произошло здесь вчера?»\n'
    'Иван: «Я слышал эту историю только от прохожего».';

const _characters = <NarrativeCharacter>[
  NarrativeCharacter(
      mentionGroupId: 'source_lena_1', labels: ['Лена'],
      citationIds: ['q_lena'], firstChapter: 0, lastChapter: 2,
      identityHintsResolved: true),
  NarrativeCharacter(
      mentionGroupId: 'source_guard_1', labels: ['Страж'],
      citationIds: ['q_guard'], firstChapter: 4, lastChapter: 4,
      identityHintsResolved: true),
  NarrativeCharacter(
      mentionGroupId: 'source_shadow_1', labels: ['Тень'],
      citationIds: ['q_shadow'], firstChapter: 0, lastChapter: 3,
      identityHintsResolved: false),
  NarrativeCharacter(
      mentionGroupId: 'source_ivan_1', labels: ['Иван'],
      citationIds: ['q_ivan_a'], firstChapter: 0, lastChapter: 1,
      identityHintsResolved: true),
  NarrativeCharacter(
      mentionGroupId: 'source_ivan_2', labels: ['Иван'],
      citationIds: ['q_ivan_b'], firstChapter: 3, lastChapter: 4,
      identityHintsResolved: false),
];

void main() {
  test('two named speakers produce source-only, chronological annotations '
      'without treating word matches as NPC knowledge', () {
    final audit = SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: _scene,
      sceneChapterIndex: 1,
      sourceCharacters: _characters,
    );
    expect(audit.hasStructuredDialogue, true);
    expect(audit.speakers.map((s) => s.speaker).toList(),
        ['Лена', 'Страж', 'Тень', 'Незнакомец', 'Иван']);
    final statuses = {
      for (final s in audit.speakers) s.speaker: s.status,
    };
    expect(statuses['Лена'],
        DialogueSpeakerEvidenceStatus.sourceMentionGroupReviewed);
    expect(statuses['Страж'],
        DialogueSpeakerEvidenceStatus.firstMentionAfterScene);
    expect(statuses['Тень'],
        DialogueSpeakerEvidenceStatus.sourceMentionIdentityUnresolved);
    expect(statuses['Незнакомец'],
        DialogueSpeakerEvidenceStatus.noMatchingSourceMention);
    expect(statuses['Иван'],
        DialogueSpeakerEvidenceStatus.ambiguousSameName);
    expect(audit.hasLaterOnlyNames, true);
    expect(audit.allSpeakersProven, false);
    expect(audit.knowsSourceFacts, false);
    expect(audit.requiresNetwork, false);
    expect(audit.changesGameRules, false);
    expect(audit.speakers.every((s) =>
        !s.provesSpokenWords && !s.provesNpcKnowledge &&
        !s.provesBookCanon), true);
    expect(audit.speakers.singleWhere((s) =>
        s.speaker == 'Страж').firstSourceChapter, 4);
    expect(audit.speakers.singleWhere((s) =>
        s.speaker == 'Иван').dossierIds, ['source_ivan_1', 'source_ivan_2']);
  });

  test('no dossiers or no attribution stay unverifiable without '
      'fabricated actor/group identifiers', () {
    final missing = SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: _scene,
      sceneChapterIndex: 1, sourceCharacters: const [],
    );
    expect(missing.speakers, hasLength(5));
    for (final item in missing.speakers) {
      expect(item.status,
          DialogueSpeakerEvidenceStatus.noMatchingSourceMention);
      expect(item.dossierIds, isEmpty);
      expect(item.firstSourceChapter, isNull);
    }
    final none = SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: '— Кто здесь?\n— Неизвестно.',
      sceneChapterIndex: 1, sourceCharacters: _characters,
    );
    expect(none.hasStructuredDialogue, false);
    expect(none.speakers, isEmpty);
    expect(() => SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: _scene,
      sceneChapterIndex: -1, sourceCharacters: _characters,
    ), throwsFormatException);
  });

  test('a name in a future chapter remains a spoiler risk until '
      'the source scene reaches that chapter', () {
    final before = SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: _scene, sceneChapterIndex: 2,
      sourceCharacters: _characters);
    expect(before.speakers.singleWhere((s) => s.speaker == 'Страж').status,
        DialogueSpeakerEvidenceStatus.firstMentionAfterScene);
    final after = SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: _scene, sceneChapterIndex: 4,
      sourceCharacters: _characters);
    expect(after.speakers.singleWhere((s) => s.speaker == 'Страж').status,
        DialogueSpeakerEvidenceStatus.sourceMentionGroupReviewed);
    expect(after.knowsSourceFacts, false);
  });
}
