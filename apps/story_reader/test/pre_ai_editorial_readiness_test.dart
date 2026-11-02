import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/preparation_readiness_report.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_narrative_extractor.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';

void main() {
  const book = ImportedBook(
    title: 'История без ИИ', author: 'Автор',
    chapters: ['Дверь была закрыта. Мария открыла дверь.'],
  );
  late BookSourceIndex index;
  late SourceEvidenceGraph graph;
  late SourceSemanticCatalog catalog;

  setUp(() {
    index = BookSourceIndexer.index(book);
    graph = SourceEvidenceGraph.empty(index);
    for (final chunk in index.chunks) {
      graph = graph.addAll(
          index, SourceNarrativeExtractor.extractChunk(index, chunk));
    }
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
  });

  test('manual editorial verdict is a proposal, never accepted world truth',
      () {
    final blank = SemanticEditorialReviewSession.create(index, catalog);
    final id = catalog.assertions.first.id;
    expect(blank.reviewedCount, 0);
    final marked = blank.decide(
        catalog, id, SemanticEditorialVerdict.canonCandidate);
    expect(marked.reviewedCount, 1);
    expect(marked.canonCandidates, 1);
    expect(blank.reviewedCount, 0);
    expect(marked.isWorldCanon, false);
    expect(marked.canPublishBookworld, false);
    final restored = SemanticEditorialReviewSession.decode(
        index, graph, catalog, marked.encode());
    expect(restored.verdicts[id], SemanticEditorialVerdict.canonCandidate);
    expect(restored.encode(), marked.encode());
    expect(restored.matches(index, catalog), true);
    final unmarked = restored.decide(catalog, id, null);
    expect(unmarked.reviewedCount, 0);
    expect(unmarked.canonCandidates, 0);
  });

  test('tampered editorial decisions and stale books are rejected', () {
    final stored = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, catalog.assertions.first.id,
            SemanticEditorialVerdict.passageOnly)
        .encode();
    final forged = jsonDecode(stored) as Map<String, dynamic>;
    (forged['payload'] as Map<String, dynamic>)['status'] = 'CANON_CONFIRMED';
    expect(() => SemanticEditorialReviewSession.decode(
        index, graph, catalog, jsonEncode(forged)), throwsFormatException);
    final outsider = jsonDecode(stored) as Map<String, dynamic>;
    (outsider['payload'] as Map<String, dynamic>)['verdicts'] =
        {'fake_assertion': 'CANONCANDIDATE'};
    expect(() => SemanticEditorialReviewSession.decode(
        index, graph, catalog, jsonEncode(outsider)), throwsFormatException);
    final alteredBook = BookSourceIndexer.index(const ImportedBook(
        title: 'Иная редакция', author: 'Автор', chapters: ['Другой текст']));
    expect(() => SemanticEditorialReviewSession.decode(
        alteredBook, graph, catalog, stored), throwsFormatException);
  });

  test('new private checkpoint scopes never erase old chapter review data',
      () async {
    final base = await Directory.systemTemp.createTemp('story_preai_scopes_');
    addTearDown(() => base.delete(recursive: true));
    FileSourceAnalysisCheckpointRepository store(SourceCheckpointScope scope) =>
        FileSourceAnalysisCheckpointRepository(
            rootDirectory: () async => base, scope: scope);
    final oldMentions = store(SourceCheckpointScope.mentions);
    final oldNarrative = store(SourceCheckpointScope.narrativeEvidence);
    final oldRelations = store(SourceCheckpointScope.identityRelations);
    final oldSemantic = store(SourceCheckpointScope.semanticProposals);
    final catalogStore = store(SourceCheckpointScope.semanticCatalog);
    final editorStore = store(SourceCheckpointScope.semanticEditorial);
    final draftStore = store(SourceCheckpointScope.intermediateDraft);

    final id = index.sourceFingerprint;
    await oldMentions.write(id, 'old mentions stay');
    await oldNarrative.write(id, 'old narrative stays');
    await oldRelations.write(id, 'old relations stay');
    await oldSemantic.write(id, 'old proposals stay');
    await catalogStore.write(id, catalog.encode());
    await editorStore.write(id,
        SemanticEditorialReviewSession.create(index, catalog).encode());
    await draftStore.write(id, '{"format":"private-draft-test-only"}');
    await editorStore.delete(id);
    expect(await editorStore.read(id), isNull);
    expect(await catalogStore.read(id), catalog.encode());
    expect(await draftStore.read(id), isNotNull);
    expect(await oldMentions.read(id), 'old mentions stay');
    expect(await oldNarrative.read(id), 'old narrative stays');
    expect(await oldRelations.read(id), 'old relations stay');
    expect(await oldSemantic.read(id), 'old proposals stay');
  });

  test('readiness reports genuine gates without ever claiming a built RPG',
      () {
    final blank = PreparationReadinessReport.assess(index);
    expect(blank.gates.any((x) =>
        x.id == 'source' &&
        x.status == PreparationGateStatus.complete), true);
    expect(blank.gates.any((x) =>
        x.id == 'compiler' &&
        x.status == PreparationGateStatus.blocked), true);
    expect(blank.canStartPlayableBook, false);
    expect(blank.mayAutomaticallySendBookToCloud, false);
    expect(blank.gameplayCoverage, 0);

    var editor = SemanticEditorialReviewSession.create(index, catalog);
    for (final c in catalog.assertions) {
      editor = editor.decide(
          catalog, c.id, SemanticEditorialVerdict.canonCandidate);
    }
    final withReview = PreparationReadinessReport.assess(index,
        evidence: graph, catalog: catalog, editorial: editor);
    expect(withReview.reviewedAssertions, catalog.assertions.length);
    expect(withReview.gates.any((x) =>
        x.id == 'editorial' &&
        x.status == PreparationGateStatus.needsReview), true);
    expect(withReview.canStartPlayableBook, false);
  });
}
