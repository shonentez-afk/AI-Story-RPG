import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:story_core/story_core.dart' show canonicalJson;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'source_analysis_checkpoint_repository.dart';
import 'whole_book_npc_campaign.dart';

String npcWritingHash(Object value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

/// Exact authoring inputs. Identity, source quotes and scene addresses are
/// not model-editable. Catalog construction does not authorize transmission.
class NpcWritingCatalog {
  NpcWritingCatalog._(this.source, this.candidates, this.digest, this.storageKey);
  final WholeBookNpcSourcePlan source;
  final Map<String, BookwideNpcConversationCandidate> candidates;
  final String digest, storageKey;

  factory NpcWritingCatalog({
    required WholeBookNpcSourcePlan source,
    required List<BookwideNpcConversationCandidate> candidates,
  }) {
    final sorted = [...candidates]..sort((a, b) => a.id.compareTo(b.id));
    if (sorted.map((c) => c.id).toSet().length != sorted.length) {
      throw const FormatException('Повторён разговор NPC.');
    }
    for (final c in sorted) {
      c.firstEvent.source.validate(source.index);
      c.responseEvent.source.validate(source.index);
      if (c.role.sourceFingerprint != source.index.sourceFingerprint) {
        throw const FormatException('NPC относится к другой редакции книги.');
      }
    }
    final digest = npcWritingHash({
      'format': 'npc_writing_catalog_v1',
      'source': source.index.sourceFingerprint, 'plan': source.planDigest,
      'candidates': [for (final c in sorted) {
        'id': c.id, 'actor': c.role.characterId, 'name': c.role.displayName,
        'group': c.role.groupDigest,
        'first_scene': c.firstSceneId, 'response_scene': c.responseSceneId,
        'first_quote': c.firstEvent.source.quote,
        'response_quote': c.responseEvent.source.quote,
      }],
    });
    return NpcWritingCatalog._(source,
      Map.unmodifiable({for (final c in sorted) c.id: c}), digest,
      npcWritingHash({'scope': 'npc_authoring_v1',
        'source': source.index.sourceFingerprint, 'plan': source.planDigest}),
    );
  }
}

/// Partial manual edits and untrusted AI suggestions are durable; permission
/// to transmit or install is NEVER part of a checkpoint.
class NpcWritingEdit {
  NpcWritingEdit({
    required this.id, this.playerLine = '', this.npcLine = '',
    Iterable<String> dependencies = const [], this.uncertainty = '',
    this.origin = 'manual', this.noSuggestion = false,
  }) : dependencies = List.unmodifiable(dependencies);
  final String id, playerLine, npcLine, uncertainty, origin;
  final List<String> dependencies;
  final bool noSuggestion;
  bool get isBlank => playerLine.isEmpty && npcLine.isEmpty && !noSuggestion;
  bool get complete => !noSuggestion &&
      playerLine.trim().length >= 4 && npcLine.trim().length >= 4;
  NpcCampaignDialogueDraft toDraft() => NpcCampaignDialogueDraft(
    candidateId: id, playerLine: playerLine.trim(), npcLine: npcLine.trim(),
    requiresCandidateIds: dependencies,
  );
  Map<String, dynamic> toJson() => {
    'id': id, 'player_line': playerLine, 'npc_line': npcLine,
    'dependencies': dependencies.toList()..sort(),
    'uncertainty': uncertainty, 'origin': origin, 'no_suggestion': noSuggestion,
  };
}

class NpcWritingSession {
  NpcWritingSession._(this.catalogDigest, this.revision, Iterable<NpcWritingEdit> edits)
      : edits = Map.unmodifiable({for (final e in edits) e.id: e});
  final String catalogDigest;
  final int revision;
  final Map<String, NpcWritingEdit> edits;
  bool get canInstallDirectly => false;
  bool get cloudConsent => false;
  bool get literaryCanon => false;
}

/// Uses the existing atomic private file repository in its OWN parent folder.
/// Source text, key, HTTP response and approval flags never enter this scope.
class NpcWritingStore {
  NpcWritingStore({SourceAnalysisCheckpointRepository? repository})
      : repository = repository ?? FileSourceAnalysisCheckpointRepository(
          rootDirectory: _privateRoot);
  final SourceAnalysisCheckpointRepository repository;
  static Future<Directory> _privateRoot() async => Directory(
      '${(await getApplicationSupportDirectory()).path}/ai_story_npc_writing_v1');
  static const _format = 'ai_story_npc_writing_checkpoint_v1';
  static const maxBytes = 192 * 1024;
  static final _queues = <String, Future<void>>{};

  static void validateEdits(NpcWritingCatalog catalog, Iterable<NpcWritingEdit> values) {
    final rows = values.toList();
    final byId = {for (final e in rows) e.id: e};
    if (rows.length > 32 || byId.length != rows.length) {
      throw const FormatException('Слишком много или повторены разговоры.');
    }
    for (final e in rows) {
      if (!catalog.candidates.containsKey(e.id) ||
          e.playerLine.length > 400 || e.npcLine.length > 400 ||
          e.uncertainty.length > 350 ||
          !const ['manual', 'ai_draft'].contains(e.origin) ||
          e.dependencies.length > 8 ||
          e.dependencies.toSet().length != e.dependencies.length ||
          e.dependencies.any((id) => id == e.id || !byId.containsKey(id)) ||
          (e.noSuggestion && (e.origin != 'ai_draft' ||
              e.playerLine.isNotEmpty || e.npcLine.isNotEmpty)) ||
          [e.playerLine, e.npcLine, e.uncertainty].any(
              (text) => RegExp(r'[\x00-\x1f\x7f]').hasMatch(text))) {
        throw const FormatException('Черновик содержит чужие или неверные данные.');
      }
    }
    final visiting = <String>{}, checked = <String>{};
    void visit(String id) {
      if (checked.contains(id)) return;
      if (!visiting.add(id)) {
        throw const FormatException('Круговая зависимость разговоров.');
      }
      for (final dependency in byId[id]!.dependencies) { visit(dependency); }
      visiting.remove(id); checked.add(id);
    }
    for (final id in byId.keys) { visit(id); }
  }

  Future<NpcWritingSession> load(NpcWritingCatalog catalog) async {
    final saved = await repository.read(catalog.storageKey);
    if (saved == null) return NpcWritingSession._(catalog.digest, 0, const []);
    if (utf8.encode(saved).length > maxBytes) {
      throw const FormatException('Сохранённый черновик слишком большой.');
    }
    try {
      final envelope = jsonDecode(saved) as Map<String, dynamic>;
      if (envelope.length != 2 || !envelope.containsKey('payload') ||
          !envelope.containsKey('sha256')) throw const FormatException();
      final p = envelope['payload'] as Map<String, dynamic>;
      if (p.length != 6 || p['format'] != _format ||
          p['source'] != catalog.source.index.sourceFingerprint ||
          p['plan'] != catalog.source.planDigest || p['catalog'] != catalog.digest ||
          p['revision'] is! int || (p['revision'] as int) < 1 ||
          p['edits'] is! List || envelope['sha256'] != npcWritingHash(p)) {
        throw const FormatException();
      }
      final entries = <NpcWritingEdit>[];
      for (final raw in p['edits'] as List) {
        final row = raw as Map<String, dynamic>;
        if (row.length != 7 || !row.keys.toSet().containsAll({
          'id', 'player_line', 'npc_line', 'dependencies',
          'uncertainty', 'origin', 'no_suggestion',
        })) throw const FormatException();
        entries.add(NpcWritingEdit(
          id: row['id'] as String, playerLine: row['player_line'] as String,
          npcLine: row['npc_line'] as String,
          dependencies: (row['dependencies'] as List).cast<String>(),
          uncertainty: row['uncertainty'] as String, origin: row['origin'] as String,
          noSuggestion: row['no_suggestion'] as bool,
        ));
      }
      validateEdits(catalog, entries);
      return NpcWritingSession._(catalog.digest, p['revision'] as int, entries);
    } catch (_) {
      throw const FormatException('Черновик повреждён или изменились источники '
          'и карточки. Старый файл сохранён; автоматическая перезапись запрещена.');
    }
  }

  Future<T> _locked<T>(String key, Future<T> Function() operation) async {
    final previous = _queues[key] ?? Future<void>.value();
    final release = Completer<void>();
    _queues[key] = release.future;
    await previous;
    try { return await operation(); }
    finally {
      release.complete();
      if (identical(_queues[key], release.future)) _queues.remove(key);
    }
  }

  Future<NpcWritingSession> save(NpcWritingCatalog catalog, {
    required Iterable<NpcWritingEdit> edits, required int expectedRevision,
  }) {
    final snapshot = List<NpcWritingEdit>.unmodifiable(edits);
    validateEdits(catalog, snapshot);
    return _locked(catalog.storageKey, () async {
      final before = await load(catalog);
      if (before.revision != expectedRevision) {
        throw const FormatException('Черновик изменён в другом окне. '
            'Перечитайте сохранённую версию перед записью.');
      }
      final ordered = [...snapshot]..sort((a, b) => a.id.compareTo(b.id));
      final payload = {
        'format': _format, 'source': catalog.source.index.sourceFingerprint,
        'plan': catalog.source.planDigest, 'catalog': catalog.digest,
        'revision': before.revision + 1,
        'edits': ordered.map((e) => e.toJson()).toList(),
      };
      final encoded = canonicalJson({'payload': payload, 'sha256': npcWritingHash(payload)});
      if (utf8.encode(encoded).length > maxBytes) {
        throw const FormatException('Слишком большой авторский черновик.');
      }
      await repository.write(catalog.storageKey, encoded);
      return NpcWritingSession._(catalog.digest, before.revision + 1, ordered);
    });
  }

  Future<void> reset(NpcWritingCatalog catalog, {required bool confirmed}) {
    if (!confirmed) throw const FormatException('Удаление не подтверждено.');
    return _locked(catalog.storageKey, () => repository.delete(catalog.storageKey));
  }
}

/// Immutable transmission preview. A resume request contains ONLY untouched
/// empty conversations. Completed/manual/refused drafts are never re-billed.
class NpcWritingRequest {
  NpcWritingRequest._(this.catalogDigest, this.revision, this.batches,
      this.approvalDigest, this.candidateCount);
  final String catalogDigest, approvalDigest;
  final int revision, candidateCount;
  final List<String> batches;
  int get requestCount => batches.length;
  int get maximumAttempts => requestCount * 3;
  String get shownText => batches.map((b) =>
      const JsonEncoder.withIndent('  ').convert(jsonDecode(b))).join('\n\n');

  static NpcWritingRequest prepare(NpcWritingCatalog catalog,
      NpcWritingSession session, {int perRequest = 3}) {
    if (session.catalogDigest != catalog.digest || perRequest < 1 || perRequest > 4) {
      throw const FormatException('Неверная редакция подготовки NPC.');
    }
    NpcWritingStore.validateEdits(catalog, session.edits.values);
    final pending = session.edits.values.where((e) => e.isBlank).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (pending.isEmpty) {
      throw const FormatException('Нет пустых разговоров для ИИ. '
          'Готовые и вручную изменённые реплики сохранены.');
    }
    final batches = <String>[];
    for (var offset = 0; offset < pending.length; offset += perRequest) {
      final rows = pending.skip(offset).take(perRequest).map((edit) {
        final c = catalog.candidates[edit.id]!;
        return <String, dynamic>{
          'candidate_id': c.id, 'actor_id': c.role.characterId,
          'speaker': c.role.displayName,
          'first_chapter': c.firstEvent.source.chapterIndex,
          'response_chapter': c.responseEvent.source.chapterIndex,
          'first_quote': c.firstEvent.source.quote,
          'response_quote': c.responseEvent.source.quote,
          'requires_episodes': edit.dependencies,
          'game_rule': 'The NPC remembers only this approved private game meeting; '
              'do not invent source truth, objects, secrets, actions or new actors.',
        };
      }).toList();
      final payload = <String, dynamic>{
        'format': 'ai_story_npc_writing_request_v1',
        'status': 'UNTRUSTED_PRIVATE_GAME_FICTION',
        'conversations': rows,
      };
      payload['batch_id'] = npcWritingHash({'catalog': catalog.digest, 'payload': payload});
      final encoded = canonicalJson(payload);
      if (utf8.encode(encoded).length > 10 * 1024) {
        throw const FormatException('Передаваемые фрагменты превышают лимит запроса.');
      }
      batches.add(encoded);
    }
    final immutable = List<String>.unmodifiable(batches);
    return NpcWritingRequest._(catalog.digest, session.revision, immutable,
      npcWritingHash({'format': 'npc_writing_consent_v1',
        'catalog': catalog.digest, 'revision': session.revision, 'batches': immutable}),
      pending.length);
  }
}
