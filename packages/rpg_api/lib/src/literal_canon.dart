part of '../rpg_api.dart';

/// A source-literal CANON route, not a model's statement about a book's
/// literary truth. Every source text chunk must survive exactly once in
/// sequence. This remains private and offline after creation.
final class RpgCanonPreview {
  const RpgCanonPreview({
    required this.title, required this.author,
    required this.sourceFingerprint, required this.approvalDigest,
    required this.chapterCount, required this.chunkCount,
    required this.requiresMediaReview,
  });
  final String title, author, sourceFingerprint, approvalDigest;
  final int chapterCount, chunkCount;
  final bool requiresMediaReview;
  bool get canCompile => !requiresMediaReview &&
      chunkCount >= 1 && chunkCount <= 5000;

  Map<String, Object?> toJson() => {
    'title': title, 'author': author,
    'source_fingerprint': sourceFingerprint,
    'approval_digest': approvalDigest,
    'chapters_total': chapterCount, 'chunks_total': chunkCount,
    'can_compile_literal_canon': canCompile,
    'requires_media_review': requiresMediaReview,
    'semantic_literary_truth_automatically_verified': false,
    'full_source_literal_text': true,
    'dynamic_private_ai_interludes': true,
  };
}

abstract interface class RpgLiteralCanonApi {
  RpgCanonPreview prepare(String filename, Uint8List bytes);
  RpgCanonPreview prepareIndex(BookSourceIndex index);
  Uint8List compileIndex(BookSourceIndex index, {
    required String approvedDigest, required bool userConfirmed,
  });
  Uint8List compile({
    required String filename, required Uint8List bytes,
    required String approvedDigest, required bool userConfirmed,
  });
}

final class LocalRpgLiteralCanonApi implements RpgLiteralCanonApi {
  const LocalRpgLiteralCanonApi();

  static ({RpgCanonPreview preview, Map<String, dynamic> index}) _indexed(
      String filename, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Book source exceeds the private budget');
    }
    final book = BookImporter.parse(filename, bytes);
    final index = BookSourceIndexer.index(book);
    final raw = Map<String, dynamic>.from(index.toJson());
    final digest = ReviewedLiteralCanonBookworldWriter.approvalDigest(
        sourceIndex: raw, title: index.title, author: index.author);
    return (
      preview: RpgCanonPreview(
        title: index.title, author: index.author,
        sourceFingerprint: index.sourceFingerprint,
        approvalDigest: digest,
        chapterCount: index.chapterCount,
        chunkCount: index.chunks.length,
        requiresMediaReview: index.unindexedMediaBlocks != 0),
      index: raw,
    );
  }

  static RpgCanonPreview _previewIndex(BookSourceIndex index) {
    final raw = Map<String, dynamic>.from(index.toJson());
    return RpgCanonPreview(
      title: index.title, author: index.author,
      sourceFingerprint: index.sourceFingerprint,
      approvalDigest: ReviewedLiteralCanonBookworldWriter.approvalDigest(
          sourceIndex: raw, title: index.title, author: index.author),
      chapterCount: index.chapterCount,
      chunkCount: index.chunks.length,
      requiresMediaReview: index.unindexedMediaBlocks != 0 ||
          index.indexedChapterCount != index.chapterCount ||
          index.indexedTextUtf16 != index.totalTextUtf16,
    );
  }

  @override
  RpgCanonPreview prepareIndex(BookSourceIndex index) => _previewIndex(index);

  @override
  Uint8List compileIndex(BookSourceIndex index, {
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    final preview = _previewIndex(index);
    if (!preview.canCompile || !userConfirmed ||
        approvedDigest != preview.approvalDigest) {
      throw const FormatException(
          'Cannot compile changed or incompletely indexed book');
    }
    final archive = const ReviewedLiteralCanonBookworldWriter().build(
      sourceIndex: Map<String, dynamic>.from(index.toJson()),
      title: preview.title, author: preview.author,
      approvedDigest: approvedDigest,
      userConfirmed: true,
    );
    final verified = const RichPrivateBookworldImporter().inspect(archive);
    if (!verified.sourceLiteralCanonVerified ||
        verified.sourceFingerprint != preview.sourceFingerprint ||
        verified.blueprint.scenes.length != preview.chunkCount ||
        verified.sourceChaptersTotal != preview.chapterCount) {
      throw const FormatException('Reviewed literary route not preserved');
    }
    return archive;
  }

  @override
  RpgCanonPreview prepare(String filename, Uint8List bytes) =>
      _indexed(filename, bytes).preview;

  @override
  Uint8List compile({
    required String filename, required Uint8List bytes,
    required String approvedDigest, required bool userConfirmed,
  }) {
    final book = BookImporter.parse(filename, bytes);
    final index = BookSourceIndexer.index(book);
    return compileIndex(index,
        approvedDigest: approvedDigest,
        userConfirmed: userConfirmed);
  }
}
