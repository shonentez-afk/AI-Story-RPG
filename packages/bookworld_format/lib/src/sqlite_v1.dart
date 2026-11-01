import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:story_core/story_core.dart';

/// Read-only audit of the compiled SQLite world. No migrations or writes.
class BworldSqliteV1 {
  BworldSqliteV1._();

  static void inspect(Uint8List bytes, StoryBlueprint blueprint,
      Map<String, dynamic> raw) {
    const signature = [
      83, 81, 76, 105, 116, 101, 32, 102, 111, 114,
      109, 97, 116, 32, 51, 0,
    ];
    if (bytes.length < 512 || bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('Invalid SQLite size');
    }
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) {
        throw const FormatException('Invalid SQLite header');
      }
    }

    final directory = Directory.systemTemp.createTempSync('ai_story_bw_');
    try {
      final name = directory.path + Platform.pathSeparator + 'world.sqlite';
      File(name).writeAsBytesSync(bytes, flush: true);
      final db = sqlite3.open(name, mode: OpenMode.readOnly);
      try {
        db.execute('PRAGMA trusted_schema=OFF');
        db.execute('PRAGMA query_only=ON');
        db.execute('PRAGMA foreign_keys=ON');
        _checkDatabase(db, blueprint, raw);
      } on SqliteException catch (error) {
        throw FormatException('Rejected SQLite payload: $error');
      } finally {
        db.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  }

  static void _checkDatabase(Database db, StoryBlueprint blueprint,
      Map<String, dynamic> raw) {
    if (db.select('PRAGMA integrity_check').single.columnAt(0) != 'ok' ||
        db.select('PRAGMA foreign_key_check').isNotEmpty ||
        db.select('PRAGMA application_id').single.columnAt(0) != 0x42574f52 ||
        db.select('PRAGMA user_version').single.columnAt(0) != 1) {
      throw const FormatException('SQLite integrity/format mismatch');
    }
    const tables = {
      'world_meta', 'scenes', 'choices', 'actors', 'items', 'canon_facts',
      'source_refs', 'event_dependencies', 'templates',
    };
    final schemaRows = db.select(
        "SELECT type,name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'");
    if (schemaRows.length != tables.length) {
      throw const FormatException('Unexpected SQLite schema objects');
    }
    final found = <String>{};
    for (final row in schemaRows) {
      if (row.columnAt(0) != 'table') {
        throw const FormatException('SQLite triggers/views forbidden');
      }
      found.add(row.columnAt(1) as String);
    }
    if (found.length != tables.length || !found.containsAll(tables)) {
      throw const FormatException('SQLite schema catalog mismatch');
    }

    final meta = <String, String>{};
    final metaRows = db.select('SELECT key,value FROM world_meta');
    for (final row in metaRows) {
      meta[row.columnAt(0) as String] = row.columnAt(1) as String;
    }
    if (metaRows.length != 4 || canonicalJson(meta) != canonicalJson({
      'schema_version': '1',
      'bookworld_id': blueprint.bookId,
      'blueprint_sha256': blueprint.blueprintHash,
      'initial_state_json': canonicalJson(raw['initial_state']),
    })) {
      throw const FormatException('SQLite metadata mismatch');
    }

    final scenes = raw['scenes'] as List<dynamic>;
    _expectRows(db, 'SELECT scene_id,body,terminal FROM scenes ORDER BY rowid',
        [
          for (final scene in scenes)
            [scene['id'], scene['text'], scene['terminal'] == true ? 1 : 0],
        ]);
    final choices = <List<Object?>>[];
    for (final scene in scenes) {
      final options = scene['choices'] as List<dynamic>;
      for (var i = 0; i < options.length; i++) {
        final c = options[i] as Map;
        choices.add([
          c['id'], scene['id'], i, c['label'], c['next_scene_id'],
          canonicalJson(c['conditions']), canonicalJson(c['effects']),
        ]);
      }
    }
    _expectRows(db,
        'SELECT choice_id,scene_id,sort_order,label,next_scene_id,'
        'conditions_json,effects_json FROM choices ORDER BY rowid',
        choices);

    const catalogs = {
      'actors': 'actors', 'items': 'items', 'canon_facts': 'facts',
    };
    for (final entry in catalogs.entries) {
      _expectRows(db, 'SELECT * FROM ' + entry.key + ' ORDER BY rowid', [
        for (final value in raw[entry.value] as List<dynamic>) [value],
      ]);
    }
    for (final table in [
      'source_refs', 'event_dependencies', 'templates',
    ]) {
      if (db.select('SELECT COUNT(*) FROM $table').single.columnAt(0) != 0) {
        throw FormatException('Unverified $table data in demo v1');
      }
    }
  }

  static void _expectRows(
      Database db, String statement, List<List<Object?>> expected) {
    final actual = [
      for (final row in db.select(statement)) row.values.toList(),
    ];
    if (canonicalJson(actual) != canonicalJson(expected)) {
      throw const FormatException('SQLite data does not match blueprint');
    }
  }
}
