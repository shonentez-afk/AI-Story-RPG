import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:story_core/story_core.dart';
import 'private_bookworld_writer.dart';
import 'private_rich_bookworld.dart';
import 'src/zip_v1.dart';

/// Explicitly reviewed starting inventory, player knowledge and gameplay gates
/// for an ALREADY source-reviewed BOOK_CHARACTER role in the SAME native v4.
/// Does not upgrade literary truth, infer another NPC's secrets or fork runtime.
final class ReviewedBookCharacterStartWriter {
  const ReviewedBookCharacterStartWriter();
  static const reviewFormat = 'ai_story_book_character_start_review_v1';
  static const scope = 'user_declared_private_game_fiction';
  static final _sha = RegExp(r'^[a-f0-9]{64}$');
  static final _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final _ctrl = RegExp(r'[\x00-\x1f\x7f]');

  static String digest(String source) => sha256.convert(
      utf8.encode('reviewed-book-character-start-v1\n' + source)).toString();

  static Map<String, dynamic> _obj(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected reviewed JSON object');
    }
    return value;
  }
  static void _keys(Map<String, dynamic> map, Set<String> keys) {
    if (map.length != keys.length || !map.keys.toSet().containsAll(keys)) {
      throw const FormatException('Unrecognized book character review');
    }
  }
  static String _key(Object? value) {
    if (value is! String || !_id.hasMatch(value)) {
      throw const FormatException('Invalid RPG identifier');
    }
    return value;
  }
  static String _hash(Object? value) {
    if (value is! String || !_sha.hasMatch(value)) {
      throw const FormatException('Invalid source evidence digest');
    }
    return value;
  }
  static String _label(Object? value, int max) {
    if (value is! String || value.trim() != value || value.isEmpty ||
        value.length > max || _ctrl.hasMatch(value)) {
      throw const FormatException('Unreviewed character attribute');
    }
    return value;
  }

  Uint8List build({
    required Uint8List verifiedBaseArchive,
    required Map<String, dynamic> sourceIndex,
    required String reviewJson,
    required String approvedDigest,
    required bool userConfirmed,
  }) {
    if (!userConfirmed || utf8.encode(reviewJson).length > 128 * 1024 ||
        approvedDigest != digest(reviewJson)) {
      throw const FormatException('Hero starting state approval is stale');
    }
    final review = _obj(jsonDecode(reviewJson));
    if (canonicalJson(review) != reviewJson) {
      throw const FormatException('Noncanonical hero approval');
    }
    _keys(review, {
      'format', 'scope', 'source_fingerprint', 'base_archive_sha256',
      'character_id', 'character_group_digest', 'hero_quote_sha256',
      'hero_mention',
      'initial_items', 'initial_facts', 'choice_gates',
      'literary_canon_verified',
    });
    final base = const RichPrivateBookworldImporter()
        .inspect(verifiedBaseArchive);
    if (base.formatVersion != 4 || review['format'] != reviewFormat ||
        review['scope'] != scope || review['literary_canon_verified'] != false ||
        review['source_fingerprint'] != base.sourceFingerprint ||
        review['base_archive_sha256'] != base.archiveSha256 ||
        sourceIndex['source_fingerprint'] != base.sourceFingerprint ||
        sourceIndex['chapter_count'] != base.sourceChaptersTotal ||
        sourceIndex['indexed_chapter_count'] != base.sourceChaptersTotal) {
      throw const FormatException('Review belongs to another source edition');
    }
    final actor = review['character_id'];
    if (actor is! String || !CharacterId.isValidNpc(actor) ||
        review['character_group_digest'] is! String ||
        !_sha.hasMatch(review['character_group_digest'] as String)) {
      throw const FormatException('Hero has no permanent reviewed identity');
    }
    final identities = base.blueprint.initial.flags.entries
        .where((entry) => entry.key.startsWith('player_is_npc_')).toList();
    if (identities.length != 1 || identities.single.key != 'player_is_' + actor ||
        identities.single.value != true ||
        base.blueprint.actors.contains(actor) ||
        base.blueprint.initial.inventory.isNotEmpty ||
        base.blueprint.initial.knowledge['player']?.isNotEmpty == true ||
        base.blueprint.initial.tick != 0) {
      throw const FormatException('Base character start is not immutable');
    }
    final entries = BworldZipV1.readPrivate(verifiedBaseArchive);
    final bp = _obj(jsonDecode(utf8.decode(entries['scenario/blueprint.json']!)));
    final provenance = _obj(jsonDecode(
        utf8.decode(entries['source/provenance.json']!)));
    if (provenance.containsKey('initial_state_review')) {
      throw const FormatException('Hero already has a reviewed start');
    }
    final origins = <String, Map<String, dynamic>>{
      for (final raw in provenance['scene_origins'] as List)
        _obj(raw)['scene_id'] as String: _obj(raw),
    };
    final initialQuotes = <String>{};
    bool sceneQuote(String sceneId, String hash) {
      final o = origins[sceneId];
      return o != null && o['origin'] == 'SOURCE_PASSAGE' &&
          (o['source_refs'] as List).any((raw) =>
            raw is Map<String, dynamic> &&
            raw['quote_sha256'] == hash &&
            raw['chapter_index'] == o['chapter_index'] &&
            raw['visible_after_chapter'] <= o['chapter_index']);
    }
    for (final o in origins.values) {
      if (o['origin'] != 'SOURCE_PASSAGE' || o['chapter_index'] != 0) continue;
      for (final raw in o['source_refs'] as List) {
        if (raw is Map<String, dynamic> && raw['chapter_index'] == 0 &&
            raw['visible_after_chapter'] == 0) {
          initialQuotes.add(raw['quote_sha256'] as String);
        }
      }
    }
    if (!initialQuotes.contains(_hash(review['hero_quote_sha256']))) {
      throw const FormatException('Hero evidence appears after game opening');
    }
    final mention = _obj(review['hero_mention']);
    _keys(mention, {'evidence_id', 'chunk_id', 'start_utf16',
      'end_utf16', 'evidence_sha256'});
    final chunkId = mention['chunk_id'];
    final begin = mention['start_utf16'], end = mention['end_utf16'];
    if (mention['evidence_id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(mention['evidence_id'] as String) ||
        chunkId is! String || begin is! int || end is! int ||
        begin < 0 || end <= begin || end - begin > 180 ||
        mention['evidence_sha256'] is! String ||
        !_sha.hasMatch(mention['evidence_sha256'] as String)) {
      throw const FormatException('Invalid reviewed hero mention');
    }
    final chunks = sourceIndex['chunks'];
    if (chunks is! List) {
      throw const FormatException('Missing original book fragments');
    }
    final matches = chunks.where((v) =>
        v is Map && v['id'] == chunkId && v['chapter_index'] == 0).toList();
    if (matches.length != 1) {
      throw const FormatException('Hero is not confirmed in opening chapter');
    }
    final chunk = _obj(matches.single);
    if (chunk['text'] is! String || chunk['start_utf16'] is! int ||
        chunk['end_utf16'] is! int ||
        begin < chunk['start_utf16'] || end > chunk['end_utf16']) {
      throw const FormatException('Hero mention outside source text');
    }
    final exact = (chunk['text'] as String).substring(
        begin - (chunk['start_utf16'] as int),
        end - (chunk['start_utf16'] as int));
    if (sha256.convert(utf8.encode(exact)).toString() !=
        mention['evidence_sha256']) {
      throw const FormatException('Hero mention SHA is invalid');
    }
    var overlap = false;
    for (final origin in origins.values) {
      if (origin['origin'] != 'SOURCE_PASSAGE' ||
          origin['chapter_index'] != 0) continue;
      for (final raw in origin['source_refs'] as List) {
        if (raw is Map<String, dynamic> &&
            raw['quote_sha256'] == review['hero_quote_sha256'] &&
            raw['chunk_id'] == chunkId &&
            raw['start_utf16'] < end && begin < raw['end_utf16']) {
          overlap = true;
        }
      }
    }
    if (!overlap) {
      throw const FormatException('Hero mention is not in signed entry scene');
    }
    final items = review['initial_items'];
    final facts = review['initial_facts'];
    final gates = review['choice_gates'];
    if (items is! List || facts is! List || gates is! List ||
        items.length > 12 || facts.length > 24 || gates.length > 16 ||
        (items.isEmpty && facts.isEmpty)) {
      throw const FormatException('Invalid starting knowledge and item count');
    }
    final itemCatalog = (bp['items'] as List).cast<String>();
    final factCatalog = (bp['facts'] as List).cast<String>();
    final initial = _obj(bp['initial_state']);
    final known = (initial['knowledge'] as Map)['player'] as List;
    final view = _obj(provenance['presentation']);
    final names = _obj(view['item_names']);
    final descriptions = _obj(view['item_descriptions']);
    final factNames = _obj(view['fact_names']);
    final newItems = <String>{}, newFacts = <String>{};
    final itemEvidence = <Map<String, dynamic>>[];
    final factEvidence = <Map<String, dynamic>>[];
    for (final raw in items) {
      final m = _obj(raw);
      _keys(m, {'item_id', 'name', 'description', 'source_quote_sha256'});
      final id = _key(m['item_id']);
      final evidence = _hash(m['source_quote_sha256']);
      if (!newItems.add(id) || itemCatalog.contains(id) ||
          !initialQuotes.contains(evidence)) {
        throw const FormatException('Item cannot start without opening citation');
      }
      itemCatalog.add(id);
      (initial['inventory'] as List).add(id);
      names[id] = _label(m['name'], 90);
      descriptions[id] = _label(m['description'], 240);
      itemEvidence.add({'item_id': id, 'source_quote_sha256': evidence});
    }
    for (final raw in facts) {
      final m = _obj(raw);
      _keys(m, {'fact_id', 'name', 'source_quote_sha256'});
      final id = _key(m['fact_id']);
      final evidence = _hash(m['source_quote_sha256']);
      if (!newFacts.add(id) || factCatalog.contains(id) ||
          !initialQuotes.contains(evidence)) {
        throw const FormatException('Fact is not known to hero at game opening');
      }
      factCatalog.add(id);
      known.add(id);
      factNames[id] = _label(m['name'], 160);
      factEvidence.add({
        'actor_id': 'player', 'fact_id': id,
        'source_quote_sha256': evidence,
      });
    }
    final scenes = <String, Map<String, dynamic>>{
      for (final raw in bp['scenes'] as List)
        _obj(raw)['id'] as String: _obj(raw),
    };
    final touched = <String>{};
    for (final raw in gates) {
      final g = _obj(raw);
      _keys(g, {
        'scene_id', 'choice_id', 'source_quote_sha256',
        'requires_items', 'requires_facts',
      });
      final sceneId = _key(g['scene_id']);
      final choiceId = _key(g['choice_id']);
      final evidence = _hash(g['source_quote_sha256']);
      final requiredItems = g['requires_items'], requiredFacts = g['requires_facts'];
      if (requiredItems is! List || requiredFacts is! List ||
          requiredItems.length + requiredFacts.length < 1 ||
          requiredItems.length + requiredFacts.length > 8 ||
          requiredItems.any((id) => id is! String || !newItems.contains(id)) ||
          requiredFacts.any((id) => id is! String || !newFacts.contains(id)) ||
          requiredItems.toSet().length != requiredItems.length ||
          requiredFacts.toSet().length != requiredFacts.length ||
          !touched.add(choiceId) || !sceneQuote(sceneId, evidence)) {
        throw const FormatException('Unreviewed hero gameplay condition');
      }
      final scene = scenes[sceneId];
      if (scene == null) {
        throw const FormatException('Unknown source scene for hero gate');
      }
      final selected = (scene['choices'] as List)
          .where((raw) => raw is Map && raw['id'] == choiceId).toList();
      if (selected.length != 1) {
        throw const FormatException('Unknown source choice for hero gate');
      }
      final choice = _obj(selected.single);
      final conditions = choice['conditions'] as List;
      conditions.addAll([
        for (final id in requiredItems) {'op': 'has_item', 'id': id},
        for (final id in requiredFacts)
          {'op': 'knows_fact', 'id': id, 'actor': 'player'},
      ]);
      if (conditions.length > 32) {
        throw const FormatException('Too many hero gameplay conditions');
      }
    }
    provenance['initial_state_review'] = {
      'format': RichPrivateBookworldImporter.initialStateReviewFormat,
      'source_fingerprint': base.sourceFingerprint,
      'review_scope': scope, 'user_confirmed': true,
      'literary_canon_verified': false, 'initial_tick': 0,
      'item_grants': itemEvidence, 'fact_grants': factEvidence,
    };
    final fingerprint = base.sourceFingerprint;
    final freshId = 'rich_' + fingerprint.substring(0, 12) + '_hero_' +
        digest(reviewJson).substring(0, 12);
    bp['book_id'] = freshId;
    provenance['bookworld_id'] = freshId;
    final packed = const RichPrivateBookworldWriter().build(
      blueprint: bp, provenance: provenance,
      sourceIndex: sourceIndex, expanded: true,
    );
    final verified = const RichPrivateBookworldImporter().inspect(packed);
    if (verified.archiveSha256 == base.archiveSha256 ||
        verified.formatVersion != 4 ||
        !verified.blueprint.initial.inventory.containsAll(newItems) ||
        !verified.blueprint.initial.knowledge['player']!.containsAll(newFacts) ||
        verified.blueprint.initial.flags['player_is_' + actor] != true ||
        verified.canDistributePublicly || verified.requiresNetwork) {
      throw const FormatException('Reviewed hero start did not survive import');
    }
    return packed;
  }
}
