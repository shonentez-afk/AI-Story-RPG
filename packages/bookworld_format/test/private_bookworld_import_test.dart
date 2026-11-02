import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const privateArtifact =
    '../../artifacts/bookworld/book_private_sample.bworld';

Uint8List readPrivate() => File(privateArtifact).readAsBytesSync();

void main() {
  test('v2 private package imports offline and replays 20 turns deterministically',
      () {
    final original = readPrivate();
    final reader = const PrivateBookworldImporter();
    final verified = reader.inspect(original);
    expect(verified.bookworldId, 'book_private_sample');
    expect(verified.sourceFingerprint, 'a' * 64);
    expect(verified.blueprint.rightsStatus, 'private_adaptation');
    expect(verified.blueprint.sourceFingerprint, verified.sourceFingerprint);
    expect(verified.blueprint.scenes.length, 3);
    expect(verified.archiveSha256, hasLength(64));
    expect(verified.provenanceSha256, hasLength(64));
    expect(verified.canDistributePublicly, false);
    expect(verified.requiresNetwork, false);

    WorldState play(String finalAction) {
      final world = StoryWorld(verified.blueprint);
      for (var i = 0; i < 20; i++) {
        final result = world.apply(
            actionId: 'wait_$i', choiceId: 'wait',
            expectedRevision: i);
        expect(result.status, DecisionStatus.applied);
        expect(world.state.sceneId, 'entry');
      }
      expect(world.events.length, 20);
      final ending = world.apply(
          actionId: 'ending_$finalAction', choiceId: finalAction,
          expectedRevision: 20);
      expect(ending.status, DecisionStatus.applied);
      expect(world.isTerminal, true);
      return world.state;
    }

    final saved = play('help');
    final departed = play('leave');
    expect(saved.sceneId, 'canon_end');
    expect(saved.flags['helped'], true);
    expect(departed.sceneId, 'alternate_end');
    expect(departed.flags['helped'], false);
    expect(saved.stateHash, isNot(departed.stateHash));
    expect(const PrivateBookworldImporter().inspect(original).archiveSha256,
        verified.archiveSha256);
  });

  test('v1 legacy reader cannot accidentally import private v2 archive', () {
    expect(() => const BookworldImporter().inspect(readPrivate()),
        throwsFormatException);
    final original = File(
      '../../artifacts/bookworld/manor_m17_original_demo.bworld',
    ).readAsBytesSync();
    expect(() => const PrivateBookworldImporter().inspect(original),
        throwsFormatException);
  });

  test('private ZIP tampering and ZIP prefixes/suffixes are rejected', () {
    final original = readPrivate();
    final changed = Uint8List.fromList(original);
    changed[85] ^= 1;
    expect(() => const PrivateBookworldImporter().inspect(changed),
        throwsFormatException);
    expect(() => const PrivateBookworldImporter().inspect(
        Uint8List.fromList([0, ...original])), throwsFormatException);
    expect(() => const PrivateBookworldImporter().inspect(
        Uint8List.fromList([...original, 0])), throwsFormatException);
  });
}
