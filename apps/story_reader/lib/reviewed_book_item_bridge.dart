import 'dart:convert';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';

/// A strictly local, reviewed item overlay on the EXISTING private scenario.
/// Every added item comes from one cited game decision; each gift/return
/// targets the same concrete choice, permanent NPC ID and cited source scene.
/// No new book-to-game engine, schema migration or cloud inference.
class ReviewedBookItemBridge {
  const ReviewedBookItemBridge._();

  static final _hash = RegExp(r'^[0-9a-f]{64}$');

  static String _text(Object? raw, String label, int limit) {
    if (raw is! String || raw.trim().isEmpty || raw.trim().length > limit ||
        raw.contains('\u0000')) {
      throw FormatException('Некорректное поле предмета: $label');
    }
    return raw.trim();
  }

  static String _id(String source, String name, String npc) =>
      'item_' + sha256.convert(utf8.encode('$source|$name|$npc'))
          .toString().substring(0, 20);

  /// Each entry is an explicit review: item_name, item_description, actor_id,
  /// acquisition/gift/optional return choice IDs and their independently
  /// reviewed quote SHA256s. No generic item creation without a source.
  /// The caller owns the fresh mutable blueprint and provenance snapshots.
  static ({Map<String, String> names, Map<String, String> descriptions,
    Map<String, dynamic>? social}) apply({
    required Map<String, dynamic> blueprint,
    required Map<String, dynamic> provenance,
    required Map<String, dynamic>? npcSocial,
    required List<Map<String, dynamic>> reviewedItems,
  }) {
    if (reviewedItems.isEmpty) {
      return (names: const {}, descriptions: const {}, social: npcSocial);
    }
    if (reviewedItems.length > 8 ||
        blueprint['rights_status'] != 'private_adaptation' ||
        provenance['rights_status'] != 'private_use_only' ||
        blueprint['source_fingerprint'] != provenance['source_fingerprint'] ||
        provenance['bookworld_id'] != blueprint['book_id']) {
      throw const FormatException('Нельзя добавить предметы без личной книги');
    }
    final source = blueprint['source_fingerprint'];
    if (source is! String || !_hash.hasMatch(source)) {
      throw const FormatException('Предметы относятся к чужому источнику');
    }
    final origins = <String, Map<String, dynamic>>{};
    final rawOrigins = provenance['scene_origins'];
    if (rawOrigins is! List) {
      throw const FormatException('Нет сцен с проверенными источниками');
    }
    for (final entry in rawOrigins) {
      if (entry is! Map<String, dynamic> ||
          entry['scene_id'] is! String ||
          origins.containsKey(entry['scene_id'])) {
        throw const FormatException('Неоднозначный источник предмета');
      }
      origins[entry['scene_id'] as String] = entry;
    }
    final byChoice = <String, (String, Map<String, dynamic>)>{};
    for (final rawScene in blueprint['scenes'] as List) {
      final scene = rawScene as Map<String, dynamic>;
      for (final rawChoice in scene['choices'] as List) {
        final choice = rawChoice as Map<String, dynamic>;
        final id = choice['id'] as String;
        if (byChoice.containsKey(id)) {
          throw const FormatException('Повтор решения для предмета');
        }
        byChoice[id] = (scene['id'] as String, choice);
      }
    }

    final social = npcSocial == null
        ? <String, dynamic>{
            'format': RichNpcSocialContract.authoredItemFormat,
            'review_scope': 'user_declared_private_game_fiction',
            'source_fingerprint': source,
            'user_confirmed': true,
            'literary_canon_verified': false,
            'witnesses': <Map<String, dynamic>>[],
            'rules': <Map<String, dynamic>>[],
            'choice_gates': <Map<String, dynamic>>[],
            'item_transfers': <Map<String, dynamic>>[],
            'item_grants': <Map<String, dynamic>>[],
          }
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(npcSocial)) as Map);
    if (social['source_fingerprint'] != source ||
        social['user_confirmed'] != true ||
        social['literary_canon_verified'] != false ||
        social['review_scope'] != 'user_declared_private_game_fiction' ||
        social['item_transfers'] is List &&
            (social['item_transfers'] as List).isNotEmpty) {
      throw const FormatException(
          'Нельзя смешивать предметы с чужой/другой проверкой NPC');
    }
    // A manually confirmed lifecycle must survive adding a cited item.
    // Never downgrade a v5 review back to the v4 item-only capability.
    final hasLife = social['format'] == RichNpcSocialContract.lifeEventFormat;
    social['format'] = hasLife
        ? RichNpcSocialContract.lifeEventFormat
        : RichNpcSocialContract.authoredItemFormat;
    social.putIfAbsent('choice_gates', () => <Map<String, dynamic>>[]);
    social['item_transfers'] = <Map<String, dynamic>>[];
    social['item_grants'] = <Map<String, dynamic>>[];
    final witnesses = social['witnesses'] as List;
    final rules = social['rules'] as List;
    final transfers = social['item_transfers'] as List;
    final grants = social['item_grants'] as List;
    final names = <String, String>{};
    final descriptions = <String, String>{};
    final allActions = <String>{};
    final initial = blueprint['initial_state'] as Map<String, dynamic>;
    final initialInventory = (initial['inventory'] as List).cast<String>();
    if (initialInventory.isNotEmpty || (blueprint['items'] as List).isNotEmpty) {
      throw const FormatException(
          'Предметы книги должны поступать из проверенного действия');
    }

    (String, Map<String, dynamic>, int) reviewedChoice(
        String action, String quote) {
      final resolved = byChoice[action];
      if (resolved == null || !_hash.hasMatch(quote)) {
        throw const FormatException('Нет подтверждённого действия предмета');
      }
      final origin = origins[resolved.$1];
      final chapter = origin?['chapter_index'];
      final refs = origin?['source_refs'];
      if (origin?['origin'] != 'SOURCE_PASSAGE' ||
          chapter is! int || refs is! List ||
          !refs.any((entry) => entry is Map &&
              entry['quote_sha256'] == quote &&
              entry['chapter_index'] is int &&
              entry['visible_after_chapter'] is int &&
              entry['chapter_index'] <= chapter &&
              entry['visible_after_chapter'] <= chapter)) {
        throw const FormatException(
            'У действия с предметом отсутствует доступная цитата книги');
      }
      return (resolved.$1, resolved.$2, chapter);
    }

    void witness(String scene, String actor, String quote) {
      final existing = witnesses.where((entry) =>
          entry is Map && entry['scene_id'] == scene &&
          entry['actor_id'] == actor).toList();
      if (existing.length > 1 ||
          (existing.isNotEmpty && existing.single['mode'] != 'present')) {
        throw const FormatException(
            'NPC не может передать вещь, если он не присутствовал');
      }
      if (existing.isEmpty) {
        witnesses.add({
          'scene_id': scene, 'actor_id': actor,
          'mode': 'present', 'source_quote_sha256': quote,
        });
      }
    }

    void memory(String scene, String action, String actor,
        String itemId, String quote) {
      final memoryId = 'item_' + sha256.convert(
          utf8.encode('$itemId|$scene|$action|$actor'))
          .toString().substring(0, 20);
      if (rules.any((entry) => entry is Map &&
          entry['observer_id'] == actor &&
          entry['memory_id'] == memoryId)) {
        throw const FormatException('Повтор памяти о передаче предмета');
      }
      rules.add({
        'memory_id': memoryId, 'scene_id': scene, 'choice_id': action,
        'observer_id': actor, 'kind': 'witnessed',
        'related_actor_id': null, 'relationship_delta': 0,
        'max_triggers': 1, 'source_quote_sha256': quote,
      });
    }

    for (final review in reviewedItems) {
      const fields = {
        'item_name', 'item_description', 'actor_id',
        'acquire_choice_id', 'acquire_quote_sha256',
        'give_choice_id', 'give_quote_sha256',
        'return_choice_id', 'return_quote_sha256',
        'personally_witnessed',
      };
      if (review.keys.toSet().length != fields.length ||
          !review.keys.toSet().containsAll(fields) ||
          review['personally_witnessed'] != true) {
        throw const FormatException('Нет личной проверки предмета и NPC');
      }
      final name = _text(review['item_name'], 'название', 90);
      final description = _text(review['item_description'],
          'краткое описание', 240);
      final actor = review['actor_id'];
      if (actor is! String || !CharacterId.isValidNpc(actor) ||
          !(blueprint['actors'] as List).contains(actor)) {
        throw const FormatException('Неверный постоянный ID владельца вещи');
      }
      final acquireId = _text(review['acquire_choice_id'], 'получение', 64);
      final giveId = _text(review['give_choice_id'], 'передача', 64);
      final returnId = review['return_choice_id'];
      if (returnId != null && (returnId is! String ||
          returnId.trim().isEmpty)) {
        throw const FormatException('Неверное действие возврата вещи');
      }
      final acquireQuote = _text(
          review['acquire_quote_sha256'], 'цитата получения', 64);
      final giveQuote = _text(
          review['give_quote_sha256'], 'цитата передачи', 64);
      final returnQuote = review['return_quote_sha256'];
      if (returnId == null && returnQuote != null ||
          returnId != null && returnQuote is! String ||
          acquireId == giveId ||
          returnId != null && (returnId == acquireId ||
                              returnId == giveId)) {
        throw const FormatException(
            'Получение, передача и возврат — разные реальные действия');
      }
      final acquired = reviewedChoice(acquireId, acquireQuote);
      final gifted = reviewedChoice(giveId, giveQuote);
      if (acquired.$3 > gifted.$3) {
        throw const FormatException('NPC получил вещь раньше её появления');
      }
      (String, Map<String, dynamic>, int)? returned;
      if (returnId != null) {
        returned = reviewedChoice(returnId, returnQuote as String);
        if (returned.$3 < gifted.$3) {
          throw const FormatException('Возврат вещи предшествует передаче');
        }
      }
      final itemId = _id(source, name, actor);
      if (names.containsKey(itemId) || names.containsValue(name)) {
        throw const FormatException('Дублирующийся игровой предмет');
      }
      names[itemId] = name;
      descriptions[itemId] = description;
      if (!allActions.add('$acquireId|$itemId') ||
          !allActions.add('$giveId|$itemId') ||
          returnId != null && !allActions.add('$returnId|$itemId')) {
        throw const FormatException('Повтор предметного действия');
      }
      (blueprint['items'] as List).add(itemId);
      (acquired.$2['effects'] as List).add({
        'op': 'grant_item', 'id': itemId,
      });
      grants.add({
        'scene_id': acquired.$1, 'choice_id': acquireId,
        'item_id': itemId, 'source_quote_sha256': acquireQuote,
      });
      (gifted.$2['conditions'] as List).add({
        'op': 'has_item', 'id': itemId,
      });
      (gifted.$2['effects'] as List).add({
        'op': 'consume_item', 'id': itemId,
      });
      witness(gifted.$1, actor, giveQuote);
      memory(gifted.$1, giveId, actor, itemId, giveQuote);
      transfers.add({
        'scene_id': gifted.$1, 'choice_id': giveId,
        'item_id': itemId, 'from_actor_id': 'player',
        'to_actor_id': actor, 'source_quote_sha256': giveQuote,
      });
      if (returned != null) {
        (returned.$2['effects'] as List).add({
          'op': 'grant_item', 'id': itemId,
        });
        witness(returned.$1, actor, returnQuote as String);
        memory(returned.$1, returnId as String, actor, itemId, returnQuote);
        transfers.add({
          'scene_id': returned.$1, 'choice_id': returnId,
          'item_id': itemId, 'from_actor_id': actor,
          'to_actor_id': 'player', 'source_quote_sha256': returnQuote,
        });
      }
    }
    // Isolate new game identity from previous campaigns and from unreviewed
    // versions of this book; never apply new items to an old save.
    final digest = sha256.convert(utf8.encode(
        canonicalJson({'previous': blueprint['book_id'], 'items': reviewedItems})))
        .toString();
    blueprint['book_id'] = 'book_' + source.substring(0, 12) +
        '_' + digest.substring(0, 20);
    provenance['bookworld_id'] = blueprint['book_id'];
    return (names: Map.unmodifiable(names),
        descriptions: Map.unmodifiable(descriptions),
        social: social);
  }
}
