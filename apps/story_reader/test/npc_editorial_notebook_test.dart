import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
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
