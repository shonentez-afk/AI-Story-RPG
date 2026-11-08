import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

const fixturePath = '../../shared_schemas/fixtures/private_classic_sample.json';
Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
Map<String, dynamic> object(Object? raw) =>
    Map<String, dynamic>.from(raw as Map);

void main() {
  const engine = BookAuthoringEngine();

  test('TXT source and exact UTF-16 index share the reader implementation', () {
    const text = 'Глава первая. Привет, мир 😀!\nГлава вторая. Конец.';
    final original = engine.parseAndIndex('book.txt', bytes(text),
        maxChunkUtf16: 256);
    final repeated = engine.indexImported(
        BookImporter.parse('book.txt', bytes(text)), maxChunkUtf16: 256);
    expect(original.index.sourceFingerprint,
        repeated.index.sourceFingerprint);
    expect(original.index.chunks.map((chunk) => chunk.text).join(), text);
    expect(original.hasCompleteText, true);
    expect(original.status['stage'], 'SOURCE_INDEX_ONLY');
    expect(original.status['full_book_rpg_ready'], false);
    expect(original.status['requires_cloud'], false);
  });

  test('FB2 parsing and indexing work without Flutter or network', () {
    const fb2 = '<?xml version="1.0" encoding="UTF-8"?>'
        '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">'
        '<description><title-info><book-title>Повесть</book-title>'
        '</title-info></description>'
        '<body><section><p>Герой проснулся.</p></section>'
        '<section><p>Герой вернулся.</p></section></body></FictionBook>';
    final src = engine.parseAndIndex('book.fb2', bytes(fb2));
    expect(src.index.chapterCount, 2);
    expect(src.index.indexedChapterCount, 2);
    expect(src.index.chunks, isNotEmpty);
    expect(src.status['scenario_reviewed'], false);
  });

  test('forged source fingerprint is rejected before authoring', () {
    final src = engine.parseAndIndex('book.txt', bytes('Начало.'));
    expect(() => engine.buildReviewedPrivateWorld(
        source: src,
        blueprint: const {'source_fingerprint': 'forged'},
        provenance: const {'source_fingerprint': 'forged'}),
        throwsFormatException);
  });

  test('exact source + reviewed scenes produces strict portable rich-v3', () {
    final fixture = object(jsonDecode(File(fixturePath).readAsStringSync()));
    final rawSource = object(fixture['source_index']);
    final chunks = (rawSource['chunks'] as List).cast<Map<String, dynamic>>();
    final bp = object(fixture['blueprint']);
    final provenance = object(fixture['provenance']);

    // Construct an actual in-memory two-chapter source: its fingerprint is
    // calculated by the SAME production importer/indexer as Flutter.
    final source = engine.indexImported(ImportedBook(
      title: provenance['source_title'] as String,
      author: provenance['source_author'] as String,
      chapters: [for (final chunk in chunks) chunk['text'] as String],
    ));
    bp['source_fingerprint'] = source.index.sourceFingerprint;
    provenance['source_fingerprint'] = source.index.sourceFingerprint;
    provenance['format'] = 'ai_story_private_provenance_v2';
    provenance['model_provenance'] = {
      'provider': 'none', 'model_id': null,
      'model_id_status': 'not_applicable',
      'tool': 'none', 'method': 'local_fixture',
    };
    provenance['presentation'] = {
      'hero': {
        'name': 'Игрок',
        'description': 'Герой синтетической source-locked проверки.',
      },
      'item_names': <String, String>{},
      'item_descriptions': <String, String>{},
      'stat_names': <String, String>{},
      'fact_names': <String, String>{},
      'scene_names': {
        'entry': 'Развилка',
        'canon_end': 'Дом',
        'alternate_end': 'Двор',
      },
    };
    for (final entry in provenance['scene_origins'] as List) {
      final origin = object(entry);
      for (final entry in origin['source_refs'] as List) {
        final quote = entry as Map<String, dynamic>;
        final chapter = quote['chapter_index'] as int;
        quote['chunk_id'] = source.index.chunks
            .singleWhere((piece) => piece.chapterIndex == chapter).id;
      }
    }
    final archive = engine.buildReviewedPrivateWorld(
        source: source, blueprint: bp, provenance: provenance);
    final world = engine.inspectPrivateWorld(archive);
    expect(world.sourceFingerprint, source.index.sourceFingerprint);
    expect(world.blueprint.scenes.length, 3);
    expect(world.requiresNetwork, false);
    expect(world.canDistributePublicly, false);

    // The independent Python validator checks these exact Dart ZIP bytes
    // in GitHub CI. This is only synthetic GAMEPLAY proof, not literary CANON.
    final file = File('../../artifacts/bookworld/story_authoring_sourcebound_fixture.bworld');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(archive);
  });
}
