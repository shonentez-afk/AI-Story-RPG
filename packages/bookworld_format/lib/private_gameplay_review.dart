import 'package:story_core/story_core.dart';

/// Optional v3 provenance extension for an EXPLICITLY USER-DECLARED private
/// gameplay adaptation. It is NOT a signature, proof of the author's meaning,
/// or evidence that a remote model produced the scene.
///
/// The original source index is rechecked by RichPrivateBookworldWriter.
class PrivateGameplayReview {
  const PrivateGameplayReview._();

  static const format = 'ai_story_private_gameplay_review_m2h8e1_v1';
  static const scope = 'user_declared_private_game_fiction';
  static final _sha = RegExp(r'^[a-f0-9]{64}$');
  static final _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static bool _label(Object? s, int max) =>
      s is String && s.trim() == s && s.isNotEmpty &&
      s.length <= max && !_controls.hasMatch(s);

  static void _keys(Map<String, dynamic> data, Set<String> keys) {
    if (data.length != keys.length ||
        !data.keys.toSet().containsAll(keys)) {
      throw const FormatException('Подменены поля редакторской приёмки');
    }
  }

  /// Importer verifies even a fully rehashed archive cannot attach a
  /// believable review to a foreign choice, forged source or phantom effect.
  static void verify(
    Map<String, dynamic> raw,
    StoryBlueprint blueprint,
    Map<String, dynamic> provenance,
  ) {
    _keys(raw, {
      'format', 'review_scope', 'source_fingerprint',
      'base_archive_sha256', 'source_payload_digest',
      'user_confirmed', 'literary_canon_verified', 'effects',
    });
    if (raw['format'] != format || raw['review_scope'] != scope ||
        raw['source_fingerprint'] != blueprint.sourceFingerprint ||
        raw['user_confirmed'] != true ||
        raw['literary_canon_verified'] != false ||
        raw['base_archive_sha256'] is! String ||
        !_sha.hasMatch(raw['base_archive_sha256'] as String) ||
        raw['source_payload_digest'] is! String ||
        !_sha.hasMatch(raw['source_payload_digest'] as String)) {
      throw const FormatException('Неподтверждённая игровая адаптация');
    }
    final effects = raw['effects'];
    if (effects is! List || effects.isEmpty || effects.length > 6) {
      throw const FormatException('Отсутствуют принятые игровые действия');
    }
    final origins = provenance['scene_origins'] as List;
    final originByScene = {
      for (final origin in origins)
        (origin as Map<String, dynamic>)['scene_id'] as String: origin,
    };
    final presentation = provenance['presentation'] as Map<String, dynamic>;
    final itemNames = presentation['item_names'] as Map<String, dynamic>;
    final factNames = presentation['fact_names'] as Map<String, dynamic>;
    final seen = <String>{};
    for (final rawEffect in effects) {
      if (rawEffect is! Map<String, dynamic>) {
        throw const FormatException('Некорректное игровое действие');
      }
      _keys(rawEffect, {
        'scene_id', 'choice_id', 'op', 'kind',
        'id', 'label', 'source_quote_sha256', 'review_note',
      });
      final sceneId = rawEffect['scene_id'];
      final choiceId = rawEffect['choice_id'];
      final id = rawEffect['id'];
      final op = rawEffect['op'];
      final kind = rawEffect['kind'];
      final label = rawEffect['label'];
      final quoteSha = rawEffect['source_quote_sha256'];
      final note = rawEffect['review_note'];
      if (sceneId is! String || !_id.hasMatch(sceneId) ||
          choiceId is! String || !_id.hasMatch(choiceId) ||
          id is! String || !_id.hasMatch(id) ||
          quoteSha is! String || !_sha.hasMatch(quoteSha) ||
          !_label(label, 120) || !_label(note, 350) ||
          (note as String).length < 18 ||
          !((kind == 'item' &&
                (op == 'grant_item' || op == 'consume_item')) ||
              (kind == 'fact' && op == 'learn_fact'))) {
        throw const FormatException('Необоснованный предмет или знание');
      }
      final key = sceneId + '/' + choiceId + '/' + op + '/' + id;
      if (!seen.add(key)) {
        throw const FormatException('Дублированное редакторское решение');
      }
      final scene = blueprint.scenes[sceneId];
      final origin = originByScene[sceneId];
      if (scene == null || origin == null ||
          origin['origin'] != 'SOURCE_PASSAGE') {
        throw const FormatException('Игровое действие без цитаты в сцене');
      }
      final refs = origin['source_refs'] as List;
      if (!refs.any((r) =>
          (r as Map<String, dynamic>)['quote_sha256'] == quoteSha)) {
        throw const FormatException('Цитата не принадлежит игровой сцене');
      }
      final choice = scene.choices.where((c) => c.id == choiceId).toList();
      if (choice.length != 1 ||
          choice.single.effects.where(
            (e) => e.op == op && e.id == id,
          ).length != 1) {
        throw const FormatException('Принятый эффект отсутствует в сценарии');
      }
      if ((kind == 'item' && itemNames[id] != label) ||
          (kind == 'fact' && factNames[id] != label)) {
        throw const FormatException('Название не совпадает с предметом');
      }
    }
    // Fail closed: the review must cover every typed inventory/knowledge
    // effect. Existing rich worlds without this OPTIONAL extension are valid.
    for (final scene in blueprint.scenes.values) {
      for (final choice in scene.choices) {
        for (final effect in choice.effects) {
          if (effect.op == 'grant_item' ||
              effect.op == 'consume_item' ||
              effect.op == 'learn_fact') {
            final key = scene.id + '/' + choice.id + '/' +
                effect.op + '/' + effect.id!;
            if (!seen.contains(key)) {
              throw const FormatException(
                  'Неучтённый предмет или знание в игровых правилах');
            }
          }
        }
      }
    }
  }
}
