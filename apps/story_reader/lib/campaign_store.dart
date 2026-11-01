import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'save_store.dart';

/// Lightweight pilot storage, not the portable .bwsave format.
/// Each slot stores the complete snapshot, journal, world and metadata
/// with one SharedPreferences.setString operation; no fragile catalog index.
class CampaignSummary {
  const CampaignSummary({
    required this.id,
    required this.sceneTitle,
    required this.savedAt,
    this.damaged = false,
  });

  final String id;
  final String sceneTitle;
  final DateTime savedAt;
  final bool damaged;
  bool get isLegacy => id == CampaignStore.legacyId;
}

class CampaignStore {
  static const legacyId = 'legacy';
  static const _prefix = 'ai_story_campaign_v1_';
  static const _format = 'ai_story_campaign_slot_v1';
  static const _activeKey = 'ai_story_campaign_active_v1';
  static const _bookId = 'ai_story_m1_intro';
  static final RegExp _safeId = RegExp(r'^[a-z0-9_-]{8,96}$');

  // Serialize writes/deletes between CampaignStore instances in-process.
  // Tombstones stop late autosaves from resurrecting deleted campaigns.
  static final Set<String> _deletedInProcess = <String>{};
  static Future<void> _writeFence = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() action) {
    final result = _writeFence.then((_) => action());
    _writeFence = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  static String newId() {
    final secure = Random.secure();
    final suffix = secure.nextInt(0x100000000).toRadixString(36);
    return 'c_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$suffix';
  }

  static void _validate(String id) {
    if (id != legacyId && !_safeId.hasMatch(id)) {
      throw FormatException('Недопустимый идентификатор кампании: $id');
    }
  }

  static String _key(String id) => '$_prefix$id';

  /// Update the full record as a single preference value. A failed write
  /// leaves the old snapshot untouched rather than partially updating it.
  Future<void> write(String id, GameSaveRecord game,
      {required String sceneTitle}) {
    _validate(id);
    return _serial(() async {
      if (_deletedInProcess.contains(id)) {
        throw StateError('Удалённое прохождение нельзя перезаписать');
      }
      final prefs = await SharedPreferences.getInstance();
      if (id == legacyId) {
        await SaveStore().writeGame(
          game.snapshot, game.journal, game.progress, game.rulesVersion,
        );
      } else {
        final payload = jsonEncode({
          'format': _format,
          'id': id,
          'bookId': _bookId,
          'sceneTitle': sceneTitle,
          'savedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'game': SaveStore.encodeGameRecord(game),
        });
        final ok = await prefs.setString(_key(id), payload);
        if (!ok) throw StateError('Не удалось записать кампанию');
      }
      try {
        await prefs.setString(_activeKey, id);
      } catch (_) {
        // The active pointer does not participate in the game write.
      }
    });
  }

  Future<GameSaveRecord?> read(String id) async {
    _validate(id);
    if (id == legacyId) return SaveStore().readGame();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(id));
    if (raw == null) return null;
    final slot = _decode(raw, id);
    return _decodeNewGame(slot.game);
  }

  static GameSaveRecord _decodeNewGame(String raw) {
    final dynamic json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Повреждённое содержимое кампании');
    }
    if (json is! Map<String, dynamic> ||
        json['format'] != 'ai_story_save_envelope_v1') {
      throw const FormatException('Неизвестный формат игрового состояния');
    }
    return SaveStore.decodeGameRecord(raw);
  }

  Future<void> markActive(String id) async {
    _validate(id);
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(id == legacyId ? SaveStore.key : _key(id))) {
      throw StateError('Кампания больше не существует');
    }
    final ok = await prefs.setString(_activeKey, id);
    if (!ok) throw StateError('Не удалось выбрать прохождение');
  }

  Future<List<CampaignSummary>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <CampaignSummary>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final id = key.substring(_prefix.length);
      if (!_safeId.hasMatch(id)) continue;
      try {
        final raw = prefs.getString(key);
        if (raw == null) throw const FormatException('Not a string slot');
        final entry = _decode(raw, id);
        _decodeNewGame(entry.game);
        result.add(CampaignSummary(
          id: id, sceneTitle: entry.sceneTitle, savedAt: entry.savedAt));
      } catch (_) {
        // Damaged entries stay visible and can only be explicitly deleted.
        result.add(CampaignSummary(
          id: id, sceneTitle: 'Повреждённое сохранение',
          savedAt: DateTime.fromMillisecondsSinceEpoch(0), damaged: true));
      }
    }
    if (prefs.containsKey(SaveStore.key)) {
      result.add(CampaignSummary(
        id: legacyId, sceneTitle: 'Старое прохождение',
        savedAt: DateTime.fromMillisecondsSinceEpoch(0)));
    }
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final active = prefs.getString(_activeKey);
    final activeIndex = result.indexWhere((entry) => entry.id == active);
    if (activeIndex > 0) result.insert(0, result.removeAt(activeIndex));
    return List<CampaignSummary>.unmodifiable(result);
  }

  /// Deletion is isolated to exactly one validated key.
  Future<void> delete(String id) {
    _validate(id);
    // Set before awaiting any I/O, so future writes cannot resurrect the ID.
    _deletedInProcess.add(id);
    return _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = id == legacyId ? SaveStore.key : _key(id);
      final ok = await prefs.remove(key);
      if (!ok) {
        _deletedInProcess.remove(id);
        throw StateError('Не удалось удалить кампанию');
      }
      if (prefs.getString(_activeKey) == id) {
        try {
          await prefs.remove(_activeKey);
        } catch (_) {
          // Stale pointer never contains gameplay state.
        }
      }
    });
  }

  static _CampaignSlot _decode(String raw, String expectedId) {
    final dynamic data;
    try {
      data = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Повреждённый JSON кампании');
    }
    if (data is! Map<String, dynamic> ||
        data['format'] != _format ||
        data['id'] != expectedId ||
        data['bookId'] != _bookId ||
        data['game'] is! String ||
        data['sceneTitle'] is! String ||
        data['savedAtUtc'] is! String) {
      throw const FormatException('Несовместимый формат кампании');
    }
    final scene = data['sceneTitle'] as String;
    if (scene.length > 256) {
      throw const FormatException('Недопустимая длина названия сцены');
    }
    final date = DateTime.tryParse(data['savedAtUtc'] as String);
    if (date == null) throw const FormatException('Некорректная дата сохранения');
    return _CampaignSlot(scene, date, data['game'] as String);
  }
}

class _CampaignSlot {
  const _CampaignSlot(this.sceneTitle, this.savedAt, this.game);
  final String sceneTitle;
  final DateTime savedAt;
  final String game;
}
