import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:story_core/story_core.dart';
import 'package:story_runtime_adapter/story_runtime_adapter.dart';

/// New, isolated M1.7.4a SQLite store. Never touches M1.6 preferences/saves.
/// Supply an app-private directory, never an untrusted book ZIP member path.
class BookworldCampaignStore {
  BookworldCampaignStore._(this._db);

  static const int _applicationId = 0x41535250;
  static const int _schemaVersion = 1;
  static const int maxTurns = 2000;
  static const String saveFormat = 'ai_story_bwsave_v2';

  final Database _db;
  static final RegExp _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final RegExp _hash = RegExp(r'^[0-9a-f]{64}$');

  /// Refuse unknown file schemas instead of silently migrating old data.
  /// SQLite WAL and FULL synchronous keep confirmed events and head atomic.
  static BookworldCampaignStore openPrivateDirectory(String privateDirectory) {
    final directory = Directory(privateDirectory);
    directory.createSync(recursive: true);
    final path = directory.path + Platform.pathSeparator +
        'bookworld_campaigns_v1.sqlite';
    final existing = File(path).existsSync();
    final db = sqlite3.open(path);
    try {
      db.execute('PRAGMA trusted_schema=OFF');
      db.execute('PRAGMA foreign_keys=ON');
      if (existing) {
        if (_intPragma(db, 'application_id') != _applicationId ||
            _intPragma(db, 'user_version') != _schemaVersion) {
          throw const FormatException('Unsupported campaign database version');
        }
        _validateSchema(db);
      } else {
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute('PRAGMA application_id=$_applicationId');
          db.execute('PRAGMA user_version=$_schemaVersion');
          db.execute(_schema);
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      }
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      db.execute('PRAGMA busy_timeout=5000');
      if (db.select('PRAGMA quick_check').single.columnAt(0) != 'ok' ||
          db.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw const FormatException('Corrupt campaign database');
      }
      _validateSchema(db);
      return BookworldCampaignStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static int _intPragma(Database db, String key) =>
      db.select('PRAGMA $key').single.columnAt(0) as int;

  static void _validateSchema(Database db) {
    const expected = {'bookworlds', 'campaigns', 'events', 'meta'};
    final rows = db.select(
      "SELECT type,name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'");
    if (rows.length != expected.length ||
        rows.any((row) => row.columnAt(0) != 'table') ||
        rows.map((row) => row.columnAt(1)).toSet()
            .difference(expected).isNotEmpty) {
      throw const FormatException('Campaign DB schema has unexpected objects');
    }
    final values = db.select('SELECT key,value FROM meta');
    if (values.length != 1 ||
        values.single.columnAt(0) != 'format' ||
        values.single.columnAt(1) != 'ai_story_campaign_sqlite_v1') {
      throw const FormatException('Unknown campaign database format');
    }
  }

  static const String _schema = '''
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO meta(key,value) VALUES('format','ai_story_campaign_sqlite_v1');

CREATE TABLE bookworlds(
  archive_sha256 TEXT PRIMARY KEY,
  bookworld_id TEXT NOT NULL,
  blueprint_sha256 TEXT NOT NULL,
  title TEXT NOT NULL,
  package BLOB NOT NULL
);

CREATE TABLE campaigns(
  campaign_id TEXT PRIMARY KEY,
  world_sha256 TEXT NOT NULL REFERENCES bookworlds(archive_sha256)
     ON DELETE RESTRICT,
  parent_campaign_id TEXT,
  revision INTEGER NOT NULL CHECK(revision >= 0 AND revision <= 2000),
  state_sha256 TEXT NOT NULL,
  head_event_sha256 TEXT,
  saved_at_utc TEXT NOT NULL,
  FOREIGN KEY(parent_campaign_id) REFERENCES campaigns(campaign_id)
     ON DELETE SET NULL,
  CHECK ((revision = 0 AND head_event_sha256 IS NULL) OR
         (revision > 0 AND head_event_sha256 IS NOT NULL))
);

CREATE TABLE events(
  campaign_id TEXT NOT NULL REFERENCES campaigns(campaign_id)
    ON DELETE CASCADE,
  sequence INTEGER NOT NULL CHECK(sequence >= 1 AND sequence <= 2000),
  action_id TEXT NOT NULL,
  event_sha256 TEXT NOT NULL,
  payload TEXT NOT NULL,
  PRIMARY KEY(campaign_id,sequence),
  UNIQUE(campaign_id,action_id)
);
''';

  static String _utc() => DateTime.now().toUtc().toIso8601String();

  static String _newId() {
    final random = Random.secure();
    String piece() => random.nextInt(0x100000000)
        .toRadixString(16).padLeft(8, '0');
    return 'c_' + piece() + piece() + piece() + piece();
  }

  static void _validId(String id, String field) {
    if (!_id.hasMatch(id)) throw FormatException('Invalid $field');
  }

  static void _validHash(String value, String field) {
    if (!_hash.hasMatch(value)) throw FormatException('Invalid $field');
  }

  static String _checksum(Object? value) =>
      sha256.convert(utf8.encode(canonicalJson(value))).toString();

  /// BEGIN IMMEDIATE serializes concurrent writers. No await or callbacks
  /// interrupt the SQLite event + head transaction.
  T _transaction<T>(T Function() operation) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = operation();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();

  /// Explicit v1/v2 dispatch; both paths independently validate every
  /// archive entry and SQLite before the store begins a transaction.
  /// No permissive ZIP fallback and no silent source/rights upgrade.
  static VerifiedBookworld _inspectBookworld(Uint8List archive) {
    try {
      return const BookworldImporter().inspect(archive);
    } on FormatException {
      final private = const PrivateBookworldImporter().inspect(archive);
      return VerifiedBookworld(
        blueprint: private.blueprint,
        archiveHash: private.archiveSha256,
      );
    }
  }

  /// Verify the entire ZIP, CRC, hashes, all scenes and read-only SQLite
  /// before the first mutation of our private catalog.
  WorldCatalogEntry installBookworld(Uint8List package) {
    final checked = _inspectBookworld(package);
    _validHash(checked.archiveHash, 'archive_sha256');
    final entry = WorldCatalogEntry(
      archiveHash: checked.archiveHash,
      bookworldId: checked.bookworldId,
      blueprintHash: checked.blueprint.blueprintHash,
      title: checked.blueprint.title,
    );
    _transaction(() {
      final rows = _db.select(
        'SELECT bookworld_id,blueprint_sha256,package FROM bookworlds '
        'WHERE archive_sha256=?', [entry.archiveHash],
      );
      if (rows.isNotEmpty) {
        final storedBytes = rows.single.columnAt(2);
        if (rows.single.columnAt(0) != entry.bookworldId ||
            rows.single.columnAt(1) != entry.blueprintHash ||
            storedBytes is! Uint8List || !_same(storedBytes, package)) {
          throw const FormatException('BookWorld collision or stored corruption');
        }
        return;
      }
      _db.execute(
        'INSERT INTO bookworlds'
        '(archive_sha256,bookworld_id,blueprint_sha256,title,package) '
        'VALUES(?,?,?,?,?)',
        [entry.archiveHash, entry.bookworldId,
         entry.blueprintHash, entry.title, package],
      );
    });
    return entry;
  }

  List<WorldCatalogEntry> installedWorlds() => [
    for (final row in _db.select(
      'SELECT archive_sha256,bookworld_id,blueprint_sha256,title '
      'FROM bookworlds ORDER BY bookworld_id,archive_sha256'))
      WorldCatalogEntry(
        archiveHash: row.columnAt(0) as String,
        bookworldId: row.columnAt(1) as String,
        blueprintHash: row.columnAt(2) as String,
        title: row.columnAt(3) as String,
      ),
  ];

  VerifiedBookworld _world(String archiveHash) {
    _validHash(archiveHash, 'archive_sha256');
    final rows = _db.select(
      'SELECT package,bookworld_id,blueprint_sha256 FROM bookworlds '
      'WHERE archive_sha256=?', [archiveHash],
    );
    if (rows.length != 1 || rows.single.columnAt(0) is! Uint8List) {
      throw const FormatException('BookWorld is not installed');
    }
    final checked = _inspectBookworld(
      rows.single.columnAt(0) as Uint8List,
    );
    if (checked.archiveHash != archiveHash ||
        checked.bookworldId != rows.single.columnAt(1) ||
        checked.blueprint.blueprintHash != rows.single.columnAt(2)) {
      throw const FormatException('Stored BookWorld integrity mismatch');
    }
    return checked;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Multiple independent campaigns per one compiled BookWorld.
  String createCampaign(String archiveHash, {String? parentCampaignId}) {
    final world = _world(archiveHash);
    if (parentCampaignId != null) _validId(parentCampaignId, 'parent ID');
    final id = _newId();
    _transaction(() {
      final parent = parentCampaignId == null
          ? null : _campaignRow(parentCampaignId);
      if (parent != null && parent.worldHash != archiveHash) {
        throw const FormatException('Cross-BookWorld parent mismatch');
      }
      // Fork from the exact verified parent head, not just a parent label.
      // All cloned events and the new campaign head are one transaction.
      final coordinator = parent == null
          ? StoryEngineCoordinator.start(world.blueprint)
          : _restore(parentCampaignId!, parent);
      _db.execute(
        'INSERT INTO campaigns'
        '(campaign_id,world_sha256,parent_campaign_id,revision,'
        'state_sha256,head_event_sha256,saved_at_utc) '
        'VALUES(?,?,?,?,?,?,?)',
        [id, archiveHash, parentCampaignId,
         coordinator.state.revision, coordinator.state.stateHash,
         coordinator.events.isEmpty ? null : coordinator.events.last.hash,
         _utc()],
      );
      if (parent != null) {
        for (final event in coordinator.events) {
          _db.execute(
            'INSERT INTO events'
            '(campaign_id,sequence,action_id,event_sha256,payload) '
            'VALUES(?,?,?,?,?)',
            [id, event.sequence, event.actionId,
             event.hash, canonicalJson(event.toJson())],
          );
        }
      }
    });
    return id;
  }

  CampaignSnapshot _campaignRow(String campaignId) {
    _validId(campaignId, 'campaign ID');
    final rows = _db.select(
      'SELECT world_sha256,parent_campaign_id,revision,state_sha256,'
      'head_event_sha256,saved_at_utc FROM campaigns WHERE campaign_id=?',
      [campaignId],
    );
    if (rows.length != 1) throw const FormatException('Campaign not found');
    final row = rows.single;
    final revision = row.columnAt(2);
    if (revision is! int || revision < 0 || revision > maxTurns ||
        row.columnAt(3) is! String) {
      throw const FormatException('Invalid stored campaign head');
    }
    return CampaignSnapshot(
      id: campaignId,
      worldHash: row.columnAt(0) as String,
      parentId: row.columnAt(1) as String?,
      revision: revision,
      stateHash: row.columnAt(3) as String,
      headEventHash: row.columnAt(4) as String?,
      savedAt: row.columnAt(5) as String,
    );
  }

  StoryEngineCoordinator _restore(
      String campaignId, CampaignSnapshot snapshot) {
    final world = _world(snapshot.worldHash);
    final rows = _db.select(
      'SELECT sequence,action_id,event_sha256,payload FROM events '
      'WHERE campaign_id=? ORDER BY sequence', [campaignId],
    );
    if (rows.length != snapshot.revision) {
      throw const FormatException('Missing or extra committed events');
    }
    final events = <Map<String, dynamic>>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final payload = row.columnAt(3);
      if (row.columnAt(0) != i + 1 || payload is! String) {
        throw const FormatException('Nonconsecutive event log');
      }
      final dynamic event;
      try {
        event = jsonDecode(payload);
      } on FormatException {
        throw const FormatException('Invalid game event JSON');
      }
      if (event is! Map<String, dynamic> ||
          canonicalJson(event) != payload ||
          event['action_id'] != row.columnAt(1) ||
          event['hash'] != row.columnAt(2)) {
        throw const FormatException('Stored event body mismatch');
      }
      events.add(event);
    }
    return StoryEngineCoordinator.restore(world.blueprint, {
      'format': 'ai_story_bridge_checkpoint_v1',
      'schema_version': 1,
      'book_id': world.bookworldId,
      'blueprint_sha256': world.blueprint.blueprintHash,
      'revision': snapshot.revision,
      'state_sha256': snapshot.stateHash,
      'head_event_sha256': snapshot.headEventHash,
      'events': events,
    });
  }

  CampaignRecord loadCampaign(String id) {
    final snapshot = _campaignRow(id);
    return CampaignRecord(snapshot, _restore(id, snapshot));
  }

  List<CampaignSnapshot> campaigns() => [
    for (final row in _db.select(
      'SELECT campaign_id FROM campaigns '
      'ORDER BY saved_at_utc DESC,campaign_id'))
      _campaignRow(row.columnAt(0) as String),
  ];

  /// No returned success until event append and head update have committed.
  DecisionResult commitChoice(String id, {
    required String actionId,
    required String choiceId,
    required int expectedRevision,
  }) {
    return _transaction(() {
      final snapshot = _campaignRow(id);
      final coordinator = _restore(id, snapshot);
      if (snapshot.revision >= maxTurns) {
        throw const FormatException('Campaign turn limit reached');
      }
      final result = coordinator.choose(
        actionId: actionId, choiceId: choiceId,
        expectedRevision: expectedRevision,
      );
      if (!result.applied) return result;
      final event = result.event!;
      if (event.sequence != snapshot.revision + 1 ||
          event.beforeStateHash != snapshot.stateHash ||
          event.previousHash != snapshot.headEventHash) {
        throw const FormatException('Invalid event transition');
      }
      _db.execute(
        'INSERT INTO events'
        '(campaign_id,sequence,action_id,event_sha256,payload) '
        'VALUES(?,?,?,?,?)',
        [id, event.sequence, actionId, event.hash,
         canonicalJson(event.toJson())],
      );
      _db.execute(
        'UPDATE campaigns SET revision=?,state_sha256=?,'
        'head_event_sha256=?,saved_at_utc=? '
        'WHERE campaign_id=? AND revision=?',
        [coordinator.state.revision, coordinator.state.stateHash,
         event.hash, _utc(), id, snapshot.revision],
      );
      if (_db.select('SELECT changes()').single.columnAt(0) != 1) {
        throw const FormatException('Concurrent campaign modification');
      }
      return result;
    });
  }


  /// Exact, verified backup of the original installed BookWorld archive.
  Uint8List exportBookworld(String archiveHash) {
    _world(archiveHash);
    final rows = _db.select(
      'SELECT package FROM bookworlds WHERE archive_sha256=?',
      [archiveHash],
    );
    return Uint8List.fromList(rows.single.columnAt(0) as Uint8List);
  }

  /// Do not cascade-delete a BookWorld that still has campaigns.
  /// The Flutter UI requires an external .bworld backup before this call.
  void deleteBookworld(String archiveHash) {
    _transaction(() {
      _world(archiveHash);
      final count = _db.select(
        'SELECT COUNT(*) FROM campaigns WHERE world_sha256=?',
        [archiveHash],
      ).single.columnAt(0) as int;
      if (count != 0) {
        throw const FormatException(
          'BookWorld has saved campaigns; export and delete them first',
        );
      }
      _db.execute(
        'DELETE FROM bookworlds WHERE archive_sha256=?', [archiveHash],
      );
      if (_db.select('SELECT changes()').single.columnAt(0) != 1) {
        throw const FormatException('BookWorld deletion did not commit');
      }
    });
  }

  /// Reject stale deletions and corrupted journals. Forks own cloned event
  /// logs; foreign key ON DELETE SET NULL only clears the parent pointer.
  void deleteCampaign(String campaignId, {required int expectedRevision}) {
    _transaction(() {
      final snapshot = _campaignRow(campaignId);
      if (snapshot.revision != expectedRevision) {
        throw const FormatException(
          'Campaign changed after backup; export again',
        );
      }
      _restore(campaignId, snapshot);
      _db.execute(
        'DELETE FROM campaigns WHERE campaign_id=? AND revision=?',
        [campaignId, expectedRevision],
      );
      if (_db.select('SELECT changes()').single.columnAt(0) != 1) {
        throw const FormatException('Concurrent campaign modification');
      }
    });
  }

  /// Portable v2: separate from the existing pilot .bwsave v1. References
  /// installed BookWorld by exact SHA; does NOT contain the book text.
  String exportPortable(String campaignId) {
    final record = loadCampaign(campaignId);
    final body = <String, dynamic>{
      'format': saveFormat,
      'schema_version': 2,
      'source_campaign_id': campaignId,
      'world_sha256': record.metadata.worldHash,
      'role': 'PROTAGONIST',
      'plot_mode': 'CANON',
      'interaction': 'CLASSIC',
      'checkpoint': record.coordinator.checkpoint(),
    };
    return jsonEncode({...body, 'checksum_sha256': _checksum(body)});
  }


  /// Read-only preflight: validate envelope, checksum, exact installed world,
  /// event chain, and deterministic replay before offering to import.
  /// Not a backup write and never creates or replaces a campaign.
  PortableSavePreview previewPortable(String text) =>
      _verifyPortable(text).preview;

  _VerifiedPortable _verifyPortable(String text) {
    if (utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException('Portable save exceeds size limit');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Invalid portable save JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid portable save envelope');
    }
    final parsed = Map<String, dynamic>.from(decoded);
    const keys = {
      'format', 'schema_version', 'source_campaign_id', 'world_sha256',
      'role', 'plot_mode', 'interaction', 'checkpoint', 'checksum_sha256',
    };
    if (parsed.length != keys.length ||
        !parsed.keys.toSet().containsAll(keys) ||
        parsed['format'] != saveFormat ||
        parsed['schema_version'] != 2 ||
        parsed['role'] != 'PROTAGONIST' ||
        parsed['plot_mode'] != 'CANON' ||
        parsed['interaction'] != 'CLASSIC') {
      throw const FormatException('Unsupported portable save');
    }
    final sourceId = parsed['source_campaign_id'];
    final archiveHash = parsed['world_sha256'];
    if (sourceId is! String || archiveHash is! String) {
      throw const FormatException('Invalid portable save identity');
    }
    _validId(sourceId, 'source_campaign_id');
    _validHash(archiveHash, 'world_sha256');
    final checksum = parsed.remove('checksum_sha256');
    if (checksum is! String || !_hash.hasMatch(checksum) ||
        checksum != _checksum(parsed)) {
      throw const FormatException('Portable save checksum mismatch');
    }
    final checkpoint = parsed['checkpoint'];
    if (checkpoint is! Map<String, dynamic>) {
      throw const FormatException('Invalid portable checkpoint');
    }
    final world = _world(archiveHash);
    final restored = StoryEngineCoordinator.restore(
      world.blueprint, checkpoint,
    );
    if (restored.events.length > maxTurns) {
      throw const FormatException('Too many portable events');
    }
    if (restored.state.revision != restored.events.length) {
      throw const FormatException('Portable event sequence mismatch');
    }
    return _VerifiedPortable(
      restored,
      PortableSavePreview(
        sourceCampaignId: sourceId,
        worldHash: archiveHash,
        revision: restored.state.revision,
        stateHash: restored.state.stateHash,
        isTerminal: restored.isTerminal,
      ),
    );
  }

  /// Same strict preflight is re-run immediately before the transaction.
  /// Never trust the source campaign ID as a local SQL key: import creates
  /// an independent new slot without overwriting the source or its forks.
  String importPortable(String text) {
    final checked = _verifyPortable(text);
    final restored = checked.coordinator;
    final archiveHash = checked.preview.worldHash;
    final newId = _newId();
    _transaction(() {
      _db.execute(
        'INSERT INTO campaigns'
        '(campaign_id,world_sha256,parent_campaign_id,revision,'
        'state_sha256,head_event_sha256,saved_at_utc) '
        'VALUES(?,?,?,?,?,?,?)',
        [newId, archiveHash, null, restored.state.revision,
         restored.state.stateHash,
         restored.events.isEmpty ? null : restored.events.last.hash, _utc()],
      );
      for (final event in restored.events) {
        _db.execute(
          'INSERT INTO events'
          '(campaign_id,sequence,action_id,event_sha256,payload) '
          'VALUES(?,?,?,?,?)',
          [newId, event.sequence, event.actionId,
           event.hash, canonicalJson(event.toJson())],
        );
      }
    });
    return newId;
  }

}

/// Verified, replayed portable save metadata for a user-facing preview.
/// This does not import, mutate or remove any campaign.
class PortableSavePreview {
  const PortableSavePreview({
    required this.sourceCampaignId,
    required this.worldHash,
    required this.revision,
    required this.stateHash,
    required this.isTerminal,
  });

  final String sourceCampaignId;
  final String worldHash;
  final int revision;
  final String stateHash;
  final bool isTerminal;
}

class _VerifiedPortable {
  const _VerifiedPortable(this.coordinator, this.preview);
  final StoryEngineCoordinator coordinator;
  final PortableSavePreview preview;
}

class WorldCatalogEntry {
  const WorldCatalogEntry({
    required this.archiveHash,
    required this.bookworldId,
    required this.blueprintHash,
    required this.title,
  });
  final String archiveHash;
  final String bookworldId;
  final String blueprintHash;
  final String title;
}

class CampaignSnapshot {
  const CampaignSnapshot({
    required this.id,
    required this.worldHash,
    required this.parentId,
    required this.revision,
    required this.stateHash,
    required this.headEventHash,
    required this.savedAt,
  });
  final String id;
  final String worldHash;
  final String? parentId;
  final int revision;
  final String stateHash;
  final String? headEventHash;
  final String savedAt;
}

class CampaignRecord {
  const CampaignRecord(this.metadata, this.coordinator);
  final CampaignSnapshot metadata;
  final StoryEngineCoordinator coordinator;
}
