import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:test/test.dart';

const fixturePath = '../../shared_schemas/fixtures/private_classic_sample.json';
const nativeOutputPath =
    '../../artifacts/bookworld/book_private_sample_dart.bworld';

Map<String, dynamic> loadFixture() =>
    Map<String, dynamic>.from(jsonDecode(
        File(fixturePath).readAsStringSync()) as Map);

Map<String, dynamic> object(Object? value) =>
    Map<String, dynamic>.from(value as Map);

void main() {
  const writer = PrivateBookworldWriter();
  const importer = PrivateBookworldImporter();

  test('native v2 package builds offline and reopens in independent Dart reader',
      () {
    final data = loadFixture();
    final generated = writer.build(
      blueprint: object(data['blueprint']),
      provenance: object(data['provenance']),
      sourceIndex: object(data['source_index']),
    );
    final verified = importer.inspect(generated);
    expect(verified.bookworldId, 'book_private_sample');
    expect(verified.sourceFingerprint, 'a' * 64);
    expect(verified.blueprint.scenes.length, 3);
    expect(verified.canDistributePublicly, false);
    expect(verified.requiresNetwork, false);
    expect(generated.length, lessThan(12 * 1024 * 1024));
    expect(writer.build(
      blueprint: object(data['blueprint']),
      provenance: object(data['provenance']),
      sourceIndex: object(data['source_index']),
    ), orderedEquals(generated));
    // CI immediately rechecks the NATIVE output with the independent Python
    // v2 verifier, before integration tests and platform builds.
    final output = File(nativeOutputPath);
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(generated, flush: true);
  });

  test('native compiler rejects wrong edition, incomplete source and fake quote',
      () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (data) => (data['source_index'] as Map<String, dynamic>)['source_fingerprint'] =
          'f' * 64,
      (data) => (data['source_index'] as Map<String, dynamic>)['text_indexed_utf16'] = 0,
      (data) => (data['source_index'] as Map<String, dynamic>)['indexed_chapter_count'] = 1,
      (data) => ((data['source_index'] as Map<String, dynamic>)['chunks'] as List).removeLast(),
      (data) => ((data['source_index'] as Map<String, dynamic>)['chunks'] as List).first['start_utf16'] = 1,
      (data) => ((data['source_index'] as Map<String, dynamic>)['chunks'] as List).first
          ['sha256_text'] = 'f' * 64,
      (data) => (((data['provenance'] as Map<String, dynamic>)['scene_origins'] as List).first
          ['source_refs'] as List).first['quote_sha256'] = '0' * 64,
      (data) => (((data['provenance'] as Map<String, dynamic>)['scene_origins'] as List).first
          ['source_refs'] as List).first['start_utf16'] = 9999,
      (data) => (data['blueprint'] as Map<String, dynamic>)['rights_status'] = 'original_demo',
      (data) => (data['provenance'] as Map<String, dynamic>)['publication_authorized'] = true,
    ]) {
      final data = loadFixture();
      change(data);
      expect(() => writer.build(
        blueprint: object(data['blueprint']),
        provenance: object(data['provenance']),
        sourceIndex: object(data['source_index']),
      ), throwsFormatException);
    }
  });

  test('legacy v1 importer remains strict for native v2 archive', () {
    final data = loadFixture();
    final generated = writer.build(
      blueprint: object(data['blueprint']),
      provenance: object(data['provenance']),
      sourceIndex: object(data['source_index']),
    );
    expect(() => const BookworldImporter().inspect(generated),
        throwsFormatException);
    final corrupted = Uint8List.fromList(generated);
    corrupted[105] ^= 0xff;
    expect(() => importer.inspect(corrupted), throwsFormatException);
  });
  test('bounded NPC learn_fact imports but unearned knowledge remains forbidden',
      () {
    final npc = 'npc_' + List.filled(20, 'a').join();
    final fact = 'fact_' + List.filled(24, 'b').join();
    Map<String, dynamic> enriched() {
      final data = loadFixture();
      final blueprint = data['blueprint'] as Map<String, dynamic>;
      blueprint['actors'] = ['player', npc];
      blueprint['facts'] = [fact];
      final state = object(blueprint['initial_state']);
      state['knowledge'] = {'player': <String>[], npc: <String>[]};
      blueprint['initial_state'] = state;
      final scene = (blueprint['scenes'] as List).first as Map;
      final choice = (scene['choices'] as List).first as Map;
      (choice['effects'] as List).add(
          {'op': 'learn_fact', 'id': fact, 'actor': npc});
      return data;
    }

    final ok = enriched();
    final package = writer.build(
      blueprint: object(ok['blueprint']),
      provenance: object(ok['provenance']),
      sourceIndex: object(ok['source_index']),
    );
    final verified = importer.inspect(package);
    expect(verified.blueprint.actors, contains(npc));
    expect(verified.blueprint.facts, contains(fact));
    expect(verified.blueprint.initial.knowledge[npc], isEmpty);

    for (final invalid in <void Function(Map<String, dynamic>)>[
      (data) {
        final bp = data['blueprint'] as Map<String, dynamic>;
        final state = object(bp['initial_state']);
        state['knowledge'] = {'player': <String>[], npc: [fact]};
        bp['initial_state'] = state;
      },
      (data) {
        final bp = data['blueprint'] as Map<String, dynamic>;
        bp['facts'] = ['plain_text'];
        final scene = (bp['scenes'] as List).first as Map;
        ((scene['choices'] as List).first as Map)['effects'] = [
          {'op': 'learn_fact', 'id': 'plain_text', 'actor': npc},
        ];
      },
      (data) {
        final bp = data['blueprint'] as Map<String, dynamic>;
        final scene = (bp['scenes'] as List).first as Map;
        ((scene['choices'] as List).first as Map)['conditions'] = [
          {'op': 'knows_fact', 'id': fact, 'actor': 'player'},
        ];
      },
      (data) {
        final bp = data['blueprint'] as Map<String, dynamic>;
        final scene = (bp['scenes'] as List).first as Map;
        ((scene['choices'] as List).first as Map)['effects'] = [
          {'op': 'stat_delta', 'id': 'missing', 'amount': 1},
        ];
      },
    ]) {
      final data = enriched();
      invalid(data);
      expect(() => writer.build(
        blueprint: object(data['blueprint']),
        provenance: object(data['provenance']),
        sourceIndex: object(data['source_index']),
      ), throwsFormatException);
    }
  });


}
