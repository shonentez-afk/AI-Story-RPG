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
      (data) => object(data['source_index'])['source_fingerprint'] =
          'f' * 64,
      (data) => object(data['source_index'])['text_indexed_utf16'] = 0,
      (data) => (object(data['source_index'])['chunks'] as List).first
          ['sha256_text'] = 'f' * 64,
      (data) => ((object(data['provenance'])['scene_origins'] as List).first
          ['source_refs'] as List).first['quote_sha256'] = '0' * 64,
      (data) => ((object(data['provenance'])['scene_origins'] as List).first
          ['source_refs'] as List).first['start_utf16'] = 9999,
      (data) => object(data['blueprint'])['rights_status'] = 'original_demo',
      (data) => object(data['provenance'])['publication_authorized'] = true,
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
}
