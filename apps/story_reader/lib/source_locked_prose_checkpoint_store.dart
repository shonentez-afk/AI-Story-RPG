import 'dart:convert';

import 'source_analysis_checkpoint_repository.dart';
import 'zai_source_locked_prose_preview.dart';
import 'story_plan.dart';

/// Application-private generated prose only. The original FB2, source quote,
/// cloud credentials and campaign state are not copied into this checkpoint.
///
/// The backing app-support directory is not E2E encrypted. Do not use this
/// store for credentials; users can clear the locally cached prose.
class SourceLockedProseCheckpointStore {
  SourceLockedProseCheckpointStore({
    SourceAnalysisCheckpointRepository? repository,
  }) : repository = repository ??
          const FileSourceAnalysisCheckpointRepository(
            scope: SourceCheckpointScope.zaiProseSceneDrafts,
          );

  final SourceAnalysisCheckpointRepository repository;

  static const format = 'ai_story_private_prose_scene_checkpoint_m2h7c2_v1';
  static const maxEntries = 128;
  static const maxUtf8Bytes = 512 * 1024;
  static final RegExp _hash = RegExp(r'^[a-f0-9]{64}$');
  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final RegExp _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static void _keys(Map<String, dynamic> map, Set<String> allowed) {
    if (map.keys.toSet().length != allowed.length ||
        !map.keys.toSet().containsAll(allowed)) {
      throw const FormatException('Неизвестная схема частного черновика.');
    }
  }

  static void _check(SourceLockedProseDraft draft,
      SourceLockedProseContext context) {
    if (!_hash.hasMatch(context.index.sourceFingerprint) ||
        !_hash.hasMatch(context.approvalDigest) ||
        !_id.hasMatch(context.situation.id) ||
        draft.sourceFingerprint != context.index.sourceFingerprint ||
        draft.approvalDigest != context.approvalDigest ||
        draft.situationId != context.situation.id ||
        draft.route != context.situation.route ||
        draft.text.trim() != draft.text ||
        draft.text.length < 80 || draft.text.length > 2600 ||
        draft.uncertainty.trim() != draft.uncertainty ||
        draft.uncertainty.length < 10 ||
        draft.uncertainty.length > 300 ||
        _controls.hasMatch(draft.text) ||
        _controls.hasMatch(draft.uncertainty)) {
      throw const FormatException('Черновик сцены повреждён '
          'или принадлежит другой версии книги/сценария.');
    }
  }

  static Map<String, Object> _encode(SourceLockedProseDraft draft) => {
    'scene_id': draft.situationId,
    'context_digest': draft.approvalDigest,
    'route': draft.route.name,
    'text': draft.text,
    'uncertainty': draft.uncertainty,
    'status': 'PROSE_DRAFT_REVIEW_REQUIRED',
  };

  static SourceLockedProseDraft _decodeDraft(
      Map<String, dynamic> map, String fingerprint) {
    _keys(map, {
      'scene_id', 'context_digest', 'route', 'text',
      'uncertainty', 'status',
    });
    if (map['status'] != 'PROSE_DRAFT_REVIEW_REQUIRED' ||
        map['scene_id'] is! String ||
        map['context_digest'] is! String ||
        map['route'] is! String ||
        map['text'] is! String ||
        map['uncertainty'] is! String) {
      throw const FormatException('Состояние черновика подменено.');
    }
    final routeName = map['route'] as String;
    final routes = StoryRoute.values.where(
        (value) => value.name == routeName).toList();
    if (routes.length != 1 ||
        !_id.hasMatch(map['scene_id'] as String) ||
        !_hash.hasMatch(map['context_digest'] as String)) {
      throw const FormatException('Неверная ссылка на художественную сцену.');
    }
    return SourceLockedProseDraft(
      sourceFingerprint: fingerprint,
      situationId: map['scene_id'] as String,
      approvalDigest: map['context_digest'] as String,
      text: map['text'] as String,
      uncertainty: map['uncertainty'] as String,
      route: routes.single,
    );
  }

  Future<List<SourceLockedProseDraft>> _readAll(
      SourceLockedProseContext context) async {
    final raw = await repository.read(context.index.sourceFingerprint);
    if (raw == null) return [];
    if (utf8.encode(raw).length > maxUtf8Bytes) {
      throw const FormatException('Слишком большой художественный checkpoint.');
    }
    try {
      final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _keys(record, {'format', 'source_fingerprint', 'entries'});
      if (record['format'] != format ||
          record['source_fingerprint'] != context.index.sourceFingerprint ||
          record['entries'] is! List) {
        throw const FormatException('Подмена сохранённой редакции книги.');
      }
      final entries = record['entries'] as List;
      if (entries.length > maxEntries) {
        throw const FormatException('Слишком много черновиков.');
      }
      final result = <SourceLockedProseDraft>[];
      final ids = <String>{};
      for (final entry in entries) {
        final decoded = _decodeDraft(
          Map<String, dynamic>.from(entry as Map),
          context.index.sourceFingerprint,
        );
        if (!ids.add(decoded.situationId)) {
          throw const FormatException('Дублирование сохранённых сцен.');
        }
        // All old plan revisions remain unapproved, even when recoverable.
        if (decoded.text.trim() != decoded.text ||
            decoded.text.length < 80 || decoded.text.length > 2600 ||
            decoded.uncertainty.trim() != decoded.uncertainty ||
            decoded.uncertainty.length < 10 ||
            decoded.uncertainty.length > 300 ||
            _controls.hasMatch(decoded.text) ||
            _controls.hasMatch(decoded.uncertainty)) {
          throw const FormatException('Повреждён сохранённый художественный текст.');
        }
        result.add(decoded);
      }
      return result;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Неверный частный checkpoint сцен.');
    }
  }

  Future<SourceLockedProseDraft?> read(
      SourceLockedProseContext context) async {
    final entries = await _readAll(context);
    for (final draft in entries) {
      if (draft.situationId == context.situation.id &&
          draft.approvalDigest == context.approvalDigest) {
        _check(draft, context);
        return draft;
      }
    }
    return null; // Changed edition, plan, or context: no cache reuse.
  }

  /// Does not overwrite an already persisted response for the SAME digest:
  /// repeated page opens never silently spend another model request.
  Future<void> save({
    required SourceLockedProseContext context,
    required SourceLockedProseDraft draft,
  }) async {
    _check(draft, context);
    final before = await _readAll(context);
    if (before.any((entry) =>
        entry.situationId == draft.situationId &&
        entry.approvalDigest == draft.approvalDigest)) {
      return;
    }
    final entries = [
      for (final item in before)
        if (item.situationId != draft.situationId) item,
      draft,
    ];
    if (entries.length > maxEntries) {
      throw const FormatException('Исчерпан предел частных черновиков.');
    }
    final encoded = jsonEncode({
      'format': format,
      'source_fingerprint': context.index.sourceFingerprint,
      'entries': [for (final item in entries) _encode(item)],
    });
    if (utf8.encode(encoded).length > maxUtf8Bytes) {
      throw const FormatException('Художественный checkpoint слишком большой.');
    }
    await repository.write(context.index.sourceFingerprint, encoded);
  }

  /// Explicit user action removes only this scene, not the imported book,
  /// another scene, game package or campaign save.
  Future<void> delete(SourceLockedProseContext context) async {
    final entries = await _readAll(context);
    final kept = entries.where((item) =>
        item.situationId != context.situation.id).toList();
    if (kept.length == entries.length) return;
    if (kept.isEmpty) {
      await repository.delete(context.index.sourceFingerprint);
      return;
    }
    await repository.write(context.index.sourceFingerprint, jsonEncode({
      'format': format,
      'source_fingerprint': context.index.sourceFingerprint,
      'entries': [for (final item in kept) _encode(item)],
    }));
  }
}
