import 'dart:async';

import 'book_isolate_workers.dart';
import 'book_source_analysis.dart';
import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_semantic_catalog.dart';
import 'story_evidence_review_session.dart';
import 'source_evidence_graph.dart';

enum OfflinePreparationStage {
  names,
  narrative,
  semantics,
  completed,
  paused,
}

class OfflinePreparationProgress {
  const OfflinePreparationProgress({
    required this.stage,
    required this.completed,
    required this.total,
    this.mentions,
    this.narrative,
    this.catalog,
  });

  final OfflinePreparationStage stage;
  final int completed;
  final int total;
  final SourceAnalysisSession? mentions;
  final StoryEvidenceReviewSession? narrative;
  final SourceSemanticCatalog? catalog;

  double get fraction => total == 0 ? 0 : completed / total;
  bool get canPublishBookworld => false;
}

class OfflinePreparationResult {
  const OfflinePreparationResult({
    required this.mentions,
    this.narrative,
    this.catalog,
    required this.paused,
  });

  final SourceAnalysisSession mentions;
  final StoryEvidenceReviewSession? narrative;
  final SourceSemanticCatalog? catalog;
  final bool paused;
  bool get canPublishBookworld => false;
  bool get complete => !paused &&
      mentions.pendingCount == 0 &&
      mentions.failedCount == 0 &&
      narrative != null && catalog != null;
}

/// One-click sequential preparation, but ONLY with local deterministic rules.
///
/// Every batch saves to the existing private source scope BEFORE reporting
/// progress; closing the page pauses between batches and retains checkpoints.
/// Corrupt checkpoints are never overwritten silently. The source book,
/// existing user decisions and campaign saves are not modified.
///
/// Platform work is on top-level compute workers, not Flutter State closures.
class OfflinePreparationCoordinator {
  const OfflinePreparationCoordinator({
    required this.mentionsRepository,
    required this.narrativeRepository,
    required this.catalogRepository,
    this.mentionsProcessor,
    this.narrativeProcessor,
    this.catalogProcessor,
    this.mentionsEncoder,
    this.mentionsDecoder,
    this.narrativeEncoder,
    this.narrativeDecoder,
    this.catalogDecoder,
  });

  final SourceAnalysisCheckpointRepository mentionsRepository;
  final SourceAnalysisCheckpointRepository narrativeRepository;
  final SourceAnalysisCheckpointRepository catalogRepository;

  /// Test seams avoid real isolate waits in WidgetTester FakeAsync.
  final Future<SourceAnalysisSession> Function(
      BookSourceIndex, SourceAnalysisSession)? mentionsProcessor;
  final Future<StoryEvidenceReviewSession> Function(
      BookSourceIndex, StoryEvidenceReviewSession)? narrativeProcessor;
  final Future<SourceSemanticCatalog> Function(
      BookSourceIndex, SourceEvidenceGraph)? catalogProcessor;
  final Future<String> Function(SourceAnalysisSession)? mentionsEncoder;
  final Future<SourceAnalysisSession> Function(
      BookSourceIndex, String)? mentionsDecoder;
  final Future<String> Function(StoryEvidenceReviewSession)? narrativeEncoder;
  final Future<StoryEvidenceReviewSession> Function(
      BookSourceIndex, String)? narrativeDecoder;
  final Future<SourceSemanticCatalog> Function(
      BookSourceIndex, SourceEvidenceGraph, String)? catalogDecoder;

  Future<OfflinePreparationResult> run(
    BookSourceIndex index, {
    bool Function()? shouldPause,
    void Function(OfflinePreparationProgress)? onProgress,
  }) async {
    bool paused() => shouldPause?.call() ?? false;
    final fingerprint = index.sourceFingerprint;
    final mentionsRaw = await mentionsRepository.read(fingerprint);
    var names = mentionsRaw == null
        ? SourceAnalysisSession.create(index)
        : mentionsDecoder == null
            ? await decodeSourceAnalysisInWorker(index, mentionsRaw)
            : await mentionsDecoder!(index, mentionsRaw);
    void notify(OfflinePreparationStage stage, int done, int total, {
      StoryEvidenceReviewSession? narrative,
      SourceSemanticCatalog? catalog,
    }) {
      onProgress?.call(OfflinePreparationProgress(
        stage: stage, completed: done, total: total,
        mentions: names, narrative: narrative, catalog: catalog,
      ));
    }
    notify(OfflinePreparationStage.names, names.processedCount,
        index.chunks.length);

    while (names.pendingCount > 0) {
      if (paused()) {
        notify(OfflinePreparationStage.paused, names.processedCount,
            index.chunks.length);
        return OfflinePreparationResult(mentions: names, paused: true);
      }
      final next = mentionsProcessor == null
          ? await processSourceBatchInWorker(index, names, limit: 24)
          : await mentionsProcessor!(index, names);
      if (next.sourceFingerprint != fingerprint ||
          next.processedCount <= names.processedCount ||
          next.processedCount > index.chunks.length) {
        throw const FormatException('Локальный поиск не продвинулся');
      }
      final encoded = mentionsEncoder == null
          ? await encodeSourceAnalysisInWorker(next)
          : await mentionsEncoder!(next);
      // Roundtrip verification catches invalid injected workers before writes.
      SourceAnalysisSession.decode(index, encoded);
      await mentionsRepository.write(fingerprint, encoded);
      names = next;
      notify(OfflinePreparationStage.names, names.processedCount,
          index.chunks.length);
      await Future<void>.delayed(Duration.zero);
    }
    if (names.failedCount > 0) {
      throw const FormatException(
          'Остались ошибочные фрагменты поиска имён, нужен явный повтор');
    }
    if (paused()) {
      notify(OfflinePreparationStage.paused,
          names.processedCount, index.chunks.length);
      return OfflinePreparationResult(mentions: names, paused: true);
    }

    final narrativeRaw = await narrativeRepository.read(fingerprint);
    var story = narrativeRaw == null
        ? StoryEvidenceReviewSession.create(index)
        : narrativeDecoder == null
            ? await decodeNarrativeEvidenceInWorker(index, narrativeRaw)
            : await narrativeDecoder!(index, narrativeRaw);
    // Existing accepted mentions are preserved, not auto-promoted to canon.
    final synced = story.syncAcceptedMentions(index, names);
    if (!identical(story, synced)) {
      final raw = narrativeEncoder == null
          ? await encodeNarrativeEvidenceInWorker(synced)
          : await narrativeEncoder!(synced);
      StoryEvidenceReviewSession.decode(index, raw);
      await narrativeRepository.write(fingerprint, raw);
      story = synced;
    }
    notify(OfflinePreparationStage.narrative,
        story.scannedChunks, index.chunks.length, narrative: story);

    while (story.scannedChunks < index.chunks.length) {
      if (paused()) {
        notify(OfflinePreparationStage.paused, story.scannedChunks,
            index.chunks.length, narrative: story);
        return OfflinePreparationResult(
            mentions: names, narrative: story, paused: true);
      }
      final next = narrativeProcessor == null
          ? await scanNarrativeEvidenceInWorker(index, story, limit: 24)
          : await narrativeProcessor!(index, story);
      if (next.sourceFingerprint != fingerprint ||
          next.scannedChunks <= story.scannedChunks ||
          next.scannedChunks > index.chunks.length) {
        throw const FormatException('Неверный результат анализа событий');
      }
      final encoded = narrativeEncoder == null
          ? await encodeNarrativeEvidenceInWorker(next)
          : await narrativeEncoder!(next);
      StoryEvidenceReviewSession.decode(index, encoded);
      await narrativeRepository.write(fingerprint, encoded);
      story = next;
      notify(OfflinePreparationStage.narrative,
          story.scannedChunks, index.chunks.length, narrative: story);
      await Future<void>.delayed(Duration.zero);
    }
    if (paused()) {
      notify(OfflinePreparationStage.paused, story.scannedChunks,
          index.chunks.length, narrative: story);
      return OfflinePreparationResult(
          mentions: names, narrative: story, paused: true);
    }

    notify(OfflinePreparationStage.semantics, 0, 1, narrative: story);
    final proposed = catalogProcessor == null
        ? await buildSourceSemanticCatalogInWorker(index, story.graph)
        : await catalogProcessor!(index, story.graph);
    if (proposed.sourceFingerprint != fingerprint ||
        proposed.canPublishBookworld) {
      throw const FormatException('Недопустимый смысловой каталог');
    }
    final canonical = proposed.encode();
    final checked = SourceSemanticCatalog.decode(index, story.graph, canonical);
    final old = await catalogRepository.read(fingerprint);
    if (old != null) {
      // Corrupt/stale catalog must not be overwritten without explicit reset.
      final restored = catalogDecoder == null
          ? await decodeSourceSemanticCatalogInWorker(index, story.graph, old)
          : await catalogDecoder!(index, story.graph, old);
      if (restored.encode() != old) {
        throw const FormatException('Повреждена сохранённая семантика');
      }
    }
    if (old != canonical) {
      await catalogRepository.write(fingerprint, canonical);
    }
    notify(OfflinePreparationStage.completed, 1, 1,
        narrative: story, catalog: checked);
    return OfflinePreparationResult(
        mentions: names, narrative: story, catalog: checked, paused: false);
  }
}
