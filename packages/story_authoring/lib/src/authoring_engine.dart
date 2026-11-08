import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';

import 'book_import.dart';
import 'book_source_index.dart';

/// Exact original book + UTF-16 source evidence index. Not a scenario or
/// certification of literary meaning. No cloud/model is called here.
class SourceLockedBook {
  const SourceLockedBook._(this.book, this.index);
  final ImportedBook book;
  final BookSourceIndex index;

  /// Exact immutable edition ID shared by every client and checkpoint.
  String get sourceFingerprint => index.sourceFingerprint;

  bool get hasCompleteText => index.chapterCount > 0 &&
      index.indexedChapterCount == index.chapterCount &&
      index.textIndexCoverage == 1;

  /// Safe status for CLI. Never print the private book's chunk contents.
  Map<String, Object?> get status => {
    'stage': 'SOURCE_INDEX_ONLY',
    'source_fingerprint': index.sourceFingerprint,
    'title': index.title,
    'author': index.author,
    'chapters': index.chapterCount,
    'indexed_chapters': index.indexedChapterCount,
    'text_utf16': index.totalTextUtf16,
    'chunks': index.chunks.length,
    'media_blocks_for_review': index.unindexedMediaBlocks,
    'source_complete': hasCompleteText,
    'scenario_reviewed': false,
    'full_book_rpg_ready': false,
    'requires_cloud': false,
  };
}

/// Standalone authoring entry. Calls the EXISTING rich-v3 compiler and its
/// independent importer. Model proposals never bypass source or core checks.
class BookAuthoringEngine {
  const BookAuthoringEngine();

  SourceLockedBook parseAndIndex(String filename, Uint8List bytes,
      {int maxChunkUtf16 = BookSourceIndexer.defaultMaxChunkUtf16}) =>
    indexImported(BookImporter.parse(filename, bytes),
        maxChunkUtf16: maxChunkUtf16);

  /// Flutter reuses an already loaded ImportedBook without changing types,
  /// source chunks, offsets or source fingerprint.
  SourceLockedBook indexImported(ImportedBook book,
      {int maxChunkUtf16 = BookSourceIndexer.defaultMaxChunkUtf16}) =>
    SourceLockedBook._(book, BookSourceIndexer.index(
        book, maxChunkUtf16: maxChunkUtf16));

  Uint8List buildReviewedPrivateWorld({
    required SourceLockedBook source,
    required Map<String, dynamic> blueprint,
    required Map<String, dynamic> provenance,
    /// Explicit opt-in to reviewed extended v4; v3 remains the default.
    bool expanded = false,
  }) {
    final index = source.index;
    if (!source.hasCompleteText ||
        blueprint['source_fingerprint'] != index.sourceFingerprint ||
        provenance['source_fingerprint'] != index.sourceFingerprint ||
        provenance['source_title'] != index.title ||
        provenance['source_author'] != index.author ||
        provenance['source_chapters_total'] != index.chapterCount ||
        provenance['source_chapters_indexed'] != index.indexedChapterCount) {
      throw const FormatException(
          'Авторский проект не привязан к полной исходной редакции книги');
    }
    final proof = StoryBlueprint.fromJson(blueprint);
    if (proof.rightsStatus != 'private_adaptation' ||
        proof.sourceFingerprint != index.sourceFingerprint) {
      throw const FormatException('Нужна проверенная частная адаптация книги');
    }
    final bytes = const RichPrivateBookworldWriter().build(
      blueprint: blueprint,
      provenance: provenance,
      sourceIndex: Map<String, dynamic>.from(index.toJson()),
      expanded: expanded,
    );
    final verified = const RichPrivateBookworldImporter().inspect(bytes);
    if (verified.sourceFingerprint != index.sourceFingerprint ||
        verified.blueprint.blueprintHash != proof.blueprintHash ||
        verified.requiresNetwork || verified.canDistributePublicly ||
        verified.formatVersion != (expanded ? 4 : 3)) {
      throw const FormatException(
          'Автономная сборка не прошла независимую проверку');
    }
    return bytes;
  }

  VerifiedRichPrivateBookworld inspectPrivateWorld(Uint8List bytes) =>
      const RichPrivateBookworldImporter().inspect(bytes);
}
