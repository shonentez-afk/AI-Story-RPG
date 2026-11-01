import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'book_import.dart';
import 'book_model.dart';

class StoredBook {
  const StoredBook({required this.id, required this.book});
  final String id;
  final ImportedBook book;
}

class BookStorage {
  Future<Directory> _folder() async {
    final base = await getApplicationDocumentsDirectory();
    final folder = Directory('${base.path}/ai_story_library');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<void> add(ImportedBook book) async {
    final folder = await _folder();
    final id = '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    final file = File('${folder.path}/$id.json');
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
    await file.writeAsString(payload, flush: true);
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

  Future<List<StoredBook>> all() async {
    final folder = await _folder();
    final records = <StoredBook>[];
    await for (final item in folder.list()) {
      if (item is! File || !item.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await item.readAsString()) as Map<String, dynamic>;
        if (data['schema'] != 1 && data['schema'] != 2) continue;
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
        // Isolate corrupt records; keep all remaining books accessible.
      }
    }
    records.sort((a, b) => a.book.title.compareTo(b.book.title));
    return records;
  }
}
