import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:story_core/story_core.dart';

import '../../../apps/story_reader/lib/book_import.dart';
import '../../../apps/story_reader/lib/book_source_index.dart';

Future<void> main() async {
  final input = jsonDecode(await stdin.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  if (input['operation'] == 'source') {
    final book = BookImporter.parse(input['filename'] as String,
        Uint8List.fromList(base64Decode(input['data'] as String)));
    final index = BookSourceIndexer.index(book,
        maxChunkUtf16: input['chunk_size'] as int);
    stdout.write(jsonEncode(index.toJson()));
  } else if (input['operation'] == 'blueprint') {
    final blueprint = StoryBlueprint.fromJson(input['blueprint']);
    stdout.write(jsonEncode({
      'book_id': blueprint.bookId,
      'scene_count': blueprint.scenes.length,
    }));
  } else {
    throw const FormatException('Unknown probe operation');
  }
}
