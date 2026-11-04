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
import 'package:ai_story_reader/zai_source_scene_board.dart';
import 'package:ai_story_reader/zai_causal_choice_notebook.dart';
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

  test('REAL one-tale Frog-Prince FB2 is importable and source-locked',
      () async {
    final file = Platform.environment['AI_RPG_FROG_PRINCE_FB2_PATH'];
    final meta = Platform.environment['AI_RPG_FROG_PRINCE_MANIFEST_PATH'];
    if (file == null || meta == null || file.isEmpty || meta.isEmpty) {
      throw StateError('Mandatory standalone Frog-Prince CI fixture missing.');
    }
    final bytes = await File(file).readAsBytes();
    final info = jsonDecode(await File(meta).readAsString())
        as Map<String, dynamic>;
    expect(info['gutenberg_id'], 2591);
    expect(info['tale'], 'THE FROG-PRINCE');
    expect(info['chapters'], 1);
    expect(info['corpus_fb2_sha256'], manifest['fb2_sha256']);
    expect(sha256.convert(bytes).toString(), info['fb2_sha256']);
    final single = BookImporter.parse('frog_prince_grimm.fb2',
        Uint8List.fromList(bytes));
    expect(single.structuredChapters, hasLength(1));
    expect(single.chapters, hasLength(1));
    expect(single.structuredChapters.single.blocks.first.text,
        'THE FROG-PRINCE');
    expect(single.chapters.single, contains('frog'));
    expect(single.chapters.single, isNot(contains('THE GOLDEN BIRD')));
    final indexed = BookSourceIndexer.index(single);
    expect(indexed.chapterCount, 1);
    expect(indexed.indexedChapterCount, 1);
    expect(indexed.textIndexCoverage, 1.0);
    // This is only a source book, not a generated or playable world.
    expect(indexed.canPublishBookworld, false);
    expect(SourceSemanticWindowPlanner.plan(indexed), isNotEmpty);
    final queue = ZaiWindowReviewQueue.empty(indexed);
    expect(queue.results, isEmpty);
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
    final board = ZaiSourceSceneBoard.empty(graph);
    expect(board.scenes, isEmpty);
    expect(ZaiCausalChoiceNotebook.empty(board).choices, isEmpty);
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
    final storyboard = ZaiSourceSceneBoard.empty(graph);
    expect(storyboard.scenes, isEmpty);
    expect(storyboard.contexts, isEmpty);
    expect(ZaiSourceSceneBoard.decode(graph, storyboard.encode())
        .scenes, isEmpty);
    final sourcePreflight = ZaiScenePreflight.assess(
        reviewQueue, storyboard, consistency: editorial);
    expect(sourcePreflight.canStartPlayableRpg, false);
    expect(sourcePreflight.totalEvents, 0);
    expect(sourcePreflight.findings.map((e) => e.issue),
        contains(ZaiSceneGateIssue.unfinishedWindows));
    // M2f3e: full real FB2 cannot automatically invent player decisions,
    // source truth, NPC secrets, or a playable BookWorld without manual edits.
    final causal = ZaiCausalChoiceNotebook.empty(storyboard);
    expect(causal.flags, isEmpty);
    expect(causal.choices, isEmpty);
    expect(ZaiCausalChoiceNotebook.decode(
        storyboard, causal.encode()).choices, isEmpty);
    final causalReport = ZaiCausalPreflight.assess(
        reviewQueue, causal, consistency: editorial);
    expect(causalReport.canCompileBookworld, false);
    expect(causalReport.canStartPlayableRpg, false);
    expect(causalReport.blockers,
        contains(ZaiCausalBlocker.emptySourceScenes));
    expect(causalReport.blockers,
        contains(ZaiCausalBlocker.unfinishedSourceReview));
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
