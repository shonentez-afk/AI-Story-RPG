import 'book_source_index.dart';
import 'npc_editorial_notebook.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_character_dossiers.dart';
import 'source_relation_review.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_evidence_review_session.dart';
import 'package:story_authoring/reviewed_hero_role.dart';
export 'package:story_authoring/reviewed_hero_role.dart';

/// Read the same five existing PRIVATE editorial checkpoints as the NPC
/// editor, on explicit user action only. Never posts to GLM and never alters
/// a source checkpoint. Missing/partial review -> no eligible hero, not a
/// made-up name match.
class ReviewedHeroRoleCatalog {
  const ReviewedHeroRoleCatalog({
    this.narrativeRepository,
    this.catalogRepository,
    this.editorialRepository,
    this.identityRepository,
    this.notebookRepository,
  });

  final SourceAnalysisCheckpointRepository? narrativeRepository;
  final SourceAnalysisCheckpointRepository? catalogRepository;
  final SourceAnalysisCheckpointRepository? editorialRepository;
  final SourceAnalysisCheckpointRepository? identityRepository;
  final SourceAnalysisCheckpointRepository? notebookRepository;

  Future<List<ReviewedHeroRole>> load(BookSourceIndex index) async {
    final fingerprint = index.sourceFingerprint;
    final notebookRaw = await (notebookRepository ??
      const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.npcEditorial)).read(fingerprint);
    if (notebookRaw == null) return const [];
    final evidenceRaw = await (narrativeRepository ??
      const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.narrativeEvidence)).read(fingerprint);
    final catalogRaw = await (catalogRepository ??
      const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.semanticCatalog)).read(fingerprint);
    final editorialRaw = await (editorialRepository ??
      const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.semanticEditorial)).read(fingerprint);
    final relationsRaw = await (identityRepository ??
      const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.identityRelations)).read(fingerprint);
    // The existing NPC editor accepts a default relation session if a
    // user has not authored any identity merges yet. Rejecting that valid
    // scenario here would hide otherwise confirmed permanent identities.
    // A present but malformed relation checkpoint must STILL fail closed.
    if (evidenceRaw == null || catalogRaw == null ||
        editorialRaw == null) {
      throw const FormatException(
          'Нужны проверенные упоминания и карточки NPC.');
    }
    final graph = StoryEvidenceReviewSession.decode(
        index, evidenceRaw).graph;
    final catalog = SourceSemanticCatalog.decode(
        index, graph, catalogRaw);
    final editorial = SemanticEditorialReviewSession.decode(
        index, graph, catalog, editorialRaw);
    final relations = relationsRaw == null
        ? SourceRelationReviewSession.create(index, graph)
        : SourceRelationReviewSession.decode(index, graph, relationsRaw);
    final dossiers = SourceCharacterDossierIndex.build(
        index, graph, relations, catalog, editorial);
    final notebook = NpcEditorialNotebook.decode(
        index, dossiers, graph, catalog, editorial, notebookRaw);
    return ReviewedHeroRole.fromReviewedSources(
        index: index, dossiers: dossiers, graph: graph, catalog: catalog,
        editorial: editorial, notebook: notebook);
  }
}
