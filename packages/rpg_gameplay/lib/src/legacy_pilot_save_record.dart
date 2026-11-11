import 'legacy_pilot_progress.dart';

/// A snapshot and the decisions that led to it are stored atomically.
class GameSaveRecord {
  const GameSaveRecord(this.snapshot, this.journal,
      [this.progress = const GameProgress(), this.rulesVersion = 0]);
  final String snapshot;
  final List<String> journal;
  final GameProgress progress;
  /// 0 = original pilot choices; 1 = inventory-gated pilot choices.
  final int rulesVersion;
}

