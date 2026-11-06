import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

void main() {
  test('opaque 128-bit NPC identity is issued by the reusable core', () {
    final issued = <String>{
      for (var i = 0; i < 40; i++) CharacterId.issueNpc(),
    };
    expect(issued.length, 40);
    for (final id in issued) {
      expect(id.length, 36);
      expect(id.startsWith('npc_'), true);
      expect(CharacterId.isValidNpc(id), isTrue);
    }
  });

  test('names, actor aliases, random text and malformed IDs are rejected', () {
    final invalid = [
      '', 'player', 'Лена', 'npc_Lena', 'npc_', 'npc_0123',
      'npc_' + List.filled(32, 'A').join(),
      'npc_' + List.filled(31, 'f').join(),
      'npc_' + List.filled(33, 'f').join(),
      'npc_' + List.filled(32, 'g').join(),
      '../npc_' + List.filled(32, 'a').join(),
    ];
    for (final id in invalid) {
      expect(CharacterId.isValidNpc(id), isFalse, reason: id);
    }
  });
}
