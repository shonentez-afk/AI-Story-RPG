import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/book_storage.dart';
import 'package:ai_story_reader/offline_preparation_coordinator.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_window.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_editorial_consistency.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mandatory REAL complete (62 tales) FB2 corpus, generated from historically
/// public-domain Gutenberg #2591; never silently SKIP or substitute synthetic
/// text. The CI step generates it; developers run the same generator first.
///
/// No personal Andersen FB2, modern translation, copyrighted illustration,
/// provider key, cloud request or user's campaigns are involved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImportedBook imported;
  late BookSourceIndex index;
  late Map<String, dynamic> manifest;

  setUpAll(() async {
    final sourceFile = Platform.environment['AI_RPG_GRIMM_PUBLIC_FB2_PATH'];
    final metaFile = Platform.environment['AI_RPG_GRIMM_PUBLIC_MANIFEST_PATH'];
    if (sourceFile == null || sourceFile.isEmpty ||
        metaFile == null || metaFile.isEmpty) {
      throw StateError('Required real full-book Grimm corpus missing. '
          'First run: python3 tools/build_grimm_public_domain_fb2.py '
          '--output apps/story_reader/test/fixtures/grimm_ci.fb2 '
          '--manifest apps/story_reader/test/fixtures/grimm_ci.json; '
          'then export AI_RPG_GRIMM_PUBLIC_FB2_PATH and '
          'AI_RPG_GRIMM_PUBLIC_MANIFEST_PATH. CI must fail, not SKIP.');
    }
    final bytes = await File(sourceFile).readAsBytes();
    manifest = jsonDecode(await File(metaFile).readAsString())
        as Map<String, dynamic>;
    expect(manifest['gutenberg_id'], 2591);
    expect(manifest['tales'], 62);
    expect(manifest['paragraphs'] as int, greaterThan(500));
    expect(manifest['source_chars'] as int, greaterThan(280000));
    expect(sha256.convert(bytes).toString(), manifest['fb2_sha256']);
    imported = BookImporter.parse('full_original_grimm.fb2',
        Uint8List.fromList(bytes));
    index = BookSourceIndexer.index(imported);
  });

  test('REAL Grimm complete 62-tale FB2: chapters, full text and citations',
      () {
    expect(imported.title, contains("Grimms' Fairy Tales"));
    expect(imported.author, contains('Jacob Grimm'));
    expect(imported.author, contains('Wilhelm Grimm'));
    expect(imported.structuredChapters, hasLength(62));
    expect(imported.chapters, hasLength(62));
    expect(imported.structuredChapters.first.blocks.first.text,
        'THE GOLDEN BIRD');
    expect(imported.structuredChapters.last.blocks.first.text,
        'SNOW-WHITE AND ROSE-RED');
    expect(imported.chapters.first, contains('golden'));
    expect(imported.chapters.last, isNotEmpty);
    expect(imported.images, isEmpty); // historical text-only edition
    expect(index.chapterCount, 62);
    expect(index.indexedChapterCount, 62);
    expect(index.textIndexCoverage, 1.0);
    expect(index.indexedTextUtf16, greaterThan(280000));
    expect(index.chunks.length, greaterThan(500));
    expect(index.chunks.every((chunk) =>
        chunk.text.isNotEmpty && chunk.chapterIndex < 62 &&
        chunk.startUtf16 < chunk.endUtf16), isTrue);
    final lastChapter = index.chunks.where((c) => c.chapterIndex == 61);
    expect(lastChapter, isNotEmpty);
    expect(index.canPublishBookworld, isFalse);
    final windows = SourceSemanticWindowPlanner.plan(index);
    expect(windows.length, greaterThan(70));
    expect(windows.expand((w) => w.chunks).length, index.chunks.length);
    for (final window in windows) {
      expect(window.utf16Length,
          lessThanOrEqualTo(SourceSemanticWindowPlanner.maxWindowUtf16));
      expect(window.utf8Length,
          lessThanOrEqualTo(SourceSemanticWindowPlanner.maxWindowUtf8));
      expect(window.chunks.map((c) => c.chapterIndex).toSet().length, 1);
    }
    final reviewQueue = ZaiWindowReviewQueue.empty(index);
    expect(reviewQueue.completedCount, 0);
    expect(reviewQueue.pendingCount, windows.length);
    expect(reviewQueue.canPublishBookworld, false);
    final restored = ZaiWindowReviewQueue.decode(index, reviewQueue.encode());
    expect(restored.pendingCount, windows.length);
    expect(restored.candidateCount, 0);
    // M2f3c must stay empty on a full real book unless actual cloud
    // candidates were separately approved by the reader. No guessing
    // aliases, facts or timeline from the title or from book length.
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(restored);
    expect(graph.reviewed, isEmpty);
    expect(ZaiConsistencyHints.reviewCues(graph), isEmpty);
    final editorial = ZaiEditorialConsistencyNotebook.empty(graph);
    expect(editorial.canPublishBookworld, false);
    expect(ZaiEditorialConsistencyNotebook.decode(
        graph, editorial.encode()).questions, isEmpty);
  });

  test('REAL Grimm full-book offline preparation, checkpoint/resume and '
      'private library reopen', () async {
    final names = MemorySourceAnalysisCheckpointRepository();
    final narrative = MemorySourceAnalysisCheckpointRepository();
    final catalog = MemorySourceAnalysisCheckpointRepository();
    final coordinator = OfflinePreparationCoordinator(
      mentionsRepository: names,
      narrativeRepository: narrative,
      catalogRepository: catalog,
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
    expect(result.narrative, isNotNull);
    expect(result.catalog, isNotNull);
    expect(result.narrative!.scannedChunks, index.chunks.length);
    expect(result.canPublishBookworld, isFalse);
    // The rule-only Russian semantic scanner may find few English mentions.
    // This is a *real input and pipeline* acceptance, NOT a claim of correct
    // canonical plot extraction or a playable RPG.
    for (final fact in result.narrative!.graph.records) {
      fact.validate(index);
      expect(fact.status, EvidenceStatus.inferred);
    }
    final sourceFingerprint = index.sourceFingerprint;
    expect(await narrative.read(sourceFingerprint),
        result.narrative!.encode());
    expect(await catalog.read(sourceFingerprint),
        result.catalog!.encode());
    final resumed = await coordinator.run(index);
    expect(resumed.complete, true);
    expect(resumed.catalog!.encode(), result.catalog!.encode());

    final temp = await Directory.systemTemp.createTemp('grimm-full-fb2-');
    try {
      final library = BookStorage(rootDirectory: () async => temp);
      await library.add(imported);
      final scan = await library.scan();
      expect(scan.unreadableCount, 0);
      expect(scan.books, hasLength(1));
      final reopened = scan.books.single.book;
      expect(reopened.structuredChapters.length, 62);
      expect(reopened.chapters.length, 62);
      expect(BookSourceIndexer.index(reopened).sourceFingerprint,
          sourceFingerprint);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
