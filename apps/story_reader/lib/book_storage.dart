import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'book_import.dart';

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
      'schema': 1,
      'title': book.title,
      'author': book.author,
      'chapters': book.chapters,
      'coverBase64': book.cover == null ? null : base64Encode(book.cover!),
    });
    await file.writeAsString(payload, flush: true);
  }

  Future<List<StoredBook>> all() async {
    final folder = await _folder();
    final records = <StoredBook>[];
    await for (final item in folder.list()) {
      if (item is! File || !item.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await item.readAsString()) as Map<String, dynamic>;
        if (data['schema'] != 1) continue;
        final cover64 = data['coverBase64'] as String?;
        records.add(StoredBook(
          id: item.uri.pathSegments.last,
          book: ImportedBook(
            title: data['title'] as String,
            author: data['author'] as String? ?? '',
            chapters: (data['chapters'] as List).cast<String>(),
            cover: cover64 == null ? null : base64Decode(cover64),
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
