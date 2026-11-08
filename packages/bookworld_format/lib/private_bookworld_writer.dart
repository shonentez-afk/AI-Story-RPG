import 'dart:convert';
import 'rich_scene_dialogue.dart';
import 'npc_social_contract.dart';
import 'npc_dialogue_knowledge.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:story_core/story_core.dart';

import 'private_bookworld.dart';
import 'private_rich_bookworld.dart';
import 'src/zip_v1.dart';

/// Offline, native-Dart PRIVATE package compiler for Windows and Android.
///
/// Inputs must have passed M2c human review and source-edition verification.
/// This writer checks every citation against an exact local UTF-16 source
/// slice, then builds ZIP+SQLite and reopens the result through the independent
/// PrivateBookworldImporter. No network, Python, shell, or cloud fallback.
class PrivateBookworldWriter {
  const PrivateBookworldWriter();

  static const _schema = '''
CREATE TABLE world_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE scenes(scene_id TEXT PRIMARY KEY, body TEXT NOT NULL,
 terminal INTEGER NOT NULL CHECK(terminal IN (0,1)));
CREATE TABLE choices(choice_id TEXT PRIMARY KEY,
 scene_id TEXT NOT NULL REFERENCES scenes(scene_id),
 sort_order INTEGER NOT NULL, label TEXT NOT NULL,
 next_scene_id TEXT NOT NULL REFERENCES scenes(scene_id),
 conditions_json TEXT NOT NULL, effects_json TEXT NOT NULL,
 UNIQUE(scene_id,sort_order));
CREATE TABLE actors(actor_id TEXT PRIMARY KEY);
CREATE TABLE items(item_id TEXT PRIMARY KEY);
CREATE TABLE canon_facts(fact_id TEXT PRIMARY KEY);
CREATE TABLE source_refs(ref_id TEXT PRIMARY KEY,
 scene_id TEXT NOT NULL REFERENCES scenes(scene_id),
 chapter_id TEXT NOT NULL, start_offset INTEGER NOT NULL,
 end_offset INTEGER NOT NULL);
CREATE TABLE event_dependencies(choice_id TEXT NOT NULL
 REFERENCES choices(choice_id), dependency_id TEXT NOT NULL,
 PRIMARY KEY(choice_id,dependency_id));
CREATE TABLE templates(template_id TEXT PRIMARY KEY,
 template TEXT NOT NULL);
''';

  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
  static Uint8List _jsonBytes(Object? value) =>
      Uint8List.fromList(utf8.encode(canonicalJson(value)));

  /// Must be built from the actual BookSourceIndex, not an untrusted model
  /// response or an archive manifest with self-asserted citations.
  void _checkOriginalSource(Map<String, dynamic> blueprint,
      Map<String, dynamic> provenance, Map<String, dynamic> sourceIndex) {
    final fingerprint = blueprint['source_fingerprint'];
    final total = sourceIndex['chapter_count'];
    final indexed = sourceIndex['indexed_chapter_count'];
    final textTotal = sourceIndex['text_total_utf16'];
    if (fingerprint is! String ||
        sourceIndex['source_fingerprint'] != fingerprint ||
        provenance['source_fingerprint'] != fingerprint ||
        total is! int || total < 1 || total > 10000 ||
        provenance['source_chapters_total'] != total ||
        indexed is! int || indexed != total ||
        provenance['source_chapters_indexed'] != indexed ||
        textTotal is! int || textTotal < 1 ||
        sourceIndex['text_indexed_utf16'] != textTotal) {
      throw const FormatException(
          'Нельзя собрать RPG: неполный или чужой исходный текст');
    }
    final chunks = sourceIndex['chunks'];
    if (chunks is! List || chunks.isEmpty || chunks.length > 30000) {
      throw const FormatException('Некорректный реестр фрагментов книги');
    }
    final byId = <String, Map<String, dynamic>>{};
    final blockEnds = <String, int>{};
    var coveredUnits = 0;
    for (final entry in chunks) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Некорректный фрагмент источника');
      }
      final id = entry['id'];
      final content = entry['text'];
      final chapter = entry['chapter_index'];
      final start = entry['start_utf16'];
      final end = entry['end_utf16'];
      if (id is! String || id.isEmpty || id.length > 120 ||
          byId.containsKey(id) || content is! String ||
          chapter is! int || chapter < 0 || chapter >= total ||
          entry['chapter_id'] is! String ||
          entry['block_index'] is! int ||
          start is! int || end is! int ||
          start < 0 || end - start != content.length ||
          entry['sha256_text'] != _hash(utf8.encode(content))) {
        throw const FormatException(
            'Некорректные позиции или SHA-256 исходного фрагмента');
      }
      // Reject missing/overlapping pieces even when a forged summary claims
      // 100% coverage. Real BookSourceIndexer chunks are contiguous in block.
      final key = '$chapter|' +
          (entry['chapter_id'] as String) + '|' +
          (entry['block_index'] as int).toString();
      if (start != (blockEnds[key] ?? 0)) {
        throw const FormatException(
            'Пропуск или наложение текстовых фрагментов');
      }
      blockEnds[key] = end;
      coveredUnits += content.length;
      byId[id] = entry;
    }
    if (coveredUnits != textTotal) {
      throw const FormatException(
          'Фактическое покрытие источника отличается от отчёта');
    }
    final origins = provenance['scene_origins'];
    if (origins is! List) {
      throw const FormatException('Отсутствует происхождение игровых сцен');
    }
    for (final raw in origins) {
      if (raw is! Map<String, dynamic> || raw['source_refs'] is! List) {
        throw const FormatException('Неверная запись источника сцены');
      }
      for (final value in raw['source_refs'] as List) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Неверная ссылка на цитату');
        }
        final chunk = byId[value['chunk_id']];
        if (chunk == null ||
            chunk['chapter_index'] != value['chapter_index'] ||
            chunk['chapter_id'] != value['chapter_id'] ||
            chunk['block_index'] != value['block_index']) {
          throw const FormatException('Цитата ссылается на другую главу');
        }
        final start = value['start_utf16'];
        final end = value['end_utf16'];
        final chunkStart = chunk['start_utf16'] as int;
        final chunkEnd = chunk['end_utf16'] as int;
        if (start is! int || end is! int || start < chunkStart ||
            end > chunkEnd || end <= start || end - start > 180) {
          throw const FormatException('Цитата вне исходного фрагмента');
        }
        final text = chunk['text'] as String;
        final from = start - chunkStart;
        final to = end - chunkStart;
        bool low(int v) => v >= 0xdc00 && v <= 0xdfff;
        if ((from > 0 && low(text.codeUnitAt(from))) ||
            (to < text.length && low(text.codeUnitAt(to)))) {
          throw const FormatException(
              'Цитата разрезает составной символ Unicode');
        }
        final quote = text.substring(from, to);
        if (quote.trim().isEmpty ||
            value['quote_sha256'] != _hash(utf8.encode(quote))) {
          throw const FormatException(
              'Хеш цитаты не соответствует оригиналу книги');
        }
      }
    }
  }

  Uint8List _writeSqlite(Map<String, dynamic> raw, String blueprintHash) {
    final dir = Directory.systemTemp.createTempSync('asr_private_m2e_');
    try {
      final file = File('${dir.path}${Platform.pathSeparator}world.sqlite');
      final db = sqlite3.open(file.path);
      try {
        db.execute('PRAGMA foreign_keys=ON');
        db.execute('PRAGMA application_id=1113018194'); // 0x42574f52
        db.execute('PRAGMA user_version=1');
        db.execute(_schema);
        db.execute('BEGIN TRANSACTION');
        final meta = <String, String>{
          'schema_version': '1',
          'bookworld_id': raw['book_id'] as String,
          'blueprint_sha256': blueprintHash,
          'initial_state_json': canonicalJson(raw['initial_state']),
        };
        final keys = meta.keys.toList()..sort();
        for (final key in keys) {
          db.execute('INSERT INTO world_meta VALUES (?, ?)',
              [key, meta[key]]);
        }
        final scenes = raw['scenes'] as List<dynamic>;
        for (final scene in scenes) {
          final row = scene as Map<String, dynamic>;
          db.execute('INSERT INTO scenes VALUES (?, ?, ?)', [
            row['id'], row['text'], row['terminal'] == true ? 1 : 0,
          ]);
        }
        for (final scene in scenes) {
          final row = scene as Map<String, dynamic>;
          final choices = row['choices'] as List<dynamic>;
          for (var i = 0; i < choices.length; i++) {
            final c = choices[i] as Map<String, dynamic>;
            db.execute(
                'INSERT INTO choices VALUES (?, ?, ?, ?, ?, ?, ?)', [
              c['id'], row['id'], i, c['label'], c['next_scene_id'],
              canonicalJson(c['conditions']), canonicalJson(c['effects']),
            ]);
          }
        }
        for (final entry in const [
          ('actors', 'actors', 'actor_id'),
          ('items', 'items', 'item_id'),
          ('canon_facts', 'facts', 'fact_id'),
        ]) {
          final table = entry.$1;
          final items = raw[entry.$2] as List<dynamic>;
          for (final id in items) {
            db.execute('INSERT INTO $table(${entry.$3}) VALUES (?)', [id]);
          }
        }
        db.execute('COMMIT');
      } finally {
        db.close();
      }
      final bytes = file.readAsBytesSync();
      if (bytes.length > BworldZipV1.maxEntry) {
        throw const FormatException('SQLite превышает лимит .bworld');
      }
      return Uint8List.fromList(bytes);
    } on SqliteException catch (error) {
      throw FormatException('Не удалось создать SQLite: $error');
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  static void _u16(BytesBuilder out, int value) =>
      out.add([value & 255, (value >>> 8) & 255]);

  static void _u32(BytesBuilder out, int value) => out.add([
    value & 255, (value >>> 8) & 255,
    (value >>> 16) & 255, (value >>> 24) & 255,
  ]);

  static final _crcTable = List<int>.generate(256, (i) {
    var n = i;
    for (var k = 0; k < 8; k++) {
      n = n & 1 != 0 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
    }
    return n;
  });

  static int _crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final b in bytes) {
      crc = _crcTable[(crc ^ b) & 255] ^ (crc >>> 8);
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  Uint8List _storedZip(Map<String, Uint8List> files) {
    final out = BytesBuilder(copy: false);
    final central = BytesBuilder(copy: false);
    var total = 0;
    for (final path in BworldZipV1.privatePaths) {
      final data = files[path]!;
      final name = ascii.encode(path);
      if (data.length > BworldZipV1.maxEntry || name.length > 65535) {
        throw const FormatException('Слишком большой элемент игрового пакета');
      }
      total += data.length;
      final offset = out.length;
      final crc = _crc32(data);
      // 30-byte local header, ZIP_STORED, DOS date 1980-01-01.
      _u32(out, 0x04034b50);
      _u16(out, 20); _u16(out, 0); _u16(out, 0);
      _u16(out, 0); _u16(out, 33);
      _u32(out, crc); _u32(out, data.length);
      _u32(out, data.length); _u16(out, name.length); _u16(out, 0);
      out.add(name); out.add(data);
      // 46-byte central directory header; mode 0100600, no extras.
      _u32(central, 0x02014b50);
      _u16(central, 0x0314); _u16(central, 20);
      _u16(central, 0); _u16(central, 0);
      _u16(central, 0); _u16(central, 33);
      _u32(central, crc); _u32(central, data.length);
      _u32(central, data.length); _u16(central, name.length);
      _u16(central, 0); _u16(central, 0); _u16(central, 0);
      _u16(central, 0); _u32(central, 0x81800000);
      _u32(central, offset); central.add(name);
    }
    if (total > BworldZipV1.maxTotal) {
      throw const FormatException('Общий объём ZIP слишком велик');
    }
    final centralStart = out.length;
    final centralBytes = central.takeBytes();
    out.add(centralBytes);
    _u32(out, 0x06054b50);
    _u16(out, 0); _u16(out, 0);
    _u16(out, BworldZipV1.privatePaths.length);
    _u16(out, BworldZipV1.privatePaths.length);
    _u32(out, centralBytes.length); _u32(out, centralStart);
    _u16(out, 0);
    if (out.length > BworldZipV1.maxArchive) {
      throw const FormatException('Игровой архив превышает лимит');
    }
    return out.takeBytes();
  }

  /// Requires a reviewed local source index; never accepts JSON from an LLM
  /// as independently verified evidence. Returns only a private game package.
  Uint8List build({
    required Map<String, dynamic> blueprint,
    required Map<String, dynamic> provenance,
    required Map<String, dynamic> sourceIndex,
  }) {
    final checked = StoryBlueprint.fromJson(blueprint);
    if (checked.rightsStatus != 'private_adaptation' ||
        checked.sourceFingerprint == null) {
      throw const FormatException('Разрешена только частная адаптация');
    }
    _checkOriginalSource(blueprint, provenance, sourceIndex);
    final scenario = _jsonBytes(blueprint);
    final origin = _jsonBytes(provenance);
    final sqlite = _writeSqlite(blueprint, checked.blueprintHash);
    final payloads = <String, Uint8List>{
      'scenario/blueprint.json': scenario,
      'source/provenance.json': origin,
      'world.sqlite': sqlite,
    };
    final hashes = <String, String>{};
    final sizes = <String, int>{};
    for (final entry in payloads.entries) {
      hashes[entry.key] = _hash(entry.value);
      sizes[entry.key] = entry.value.length;
    }
    final manifest = <String, dynamic>{
      'format': 'ai_story_bookworld',
      'format_version': 2,
      'bookworld_id': checked.bookId,
      'source_fingerprint': checked.sourceFingerprint,
      'title': checked.title,
      'author': provenance['source_author'],
      'languages': ['ru'],
      'engine_min_version': '0.1.0',
      'scenario_format': 'ai_story_blueprint_v1',
      'scenario_format_version': 1,
      'content_capabilities': blueprint['supported_modes'],
      'build_status': 'private_classic_structural',
      'rights_status': 'private_use_only',
      'build_tool': {
        'name': 'ai_story_private_bookworld', 'version': '2.0',
      },
      'model_provenance': {'provider': 'none', 'model_id': null},
      'hashes': hashes,
      'sizes': sizes,
      'blueprint_sha256': _hash(scenario),
    };
    final packed = _storedZip({
      'manifest.json': _jsonBytes(manifest),
      ...payloads,
    });
    // Independent importer inspects manifest, all ZIP and SQLite bytes,
    // source reference structure, rights and exhaustive causal reachability.
    final inspected = const PrivateBookworldImporter().inspect(packed);
    if (inspected.sourceFingerprint != checked.sourceFingerprint ||
        inspected.blueprint.blueprintHash != checked.blueprintHash) {
      throw const FormatException('Самопроверка игрового пакета не пройдена');
    }
    return packed;
  }
}


/// Native v3 writer. Shares the exact source, SQLite and ZIP implementation
/// with the accepted v2 writer; the independent *rich* importer is the final
/// authority. No Python, network request or human-supplied manifest is needed.
///
/// The caller must provide validated, source-bound typed effects and honest
/// model provenance. This writer never derives inventory from narrative prose.
class RichPrivateBookworldWriter {
  const RichPrivateBookworldWriter();

  Uint8List build({
    required Map<String, dynamic> blueprint,
    required Map<String, dynamic> provenance,
    required Map<String, dynamic> sourceIndex,
    /// A separately versioned v4 archive, never a silent upgrade of v3.
    bool expanded = false,
  }) {
    final checked = StoryBlueprint.fromJson(blueprint);
    if (checked.rightsStatus != 'private_adaptation' ||
        checked.sourceFingerprint == null) {
      throw const FormatException('Разрешена только частная RPG по книге');
    }
    final base = const PrivateBookworldWriter();
    // Verification uses the actual UTF-16 source chunks, not an AI claim.
    base._checkOriginalSource(blueprint, provenance, sourceIndex);
    final sceneBytes = PrivateBookworldWriter._jsonBytes(blueprint);
    final originBytes = PrivateBookworldWriter._jsonBytes(provenance);
    final sqliteBytes = base._writeSqlite(blueprint, checked.blueprintHash);
    final payloads = <String, Uint8List>{
      'scenario/blueprint.json': sceneBytes,
      'source/provenance.json': originBytes,
      'world.sqlite': sqliteBytes,
    };
    final hashes = <String, String>{};
    final sizes = <String, int>{};
    for (final entry in payloads.entries) {
      hashes[entry.key] = PrivateBookworldWriter._hash(entry.value);
      sizes[entry.key] = entry.value.length;
    }
    final manifest = <String, dynamic>{
      'format': 'ai_story_bookworld',
      'format_version': expanded ? 4 : 3,
      if (provenance.containsKey('npc_knowledge'))
        'npc_knowledge_format':
            RichPrivateBookworldImporter.npcKnowledgeFormat,
      if (provenance.containsKey('npc_social'))
        'npc_social_format': provenance['npc_social'] is Map
            ? (provenance['npc_social'] as Map)['format'] : null,
      if (expanded && provenance.containsKey('initial_state_review'))
        'initial_state_review_format': RichPrivateBookworldImporter.initialStateReviewFormat,
      'bookworld_id': checked.bookId,
      'source_fingerprint': checked.sourceFingerprint,
      'title': checked.title,
      'author': provenance['source_author'],
      'languages': ['ru'],
      'engine_min_version': '0.1.0',
      'scenario_format': 'ai_story_blueprint_v1',
      'scenario_format_version': 1,
      'content_capabilities': blueprint['supported_modes'],
      'build_status': expanded ? 'private_extended_structural' : 'private_rich_structural',
      'rights_status': 'private_use_only',
      'build_tool': {
        'name': expanded ? 'ai_story_private_extended_bookworld' : 'ai_story_private_rich_bookworld',
        'version': expanded ? '4.0' : '3.0',
      },
      'model_provenance': provenance['model_provenance'],
      'hashes': hashes,
      'sizes': sizes,
      'blueprint_sha256': PrivateBookworldWriter._hash(sceneBytes),
    };
    final package = base._storedZip({
      'manifest.json': PrivateBookworldWriter._jsonBytes(manifest),
      ...payloads,
    });
    final verified = const RichPrivateBookworldImporter().inspect(package);
    if (verified.bookworldId != checked.bookId ||
        verified.sourceFingerprint != checked.sourceFingerprint ||
        verified.blueprint.blueprintHash != checked.blueprintHash ||
        verified.canDistributePublicly ||
        verified.requiresNetwork ||
        verified.formatVersion != (expanded ? 4 : 3)) {
      throw const FormatException('Нативная сборка v3 не прошла самопроверку');
    }
    return package;
  }

  /// Promote a source-reviewed, independently verified flag-only v2 draft
  /// to the single rich v3 target without manual enrichment or a model call.
  /// No invented items, stats, facts or literary source claims are added.
  Uint8List upgradeReviewedV2({
    required Uint8List verifiedPrivateV2Archive,
    required Map<String, dynamic> sourceIndex,
    String heroName = 'Игрок',
    String heroDescription =
        'Участник частной игровой адаптации. Поступки сохраняются в журнале.',
    Map<String, String> sceneTitles = const {},
    Map<String, dynamic>? reviewedNpcArc,
  }) {
    final original = const PrivateBookworldImporter()
        .inspect(verifiedPrivateV2Archive);
    if (heroName.trim().isEmpty || heroName.length > 120 ||
        heroDescription.trim().isEmpty || heroDescription.length > 1200 ||
        heroName.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        heroDescription.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
      throw const FormatException('Некорректные сведения выбранного героя');
    }

    final entries = BworldZipV1.readPrivate(verifiedPrivateV2Archive);
    final bp = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(entries['scenario/blueprint.json']!)) as Map);
    final origin = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(entries['source/provenance.json']!)) as Map);
    final state = Map<String, dynamic>.from(bp['initial_state'] as Map);
    if ((bp['items'] as List).isNotEmpty ||
        (bp['facts'] as List).isNotEmpty ||
        (state['stats'] as Map).isNotEmpty ||
        (bp['actors'] as List).length != 1 ||
        (bp['actors'] as List).single != 'player') {
      throw const FormatException(
          'Нельзя переносить богатый v2-сценарий без реальных имён '
          'предметов, знаний и характеристик');
    }
    final scenes = bp['scenes'] as List;
    final ids = {for (final s in scenes) (s as Map)['id'] as String};
    if (sceneTitles.keys.any((id) => !ids.contains(id))) {
      throw const FormatException('Название относится к чужой сцене');
    }
    final names = <String, String>{};
    for (var i = 0; i < scenes.length; i++) {
      final sceneId = (scenes[i] as Map)['id'] as String;
      final proposed = sceneTitles[sceneId]?.trim() ?? '';
      // Fallback is neutral UI labeling, never a fabricated source fact.
      final safe = proposed.isNotEmpty && proposed.length <= 120 &&
          !proposed.contains(RegExp(r'[\x00-\x1f\x7f]'));
      names[sceneId] = safe ? proposed : 'Сцена ' + (i + 1).toString();
    }
    final key = sha256.convert(utf8.encode(original.archiveSha256 +
        '|' + heroName.trim() + '|' + canonicalJson(names))).toString();
    final newId = 'rich_' + original.sourceFingerprint.substring(0, 12) +
        '_' + key.substring(0, 12);
    bp['book_id'] = newId;
    origin['bookworld_id'] = newId;
    origin['format'] = 'ai_story_private_provenance_v2';
    // A reviewed checkpoint may already contain AI suggestions, but its v2
    // archive does not attest the model. Never claim "no AI".
    origin['model_provenance'] = {
      'provider': 'unknown',
      'model_id': null,
      'model_id_status': 'not_attested',
      'tool': 'AI Story RPG',
      'method': 'reviewed_local_compilation',
    };
    // A dialogue is a deterministic projection of ALREADY approved scene
    // text, not an independent LLM claim or new character. Store it inside
    // the signed v3 provenance and verify again at import and playback.
    final dialogues = <String, Map<String, Object?>>{};
    for (final scene in scenes) {
      final raw = scene as Map;
      final id = raw['id'] as String;
      final script = RichSceneDialogue.presentationFor(
          raw['text'] as String);
      if (script != null) dialogues[id] = script;
    }
    origin['presentation'] = {
      'hero': {
        'name': heroName.trim(),
        'description': heroDescription.trim(),
      },
      'item_names': <String, String>{},
      'item_descriptions': <String, String>{},
      'stat_names': <String, String>{},
      'fact_names': <String, String>{},
      'scene_names': names,
      'scene_dialogues': dialogues,
    };
    if (reviewedNpcArc != null) {
      _applyReviewedBookwideNpcArc(bp, origin, reviewedNpcArc);
    }
    return build(
      blueprint: bp,
      provenance: origin,
      sourceIndex: sourceIndex,
    );
  }

  /// Enhances the SAME independently validated v2->v3 compilation. There
  /// is no parallel engine, remote LLM request, or guessed character ID.
  /// An app-side reviewer has already checked a literal source mention;
  /// both quote digests are checked AGAIN against the signed scene origins.
  void _applyReviewedBookwideNpcArc(
      Map<String, dynamic> blueprint,
      Map<String, dynamic> provenance,
      Map<String, dynamic> review) {
    const keys = {
      'actor_id', 'display_name', 'first_scene_id', 'first_choice_id',
      'second_scene_id', 'second_choice_id', 'first_quote_sha256',
      'second_quote_sha256', 'player_line', 'npc_line', 'user_confirmed',
    };
    if (review.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(review.keys.toSet()).isNotEmpty ||
        review['user_confirmed'] != true ||
        review['actor_id'] is! String ||
        !CharacterId.isValidNpc(review['actor_id'] as String)) {
      throw const FormatException('Подмена подтверждённого NPC в книге.');
    }
    final actor = review['actor_id'] as String;
    final name = review['display_name'];
    final playerLine = review['player_line'];
    final npcLine = review['npc_line'];
    if (name is! String || playerLine is! String || npcLine is! String ||
        !RegExp(r'^[А-ЯЁA-Z][А-Яа-яЁёA-Za-z0-9 .-]{0,49}$',
            unicode: true).hasMatch(name) ||
        playerLine.isEmpty || npcLine.isEmpty ||
        playerLine.length > 250 || npcLine.length > 250 ||
        playerLine != playerLine.trim() ||
        npcLine != npcLine.trim() ||
        playerLine.contains(RegExp(r'[\x00-\x1f\x7f«»]')) ||
        npcLine.contains(RegExp(r'[\x00-\x1f\x7f«»]'))) {
      throw const FormatException('Не подтверждены игровые реплики NPC.');
    }
    final scenes = {
      for (final raw in blueprint['scenes'] as List)
        (raw as Map<String, dynamic>)['id'] as String: raw,
    };
    final origins = {
      for (final raw in provenance['scene_origins'] as List)
        (raw as Map<String, dynamic>)['scene_id'] as String: raw,
    };
    Map<String, dynamic> scene(String key, String quote) {
      final id = review[key];
      final digest = review[quote];
      if (id is! String || digest is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const FormatException('Некорректная ссылка на встречу NPC.');
      }
      final original = origins[id];
      final refs = original?['source_refs'];
      if (original?['origin'] != 'SOURCE_PASSAGE' || refs is! List ||
          !refs.any((r) => r is Map &&
              r['quote_sha256'] == digest &&
              r['chapter_index'] == original?['chapter_index'])) {
        throw const FormatException(
            'Знание NPC не связано с подтверждённой цитатой.');
      }
      final found = scenes[id];
      if (found is! Map<String, dynamic>) {
        throw const FormatException('Нет исходной сцены встречи NPC.');
      }
      return found;
    }
    final first = scene('first_scene_id', 'first_quote_sha256');
    final second = scene('second_scene_id', 'second_quote_sha256');
    final firstId = first['id'] as String;
    final secondId = second['id'] as String;
    if (firstId == secondId ||
        (origins[firstId]!['chapter_index'] as int) >
            (origins[secondId]!['chapter_index'] as int)) {
      throw const FormatException('Диалог NPC расположен раньше знакомства.');
    }
    Map<String, dynamic> choice(Map<String, dynamic> scene, String key) {
      final id = review[key];
      if (id is! String) {
        throw const FormatException('Нет решения для диалога NPC.');
      }
      final matches = (scene['choices'] as List)
          .where((c) => (c as Map)['id'] == id).toList();
      if (matches.length != 1) {
        throw const FormatException('Нет исходного действия NPC.');
      }
      return matches.single as Map<String, dynamic>;
    }
    final listen = choice(first, 'first_choice_id');
    final reply = choice(second, 'second_choice_id');
    if (!(listen['id'] as String).endsWith('_npc_listen') ||
        !(reply['id'] as String).endsWith('_npc_reply') ||
        (listen['next_scene_id'] as String) != secondId) {
      throw const FormatException('NPC-продолжение не связано с первым ходом.');
    }
    const fact = 'bookwide_npc_contact_fact';
    const memory = 'bookwide_npc_witnessed_contact';
    (listen['effects'] as List).add({
      'op': 'learn_fact', 'id': fact, 'actor': actor,
    });
    (reply['conditions'] as List).add({
      'op': 'knows_fact', 'id': fact, 'actor': actor,
    });
    blueprint['actors'] = ['player', actor];
    blueprint['facts'] = [fact];
    final state = blueprint['initial_state'] as Map<String, dynamic>;
    final knowledge = Map<String, dynamic>.from(state['knowledge'] as Map);
    knowledge[actor] = <String>[];
    state['knowledge'] = knowledge;

    final firstQuote = review['first_quote_sha256'] as String;
    final secondQuote = review['second_quote_sha256'] as String;
    provenance['npc_knowledge'] = {
      'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': blueprint['source_fingerprint'],
      'user_confirmed': true, 'literary_canon_verified': false,
      'grants': [
        {
          'scene_id': firstId, 'choice_id': listen['id'],
          'actor_id': actor, 'fact_id': fact,
          'source_quote_sha256': firstQuote,
        },
      ],
    };
    provenance['npc_social'] = {
      'format': RichNpcSocialContract.choiceGateFormat,
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': blueprint['source_fingerprint'],
      'user_confirmed': true, 'literary_canon_verified': false,
      'witnesses': [
        {'scene_id': firstId, 'actor_id': actor, 'mode': 'present',
         'source_quote_sha256': firstQuote},
      ],
      'rules': [
        {
          'memory_id': memory, 'scene_id': firstId,
          'choice_id': listen['id'], 'observer_id': actor,
          'kind': 'witnessed', 'related_actor_id': 'player',
          'relationship_delta': 1, 'max_triggers': 1,
          'source_quote_sha256': firstQuote,
        },
      ],
      'choice_gates': [
        {
          'scene_id': secondId, 'choice_id': reply['id'],
          'actor_id': actor, 'required_memory_id': memory,
          'minimum_trust_to_player': 1,
          'source_quote_sha256': secondQuote,
        },
      ],
    };

    // Exactly TWO user-reviewed fictional spoken lines. Other dialogue
    // cannot be silently assigned an NPC identity from its printed name.
    final presentation =
        provenance['presentation'] as Map<String, dynamic>;
    final signed = presentation['scene_dialogues'] as Map<String, dynamic>;
    if (signed.isNotEmpty) {
      throw const FormatException(
          'Другие реплики книги требуют отдельной проверки авторства.');
    }
    second['text'] = (second['text'] as String) +
        '\n\nЧАСТНЫЙ ИГРОВОЙ ДИАЛОГ, НЕ ДОСЛОВНЫЙ ТЕКСТ КНИГИ:\n' +
        'Игрок: «' + playerLine + '»\n' +
        name + ': «' + npcLine + '»';
    final script = RichSceneDialogue.presentationFor(
        second['text'] as String);
    if (script == null) {
      throw const FormatException('Диалог не соответствует формату реплик.');
    }
    signed[secondId] = script;
    final turns = (script['turns'] as List)
        .map((row) => row as Map<String, Object?>).toList();
    final names = <int>[];
    for (var i = 0; i < turns.length; i++) {
      if (turns[i]['speaker'] != null) names.add(i);
    }
    if (names.length != 2 ||
        turns[names[0]]['speaker'] != 'Игрок' ||
        turns[names[1]]['speaker'] != name) {
      throw const FormatException('Два участника диалога не подтверждены.');
    }
    presentation['fact_names'] = {fact: 'Факт игрового знакомства с NPC'};
    presentation['scene_dialogue_knowledge'] = {
      secondId: [
        {
          'turn_index': names[0], 'speaker': 'Игрок',
          'actor_id': 'player', 'required_fact_ids': <String>[],
        },
        {
          'turn_index': names[1], 'speaker': name,
          'actor_id': actor, 'required_fact_ids': [fact],
          'required_social_memory_id': memory,
          'minimum_trust_to_player': 1,
          'required_prior_choice_id': listen['id'],
          'source_quote_sha256': firstQuote,
          'private_fiction_confirmed': true,
        },
      ],
    };

    // A changed character/reply is a NEW private world, never a silent
    // mutation of an installed old campaign or its event history.
    final oldId = blueprint['book_id'] as String;
    final digest = sha256.convert(
        utf8.encode(oldId + '|' + canonicalJson(review))).toString();
    final newId = oldId + '_npc_' + digest.substring(0, 12);
    blueprint['book_id'] = newId;
    provenance['bookworld_id'] = newId;
    final checked = StoryBlueprint.fromJson(blueprint);
    final social = RichNpcSocialContract.inspect(
      provenance, {
        'npc_social_format': RichNpcSocialContract.choiceGateFormat,
      }, checked,
    );
    RichNpcDialogueKnowledge.validate(
      presentation['scene_dialogue_knowledge'] as Map<String, dynamic>,
      checked, signed,
      socialRules: social,
      sceneOrigins: Map<String, dynamic>.from(origins),
    );
    RichNpcDialogueKnowledge.auditExecutableRoutes(
      presentation['scene_dialogue_knowledge'] as Map<String, dynamic>,
      checked, socialRules: social,
    );
  }

}
