import 'dart:convert';

import 'book_model.dart';
import 'book_source_index.dart';

/// M2f2d: a bounded, read-only context window built from consecutive indexed
/// source chunks. The original SourceChunk ids/offsets remain authoritative:
/// never use a concatenated window offset for citations or BookWorld.
class SourceSemanticWindow {
  SourceSemanticWindow(List<SourceChunk> value)
      : chunks = List<SourceChunk>.unmodifiable(value) {
    if (chunks.isEmpty) {
      throw const FormatException('Пустое смысловое окно');
    }
  }

  final List<SourceChunk> chunks;

  int get chapterIndex => chunks.first.chapterIndex;

  bool get hasNarrativeText =>
      chunks.any((chunk) => chunk.blockKind == BookBlockKind.paragraph);

  int get utf16Length => displayText.length;

  int get utf8Length => utf8.encode(displayText).length;

  String get displayText => chunks.map((c) => c.text).join('\n\n');

  /// A strict, UI-reviewable shape: each exact original source piece gets
  /// its own ID, kind and text, never a flattened, impossible-to-cite string.
  List<Map<String, String>> get sourcePieces => [
    for (final c in chunks)
      <String, String>{
        'source_id': c.id,
        'kind': c.blockKind.name,
        'text': c.text,
      },
  ];
}

class SourceSemanticWindowPlanner {
  const SourceSemanticWindowPlanner._();

  /// Bounded input for the free provider, not the book source indexer.
  static const maxWindowUtf16 = 5000;
  static const maxWindowUtf8 = 16 * 1024;
  static const maxSourceChunks = 12;

  static List<SourceSemanticWindow> plan(BookSourceIndex index) {
    if (index.chunks.isEmpty) {
      throw const FormatException('Нет исходных фрагментов книги');
    }
    final windows = <SourceSemanticWindow>[];
    var current = <SourceChunk>[];
    var chars = 0;
    var bytes = 0;

    void closeCurrent() {
      if (current.isNotEmpty) {
        windows.add(SourceSemanticWindow(current));
        current = <SourceChunk>[];
        chars = 0;
        bytes = 0;
      }
    }

    for (final chunk in index.chunks) {
      final pieceBytes = utf8.encode(chunk.text).length;
      if (chunk.text.isEmpty ||
          chunk.text.length > maxWindowUtf16 ||
          pieceBytes > maxWindowUtf8) {
        throw const FormatException('Фрагмент слишком длинный для ИИ');
      }
      final separatorChars = current.isEmpty ? 0 : 2;
      final separatorBytes = current.isEmpty ? 0 : 2;
      if (current.isNotEmpty &&
          (current.first.chapterIndex != chunk.chapterIndex ||
           current.length == maxSourceChunks ||
           chars + separatorChars + chunk.text.length > maxWindowUtf16 ||
           bytes + separatorBytes + pieceBytes > maxWindowUtf8)) {
        closeCurrent();
      }
      if (current.isNotEmpty &&
          current.last.chapterIndex != chunk.chapterIndex) {
        throw const FormatException('Смешанные главы в одном окне');
      }
      final delimiter = current.isEmpty ? 0 : 2;
      chars += delimiter + chunk.text.length;
      bytes += delimiter + pieceBytes;
      current.add(chunk);
    }
    closeCurrent();

    // Invariant: every original piece appears exactly once and in order.
    // Windowing changes neither edition fingerprint nor book source coverage.
    final restored = windows.expand((w) => w.chunks).toList();
    if (restored.length != index.chunks.length ||
        restored.indexed.any((item) =>
            !identical(item.$2, index.chunks[item.$1]))) {
      throw const FormatException('Смысловые окна нарушили исходный порядок');
    }
    return List<SourceSemanticWindow>.unmodifiable(windows);
  }

  /// Refuse a forged or stale window BEFORE network access. A caller cannot
  /// send a hidden neighbor, a different edition, duplicate chunks or
  /// chapters not shown in the UI.
  static void validate(BookSourceIndex index, SourceSemanticWindow window) {
    if (window.chunks.length > maxSourceChunks ||
        window.utf16Length > maxWindowUtf16 ||
        window.utf8Length > maxWindowUtf8 ||
        !window.hasNarrativeText) {
      throw const FormatException('Некорректное или пустое окно анализа');
    }
    final originals = index.chunks;
    final firstIndex = originals.indexWhere(
        (c) => c.id == window.chunks.first.id);
    if (firstIndex < 0 ||
        firstIndex + window.chunks.length > originals.length) {
      throw const FormatException('Смысловое окно не найдено в книге');
    }
    for (var i = 0; i < window.chunks.length; i++) {
      final actual = originals[firstIndex + i];
      final supplied = window.chunks[i];
      if (!identical(actual, supplied) ||
          supplied.chapterIndex != window.chapterIndex ||
          supplied.text.isEmpty) {
        throw const FormatException(
            'Смысловое окно не соответствует исходному индексу');
      }
    }
  }
}
