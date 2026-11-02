import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'book_import.dart';
import 'book_model.dart';

class StoredBook {
  const StoredBook({required this.id, required this.book});
  final String id;
  final ImportedBook book;
}

/// A corrupt or interrupted import is reported instead of silently
/// disappearing from the library. No existing user file is removed.
class BookLibraryScan {
  const BookLibraryScan({required this.books, required this.unreadableCount});
  final List<StoredBook> books;
  final int unreadableCount;
}

class BookStorage {
  BookStorage({this.rootDirectory});

  /// Test-only directory override; production uses the app's Documents area.
  final Future<Directory> Function()? rootDirectory;

  Future<Directory> _folder() async {
    final base = await (rootDirectory?.call() ??
        getApplicationDocumentsDirectory());
    final folder = Directory('${base.path}/ai_story_library');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<void> add(ImportedBook book) async {
    final folder = await _folder();
    final id = '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    final file = File('${folder.path}/$id.json');
    final temp = File('${folder.path}/$id.json.tmp');
    final payload = jsonEncode({
      'schema': 2,
      'structuredChapters': book.structuredChapters.map((ch) => ch.toJson()).toList(),
      'images': book.images.map((id, image) => MapEntry(id, {
        'mediaType': image.mediaType, 'bytes': base64Encode(image.bytes),
      })),
      'title': book.title,
      'author': book.author,
      'chapters': book.chapters,
      'coverBase64': book.cover == null ? null : base64Encode(book.cover!),
    });
    try {
      // A half-written JSON must never masquerade as an imported book.
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Remove one imported library file; game saves stay separate.
  Future<void> remove(String bookId) async {
    if (!RegExp(r'^[0-9]+_[0-9]+\.json$').hasMatch(bookId)) {
      throw const FormatException('Недопустимый идентификатор книги');
    }
    final folder = await _folder();
    final file = File('${folder.path}/$bookId');
    if (!await file.exists()) throw StateError('Книга не найдена');
    await file.delete();
  }

  /// Scan stored books off the main Flutter isolate. Parsing a large FB2
  /// JSON with embedded images used to freeze navigation and opening.
  Future<BookLibraryScan> scan() async {
    final folder = await _folder();
    final path = folder.path;
    return compute(_scanFiles, path, debugLabel: 'story-library-scan');
  }

  Future<List<StoredBook>> all() async => (await scan()).books;

  static Future<BookLibraryScan> _scanFiles(String directoryPath) async {
    final folder = Directory(directoryPath);
    final records = <StoredBook>[];
    var unreadable = 0;
    await for (final item in folder.list()) {
      // The .tmp suffix is deliberately ignored until an atomic rename.
      if (item is! File || !item.path.endsWith('.json')) continue;
      try {
        // Keep unsafe/decompressed JSON from exhausting the worker memory.
        if (await item.length() > 64 * 1024 * 1024) {
          unreadable++;
          continue;
        }
        final data = jsonDecode(await item.readAsString())
            as Map<String, dynamic>;
        if (data['schema'] != 1 && data['schema'] != 2) {
          unreadable++;
          continue;
        }
        final cover64 = data['coverBase64'] as String?;
        records.add(StoredBook(
          id: item.uri.pathSegments.last,
          book: ImportedBook(
            title: data['title'] as String,
            author: data['author'] as String? ?? '',
            chapters: (data['chapters'] as List).cast<String>(),
            cover: cover64 == null ? null : base64Decode(cover64),
            structuredChapters: data['schema'] == 2
                ? (data['structuredChapters'] as List).map((x) =>
                    BookChapter.fromJson(x as Map<String, dynamic>)).toList()
                : const [],
            images: data['schema'] == 2
                ? (data['images'] as Map<String, dynamic>).map((id, item) {
                    final value = item as Map<String, dynamic>;
                    return MapEntry(id, BookImage(
                      id: id,
                      mediaType: value['mediaType'] as String,
                      bytes: base64Decode(value['bytes'] as String),
                    ));
                  })
                : const {},
          ),
        ));
      } catch (_) {
        // A bad file never hides other books and is not auto-deleted.
        unreadable++;
      }
    }
    records.sort((a, b) => a.book.title.compareTo(b.book.title));
    return BookLibraryScan(
      books: List.unmodifiable(records),
      unreadableCount: unreadable,
    );
  }
}
