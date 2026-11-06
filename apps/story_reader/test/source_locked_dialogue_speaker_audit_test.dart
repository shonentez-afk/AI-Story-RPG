import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/npc_character_card.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
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


  test('reviewed names bind to saved IDs, but later, ambiguous and '
      'unreviewed speakers cannot acquire an NPC identity', () {
    final bookIndex = BookSourceIndexer.index(const ImportedBook(
      title: 'Источник NPC', author: 'Автор',
      chapters: ['Лена и Страж у ворот.', 'Продолжение у ворот.'],
    ));
    final id = 'npc_' + List.filled(32, 'a').join();
    final profile = NpcDraftProfile(
      dossierId: 'source_lena_1',
      mentionIds: const ['q_lena'],
      displayName: 'Лена в авторской версии',
      notes: const [],
      card: NpcCharacterCard(characterId: id),
    );
    final notebook = NpcEditorialNotebook.empty(bookIndex)
        .putProfile(profile);
    final audit = SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: _scene,
      sceneChapterIndex: 1,
      sourceCharacters: _characters,
    );
    final bound = audit.bindReviewedCharacterIds(
      sourceFingerprint: bookIndex.sourceFingerprint,
      sourceCharacters: _characters,
      notebook: notebook,
    );
    expect(bound, {'Лена': id});
    expect(bound.containsKey('Страж'), false); // future spoiler
    expect(bound.containsKey('Иван'), false); // ambiguous name
    expect(bound.containsKey('Тень'), false); // unreviewed identity
    expect(bound.containsKey('Незнакомец'), false); // no source

    // Names and prose may change while identity stays the same.
    final renamed = notebook.putProfile(profile.copyWith(
        displayName: 'Новая кличка',
        card: profile.card!.copyWith(aliases: ['Тихая'])));
    expect(audit.bindReviewedCharacterIds(
      sourceFingerprint: bookIndex.sourceFingerprint,
      sourceCharacters: _characters,
      notebook: renamed,
    )['Лена'], id);

    // A changed mention group never rebinds an actor by matching its name.
    final stale = NpcEditorialNotebook.empty(bookIndex).putProfile(
      NpcDraftProfile(
        dossierId: profile.dossierId, mentionIds: const ['other_quote'],
        displayName: profile.displayName, notes: const [],
        card: profile.card,
      ),
    );
    expect(audit.bindReviewedCharacterIds(
      sourceFingerprint: bookIndex.sourceFingerprint,
      sourceCharacters: _characters, notebook: stale,
    ), isEmpty);

    expect(() => audit.bindReviewedCharacterIds(
      sourceFingerprint: 'another_book_revision',
      sourceCharacters: _characters,
      notebook: notebook,
    ), throwsFormatException);
  });

  test('duplicate character IDs across source groups are rejected', () {
    final bookIndex = BookSourceIndexer.index(const ImportedBook(
      title: 'Два героя', author: 'Автор',
      chapters: ['Лена встретила Стража.'],
    ));
    final id = 'npc_' + List.filled(32, 'c').join();
    final first = NpcDraftProfile(
      dossierId: 'source_lena_1',
      mentionIds: const ['q_lena'],
      displayName: 'Лена', notes: const [],
      card: NpcCharacterCard(characterId: id),
    );
    final second = NpcDraftProfile(
      dossierId: 'source_guard_1',
      mentionIds: const ['q_guard'],
      displayName: 'Страж', notes: const [],
      card: NpcCharacterCard(characterId: id),
    );
    final notebook = NpcEditorialNotebook.empty(bookIndex)
        .putProfile(first).putProfile(second);
    final audit = SourceLockedDialogueSpeakerAudit.inspect(
      approvedSceneText: _scene,
      sceneChapterIndex: 1,
      sourceCharacters: _characters,
    );
    expect(() => audit.bindReviewedCharacterIds(
      sourceFingerprint: bookIndex.sourceFingerprint,
      sourceCharacters: _characters,
      notebook: notebook,
    ), throwsFormatException);
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
