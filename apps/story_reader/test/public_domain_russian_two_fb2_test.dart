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
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:ai_story_reader/zai_source_scene_board.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// TWO distinct, complete original Russian folk tales; NOT a fake translated
/// Grimm corpus or the user's private FB2. Each exact source is independently
/// retrieved and hashed in the CI runner. A failed source fetch FAILS CI.
///
/// This verifies import, offline source processing, resumability, uniqueness
/// and library reopen. Literary CANON and a playable RPG still require
/// checked events, actor roles, choices and explicit source review.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final specs = <({
    String id, String pathEnv, String metaEnv,
    String title, int chapters, String marker,
  })>[
    (
      id: 'morozko',
      pathEnv: 'AI_RPG_RU_MOROZKO_FB2_PATH',
      metaEnv: 'AI_RPG_RU_MOROZKO_MANIFEST_PATH',
      title: 'Морозко', chapters: 2, marker: 'старик',
    ),
    (
      id: 'frog_princess',
      pathEnv: 'AI_RPG_RU_FROG_PRINCESS_FB2_PATH',
      metaEnv: 'AI_RPG_RU_FROG_PRINCESS_MANIFEST_PATH',
      title: 'Царевна-лягушка', chapters: 3, marker: 'Иван',
    ),
  ];
  final books = <ImportedBook>[];
  final indices = <BookSourceIndex>[];
  final manifests = <Map<String, dynamic>>[];

  setUpAll(() async {
    for (final spec in specs) {
      final file = Platform.environment[spec.pathEnv];
      final meta = Platform.environment[spec.metaEnv];
      if (file == null || meta == null || file.isEmpty || meta.isEmpty) {
        throw StateError('Two mandatory original Russian FB2 missing: '
            'run tools/build_russian_public_domain_fb2.py '
            '--output-dir test/fixtures/ru_afanasyev; '
            'never skip or replace with a fabricated fairy tale.');
      }
      final bytes = await File(file).readAsBytes();
      final info = jsonDecode(await File(meta).readAsString())
          as Map<String, dynamic>;
      expect(info['book'], spec.id);
      expect(info['title'], spec.title);
      expect(info['language'], 'ru');
      expect(info['chapters'], spec.chapters);
      expect(info['status'], 'BOOK_ONLY_NOT_PLAYABLE');
      expect(info['ai_calls'], 0);
      expect(info['source_sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(sha256.convert(bytes).toString(), info['fb2_sha256']);
      expect(info['source_chars'] as int, greaterThan(1500));
      expect(info['paragraphs'] as int, greaterThan(5));

      final book = BookImporter.parse(spec.id + '.fb2',
          Uint8List.fromList(bytes));
      expect(book.title, spec.title);
      expect(book.structuredChapters, hasLength(spec.chapters));
      expect(book.chapters, hasLength(spec.chapters));
      expect(book.chapters.join(' '), contains(spec.marker));
      expect(book.structuredChapters.first.blocks.length,
          greaterThan(2));
      final index = BookSourceIndexer.index(book);
      expect(index.chapterCount, spec.chapters);
      expect(index.indexedChapterCount, spec.chapters);
      expect(index.textIndexCoverage, 1.0);
      expect(index.canPublishBookworld, isFalse);
      expect(SourceSemanticWindowPlanner.plan(index), isNotEmpty);
      books.add(book);
      indices.add(index);
      manifests.add(info);
    }
    expect(indices[0].sourceFingerprint,
        isNot(indices[1].sourceFingerprint));
    expect(manifests[0]['source_sha256'],
        isNot(manifests[1]['source_sha256']));
  });

  test('TWO real original Russian FB2 stay independent and cannot be '
      'silently promoted into playable canonical worlds', () {
    for (final index in indices) {
      final queue = ZaiWindowReviewQueue.empty(index);
      expect(queue.results, isEmpty);
      final graph = ZaiCrossWindowEvidenceGraph.fromQueue(queue);
      final board = ZaiSourceSceneBoard.empty(graph);
      expect(board.scenes, isEmpty);
      expect(index.canPublishBookworld, isFalse);
    }
  });

  test('TWO different authentic Russian books: complete offline scan, '
      'durable source-locked checkpoint and exact-edition Resume', () async {
    for (final index in indices) {
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
      final first = await coordinator.run(index);
      expect(first.paused, isFalse);
      expect(first.complete, isTrue);
      expect(first.canPublishBookworld, isFalse);
      expect(first.mentions.processedCount, index.chunks.length);
      expect(first.narrative!.scannedChunks, index.chunks.length);
      for (final fact in first.narrative!.graph.records) {
        fact.validate(index);
        expect(fact.status, EvidenceStatus.inferred,
            reason: 'Automated source proposals are not literary canon');
      }
      final stored = await narrative.read(index.sourceFingerprint);
      expect(stored, first.narrative!.encode());
      final repeated = await coordinator.run(index);
      expect(repeated.complete, isTrue);
      expect(repeated.catalog!.encode(), first.catalog!.encode());
      expect(await catalog.read(index.sourceFingerprint),
          first.catalog!.encode());
    }
  });

  test('both Russian source editions survive a two-book private library '
      'reopen with stable independent fingerprints', () async {
    final dir = await Directory.systemTemp.createTemp('rpg-ru-fb2-two-');
    try {
      final storage = BookStorage(rootDirectory: () async => dir);
      for (final book in books) {
        await storage.add(book);
      }
      final reloaded = await storage.scan();
      expect(reloaded.unreadableCount, 0);
      expect(reloaded.books, hasLength(2));
      final ids = reloaded.books.map((b) =>
          BookSourceIndexer.index(b.book).sourceFingerprint).toSet();
      expect(ids, indices.map((i) => i.sourceFingerprint).toSet());
      expect(reloaded.books.map((b) => b.book.title).toSet(),
          {'Морозко', 'Царевна-лягушка'});
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
