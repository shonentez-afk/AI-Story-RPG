import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/npc_character_card.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const story = ImportedBook(
    title: 'Роман с персонажами', author: 'Автор',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. Дверь была закрыта.',
      'Мария по прозвищу Лиса увидела дом. Дверь была открыта.',
      'Артем встретил Мария. Волк увидел Лиса.',
    ],
  );
  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceRelationReviewSession relations;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;
  late SourceCharacterDossierIndex dossiers;
  late SourceCharacterDossier artem;
  late SourceCharacterDossier maria;
  late SourceSemanticAssertion meeting;

  SourceCharacterDossierIndex computeDossiers(
      SourceRelationReviewSession session, {SourceEvidenceGraph? evidence}) =>
      SourceCharacterDossierIndex.build(index, evidence ?? graph,
          session, catalog, editorial);

  setUp(() {
    index = BookSourceIndexer.index(story);
    final all = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      all.addAll(SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    graph = SourceEvidenceGraph.empty(index).addAll(index, all);
    for (final source in graph.records) {
      graph = graph.review(index, source.id, EvidenceStatus.confirmed);
    }
    relations = SourceRelationReviewSession.create(index, graph);
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    editorial = SemanticEditorialReviewSession.create(index, catalog);
    meeting = catalog.assertions.firstWhere(
        (a) => a.kind == SemanticAssertionKind.relation);
    editorial = editorial.decide(catalog, meeting.id,
        SemanticEditorialVerdict.canonCandidate);
    dossiers = computeDossiers(relations);
    artem = dossiers.dossiers.firstWhere(
        (d) => d.labels.contains('Артем'));
    maria = dossiers.dossiers.firstWhere(
        (d) => d.labels.contains('Мария'));
  });

  NpcEditorialNotebook checked(NpcEditorialNotebook book) {
    book.validate(index, dossiers, graph, catalog, editorial);
    return book;
  }

  test('new NPC stores one permanent character ID through rename, notes, '
      'restart and source-only facts', () {
    final first = NpcEditorialNotebook.freshProfile(artem);
    final other = NpcEditorialNotebook.freshProfile(maria);
    expect(first.characterId, isNotNull);
    expect(first.characterId, isNot(other.characterId));
    expect(first.hasPermanentIdentity, true);
    expect(first.card!.literaryCanonVerified, false);

    var notebook = NpcEditorialNotebook.empty(index)
        .putProfile(first).putProfile(other);
    checked(notebook);
    final previousId = first.characterId!;
    // The existing editor sometimes reconstructs a profile from notes.
    // Even if that old call-site omits the card, putProfile retains the ID.
    notebook = notebook.putProfile(NpcDraftProfile(
      dossierId: first.dossierId, mentionIds: first.mentionIds,
      displayName: 'Волк, личная адаптация',
      notes: const [
        NpcDraftNote(
          id: 'npc_note_1', field: NpcDraftField.knowledge,
          text: 'Нельзя считать известным до выбранного события.',
        ),
      ],
    ));
    final changed = notebook.profiles.singleWhere(
        (item) => item.dossierId == first.dossierId);
    expect(changed.characterId, previousId);
    notebook = notebook.putProfile(changed.copyWith(
        displayName: 'Страж ворот',
        card: changed.card!.copyWith(
          aliases: ['Волк'],
          appearance: 'Седой плащ',
          personality: 'Осторожный',
          speechStyle: 'Медленно и коротко',
          goals: 'Охранять проход',
          portraitAssetId: 'wolf_local',
        )));
    checked(notebook);
    final raw = notebook.encode();
    final restored = NpcEditorialNotebook.decode(
        index, dossiers, graph, catalog, editorial, raw);
    expect(restored.encode(), raw);
    final confirmed = restored.profiles.singleWhere(
        (item) => item.dossierId == first.dossierId);
    expect(confirmed.characterId, previousId);
    expect(confirmed.displayName, 'Страж ворот');
    expect(confirmed.card!.aliases, ['Волк']);
    expect(confirmed.card!.portraitAssetId, 'wolf_local');
    expect(confirmed.notes.single.field,
        NpcDraftField.knowledge);

    // Reissuing an ID is NOT a rename. Duplicate or swapped IDs fail.
    final swapped = NpcCharacterCard.fresh();
    expect(() => restored.putProfile(confirmed.copyWith(
      card: swapped,
    )), throwsFormatException);
    final sameId = NpcCharacterCard(
        characterId: confirmed.characterId!);
    final duplicate = NpcEditorialNotebook.empty(index)
        .putProfile(confirmed)
        .putProfile(other.copyWith(card: sameId));
    expect(() => checked(duplicate), throwsFormatException);
    expect(restored.canPublishBookworld, false);
  });

  test('explicit role, motivation, secret and linked knowledge roundtrip',
      () {
    expect(NpcEditorialNotebook.isConfirmedDossier(artem), true);
    var book = NpcEditorialNotebook.empty(index);
    final profile = NpcEditorialNotebook.freshProfile(artem);
    expect(profile.notes, isEmpty);
    book = book.putProfile(NpcDraftProfile(
      dossierId: profile.dossierId,
      mentionIds: profile.mentionIds,
      displayName: 'Артем — охранник в адаптации',
      notes: [
        const NpcDraftNote(
          id: 'npc_note_1', field: NpcDraftField.role,
          text: 'Охранник двери', 
        ),
        const NpcDraftNote(
          id: 'npc_note_2', field: NpcDraftField.motivation,
          text: 'Найти ключ (авторская версия)',
        ),
        const NpcDraftNote(
          id: 'npc_note_3', field: NpcDraftField.secret,
          text: 'Скрывает неизвестный факт',
        ),
        NpcDraftNote(
          id: 'npc_note_4', field: NpcDraftField.knowledge,
          text: 'Был свидетелем встречи: только кандидат',
          sourceAssertionId: meeting.id,
        ),
      ],
    ));
    checked(book);
    final saved = book.encode();
    final restored = NpcEditorialNotebook.decode(
        index, dossiers, graph, catalog, editorial, saved);
    expect(restored.encode(), saved);
    expect(restored.profiles.single.notes.length, 4);
    expect(restored.profiles.single.notes.last.isAuthorial, false);
    expect(restored.profiles.single.notes.last.isWorldCanon, false);
    expect(restored.isLlmPromptApproved, false);
    expect(restored.canPublishBookworld, false);
    expect(restored.nextNoteId(), 'npc_note_5');
  });

  test('manual relationship is bound to exact target source group', () {
    final profile = NpcEditorialNotebook.freshProfile(artem);
    final link = NpcDraftNote(
      id: 'npc_note_1', field: NpcDraftField.relationship,
      text: 'Дружит с Марией только в альтернативной версии',
      targetDossierId: maria.id,
      targetGroupDigest: NpcEditorialNotebook.groupDigest(maria),
    );
    final book = checked(NpcEditorialNotebook.empty(index).putProfile(
        NpcDraftProfile(
          dossierId: profile.dossierId,
          mentionIds: profile.mentionIds,
          displayName: profile.displayName,
          notes: [link],
        )));
    expect(NpcEditorialNotebook.decode(
        index, dossiers, graph, catalog, editorial, book.encode())
        .profiles.single.notes.single.isAuthorial, true);
    final broken = NpcEditorialNotebook.empty(index).putProfile(
        NpcDraftProfile(
          dossierId: profile.dossierId,
          mentionIds: profile.mentionIds,
          displayName: profile.displayName,
          notes: [
            NpcDraftNote(
              id: link.id, field: link.field, text: link.text,
              targetDossierId: link.targetDossierId,
              targetGroupDigest: 'deadbeef',
            ),
          ],
        ));
    expect(() => checked(broken), throwsFormatException);
  });

  test('permanent relationship target survives renaming but rejects mismatched ID', () {
    final source = NpcEditorialNotebook.freshProfile(artem);
    final target = NpcEditorialNotebook.freshProfile(maria);
    final link = NpcDraftNote(
      id: 'npc_note_1',
      field: NpcDraftField.relationship,
      text: 'Доверяет Марии в частной адаптации',
      targetDossierId: maria.id,
      targetGroupDigest: NpcEditorialNotebook.groupDigest(maria),
      targetCharacterId: target.characterId,
    );
    final notebook = checked(NpcEditorialNotebook.empty(index)
        .putProfile(source.copyWith(notes: [link]))
        .putProfile(target));
    final targetId = target.characterId;
    expect(targetId, isNotNull);
    expect(targetId!.startsWith('npc_'), true);
    final reopened = NpcEditorialNotebook.decode(
        index, dossiers, graph, catalog, editorial, notebook.encode());
    expect(reopened.profiles.first.notes.single.targetCharacterId, targetId);

    final renamed = checked(reopened.putProfile(target.copyWith(
      displayName: 'Новая кличка',
      card: target.card!.copyWith(aliases: ['Лиса']),
    )));
    expect(renamed.profiles.first.notes.single.targetCharacterId, targetId);
    expect(renamed.profiles.last.characterId, targetId);

    final wrongId = NpcCharacterCard.fresh().characterId;
    final tampered = NpcEditorialNotebook.empty(index)
        .putProfile(source.copyWith(notes: [
          NpcDraftNote(
            id: link.id, field: link.field, text: link.text,
            targetDossierId: link.targetDossierId,
            targetGroupDigest: link.targetGroupDigest,
            targetCharacterId: wrongId,
          ),
        ]))
        .putProfile(target);
    expect(() => checked(tampered), throwsFormatException);
    expect(() => checked(NpcEditorialNotebook.empty(index)
        .putProfile(source.copyWith(notes: [link]))), throwsFormatException);
  });

  test('target character ID is forbidden on a non-relationship note', () {
    final source = NpcEditorialNotebook.freshProfile(artem);
    final wrong = source.copyWith(notes: [
      NpcDraftNote(
        id: 'npc_note_1', field: NpcDraftField.role,
        text: 'Страж', targetCharacterId: source.characterId,
      ),
    ]);
    expect(() => checked(NpcEditorialNotebook.empty(index)
        .putProfile(wrong)), throwsFormatException);
  });

  test('source citations are reviewed candidates, revoked verdict blocks',
      () {
    final profile = NpcEditorialNotebook.freshProfile(artem);
    final book = checked(NpcEditorialNotebook.empty(index).putProfile(
      NpcDraftProfile(
        dossierId: profile.dossierId, mentionIds: profile.mentionIds,
        displayName: profile.displayName,
        notes: [
          NpcDraftNote(
            id: 'npc_note_1', field: NpcDraftField.knowledge,
            text: 'Артем встретил Марию',
            sourceAssertionId: meeting.id,
          ),
        ],
      ),
    ));
    final denied = SemanticEditorialReviewSession.create(index, catalog);
    expect(() => book.validate(index, dossiers, graph, catalog, denied),
        throwsFormatException);
    final quote = meeting.evidenceIds.single;
    final rejected = graph.review(index, quote, EvidenceStatus.rejected);
    final freshRelations = SourceRelationReviewSession.create(index, rejected);
    final newDossiers = SourceCharacterDossierIndex.build(
        index, rejected, freshRelations, catalog, editorial);
    expect(() => NpcEditorialNotebook.decode(
        index, newDossiers, rejected, catalog, editorial, book.encode()),
        throwsFormatException);
  });

  test('manual SAME can invalidate anchored profile instead of migrating it',
      () {
    final profile = NpcEditorialNotebook.freshProfile(artem);
    final book = checked(NpcEditorialNotebook.empty(index).putProfile(profile));
    final pair = relations.hints.firstWhere((hint) =>
        hint.kind == IdentityHintKind.explicitAlias &&
        (hint.firstId == artem.id || hint.secondId == artem.id));
    final reviewed = relations.decide(
        index, graph, pair.id, IdentityDecision.same);
    final newDossiers = computeDossiers(reviewed);
    expect(() => NpcEditorialNotebook.decode(
        index, newDossiers, graph, catalog, editorial, book.encode()),
        throwsFormatException);
  });

  test('source candidate is not allowed without real character association',
      () {
    final profile = NpcEditorialNotebook.freshProfile(maria);
    final unrelated = catalog.assertions.firstWhere(
        (a) => a.kind == SemanticAssertionKind.fact);
    final adopted = editorial.decide(catalog, unrelated.id,
        SemanticEditorialVerdict.canonCandidate);
    final book = NpcEditorialNotebook.empty(index).putProfile(
        NpcDraftProfile(
          dossierId: profile.dossierId,
          mentionIds: profile.mentionIds,
          displayName: profile.displayName,
          notes: [
            NpcDraftNote(
              id: 'npc_note_1', field: NpcDraftField.knowledge,
              text: 'Необоснованный факт',
              sourceAssertionId: unrelated.id,
            ),
          ],
        ));
    expect(() => book.validate(index, dossiers, graph, catalog, adopted),
        throwsFormatException);
  });

  test('size limits, invalid targets and duplicate notes fail closed', () {
    final profile = NpcEditorialNotebook.freshProfile(artem);
    NpcEditorialNotebook build(List<NpcDraftNote> notes) =>
        NpcEditorialNotebook.empty(index).putProfile(NpcDraftProfile(
          dossierId: profile.dossierId, mentionIds: profile.mentionIds,
          displayName: profile.displayName, notes: notes,
        ));
    expect(() => checked(build([
      NpcDraftNote(
        id: 'npc_note_1', field: NpcDraftField.role,
        text: List.filled(801, 'a').join(),
      ),
    ])), throwsFormatException);
    expect(() => checked(build([
      const NpcDraftNote(
          id: 'npc_note_1', field: NpcDraftField.role, text: 'Первая роль'),
      const NpcDraftNote(
          id: 'npc_note_1', field: NpcDraftField.secret, text: 'Секрет'),
    ])), throwsFormatException);
    expect(() => checked(build([
      const NpcDraftNote(
          id: 'npc_note_1', field: NpcDraftField.relationship,
          text: 'Нет цели отношения'),
    ])), throwsFormatException);
    expect(() => checked(build([
      const NpcDraftNote(
          id: 'npc_note_1', field: NpcDraftField.role,
          text: 'Не должна иметь цель', targetDossierId: 'x'),
    ])), throwsFormatException);
  });

  test('corrupt, edited digest and other edition cannot be loaded', () {
    final book = checked(NpcEditorialNotebook.empty(index).putProfile(
        NpcEditorialNotebook.freshProfile(artem)));
    final raw = book.encode();
    final altered = raw.replaceFirst('Артем', 'Михаил');
    expect(() => NpcEditorialNotebook.decode(
        index, dossiers, graph, catalog, editorial, altered),
        throwsFormatException);
    final other = BookSourceIndexer.index(const ImportedBook(
        title: 'Другой роман', author: 'Автор',
        chapters: ['По имени Сергей.']));
    expect(() => NpcEditorialNotebook.decode(
        other, dossiers, graph, catalog, editorial, raw),
        throwsFormatException);
  });

  test('separate disk scope preserves short and multi-scene drafts',
      () async {
    final root = await Directory.systemTemp.createTemp('story_npc_m2e5b2_');
    addTearDown(() => root.delete(recursive: true));
    FileSourceAnalysisCheckpointRepository storage(SourceCheckpointScope scope) =>
        FileSourceAnalysisCheckpointRepository(
          rootDirectory: () async => root, scope: scope);
    final source = storage(SourceCheckpointScope.intermediateDraft);
    final multi = storage(SourceCheckpointScope.multiSceneDraft);
    final relation = storage(SourceCheckpointScope.identityRelations);
    final npc = storage(SourceCheckpointScope.npcEditorial);
    final fingerprint = index.sourceFingerprint;
    await source.write(fingerprint, 'legacy short draft');
    await multi.write(fingerprint, 'legacy multi draft');
    await relation.write(fingerprint, relations.encode());
    final current = checked(NpcEditorialNotebook.empty(index)
        .putProfile(NpcEditorialNotebook.freshProfile(artem)));
    await npc.write(fingerprint, current.encode());
    expect(NpcEditorialNotebook.decode(index, dossiers, graph, catalog,
        editorial, (await npc.read(fingerprint))!).profiles.length, 1);
    expect(await source.read(fingerprint), 'legacy short draft');
    expect(await multi.read(fingerprint), 'legacy multi draft');
    expect(await relation.read(fingerprint), relations.encode());
    await npc.delete(fingerprint);
    expect(await npc.read(fingerprint), isNull);
    expect(await multi.read(fingerprint), 'legacy multi draft');
    expect(await source.read(fingerprint), 'legacy short draft');
    expect(await relation.read(fingerprint), relations.encode());
  });
}
