import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

void main() {
  const book = ImportedBook(
    title: 'Два персонажа', author: 'Автор',
    chapters: [
      'Артем по прозвищу Волк открыл дверь. Дверь закрыта.',
      'Мария по прозвищу Лиса увидела дом. Дверь открыта.',
      'Артем встретил Мария. Волк увидел Лиса.',
    ],
  );
  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;
  late SourceRelationReviewSession relations;
  late SourceCharacterDossierIndex dossiers;
  late SourceCharacterDossier artem;
  late SourceCharacterDossier maria;

  setUp(() {
    index = BookSourceIndexer.index(book);
    final refs = <SourceEvidence>[];
    for (final chunk in index.chunks) {
      refs.addAll(SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    graph = SourceEvidenceGraph.empty(index).addAll(index, refs);
    for (final ref in graph.records) {
      graph = graph.review(index, ref.id, EvidenceStatus.confirmed);
    }
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    editorial = SemanticEditorialReviewSession.create(index, catalog);
    relations = SourceRelationReviewSession.create(index, graph);
    dossiers = SourceCharacterDossierIndex.build(
        index, graph, relations, catalog, editorial);
    artem = dossiers.dossiers.firstWhere((d) => d.labels.contains('Артем'));
    maria = dossiers.dossiers.firstWhere((d) => d.labels.contains('Мария'));
  });

  NpcEditorialNotebook notebook(List<NpcDraftNote> notes,
      {bool withMaria = false}) {
    final a = NpcEditorialNotebook.freshProfile(artem);
    var result = NpcEditorialNotebook.empty(index).putProfile(
      NpcDraftProfile(dossierId: a.dossierId, mentionIds: a.mentionIds,
          displayName: 'Артем, версия RPG', notes: notes),
    );
    if (withMaria) result = result.putProfile(
        NpcEditorialNotebook.freshProfile(maria));
    return result;
  }

  NpcContinuityAudit inspect(NpcEditorialNotebook notes,
      {IntermediateStoryBlueprint? scenario,
       SourceCharacterDossierIndex? updated,
       SemanticEditorialReviewSession? decisions}) =>
      NpcContinuityAudit.inspect(
        index: index, dossiers: updated ?? dossiers, graph: graph,
        catalog: catalog, editorial: decisions ?? editorial,
        notebook: notes, scenario: scenario,
      );

  IntermediateStoryBlueprint story(int chapter) =>
      IntermediateStoryBlueprint(
        sourceFingerprint: index.sourceFingerprint, title: index.title,
        entrySceneId: 'entry', rights: PreparationRights.privateUse,
        flags: const [], initialFlags: const [],
        scenes: [
          DraftScene(id: 'entry', chapterIndex: chapter,
            text: 'Авторская развилка', terminal: true,
            origin: DraftSceneOrigin.explicitAdaptation,
            assertionIds: const [], choices: const []),
        ],
      );

  test('stable non-game staging ID; secrets never become player-visible', () {
    final notes = notebook(const [
      NpcDraftNote(id: 'npc_note_1', field: NpcDraftField.role,
          text: 'Смотритель'),
      NpcDraftNote(id: 'npc_note_2', field: NpcDraftField.secret,
          text: 'Тайна только для редактора'),
    ]);
    final one = inspect(notes);
    expect(one.actors.single.stagingId, inspect(notes).actors.single.stagingId);
    expect(one.actors.single.stagingId, startsWith('stage_npc_'));
    expect(one.actors.single.canInstallInWorld, false);
    expect(one.actors.single.canSendToAi, false);
    expect(one.canPublishNpcActors, false);
    expect(one.canRevealPlayerSecrets, false);
    expect(one.canCreateLlmContext, false);
    final secret = one.actors.single.noteGates.last;
    expect(secret.earliestSourceChapter, isNull);
    expect(secret.isSafeToRevealAutomaticallyAt(999), false);
    expect(secret.isAutomaticallyPlayerVisible, false);
  });

  test('multiple roles/motivations are warnings, never canonical facts', () {
    final audit = inspect(notebook(const [
      NpcDraftNote(id: 'npc_note_1', field: NpcDraftField.role,
          text: 'Смотритель'),
      NpcDraftNote(id: 'npc_note_2', field: NpcDraftField.role,
          text: 'Кузнец'),
      NpcDraftNote(id: 'npc_note_3', field: NpcDraftField.motivation,
          text: 'Спасти сестру'),
      NpcDraftNote(id: 'npc_note_4', field: NpcDraftField.motivation,
          text: 'Уйти из города'),
    ]));
    expect(audit.findings.map((x) => x.kind),
        contains(NpcContinuityFindingKind.competingRoles));
    expect(audit.findings.map((x) => x.kind),
        contains(NpcContinuityFindingKind.competingMotivations));
    expect(audit.findings.every((x) => !x.isProvenContradiction), true);
  });

  test('relationship needs target profile, never auto-adopts world link', () {
    final notes = [
      const NpcDraftNote(id: 'npc_note_1', field: NpcDraftField.role,
          text: 'Смотритель'),
      NpcDraftNote(id: 'npc_note_2', field: NpcDraftField.relationship,
          text: 'Знаком с Марией только в новой версии',
          targetDossierId: maria.id,
          targetGroupDigest: NpcEditorialNotebook.groupDigest(maria)),
    ];
    final before = inspect(notebook(notes));
    expect(before.relations.single.targetStagingId, isNull);
    expect(before.relations.single.isWorldRelationship, false);
    expect(before.findings.map((x) => x.kind),
        contains(NpcContinuityFindingKind.linkWithoutTargetProfile));
    final after = inspect(notebook(notes, withMaria: true));
    expect(after.relations.single.targetStagingId, isNotNull);
    expect(after.actors.length, 2);
  });

  test('cited knowledge has earliest chapter, no automatic disclosure', () {
    final claim = catalog.assertions.firstWhere(
        (c) => c.kind == SemanticAssertionKind.relation);
    final accepted = editorial.decide(
        catalog, claim.id, SemanticEditorialVerdict.canonCandidate);
    final notes = notebook([
      const NpcDraftNote(id: 'npc_note_1', field: NpcDraftField.role,
          text: 'Свидетель'),
      NpcDraftNote(id: 'npc_note_2', field: NpcDraftField.knowledge,
          text: 'Встреча — только гипотеза',
          sourceAssertionId: claim.id),
    ]);
    final audit = inspect(notes, decisions: accepted, scenario: story(0));
    final gate = audit.actors.single.noteGates.last;
    expect(gate.earliestSourceChapter, 2);
    expect(gate.isSafeToRevealAutomaticallyAt(3), false);
    expect(audit.findings.map((x) => x.kind),
        contains(NpcContinuityFindingKind.sourceKnowledgeBeyondDraft));
    expect(audit.scenarioLinked, true);
    expect(audit.actors.single.possibleSceneIds, ['entry']);
  });

  test('SAME changes and foreign draft reject stage preview', () {
    final notes = notebook(const [
      NpcDraftNote(id: 'npc_note_1', field: NpcDraftField.role,
          text: 'Страж'),
    ]);
    final edge = relations.hints.firstWhere((h) =>
        h.kind == IdentityHintKind.explicitAlias &&
        (h.firstId == artem.id || h.secondId == artem.id));
    final merged = SourceCharacterDossierIndex.build(
        index, graph, relations.decide(index, graph,
            edge.id, IdentityDecision.same), catalog, editorial);
    expect(() => inspect(notes, updated: merged), throwsFormatException);
    final foreign = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая редакция', author: 'Автор', chapters: ['Иной сюжет.']));
    final wrong = IntermediateStoryBlueprint(
      sourceFingerprint: foreign.sourceFingerprint,
      title: foreign.title, entrySceneId: 'entry',
      rights: PreparationRights.privateUse,
      flags: const [], initialFlags: const [],
      scenes: [
        DraftScene(id: 'entry', chapterIndex: 0, text: 'Сцена',
            origin: DraftSceneOrigin.explicitAdaptation,
            assertionIds: const [], terminal: true, choices: const []),
      ],
    );
    expect(() => inspect(notes, scenario: wrong), throwsFormatException);
  });

}
