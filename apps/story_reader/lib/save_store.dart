import 'dart:convert';
import 'game_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A snapshot and the decisions that led to it are stored atomically.
class GameSaveRecord {
  const GameSaveRecord(this.snapshot, this.journal, [this.progress = const GameProgress()]);
  final String snapshot;
  final List<String> journal;
  final GameProgress progress;
}

/// M1 single-slot persistence, compatible with existing raw engine snapshots.
class SaveStore {
  static const key = 'ai_story_m1_snapshot_v1';
  static const _format = 'ai_story_save_envelope_v1';

  /// Legacy API retained for older call sites and save fixtures.
  Future<void> write(String snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(key, snapshot);
    if (!ok) throw StateError('Could not persist game snapshot');
  }

  Future<void> writeGame(String snapshot, List<String> journal,
      [GameProgress progress = const GameProgress()]) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'format': _format,
      'snapshot': snapshot,
      'journal': List<String>.of(journal),
      'progress': progress.toJson(),
    });
    final ok = await prefs.setString(key, data);
    if (!ok) throw StateError('Could not persist game and journal');
  }

  Future<GameSaveRecord?> readGame() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    final dynamic json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      // The engine codec owns validation of legacy snapshot payloads.
      return GameSaveRecord(raw, const []);
    }
    if (json is Map && json['format'] == _format) {
      final snapshot = json['snapshot'];
      final journal = json['journal'];
      if (snapshot is! String || journal is! List ||
          journal.any((entry) => entry is! String)) {
        throw const FormatException('Invalid game save envelope');
      }
      final progress = json['progress'];
      if (progress != null && progress is! Map<String, dynamic>) {
        throw const FormatException('Invalid RPG progress payload');
      }
      return GameSaveRecord(snapshot, List<String>.unmodifiable(journal.cast<String>()),
          progress == null ? const GameProgress() : GameProgress.fromJson(progress));
    }
    return GameSaveRecord(raw, const []);
  }

  Future<String?> read() async => (await readGame())?.snapshot;
}
