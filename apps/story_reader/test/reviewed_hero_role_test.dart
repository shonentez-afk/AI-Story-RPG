import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/npc_editorial_notebook.dart';
import 'package:ai_story_reader/reviewed_hero_role.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_character_dossiers.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('existing private NPC notebook supplies stable selectable '
      'hero IDs after restart, not inferred names', () async {
    final index = BookSourceIndexer.index(const ImportedBook(
      title: 'Роман с подтвержденным героем',
      author: 'Локальные проверочные источники',
      chapters: [
        'Артем по прозвищу Волк нашел у ворот старый ключ. '
            'Артем прочитал надпись на камне.',
        'Мария по прозвищу Лиса увидела дом. '
            'Артем и Мария встретились в конце пути.',
      ],
    ));
    var source = StoryEvidenceReviewSession.create(index)
        .scanNext(index, limit: 24);
    expect(source.graph.records, isNotEmpty);
    for (final evidence in source.graph.records) {
      source = source.review(index, evidence.id, EvidenceStatus.confirmed);
    }
    final graph = source.graph;
    final relations = SourceRelationReviewSession.create(index, graph);
    final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    final editorial = SemanticEditorialReviewSession.create(index, catalog);
    final dossiers = SourceCharacterDossierIndex.build(
        index, graph, relations, catalog, editorial);
    final artem = dossiers.dossiers.firstWhere(
        (d) => d.labels.contains('Артем'));
    final profile = NpcEditorialNotebook.freshProfile(artem);
    final notebook = NpcEditorialNotebook.empty(index).putProfile(profile);
    notebook.validate(index, dossiers, graph, catalog, editorial);

    final narrativeRepo = MemorySourceAnalysisCheckpointRepository();
    final catalogRepo = MemorySourceAnalysisCheckpointRepository();
    final editorialRepo = MemorySourceAnalysisCheckpointRepository();
    final relationsRepo = MemorySourceAnalysisCheckpointRepository();
    final notebookRepo = MemorySourceAnalysisCheckpointRepository();
    final roles = ReviewedHeroRoleCatalog(
        narrativeRepository: narrativeRepo,
        catalogRepository: catalogRepo,
        editorialRepository: editorialRepo,
        identityRepository: relationsRepo,
        notebookRepository: notebookRepo);
    expect(await roles.load(index), isEmpty);
    await narrativeRepo.write(index.sourceFingerprint, source.encode());
    await catalogRepo.write(index.sourceFingerprint, catalog.encode());
    await editorialRepo.write(index.sourceFingerprint, editorial.encode());
    await relationsRepo.write(index.sourceFingerprint, relations.encode());
    await notebookRepo.write(index.sourceFingerprint, notebook.encode());
    final loaded = await roles.load(index);
    expect(loaded, hasLength(1));
    expect(loaded.single.characterId, profile.characterId);
    expect(loaded.single.playerIdentityFlag,
        'player_is_' + profile.characterId!);
    expect(loaded.single.firstSourceChapter, 0);

    final renamed = notebook.putProfile(
        profile.copyWith(displayName: 'Артем — игровая роль'));
    await notebookRepo.write(index.sourceFingerprint, renamed.encode());
    final after = await roles.load(index);
    expect(after.single.characterId, loaded.single.characterId);
    expect(after.single.displayName, 'Артем — игровая роль');
    expect(after.single.groupDigest, loaded.single.groupDigest);

    await notebookRepo.write(index.sourceFingerprint, '{"forged":true}');
    await expectLater(roles.load(index), throwsFormatException);
    final changedEdition = BookSourceIndexer.index(const ImportedBook(
      title: 'Другое издание', author: 'Другой автор',
      chapters: ['Артем и другая книга.'],
    ));
    expect(await roles.load(changedEdition), isEmpty);
  });
}
