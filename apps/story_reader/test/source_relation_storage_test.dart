import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_relation_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';

void main() {
  test('M2b1, M2b3b, M2b3c have distinct private files and reset scopes',
      () async {
    final root = await Directory.systemTemp.createTemp('story_relations_');
    addTearDown(() => root.delete(recursive: true));
    const book = ImportedBook(
      title: 'Три каталога',
      author: 'Тест',
      chapters: ['Артем по прозвищу Волк открыл дверь.'],
    );
    final index = BookSourceIndexer.index(book);
    FileSourceAnalysisCheckpointRepository store(SourceCheckpointScope scope) =>
        FileSourceAnalysisCheckpointRepository(
          rootDirectory: () async => root, scope: scope,
        );
    final mentions = SourceAnalysisSession.create(index).encode();
    final narrative = StoryEvidenceReviewSession.create(index).encode();
    final relations = SourceRelationReviewSession.create(
        index, SourceEvidenceGraph.empty(index)).encode();

    await store(SourceCheckpointScope.mentions).write(
        index.sourceFingerprint, mentions);
    await store(SourceCheckpointScope.narrativeEvidence).write(
        index.sourceFingerprint, narrative);
    await store(SourceCheckpointScope.identityRelations).write(
        index.sourceFingerprint, relations);

    expect(await store(SourceCheckpointScope.mentions)
        .read(index.sourceFingerprint), mentions);
    expect(await store(SourceCheckpointScope.narrativeEvidence)
        .read(index.sourceFingerprint), narrative);
    expect(await store(SourceCheckpointScope.identityRelations)
        .read(index.sourceFingerprint), relations);

    await store(SourceCheckpointScope.identityRelations)
        .delete(index.sourceFingerprint);
    expect(await store(SourceCheckpointScope.identityRelations)
        .read(index.sourceFingerprint), isNull);
    expect(await store(SourceCheckpointScope.narrativeEvidence)
        .read(index.sourceFingerprint), narrative);
    expect(await store(SourceCheckpointScope.mentions)
        .read(index.sourceFingerprint), mentions);

    await expectLater(
      store(SourceCheckpointScope.identityRelations).read('../traversal'),
      throwsFormatException,
    );
  });
}
