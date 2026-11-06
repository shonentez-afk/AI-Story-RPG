import 'dart:math';

/// An opaque, stable actor identity used by all RPG clients.
///
/// In the current v1 world contract, 'player' is the reserved player actor.
/// Authored NPC identities use 128 cryptographically random bits encoded as
/// npc_ + 32 lowercase hex digits. No name, book hash, portrait, quote,
/// relationship, dialogue or current scene is part of the ID.
///
/// This utility does NOT assert that an NPC is canonical, knows a fact, has
/// game permissions or appears in a validated BookWorld.
abstract final class CharacterId {
  static final RegExp _npc = RegExp(r'^npc_[0-9a-f]{32}$');

  static bool isValidNpc(String value) => _npc.hasMatch(value);

  /// Allocate once when a PRIVATE authored NPC is created. Persist/reuse
  /// the returned ID on every rename/restart instead of allocating again.
  static String issueNpc() {
    final random = Random.secure();
    final output = StringBuffer('npc_');
    for (var i = 0; i < 16; ++i) {
      output.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return output.toString();
  }
}
