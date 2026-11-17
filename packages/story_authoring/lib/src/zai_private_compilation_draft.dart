import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'zai_causal_choice_notebook.dart';

/// Private M2f3f2 editor checkpoint. Contains ONLY the user's own scene
/// prose and explicit IDs. No original FB2 text, API key, license grant or
/// generated BookWorld is embedded in the checkpoint.
class ZaiPrivateCompilationDraft {
  ZaiPrivateCompilationDraft._(
    this.sourceFingerprint,
    this.causalSha256,
    Set<String> sourceSceneIds,
    Map<String, String> eventAssertionIds,
    Map<String, String> authoredSceneTexts,
  ) : sourceSceneIds = Set.unmodifiable(sourceSceneIds),
      eventAssertionIds = Map.unmodifiable(eventAssertionIds),
      authoredSceneTexts = Map.unmodifiable(authoredSceneTexts);

  static const format = 'ai_story_zai_private_compile_draft_m2f3f2_v1';
  static const maxBytes = 2 * 1024 * 1024;

  final String sourceFingerprint;
  final String causalSha256;
  final Set<String> sourceSceneIds;
  final Map<String, String> eventAssertionIds;
  final Map<String, String> authoredSceneTexts;

  static String _sha(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String _signature(ZaiCausalChoiceNotebook notebook) =>
      _sha(notebook.encode());

  static ZaiPrivateCompilationDraft empty(
          ZaiCausalChoiceNotebook notebook) =>
      ZaiPrivateCompilationDraft._(
        notebook.board.graph.index.sourceFingerprint,
        _signature(notebook), const {}, const {}, const {});

  void _validate(ZaiCausalChoiceNotebook notebook) {
    final board = notebook.board;
    final scenes = {for (final scene in board.scenes) scene.id};
    final events = {
      for (final scene in board.scenes) ...scene.eventIds,
    };
    if (sourceFingerprint != board.graph.index.sourceFingerprint ||
        causalSha256 != _signature(notebook) ||
        sourceSceneIds.length > 192 ||
        !scenes.containsAll(sourceSceneIds) ||
        authoredSceneTexts.length > scenes.length ||
        !scenes.containsAll(authoredSceneTexts.keys) ||
        authoredSceneTexts.values.any((s) => s.length > 6000) ||
        eventAssertionIds.length > events.length ||
        !events.containsAll(eventAssertionIds.keys) ||
        eventAssertionIds.values.any(
            (v) => !RegExp(r'^[a-f0-9]{32}$').hasMatch(v))) {
      throw const FormatException(
          'Подготовка M2f3f2 относится к другой редакции сцены или содержит ошибку.');
    }
    final sourceEvents = <String>{
      for (final scene in board.scenes)
        if (sourceSceneIds.contains(scene.id)) ...scene.eventIds,
    };
    if (!sourceEvents.containsAll(eventAssertionIds.keys)) {
      throw const FormatException(
          'Подтверждение цитаты относится к авторской альтернативе.');
    }
  }

  ZaiPrivateCompilationDraft _copy(
      ZaiCausalChoiceNotebook notebook, {
      Set<String>? sourceIds,
      Map<String, String>? links,
      Map<String, String>? texts,
    }) {
    final result = ZaiPrivateCompilationDraft._(
      sourceFingerprint,
      causalSha256,
      sourceIds ?? sourceSceneIds,
      links ?? eventAssertionIds,
      texts ?? authoredSceneTexts,
    );
    result._validate(notebook);
    return result;
  }

  ZaiPrivateCompilationDraft setSource(
      ZaiCausalChoiceNotebook notebook, String sceneId, bool isSource) {
    if (!notebook.board.scenes.any((s) => s.id == sceneId)) {
      throw const FormatException('Сцена больше не существует.');
    }
    final next = Set<String>.from(sourceSceneIds);
    if (isSource) { next.add(sceneId); } else { next.remove(sceneId); }
    final sourceEvents = {
      for (final scene in notebook.board.scenes)
        if (next.contains(scene.id)) ...scene.eventIds,
    };
    return _copy(notebook, sourceIds: next,
      links: Map.fromEntries(eventAssertionIds.entries
          .where((e) => sourceEvents.contains(e.key))));
  }

  ZaiPrivateCompilationDraft setText(
      ZaiCausalChoiceNotebook notebook, String sceneId, String value) {
    if (!notebook.board.scenes.any((s) => s.id == sceneId)) {
      throw const FormatException('Сцена больше не существует.');
    }
    return _copy(notebook, texts: {...authoredSceneTexts, sceneId: value});
  }

  ZaiPrivateCompilationDraft setAssertion(
      ZaiCausalChoiceNotebook notebook, String eventId, String? assertionId) {
    final links = Map<String, String>.from(eventAssertionIds);
    if (assertionId == null) { links.remove(eventId); }
    else { links[eventId] = assertionId; }
    return _copy(notebook, links: links);
  }

  Map<String, Object> _payload() => {
    'source_fingerprint': sourceFingerprint,
    'causal_sha256': causalSha256,
    'source_scene_ids': sourceSceneIds.toList()..sort(),
    'event_assertion_ids': {
      for (final key in eventAssertionIds.keys.toList()..sort())
        key: eventAssertionIds[key]!,
    },
    'authored_scene_texts': {
      for (final key in authoredSceneTexts.keys.toList()..sort())
        key: authoredSceneTexts[key]!,
    },
    'status': 'PRIVATE_EDITOR_INPUTS_NOT_GAME',
  };

  String encode(ZaiCausalChoiceNotebook notebook) {
    _validate(notebook);
    final payload = _payload();
    final raw = jsonEncode({
      'format': format,
      'payload': payload,
      'sha256': _sha(jsonEncode(payload)),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой редакторский черновик.');
    }
    return raw;
  }

  static ZaiPrivateCompilationDraft decode(
      ZaiCausalChoiceNotebook notebook, String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Слишком большой checkpoint M2f3f2.');
    }
    try {
      final root = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      const keys = {'format', 'payload', 'sha256'};
      if (root.keys.toSet().length != keys.length ||
          !root.keys.toSet().containsAll(keys) ||
          root['format'] != format) {
        throw const FormatException('Неизвестная версия черновика M2f3f2.');
      }
      final p = Map<String, dynamic>.from(root['payload'] as Map);
      const payloadKeys = {
        'source_fingerprint', 'causal_sha256', 'source_scene_ids',
        'event_assertion_ids', 'authored_scene_texts', 'status',
      };
      if (p.keys.toSet().length != payloadKeys.length ||
          !p.keys.toSet().containsAll(payloadKeys) ||
          p['status'] != 'PRIVATE_EDITOR_INPUTS_NOT_GAME' ||
          root['sha256'] != _sha(jsonEncode(p))) {
        throw const FormatException('Подмена редакторского checkpoint.');
      }
      final value = ZaiPrivateCompilationDraft._(
        p['source_fingerprint'] as String,
        p['causal_sha256'] as String,
        (p['source_scene_ids'] as List).cast<String>().toSet(),
        Map<String, String>.from(p['event_assertion_ids'] as Map),
        Map<String, String>.from(p['authored_scene_texts'] as Map),
      );
      value._validate(notebook);
      // Reject forged duplicates in set fields, not just an arbitrary hash.
      if ((p['source_scene_ids'] as List).length !=
          value.sourceSceneIds.length) {
        throw const FormatException('Повторное подтверждение исходной сцены.');
      }
      return value;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён checkpoint M2f3f2.');
    }
  }
}
