import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_import.dart';
import 'book_model.dart';

/// M2a: offline, deterministic *source indexing*, NOT AI interpretation
/// and NOT a playable BookWorld. All offsets are UTF-16 code-unit ranges in
/// their original parsed chapter/block. Exact chunk concatenation reproduces
/// every parsed text block, including whitespace and emoji.
class SourceChunk {
  const SourceChunk({
    required this.id,
    required this.chapterIndex,
    required this.chapterId,
    required this.blockIndex,
    required this.startUtf16,
    required this.endUtf16,
    required this.text,
    required this.sha256Text,
  });

  final String id;
  final int chapterIndex;
  final String chapterId;
  final int blockIndex;
  final int startUtf16;
  final int endUtf16;
  final String text;
  final String sha256Text;

  Map<String, Object> toJson() => {
    'id': id,
    'chapter_index': chapterIndex,
    'chapter_id': chapterId,
    'block_index': blockIndex,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    'text': text,
    'sha256_text': sha256Text,
    'analysis_status': 'PENDING',
  };
}

class SourceChapterCoverage {
  const SourceChapterCoverage({
    required this.chapterIndex,
    required this.chapterId,
    required this.totalUtf16,
    required this.indexedUtf16,
    required this.textBlocks,
    required this.imageBlocks,
    required this.sourceChunks,
  });

  final int chapterIndex;
  final String chapterId;
  final int totalUtf16;
  final int indexedUtf16;
  final int textBlocks;
  final int imageBlocks;
  final int sourceChunks;

  /// Text extraction does not equal semantic/story compilation.
  bool get fullyIndexed =>
      totalUtf16 > 0 && indexedUtf16 == totalUtf16;
  bool get hasUnindexedMedia => imageBlocks > 0;

  Map<String, Object> toJson() => {
    'chapter_index': chapterIndex,
    'chapter_id': chapterId,
    'text_utf16_total': totalUtf16,
    'text_utf16_indexed': indexedUtf16,
    'text_blocks': textBlocks,
    'media_blocks_for_review': imageBlocks,
    'source_chunks': sourceChunks,
    'text_indexed': fullyIndexed,
  };
}

class BookSourceIndex {
  const BookSourceIndex({
    required this.sourceFingerprint,
    required this.title,
    required this.author,
    required this.chapters,
    required this.chunks,
  });

  final String sourceFingerprint;
  final String title;
  final String author;
  final List<SourceChapterCoverage> chapters;
  final List<SourceChunk> chunks;

  int get chapterCount => chapters.length;
  int get indexedChapterCount =>
      chapters.where((chapter) => chapter.fullyIndexed).length;
  int get totalTextUtf16 =>
      chapters.fold(0, (sum, chapter) => sum + chapter.totalUtf16);
  int get indexedTextUtf16 =>
      chapters.fold(0, (sum, chapter) => sum + chapter.indexedUtf16);
  int get unindexedMediaBlocks =>
      chapters.fold(0, (sum, chapter) => sum + chapter.imageBlocks);

  /// Reports indexing only. No evidence supports any scene/game coverage yet.
  double get textIndexCoverage => totalTextUtf16 == 0
      ? 0 : indexedTextUtf16 / totalTextUtf16;
  double get gameplayCoverage => 0;
  bool get canPublishBookworld => false;

  Map<String, Object> toJson() => {
    'format': 'ai_story_source_index_v1',
    'schema_version': 1,
    'source_fingerprint': sourceFingerprint,
    'fingerprint_scope': 'normalized_parsed_content',
    'title': title,
    'author': author,
    'chapter_count': chapterCount,
    'indexed_chapter_count': indexedChapterCount,
    'text_indexed_utf16': indexedTextUtf16,
    'text_total_utf16': totalTextUtf16,
    'media_blocks_for_review': unindexedMediaBlocks,
    'gameplay_coverage': 0,
    'can_publish_bookworld': false,
    'stage': 'SOURCE_INDEX_ONLY',
    'chapters': chapters.map((x) => x.toJson()).toList(),
    'chunks': chunks.map((x) => x.toJson()).toList(),
  };
}

/// Local preprocessor shared by Android and Windows. It never reads secrets,
/// executes file content, publishes worlds, or sends books to the internet.
class BookSourceIndexer {
  const BookSourceIndexer._();
  static const defaultMaxChunkUtf16 = 4096;
  static const maxTextUtf16 = 20 * 1024 * 1024;
  static const maxChunks = 30000;

  static BookSourceIndex index(
    ImportedBook book, {int maxChunkUtf16 = defaultMaxChunkUtf16,
  }) {
    if (maxChunkUtf16 < 256 || maxChunkUtf16 > 12000) {
      throw const FormatException('Недопустимый размер фрагмента книги');
    }
    if (book.title.trim().isEmpty) {
      throw const FormatException('У книги отсутствует название');
    }
    final isStructured = book.structuredChapters.isNotEmpty;
    final count = isStructured
        ? book.structuredChapters.length : book.chapters.length;
    if (count == 0 || count > 10000) {
      throw const FormatException('Недопустимое количество глав');
    }

    final coverage = <SourceChapterCoverage>[];
    final chunks = <SourceChunk>[];
    final canonicalInput = <Object>[];
    var totalUtf16 = 0;

    for (var chapterIndex = 0; chapterIndex < count; chapterIndex++) {
      final chapterId = isStructured
          ? book.structuredChapters[chapterIndex].id
          : 'chapter_$chapterIndex';
      final blocks = isStructured
          ? book.structuredChapters[chapterIndex].blocks
          : <BookBlock>[BookBlock(
              kind: BookBlockKind.paragraph, text: book.chapters[chapterIndex],
            )];
      final canonicalBlocks = <Object>[];
      var textLength = 0;
      var indexedLength = 0;
      var textBlocks = 0;
      var imageBlocks = 0;
      final firstChunk = chunks.length;

      for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
        final block = blocks[blockIndex];
        canonicalBlocks.add({
          'kind': block.kind.name,
          'text': block.text,
          'resource_id': block.resourceId,
        });
        if (block.kind == BookBlockKind.image) {
          imageBlocks++;
          continue;
        }
        final text = block.text;
        if (text.isEmpty) continue;
        textBlocks++;
        textLength += text.length;
        totalUtf16 += text.length;
        if (totalUtf16 > maxTextUtf16) {
          throw const FormatException('Слишком большой исходный текст');
        }

        var start = 0;
        var part = 0;
        while (start < text.length) {
          final end = _chunkEnd(text, start, maxChunkUtf16);
          final piece = text.substring(start, end);
          if (piece.isEmpty || end <= start || chunks.length >= maxChunks) {
            throw const FormatException('Ошибка разбиения текста книги');
          }
          chunks.add(SourceChunk(
            id: 'c${chapterIndex}_b${blockIndex}_p$part',
            chapterIndex: chapterIndex,
            chapterId: chapterId,
            blockIndex: blockIndex,
            startUtf16: start,
            endUtf16: end,
            text: piece,
            sha256Text: sha256.convert(utf8.encode(piece)).toString(),
          ));
          indexedLength += piece.length;
          start = end;
          part++;
        }
      }

      canonicalInput.add({
        'chapter_id': chapterId,
        'blocks': canonicalBlocks,
      });
      coverage.add(SourceChapterCoverage(
        chapterIndex: chapterIndex,
        chapterId: chapterId,
        totalUtf16: textLength,
        indexedUtf16: indexedLength,
        textBlocks: textBlocks,
        imageBlocks: imageBlocks,
        sourceChunks: chunks.length - firstChunk,
      ));
    }

    if (totalUtf16 == 0) {
      throw const FormatException('В книге отсутствует извлекаемый текст');
    }
    final fingerprint = sha256.convert(utf8.encode(jsonEncode({
      'title': book.title,
      'author': book.author,
      'chapters': canonicalInput,
    }))).toString();

    return BookSourceIndex(
      sourceFingerprint: fingerprint,
      title: book.title,
      author: book.author,
      chapters: List.unmodifiable(coverage),
      chunks: List.unmodifiable(chunks),
    );
  }

  static int _chunkEnd(String text, int start, int limit) {
    var end = (start + limit).clamp(start + 1, text.length).toInt();
    if (end == text.length) return end;
    // Never split between the surrogate halves of one Unicode code point.
    if (_lowSurrogate(text.codeUnitAt(end))) end--;
    if (end <= start) {
      throw const FormatException('Размер фрагмента разрывает символ');
    }
    final minimum = start + ((end - start) * 0.6).floor();
    for (var i = end - 1; i >= minimum; i--) {
      final code = text.codeUnitAt(i);
      if (code == 10 || code == 32 || code == 9 ||
          code == 46 || code == 33 || code == 63 ||
          code == 0x3002 || code == 0xFF01 || code == 0xFF1F) {
        final choice = i + 1;
        if (choice < text.length &&
            !_lowSurrogate(text.codeUnitAt(choice))) return choice;
      }
    }
    return end;
  }

  static bool _lowSurrogate(int code) =>
      code >= 0xDC00 && code <= 0xDFFF;
}
