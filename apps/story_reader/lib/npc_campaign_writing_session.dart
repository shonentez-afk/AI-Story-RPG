import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:story_core/story_core.dart' show canonicalJson;
import 'package:path_provider/path_provider.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'package:story_authoring/npc_campaign_writing_session.dart'
    show npcWritingHash, NpcWritingCatalog, NpcWritingEdit,
        NpcWritingSession, NpcWritingDraftRules;

export 'package:story_authoring/npc_campaign_writing_session.dart'
    show npcWritingHash, NpcWritingCatalog, NpcWritingEdit,
        NpcWritingSession, NpcWritingRequest, NpcWritingDraftRules;

class NpcWritingStore {
  NpcWritingStore({SourceAnalysisCheckpointRepository? repository})
      : repository = repository ?? FileSourceAnalysisCheckpointRepository(rootDirectory: _privateRoot);
  final SourceAnalysisCheckpointRepository repository;
  static Future<Directory> _privateRoot() async => Directory(
      '${(await getApplicationSupportDirectory()).path}/ai_story_npc_writing_v1');
  static const _format = 'ai_story_npc_writing_checkpoint_v1';
  static const maxBytes = 192 * 1024;
  static final _queues = <String, Future<void>>{};

  /// Compatibility method: the authoritative rule is pure Dart.
  static void validateEdits(NpcWritingCatalog catalog,
      Iterable<NpcWritingEdit> values) =>
      NpcWritingDraftRules.validateEdits(catalog, values);

  Future<NpcWritingSession> load(NpcWritingCatalog catalog) async {
    final saved = await repository.read(catalog.storageKey);
    if (saved == null) return NpcWritingSession.verified(catalog, 0, const []);
    if (utf8.encode(saved).length > maxBytes) throw const FormatException('Сохранённый черновик слишком большой.');
    try {
      final envelope = jsonDecode(saved) as Map<String, dynamic>;
      if (envelope.length != 2 || !envelope.containsKey('payload') ||
          !envelope.containsKey('sha256')) throw const FormatException();
      final p = envelope['payload'] as Map<String, dynamic>;
      if (p.length != 6 || p['format'] != _format ||
          p['source'] != catalog.source.index.sourceFingerprint ||
          p['plan'] != catalog.source.planDigest || p['catalog'] != catalog.digest ||
          p['revision'] is! int || (p['revision'] as int) < 1 ||
          p['edits'] is! List || envelope['sha256'] != npcWritingHash(p)) throw const FormatException();
      final entries = <NpcWritingEdit>[];
      for (final raw in p['edits'] as List) {
        final row = raw as Map<String, dynamic>;
        if (row.length != 7 || !row.keys.toSet().containsAll({
          'id', 'player_line', 'npc_line', 'dependencies', 'uncertainty', 'origin', 'no_suggestion',
        })) throw const FormatException();
        entries.add(NpcWritingEdit(id: row['id'] as String,
          playerLine: row['player_line'] as String, npcLine: row['npc_line'] as String,
          dependencies: (row['dependencies'] as List).cast<String>(),
          uncertainty: row['uncertainty'] as String, origin: row['origin'] as String,
          noSuggestion: row['no_suggestion'] as bool));
      }
      validateEdits(catalog, entries);
      return NpcWritingSession.verified(catalog, p['revision'] as int, entries);
    } catch (_) {
      throw const FormatException('Черновик повреждён или изменились источники '
          'и карточки. Старый файл сохранён; автоматическая перезапись запрещена.');
    }
  }

  Future<T> _locked<T>(String key, Future<T> Function() operation) async {
    final previous = _queues[key] ?? Future<void>.value();
    final release = Completer<void>(); _queues[key] = release.future;
    await previous;
    try { return await operation(); }
    finally {
      release.complete();
      if (identical(_queues[key], release.future)) _queues.remove(key);
    }
  }

  Future<NpcWritingSession> save(NpcWritingCatalog catalog, {
    required Iterable<NpcWritingEdit> edits, required int expectedRevision,
    String? expectedSnapshotDigest, Future<void> Function()? beforeWrite,
  }) {
    final snapshot = List<NpcWritingEdit>.unmodifiable(edits);
    validateEdits(catalog, snapshot);
    return _locked(catalog.storageKey, () async {
      if (beforeWrite != null) await beforeWrite();
      final before = await load(catalog);
      if (before.revision != expectedRevision ||
          (expectedSnapshotDigest != null && before.snapshotDigest != expectedSnapshotDigest)) {
        throw const FormatException('Черновик изменён в другом окне. '
            'Перечитайте сохранённую версию перед записью.');
      }
      final ordered = [...snapshot]..sort((a, b) => a.id.compareTo(b.id));
      final payload = {
        'format': _format, 'source': catalog.source.index.sourceFingerprint,
        'plan': catalog.source.planDigest, 'catalog': catalog.digest,
        'revision': before.revision + 1, 'edits': ordered.map((e) => e.toJson()).toList(),
      };
      final encoded = canonicalJson({'payload': payload, 'sha256': npcWritingHash(payload)});
      if (utf8.encode(encoded).length > maxBytes) throw const FormatException('Слишком большой авторский черновик.');
      await repository.write(catalog.storageKey, encoded);
      return NpcWritingSession.verified(catalog, before.revision + 1, ordered);
    });
  }

  Future<void> reset(NpcWritingCatalog catalog, {required bool confirmed}) {
    if (!confirmed) throw const FormatException('Удаление не подтверждено.');
    return _locked(catalog.storageKey, () => repository.delete(catalog.storageKey));
  }
}

