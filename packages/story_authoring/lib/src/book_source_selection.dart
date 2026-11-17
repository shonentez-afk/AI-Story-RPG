import 'book_import.dart';
import 'book_model.dart';

/// Select a single original tale/chapter without modifying the library book.
///
/// This is pure Dart: the existing indexer binds an independently selected
/// source scope to its own immutable fingerprint and editorial checkpoints.
class BookSourceSelection {
  const BookSourceSelection._();

  static final _variantHeading = RegExp(
      r'вариант\s*№\s*\d+', caseSensitive: false, unicode: true);

  static String chapterLabel(ImportedBook book, int index) {
    if (index < 0 || index >= book.chapters.length) {
      throw RangeError.index(index, book.chapters, 'chapterIndex');
    }
    if (book.structuredChapters.length == book.chapters.length) {
      for (final block in book.structuredChapters[index].blocks) {
        if (block.kind != BookBlockKind.heading) continue;
        final value = block.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (value.isNotEmpty) {
          return value.length > 100
              ? value.substring(0, 100) + '…' : value;
        }
      }
    }
    return 'Глава ' + (index + 1).toString();
  }

  /// Numbered historical versions are alternatives, never chronological acts.
  /// Novels and ordinary anthologies retain whole-book scope by default.
  static int? defaultChapter(ImportedBook book) {
    if (book.chapters.length < 2 ||
        book.structuredChapters.length != book.chapters.length) return null;
    final allVariants = List.generate(book.chapters.length,
        (i) => _variantHeading.hasMatch(chapterLabel(book, i)))
        .every((matched) => matched);
    return allVariants ? 0 : null;
  }

  static ImportedBook selectChapter(ImportedBook book, int index) {
    if (index < 0 || index >= book.chapters.length) {
      throw RangeError.index(index, book.chapters, 'chapterIndex');
    }
    final text = book.chapters[index];
    if (text.trim().isEmpty) {
      throw const FormatException('Выбранный фрагмент книги пуст.');
    }
    final selected = book.structuredChapters.length == book.chapters.length
        ? [book.structuredChapters[index]]
        : const <BookChapter>[];
    return ImportedBook(
      title: book.title + ' · ' + chapterLabel(book, index),
      author: book.author,
      chapters: [text],
      structuredChapters: selected,
      cover: book.cover,
      images: book.images,
    );
  }
}
