import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

import 'private_bookworld_writer.dart';
import 'private_gameplay_review.dart';
import 'private_rich_bookworld.dart';
import 'src/zip_v1.dart';

/// Recompiles an ALREADY VALIDATED private v3 bookworld with explicitly
/// reviewed user-declared FICTIONAL gameplay effects. The original game and
/// any saved campaign remain untouched; a new archive identity is created.
///
/// No model output is trusted as a rule, no new source quote is invented and
/// NO literary-canon certification is made. The optional review record is
/// checked independently on every future import by both Dart and Python.
class ReviewedGameplayBookworldWriter {
  const ReviewedGameplayBookworldWriter();

  Uint8List build({
    required Uint8List verifiedBaseArchive,
    required Map<String, dynamic> sourceIndex,
    required Map<String, dynamic> userReview,
  }) {
    final base = const RichPrivateBookworldImporter()
        .inspect(verifiedBaseArchive);
    final files = BworldZipV1.readPrivate(verifiedBaseArchive);
    final raw = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(files['scenario/blueprint.json']!)) as Map);
    final provenance = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(files['source/provenance.json']!)) as Map);

    final sourceHash = sha256.convert(verifiedBaseArchive).toString();
    final signature = RegExp(r'^[a-f0-9]{64}$');
    if (provenance.containsKey('gameplay_review') ||
        (raw['items'] as List).isNotEmpty ||
        (raw['facts'] as List).isNotEmpty ||
        (raw['initial_state'] as Map)['stats'] is! Map ||
        ((raw['initial_state'] as Map)['stats'] as Map).isNotEmpty ||
        userReview['format'] != PrivateGameplayReview.format ||
        userReview['review_scope'] != PrivateGameplayReview.scope ||
        userReview['source_fingerprint'] != base.sourceFingerprint ||
        userReview['base_archive_sha256'] != sourceHash ||
        userReview['source_payload_digest'] is! String ||
        !signature.hasMatch(userReview['source_payload_digest'] as String) ||
        userReview['user_confirmed'] != true ||
        userReview['literary_canon_verified'] != false) {
      throw const FormatException(
          'Нужен новый проверенный игровой мир и явное частное согласие');
    }
    final options = userReview['effects'];
    if (options is! List || options.isEmpty || options.length > 6) {
      throw const FormatException('Нет согласованных игровых действий');
    }
    final addedItems = <String, String>{};
    final addedFacts = <String, String>{};
    final seenOps = <String>{};
    final scenes = raw['scenes'] as List;
    for (final entry in options) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Некорректное редакторское действие');
      }
      final sceneId = entry['scene_id'];
      final choiceId = entry['choice_id'];
      final key = entry['id'];
      final op = entry['op'];
      final kind = entry['kind'];
      final label = entry['label'];
      if (sceneId is! String || choiceId is! String ||
          key is! String || label is! String ||
          !seenOps.add('$sceneId/$choiceId/$op/$key')) {
        throw const FormatException('Повторная или чужая игровая операция');
      }
      final sceneMatches = scenes.where(
        (s) => (s as Map)['id'] == sceneId).toList();
      if (sceneMatches.length != 1) {
        throw const FormatException('Отсутствует игровая сцена');
      }
      final choices = (sceneMatches.single as Map)['choices'] as List;
      final match = choices.where(
        (c) => (c as Map)['id'] == choiceId).toList();
      if (match.length != 1) {
        throw const FormatException('Отсутствует выбор для предмета');
      }
      final choice = match.single as Map<String, dynamic>;
      final effect = <String, dynamic>{'op': op, 'id': key};
      if (kind == 'item' &&
          (op == 'grant_item' || op == 'consume_item')) {
        final old = addedItems[key];
        if (old != null && old != label) {
          throw const FormatException('Один предмет имеет разные названия');
        }
        addedItems[key] = label;
      } else if (kind == 'fact' && op == 'learn_fact') {
        final old = addedFacts[key];
        if (old != null && old != label) {
          throw const FormatException('Одно знание имеет разные названия');
        }
        addedFacts[key] = label;
        effect['actor'] = 'player';
      } else {
        throw const FormatException('Неодобренный тип изменения RPG');
      }
      choice['effects'] = [
        ...(choice['effects'] as List),
        effect,
      ];
    }
    raw['items'] = addedItems.keys.toList()..sort();
    raw['facts'] = addedFacts.keys.toList()..sort();
    final oldPresentation =
        provenance['presentation'] as Map<String, dynamic>;
    final newPresentation = Map<String, dynamic>.of(oldPresentation);
    newPresentation['item_names'] = addedItems;
    newPresentation['item_descriptions'] = {
      for (final entry in addedItems.entries)
        entry.key: 'Частная игровая адаптация: ' + entry.value +
          '. Не подтверждено как литературный канон.',
    };
    newPresentation['fact_names'] = addedFacts;
    provenance['presentation'] = newPresentation;
    // Keep exact per-source citations and all existing model attribution.
    // An offline editor must NOT replace unknown by an invented provider.
    provenance['gameplay_review'] = Map<String, dynamic>.from(userReview);
    final nextId = 'reviewed_' +
        base.sourceFingerprint.substring(0, 12) + '_' +
        sha256.convert(utf8.encode(
            sourceHash + ':' + canonicalJson(userReview)))
            .toString().substring(0, 12);
    raw['book_id'] = nextId;
    provenance['bookworld_id'] = nextId;

    // Independently rejects bogus source refs, phantom effects, impossible
    // consumption, unreachable endings, altered rights and bad SQLite.
    return const RichPrivateBookworldWriter().build(
      blueprint: raw,
      provenance: provenance,
      sourceIndex: sourceIndex,
    );
  }
}
