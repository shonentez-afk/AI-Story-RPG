import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'source_semantic_window.dart';
import 'semantic_preview_models.dart';
import 'source_semantic_provider.dart';
import 'zai_semantic_review_queue.dart';

/// Explicit permission covers a FINGERPRINTED list of the exact source
/// windows selected from this particular local book. The consent UI must show
/// the title, total chapters, number of windows and that these full pieces
/// will be sent to Z.ai; it must offer cancellation before any POST.
///
/// This is not implied by a saved API key or by enabling cloud preferences.
class ZaiWholeBookConsentManifest {
  ZaiWholeBookConsentManifest._({
    required this.sourceFingerprint,
    required this.bookTitle,
    required this.bookAuthor,
    required this.chapters,
    required this.approvalDigest,
    required this.sourceUtf8Bytes,
    required Map<int, SourceSemanticWindow> windows,
  }) : windows = Map.unmodifiable(windows);

  final String sourceFingerprint;
  final String bookTitle;
  final String bookAuthor;
  final int chapters;
  final String approvalDigest;
  /// Minimum plain payload size; API and JSON protocol overhead is extra.
  final int sourceUtf8Bytes;
  final Map<int, SourceSemanticWindow> windows;

  int get plannedRequests => windows.length;
  int get modelMaximumAttempts => windows.length *
      SemanticPreviewWireContract.maxAttempts;

  static ZaiWholeBookConsentManifest fromIndex(BookSourceIndex index) {
    if (index.chapterCount <= 0 ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        index.title.trim().isEmpty) {
      throw const FormatException(
          'Нельзя отправлять неполную или неиндексированную книгу.');
    }
    final queue = ZaiWindowReviewQueue.empty(index);
    final windows = <int, SourceSemanticWindow>{
      for (var i = 0; i < queue.windows.length; i++)
        if (queue.windows[i].hasNarrativeText) i: queue.windows[i],
    };
    if (windows.isEmpty || windows.length > 4096) {
      throw const FormatException(
          'Нет подходящих фрагментов или книга превышает лимит анализа.');
    }
    for (final window in windows.values) {
      SourceSemanticWindowPlanner.validate(index, window);
    }
    final sourceUtf8Bytes = windows.values.fold<int>(
        0, (sum, w) => sum + utf8.encode(w.displayText).length);
    final toHash = <String, Object>{
      'format': 'ai_story_book_wide_consent_m2g2_v1',
      'fingerprint': index.sourceFingerprint,
      'title': index.title,
      'author': index.author,
      'chapters': index.chapterCount,
      'windows': [
        for (final entry in windows.entries)
          {
            'position': entry.key,
            'chunks': [
              for (final chunk in entry.value.chunks)
                {
                  'id': chunk.id,
                  'sha256': chunk.sha256Text,
                  'start_utf16': chunk.startUtf16,
                  'end_utf16': chunk.endUtf16,
                },
            ],
          },
      ],
    };
    return ZaiWholeBookConsentManifest._(
      sourceFingerprint: index.sourceFingerprint,
      bookTitle: index.title,
      bookAuthor: index.author,
      chapters: index.chapterCount,
      sourceUtf8Bytes: sourceUtf8Bytes,
      windows: windows,
      approvalDigest:
          sha256.convert(utf8.encode(jsonEncode(toHash))).toString(),
    );
  }
}

class ZaiWholeBookProgress {
  const ZaiWholeBookProgress({
    required this.completed,
    required this.total,
    required this.candidates,
    required this.eventProposals,
  });
  final int completed;
  final int total;
  final int candidates;
  final int eventProposals;
  int get remaining => total - completed;
  bool get finished => completed == total;
}

/// The records contain only hypotheses (the original quote verifier remains
/// authoritative); none can become world canon, scenes or SQLite actions.
class ZaiWholeBookReviewResult {
  const ZaiWholeBookReviewResult({
    required this.manifest,
    required this.queue,
    required this.progress,
  });
  final ZaiWholeBookConsentManifest manifest;
  final ZaiWindowReviewQueue queue;
  final ZaiWholeBookProgress progress;

  bool get complete => progress.finished;
  bool get canCompileBookworld => false;
  bool get hasAcceptedCanon => false;
}


/// A provider-independent model port. The caller chooses local inference,
/// Z.ai or a test implementation and must make source disclosure explicit.
/// Every response is rechecked against exactly the original source chunks.
typedef PortableWholeBookWindowPreview = Future<ZaiSemanticPreviewResult>
    Function(BookSourceIndex index, SourceSemanticWindow window,
        bool includeBookTitle);

/// Persisted checkpoints remain local/private and may be provided by
/// filesystem, database or an in-memory unit test. Neither Flutter nor
/// HTTP is imported into this authoring orchestration.
typedef AuthoringCheckpointReader = Future<String?> Function(String sourceId);
typedef AuthoringCheckpointWriter = Future<void> Function(
    String sourceId, String checkedJson);

class PortableWholeBookAnalyzer {
  const PortableWholeBookAnalyzer({
    required this.readCheckpoint,
    required this.writeCheckpoint,
    required this.preview,
  });

  final AuthoringCheckpointReader readCheckpoint;
  final AuthoringCheckpointWriter writeCheckpoint;
  final PortableWholeBookWindowPreview preview;

  static ZaiWholeBookProgress progress(
      ZaiWindowReviewQueue queue, ZaiWholeBookConsentManifest manifest) {
    var completed = 0;
    for (final position in manifest.windows.keys) {
      if (queue.results.containsKey(position)) completed++;
    }
    final events = queue.allCandidates
        .where((c) => c.category == SemanticCategory.event).length;
    return ZaiWholeBookProgress(
      completed: completed, total: manifest.plannedRequests,
      candidates: queue.candidateCount, eventProposals: events,
    );
  }

  Future<ZaiWholeBookReviewResult> read(BookSourceIndex index) async {
    final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
    final raw = await readCheckpoint(index.sourceFingerprint);
    final queue = raw == null ? ZaiWindowReviewQueue.empty(index) :
        ZaiWindowReviewQueue.decode(index, raw);
    return ZaiWholeBookReviewResult(
      manifest: manifest, queue: queue,
      progress: progress(queue, manifest),
    );
  }

  /// Only the exact approved source window list can be processed, in bounded
  /// batches. A partial write or failed model response never counts as
  /// completed. A second invocation requires a NEW, explicit consent.
  Future<ZaiWholeBookReviewResult> analyze({
    required BookSourceIndex index,
    required String approvedManifestDigest,
    required bool explicitWholeBookConsent,
    bool consentForBookTitle = false,
    int maxWindowsPerRun = 16,
    void Function()? checkCancelled,
    void Function(ZaiWholeBookProgress progress)? onProgress,
  }) async {
    final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
    if (!explicitWholeBookConsent ||
        approvedManifestDigest != manifest.approvalDigest) {
      throw const FormatException(
          'Нет согласия на передачу именно этой книги в модель.');
    }
    if (maxWindowsPerRun < 1 || maxWindowsPerRun > 64) {
      throw RangeError.range(maxWindowsPerRun, 1, 64);
    }
    checkCancelled?.call();
    final saved = await read(index);
    var queue = saved.queue;
    checkCancelled?.call();
    var requests = 0;
    for (final entry in manifest.windows.entries) {
      if (requests >= maxWindowsPerRun) break;
      if (queue.results.containsKey(entry.key)) continue;
      checkCancelled?.call();
      final window = entry.value;
      // No unapproved neighboring piece is added to this model call.
      final proposal = await preview(index, window, consentForBookTitle);
      checkCancelled?.call();
      final next = queue.record(entry.key, proposal);
      await writeCheckpoint(index.sourceFingerprint, next.encode());
      queue = next;
      requests++;
      onProgress?.call(progress(queue, manifest));
    }
    return ZaiWholeBookReviewResult(
      manifest: manifest, queue: queue,
      progress: progress(queue, manifest),
    );
  }
}
