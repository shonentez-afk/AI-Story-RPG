import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_engine/story_engine.dart';

import 'legacy_pilot_progress.dart';
import 'legacy_pilot_save_record.dart';

/// M1.6.6 portable JSON pilot save. Not a complete BookWorld/SQLite .bwsave:
/// the embedded demo has no BookWorld hash, campaign roles or RNG seed yet.
/// Those fields are explicitly null, never fabricated.
class PilotSaveImport {
  const PilotSaveImport({
    required this.sourceCampaignId,
    required this.sceneTitle,
    required this.exportedAt,
    required this.game,
  });

  final String sourceCampaignId;
  final String sceneTitle;
  final DateTime exportedAt;
  final GameSaveRecord game;
}

class PilotSaveCodec {
  static const extension = 'bwsave';
  static const format = 'ai_story_pilot_bwsave_v1';
  static const schemaVersion = 1;
  static const bookId = 'ai_story_m1_intro';
  static const runtimeId = 'story_engine';
  static const runtimeVersion = '0.1.0-alpha.1';
  static const maxFileBytes = 4 * 1024 * 1024;
  static const maxSnapshotChars = 2 * 1024 * 1024;
  static const maxJournalEntries = 3000;
  static const maxJournalEntryChars = 3000;
  static final _campaignIdPattern = RegExp(r'^(legacy|[a-z0-9_-]{8,96})$');
  static final _hashPattern = RegExp(r'^[0-9a-f]{64}$');

  static Uint8List encode({
    required String sourceCampaignId,
    required GameSaveRecord game,
    required StoryProject project,
  }) {
    if (!_campaignIdPattern.hasMatch(sourceCampaignId)) {
      throw const FormatException('Недопустимый ID исходной кампании');
    }
    final scene = _validateGame(game, project);
    final payload = <String, dynamic>{
      'book_id': bookId,
      'bookworld_hash': null,
      'source_kind': 'embedded_pilot',
      'source_campaign_id': sourceCampaignId,
      'last_scene': scene,
      'exported_at_utc': DateTime.now().toUtc().toIso8601String(),
      'role': null,
      'plot': null,
      'interaction': 'CLASSIC',
      'rng_seed': null,
      'checkpoints': <dynamic>[],
      'runtime': <String, dynamic>{
        'id': runtimeId,
        'version': runtimeVersion,
      },
      'engine_snapshot': game.snapshot,
      'world_state': game.progress.toJson(),
      'decision_journal': List<String>.of(game.journal),
      'rules_version': game.rulesVersion,
    };
    final data = <String, dynamic>{
      'format': format,
      'schema_version': schemaVersion,
      'payload': payload,
      'payload_sha256': _sha256(payload),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > maxFileBytes) {
      throw const FormatException('Сохранение превышает допустимый размер');
    }
    return bytes;
  }

  static PilotSaveImport decode(Uint8List bytes, {
    required StoryProject project,
  }) {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('Неверный размер файла сохранения');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      throw const FormatException('Файл не является корректным UTF-8 JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['schema_version'] != schemaVersion) {
      throw const FormatException('Неизвестная версия .bwsave');
    }
    final payload = decoded['payload'];
    final hash = decoded['payload_sha256'];
    if (payload is! Map<String, dynamic> ||
        hash is! String || !_hashPattern.hasMatch(hash) ||
        _sha256(payload) != hash) {
      throw const FormatException('Контрольная сумма .bwsave не совпадает');
    }
    if (payload['book_id'] != bookId ||
        project.id.value != bookId ||
        !payload.containsKey('bookworld_hash') ||
        payload['bookworld_hash'] != null ||
        payload['source_kind'] != 'embedded_pilot') {
      throw const FormatException(
          'Этот файл не относится к встроенной демонстрационной истории');
    }
    if (payload['role'] != null ||
        payload['plot'] != null ||
        payload['interaction'] != 'CLASSIC' ||
        payload['rng_seed'] != null ||
        payload['checkpoints'] is! List ||
        (payload['checkpoints'] as List).isNotEmpty) {
      throw const FormatException('Неподдерживаемая конфигурация прохождения');
    }
    final runtime = payload['runtime'];
    if (runtime is! Map<String, dynamic> ||
        runtime['id'] != runtimeId ||
        runtime['version'] != runtimeVersion) {
      throw const FormatException('Несовместимая версия игрового движка');
    }
    final sourceId = payload['source_campaign_id'];
    final snapshot = payload['engine_snapshot'];
    final world = payload['world_state'];
    final journal = payload['decision_journal'];
    final rules = payload['rules_version'];
    final date = payload['exported_at_utc'];
    final scene = payload['last_scene'];
    if (sourceId is! String || !_campaignIdPattern.hasMatch(sourceId) ||
        snapshot is! String ||
        world is! Map<String, dynamic> ||
        journal is! List ||
        journal.any((entry) => entry is! String) ||
        rules is! int ||
        date is! String ||
        scene is! String ||
        scene.length > 256 ||
        DateTime.tryParse(date) == null) {
      throw const FormatException('Повреждена структура игрового сохранения');
    }
    final rawItems = world['items'];
    if (world['courage'] is! int ||
        world['insight'] is! int ||
        rawItems is! List ||
        rawItems.any((id) =>
            id is! String || !GameProgress.itemNames.containsKey(id)) ||
        rawItems.toSet().length != rawItems.length) {
      throw const FormatException('Недопустимый состав игрового инвентаря');
    }
    final game = GameSaveRecord(
      snapshot,
      List<String>.unmodifiable(journal.cast<String>()),
      GameProgress.fromJson(world),
      rules,
    );
    if (_validateGame(game, project) != scene) {
      throw const FormatException('Последняя сцена не совпадает со снимком');
    }
    return PilotSaveImport(
      sourceCampaignId: sourceId,
      sceneTitle: scene,
      exportedAt: DateTime.parse(date),
      game: game,
    );
  }

  /// Rehydrate with the installed deterministic runtime before any import
  /// writes occur. A checksum alone cannot establish save compatibility.
  static String _validateGame(GameSaveRecord game, StoryProject project) {
    if (project.id.value != bookId ||
        (game.rulesVersion != 0 && game.rulesVersion != 1) ||
        game.snapshot.isEmpty ||
        game.snapshot.length > maxSnapshotChars ||
        game.journal.length > maxJournalEntries ||
        game.journal.any((line) =>
            line.length > maxJournalEntryChars) ||
        game.progress.courage < 0 ||
        game.progress.insight < 0 ||
        game.progress.courage > 1000000 ||
        game.progress.insight > 1000000 ||
        game.progress.items.toSet().length != game.progress.items.length ||
        game.progress.items.any((id) =>
            !GameProgress.itemNames.containsKey(id))) {
      throw const FormatException('Недопустимое состояние игры');
    }
    try {
      final codec = StoryRuntimeSnapshotCodec();
      final restored = StoryEngine.restore(
        project: project,
        snapshot: codec.decodeJson(game.snapshot, project: project),
      );
      return restored.currentEvent?.presentation?.title?.value
          ?? 'История завершена';
    } catch (_) {
      throw const FormatException(
          'Снимок игрового движка повреждён или несовместим');
    }
  }

  /// Stable recursive key order makes the checksum the same on Windows and
  /// Android regardless of JSON input property order.
  static String _sha256(Map<String, dynamic> data) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(data)))).toString();

  static Object? _canonical(Object? source) {
    if (source is Map) {
      final keys = source.keys.cast<String>().toList()..sort();
      final sorted = SplayTreeMap<String, Object?>();
      for (final key in keys) {
        sorted[key] = _canonical(source[key]);
      }
      return sorted;
    }
    if (source is List) {
      return source.map(_canonical).toList(growable: false);
    }
    return source;
  }
}
