import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_runtime_adapter/story_runtime_adapter.dart';
import 'package:test/test.dart';

const artifact = '../../artifacts/bookworld/manor_m17_original_demo.bworld';

Uint8List bytes() => File(artifact).readAsBytesSync();

void main() {
  test('real .bworld ZIP/SQLite opens offline and preserves original rules',
      () {
    final checked = const BookworldImporter().inspect(bytes());
    expect(checked.bookworldId, 'manor_m17_original_demo');
    expect(checked.blueprint.scenes.length, 8);
    expect(checked.blueprint.scenes.values.fold<int>(
        0, (n, s) => n + s.choices.length), 15);
    expect(checked.archiveHash.length, 64);
    final game = StoryEngineCoordinator.start(checked.blueprint);
    expect(game.sceneId, 'gate');
    expect(game.choices.length, 4);
    expect(game.choices.singleWhere((c) => c.id == 'enter_hall').enabled,
        isFalse);
    expect(game.choose(
        actionId: 'inspect_1',
        choiceId: 'inspect_gate',
        expectedRevision: 0).applied, isTrue);
    expect(game.state.stats['insight'], 1);
    final restored = StoryEngineCoordinator.restore(
        checked.blueprint, game.checkpoint());
    expect(restored.state.stateHash, game.state.stateHash);
    expect(restored.sceneId, game.sceneId);
  });

  test('the same package gives identical bookworld and blueprint hashes', () {
    final a = const BookworldImporter().inspect(bytes());
    final b = const BookworldImporter().inspect(bytes());
    expect(a.archiveHash, b.archiveHash);
    expect(a.blueprint.blueprintHash, b.blueprint.blueprintHash);
  });

  test('truncated and prefixed/trailed ZIPs fail closed without extraction', () {
    final original = bytes();
    final importer = const BookworldImporter();
    expect(() => importer.inspect(Uint8List.fromList(original.take(20).toList())),
        throwsFormatException);
    final withPrefix = Uint8List.fromList([0] + original);
    expect(() => importer.inspect(withPrefix), throwsFormatException);
    final withSuffix = Uint8List.fromList([...original, 0]);
    expect(() => importer.inspect(withSuffix), throwsFormatException);
    final damaged = Uint8List.fromList(original);
    damaged[damaged.length - 22] = 0;
    expect(() => importer.inspect(damaged), throwsFormatException);
  });

  test('ZIP entry size and compression method manipulation are rejected', () {
    final original = bytes();
    final footer = ByteData.sublistView(original);
    final end = original.length - 22;
    final central = footer.getUint32(end + 16, Endian.little);
    final inflated = Uint8List.fromList(original);
    final inflatedData = ByteData.sublistView(inflated);
    inflatedData.setUint32(central + 24, 0xffffffff, Endian.little);
    expect(() => const BookworldImporter().inspect(inflated),
        throwsFormatException);

    final compressed = Uint8List.fromList(original);
    final compressedData = ByteData.sublistView(compressed);
    compressedData.setUint16(central + 10, 8, Endian.little);
    expect(() => const BookworldImporter().inspect(compressed),
        throwsFormatException);
  });

  test('archive CRC mismatch prevents SQLite from being opened', () {
    final corrupt = Uint8List.fromList(bytes());
    // The bytes at this offset reside inside the stored manifest.
    corrupt[90] ^= 0x01;
    expect(() => const BookworldImporter().inspect(corrupt),
        throwsFormatException);
  });
}
