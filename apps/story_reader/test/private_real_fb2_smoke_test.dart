import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/book_storage.dart';
import 'package:ai_story_reader/offline_preparation_coordinator.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// The user's source book is PRIVATE: no content or assets in public GitHub,
/// Actions artifacts, test logs, generated snapshots, or release bundles.
///
/// To run on a machine with the provided standalone FB2:
///   cd apps/story_reader
///   AI_RPG_PRIVATE_FB2_PATH=/absolute/path/04_Svinopas.fb2 \\
///       flutter test test/private_real_fb2_smoke_test.dart
///
/// This is a local functional test, NOT a device UX acceptance or an
/// automatic conversion of the book into a finished game.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bookPath = Platform.environment['AI_RPG_PRIVATE_FB2_PATH'];
  test('private Andersen single-tale FB2: import -> offline extraction -> '
      'checkpoints -> storage/reopen', () async {
    final bytes = await File(bookPath!).readAsBytes();
    final imported = BookImporter.parse('04_Svinopas.fb2', bytes);
    expect(imported.title, 'Свинопас');
    expect(imported.structuredChapters, hasLength(1));
    expect(imported.structuredChapters.single.blocks
        .where((b) => b.kind == BookBlockKind.image), hasLength(5));
    expect(imported.images.length, 5);
    expect(imported.cover, isNotNull);
    expect(imported.chapters.single, isNotEmpty);

    final index = BookSourceIndexer.index(imported);
    expect(index.chapterCount, 1);
    expect(index.indexedChapterCount, 1);
    expect(index.unindexedMediaBlocks, 5);
    expect(index.textIndexCoverage, 1.0);
    expect(index.chunks, isNotEmpty);
    expect(index.canPublishBookworld, isFalse);
    final fingerprint = index.sourceFingerprint;

    final names = MemorySourceAnalysisCheckpointRepository();
    final events = MemorySourceAnalysisCheckpointRepository();
    final semantics = MemorySourceAnalysisCheckpointRepository();
    final coordinator = OfflinePreparationCoordinator(
      mentionsRepository: names,
      narrativeRepository: events,
      catalogRepository: semantics,
      mentionsProcessor: (i, current) async =>
          current.processBatch(i, limit: 24),
      narrativeProcessor: (i, current) async =>
          current.scanNext(i, limit: 24),
      catalogProcessor: (i, graph) async =>
          SourceSemanticCatalog.fromLocalEvidence(i, graph),
      mentionsEncoder: (current) async => current.encode(),
      mentionsDecoder: (i, raw) async =>
          SourceAnalysisSession.decode(i, raw),
      narrativeEncoder: (current) async => current.encode(),
      narrativeDecoder: (i, raw) async =>
          StoryEvidenceReviewSession.decode(i, raw),
      catalogDecoder: (i, graph, raw) async =>
          SourceSemanticCatalog.decode(i, graph, raw),
    );
    final result = await coordinator.run(index);
    expect(result.paused, isFalse);
    expect(result.complete, isTrue);
    expect(result.narrative!.scannedChunks, index.chunks.length);
    expect(result.catalog, isNotNull);
    expect(result.canPublishBookworld, isFalse);
    expect(result.narrative!.graph.records, isNotEmpty);
    final graph = result.narrative!.graph;
    expect(graph.records.where((e) => e.kind == EvidenceKind.event),
        isNotEmpty);
    expect(graph.records.where((e) => e.kind == EvidenceKind.character),
        isNotEmpty);
    expect(graph.records.every((e) => e.status == EvidenceStatus.inferred),
        isTrue);
    expect(graph.visibleToPlayer(currentChapter: 999), isEmpty);
    for (final candidate in graph.records) {
      candidate.validate(index); // exact original text offsets and SHA.
    }
    expect(await events.read(fingerprint), result.narrative!.encode());
    expect(await semantics.read(fingerprint), result.catalog!.encode());
    final repeat = await coordinator.run(index);
    expect(repeat.catalog!.encode(), result.catalog!.encode());

    final temp = await Directory.systemTemp.createTemp('rpg-private-fb2-');
    try {
      final library = BookStorage(rootDirectory: () async => temp);
      await library.add(imported);
      final scan = await library.scan();
      expect(scan.unreadableCount, 0);
      expect(scan.books, hasLength(1));
      final reopened = scan.books.single.book;
      expect(reopened.title, imported.title);
      expect(reopened.structuredChapters, hasLength(1));
      expect(reopened.images.length, 5);
      expect(BookSourceIndexer.index(reopened).sourceFingerprint, fingerprint);
    } finally {
      await temp.delete(recursive: true);
    }
  }, skip: bookPath == null || bookPath.isEmpty
      ? 'Real private FB2 not in public CI. Set AI_RPG_PRIVATE_FB2_PATH.'
      : false);
}
