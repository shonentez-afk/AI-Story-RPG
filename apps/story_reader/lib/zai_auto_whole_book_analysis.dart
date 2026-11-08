import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_semantic_window.dart';
import 'zai_semantic_preview.dart';
import 'package:story_authoring/bookwide_semantic_authoring.dart';

export 'package:story_authoring/bookwide_semantic_authoring.dart'
    show ZaiWholeBookConsentManifest, ZaiWholeBookProgress,
         ZaiWholeBookReviewResult, PortableWholeBookAnalyzer;

/// Existing model-specific preview seam remains app-only.
typedef ZaiWholeBookPreview = Future<ZaiSemanticPreviewResult> Function(
    BookSourceIndex index,
    SourceSemanticWindow window,
    ZaiPreviewCancellation token,
    bool includeTitle);

/// The Z.ai app adapter owns credentials, HTTP, device checkpoint storage
/// and cancellation. ALL full-book windows, consent scope, source checks,
/// replay and progress now run in the shared pure Dart coordinator.
class ZaiAutoWholeBookAnalysis {
  ZaiAutoWholeBookAnalysis({
    SourceAnalysisCheckpointRepository? repository,
    ZaiSemanticPreviewService? service,
    ZaiWholeBookPreview? preview,
  }) : repository = repository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.zaiAutoWholeBookReview),
       service = service ?? ZaiSemanticPreviewService(),
       previewOverride = preview;

  final SourceAnalysisCheckpointRepository repository;
  final ZaiSemanticPreviewService service;
  final ZaiWholeBookPreview? previewOverride;

  PortableWholeBookAnalyzer _portable(ZaiPreviewCancellation token) =>
      PortableWholeBookAnalyzer(
        readCheckpoint: repository.read,
        writeCheckpoint: repository.write,
        preview: (index, window, includeTitle) async =>
            previewOverride != null
              ? previewOverride!(index, window, token, includeTitle)
              : service.preview(
                  index: index, chunk: window.chunks.first,
                  window: window, consentForThisChunk: true,
                  consentForBookTitle: includeTitle, cancellation: token),
      );

  Future<ZaiWholeBookReviewResult> read(BookSourceIndex index) =>
      _portable(ZaiPreviewCancellation()).read(index);

  Future<ZaiWholeBookReviewResult> analyze({
    required BookSourceIndex index,
    required String approvedManifestDigest,
    required bool explicitWholeBookConsent,
    bool consentForBookTitle = false,
    int maxWindowsPerRun = 16,
    ZaiPreviewCancellation? cancellation,
    void Function(ZaiWholeBookProgress progress)? onProgress,
  }) {
    final token = cancellation ?? ZaiPreviewCancellation();
    return _portable(token).analyze(
      index: index,
      approvedManifestDigest: approvedManifestDigest,
      explicitWholeBookConsent: explicitWholeBookConsent,
      consentForBookTitle: consentForBookTitle,
      maxWindowsPerRun: maxWindowsPerRun,
      checkCancelled: token.check,
      onProgress: onProgress,
    );
  }
}
