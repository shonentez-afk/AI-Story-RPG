import 'dart:convert';
import 'game_progress.dart';
import 'package:rpg_gameplay/rpg_gameplay.dart' show GameSaveRecord;
export 'package:rpg_gameplay/rpg_gameplay.dart' show GameSaveRecord;
import 'package:shared_preferences/shared_preferences.dart';

/// Legacy single-slot format. Read/write retained for older players.
/// New independent campaigns share this game's envelope codec.
class SaveStore {
  static const key = 'ai_story_m1_snapshot_v1';
  static const _format = 'ai_story_save_envelope_v1';

  /// Pre-M1.6 API retained for raw engine snapshot fixtures.
  Future<void> write(String snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(key, snapshot);
    if (!ok) throw StateError('Could not persist game snapshot');
  }

  Future<void> writeGame(String snapshot, List<String> journal,
      [GameProgress progress = const GameProgress(), int rulesVersion = 0]) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(key, encodeGameRecord(
      GameSaveRecord(snapshot, journal, progress, rulesVersion),
    ));
    if (!ok) throw StateError('Could not persist game and journal');
  }

  Future<GameSaveRecord?> readGame() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    return raw == null ? null : decodeGameRecord(raw);
  }

  static String encodeGameRecord(GameSaveRecord record) {
    if (record.rulesVersion != 0 && record.rulesVersion != 1) {
      throw ArgumentError.value(record.rulesVersion, 'rulesVersion');
    }
    return jsonEncode({
      'format': _format,
      'snapshot': record.snapshot,
      'journal': List<String>.of(record.journal),
      'progress': record.progress.toJson(),
      'rulesVersion': record.rulesVersion,
    });
  }

  static GameSaveRecord decodeGameRecord(String raw) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // The engine codec owns validation of raw pre-M1.6 snapshots.
      return GameSaveRecord(raw, const []);
    }
    if (decoded is Map && decoded['format'] == _format) {
      final snapshot = decoded['snapshot'];
      final journal = decoded['journal'];
      if (snapshot is! String || journal is! List ||
          journal.any((entry) => entry is! String)) {
        throw const FormatException('Invalid game save envelope');
      }
      final rulesVersion = decoded['rulesVersion'] ?? 0;
      if (rulesVersion is! int || (rulesVersion != 0 && rulesVersion != 1)) {
        throw const FormatException('Invalid pilot rules version');
      }
      final progress = decoded['progress'];
      if (progress != null && progress is! Map<String, dynamic>) {
        throw const FormatException('Invalid RPG progress payload');
      }
      return GameSaveRecord(
        snapshot, List<String>.unmodifiable(journal.cast<String>()),
        progress == null ? const GameProgress() : GameProgress.fromJson(progress),
        rulesVersion,
      );
    }
    return GameSaveRecord(raw, const []);
  }

  Future<String?> read() async => (await readGame())?.snapshot;
}
