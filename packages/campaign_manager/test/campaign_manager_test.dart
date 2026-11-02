import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

const fixturePath = '../../artifacts/bookworld/manor_m17_original_demo.bworld';

void main() {
  late Directory temp;
  late BookworldCampaignStore store;
  late Uint8List archive;
  late WorldCatalogEntry world;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('story_campaign_test_');
    store = BookworldCampaignStore.openPrivateDirectory(temp.path);
    archive = File(fixturePath).readAsBytesSync();
    world = store.installBookworld(archive);
  });

  tearDown(() {
    store.close();
    temp.deleteSync(recursive: true);
  });

  DecisionResult take(String campaign, String id, String choice) =>
      store.commitChoice(
        campaign,
        actionId: id,
        choiceId: choice,
        expectedRevision: store.loadCampaign(campaign).metadata.revision,
      );

  test('BookWorld catalog deduplicates exact byte-identical package', () {
    expect(world.bookworldId, 'manor_m17_original_demo');
    expect(world.blueprintHash.length, 64);
    expect(store.installedWorlds().length, 1);
    expect(store.installBookworld(archive).archiveHash, world.archiveHash);
    expect(store.installedWorlds().length, 1);
    final corrupt = Uint8List.fromList(archive);
    corrupt[50] ^= 0x40;
    expect(() => store.installBookworld(corrupt), throwsFormatException);
    expect(store.installedWorlds().length, 1);
  });

  test('35 committed turns survive process restart, integrity and ending', () {
    final campaign = store.createCampaign(world.archiveHash);
    for (var i = 0; i < 23; i++) {
      expect(take(campaign, 'inspect_$i', 'inspect_gate').applied, isTrue);
    }
    final before = store.loadCampaign(campaign);
    expect(before.metadata.revision, 23);
    expect(before.coordinator.sceneId, 'gate');
    expect(before.coordinator.state.tick, 46);
    final stableHash = before.metadata.stateHash;
    store.close();
    store = BookworldCampaignStore.openPrivateDirectory(temp.path);
    expect(store.installedWorlds().single.archiveHash, world.archiveHash);
    expect(store.loadCampaign(campaign).metadata.stateHash, stableHash);
    final rest = <(String, String)>[
      ('market_1', 'walk_market'),
      ('trust', 'ask_guard'),
      ('market_2', 'walk_market'),
      ('map', 'buy_map'),
      ('market_3', 'walk_market'),
      ('key', 'find_key'),
      ('hall', 'enter_hall'),
      ('family', 'learn_from_guard'),
      ('note', 'write_note'),
      ('cellar', 'go_cellar'),
      ('vault', 'open_vault'),
      ('publish', 'publish_archive'),
    ];
    for (final action in rest) {
      expect(take(campaign, action.$1, action.$2).applied, isTrue,
          reason: action.$1);
    }
    final completed = store.loadCampaign(campaign);
    expect(completed.metadata.revision, 35);
    expect(completed.coordinator.sceneId, 'end_reveal');
    expect(completed.coordinator.isTerminal, isTrue);
    expect(completed.coordinator.state.flags['revealed'], true);
    expect(completed.coordinator.state.inventory, isNot(contains('key')));
    expect(completed.coordinator.state.knowledge['player'],
        contains('archive_origin'));
    expect(completed.coordinator.state.knowledge['guard'], isEmpty);
    expect(store.campaigns().length, 1);
  });

  test('denied, stale and duplicate actions never create a second event', () {
    final campaign = store.createCampaign(world.archiveHash);
    final initial = store.loadCampaign(campaign);
    final hash = initial.metadata.stateHash;
    final rejected = take(campaign, 'locked', 'enter_hall');
    expect(rejected.status, DecisionStatus.denied);
    expect(store.loadCampaign(campaign).metadata.stateHash, hash);
    final successful = take(campaign, 'first', 'inspect_gate');
    expect(successful.applied, isTrue);
    final once = store.loadCampaign(campaign);
    expect(once.metadata.revision, 1);
    expect(store.commitChoice(campaign,
      actionId: 'first', choiceId: 'inspect_gate',
      expectedRevision: 0).status, DecisionStatus.duplicate);
    expect(store.commitChoice(campaign,
      actionId: 'stale', choiceId: 'walk_market',
      expectedRevision: 0).status, DecisionStatus.denied);
    expect(store.loadCampaign(campaign).metadata.stateHash,
        once.metadata.stateHash);
    expect(() => store.commitChoice(campaign,
      actionId: 'first', choiceId: 'walk_market', expectedRevision: 1),
      throwsFormatException);
  });

  test('two independent campaigns share world but never leak inventory', () {
    final a = store.createCampaign(world.archiveHash);
    final b = store.createCampaign(world.archiveHash);
    expect(take(a, 'a_market', 'walk_market').applied, isTrue);
    expect(take(a, 'a_key', 'find_key').applied, isTrue);
    expect(store.loadCampaign(a).coordinator.state.inventory, contains('key'));
    expect(store.loadCampaign(b).coordinator.state.inventory, isEmpty);
    expect(take(b, 'b_leave', 'leave').applied, isTrue);
    expect(store.loadCampaign(b).coordinator.isTerminal, isTrue);
    expect(store.loadCampaign(a).coordinator.isTerminal, isFalse);
  });

  test('branch copies verified parent events and then evolves independently', () {
    final parent = store.createCampaign(world.archiveHash);
    expect(take(parent, 'parent_market', 'walk_market').applied, isTrue);
    expect(take(parent, 'parent_key', 'find_key').applied, isTrue);
    final parentBefore = store.loadCampaign(parent);
    final child = store.createCampaign(
      world.archiveHash, parentCampaignId: parent,
    );
    final branch = store.loadCampaign(child);
    expect(branch.metadata.parentId, parent);
    expect(branch.metadata.revision, parentBefore.metadata.revision);
    expect(branch.metadata.headEventHash, parentBefore.metadata.headEventHash);
    expect(branch.metadata.stateHash, parentBefore.metadata.stateHash);
    expect(branch.coordinator.state.inventory, contains('key'));
    expect(take(child, 'child_inspect', 'inspect_gate').applied, isTrue);
    expect(store.loadCampaign(parent).metadata.stateHash,
        parentBefore.metadata.stateHash);
    expect(store.loadCampaign(parent).metadata.revision, 2);
    expect(store.loadCampaign(child).metadata.revision, 3);
    expect(take(parent, 'parent_leave', 'leave').applied, isTrue);
    expect(store.loadCampaign(parent).coordinator.isTerminal, isTrue);
    expect(store.loadCampaign(child).coordinator.isTerminal, isFalse);
  });

  test('portable v2 save verifies then forks to a fresh local ID', () {
    final campaign = store.createCampaign(world.archiveHash);
    take(campaign, 'inspect', 'inspect_gate');
    take(campaign, 'walk', 'walk_market');
    final serialized = store.exportPortable(campaign);
    final envelope = jsonDecode(serialized) as Map<String, dynamic>;
    expect(envelope['format'], BookworldCampaignStore.saveFormat);
    expect(envelope['world_sha256'], world.archiveHash);
    expect(envelope.containsKey('source_text'), isFalse);
    final imported = store.importPortable(serialized);
    expect(imported, isNot(campaign));
    expect(store.loadCampaign(imported).metadata.revision, 2);
    expect(store.loadCampaign(imported).metadata.stateHash,
        store.loadCampaign(campaign).metadata.stateHash);
    expect(take(imported, 'local_new', 'return_gate').applied, isTrue);
    expect(store.loadCampaign(campaign).metadata.revision, 2);
    expect(store.loadCampaign(imported).metadata.revision, 3);
  });

  test('tampered portable envelope and incompatible world are rejected', () {
    final a = store.createCampaign(world.archiveHash);
    take(a, 'inspect', 'inspect_gate');
    final text = store.exportPortable(a);
    final altered = jsonDecode(text) as Map<String, dynamic>;
    altered['role'] = 'CUSTOM';
    expect(() => store.importPortable(jsonEncode(altered)),
        throwsFormatException);
    final incompatible = jsonDecode(text) as Map<String, dynamic>;
    incompatible['world_sha256'] = List.filled(64, 'a').join();
    expect(() => store.importPortable(jsonEncode(incompatible)),
        throwsFormatException);
    // Even after forging a new outer checksum, inner event-head and
    // expected revision are verified from the exact story blueprint.
    final short = jsonDecode(text) as Map<String, dynamic>;
    final checkpoint = short['checkpoint'] as Map<String, dynamic>;
    (checkpoint['events'] as List).clear();
    short.remove('checksum_sha256');
    short['checksum_sha256'] =
        sha256.convert(utf8.encode(canonicalJson(short))).toString();
    expect(() => store.importPortable(jsonEncode(short)),
        throwsFormatException);
    expect(store.campaigns().length, 1);
    final otherRoot = Directory.systemTemp.createTempSync('story_new_');
    final other = BookworldCampaignStore.openPrivateDirectory(otherRoot.path);
    try {
      expect(() => other.importPortable(text), throwsFormatException);
    } finally {
      other.close();
      otherRoot.deleteSync(recursive: true);
    }
  });

  test('corrupt SQLite event is refused, not silently auto-repaired', () {
    final a = store.createCampaign(world.archiveHash);
    take(a, 'first', 'inspect_gate');
    final path = temp.path + Platform.pathSeparator +
        'bookworld_campaigns_v1.sqlite';
    final db = sqlite3.open(path);
    try {
      db.execute(
        "UPDATE events SET payload='{}' WHERE campaign_id=?", [a],
      );
    } finally {
      db.close();
    }
    expect(() => store.loadCampaign(a), throwsFormatException);
    expect(store.installedWorlds().length, 1);
  });

  test('SQLite failure after gameplay validation rolls back whole turn', () {
    final a = store.createCampaign(world.archiveHash);
    final initial = store.loadCampaign(a).metadata;
    final path = temp.path + Platform.pathSeparator +
        'bookworld_campaigns_v1.sqlite';
    final other = sqlite3.open(path);
    try {
      other.execute("CREATE TRIGGER sabotage BEFORE INSERT ON events "
          "BEGIN SELECT RAISE(ABORT, 'synthetic storage failure'); END");
    } finally {
      other.close();
    }
    expect(() => take(a, 'attempt', 'inspect_gate'),
        throwsA(isA<SqliteException>()));
    final after = store.loadCampaign(a).metadata;
    expect(after.revision, initial.revision);
    expect(after.stateHash, initial.stateHash);
    final cleanup = sqlite3.open(path);
    try {
      cleanup.execute('DROP TRIGGER sabotage');
    } finally {
      cleanup.close();
    }
    expect(take(a, 'retry', 'inspect_gate').applied, isTrue);
    expect(store.loadCampaign(a).metadata.revision, 1);
  });


  test('deleting parent retains fork and exported save restores', () {
    final parent = store.createCampaign(world.archiveHash);
    expect(take(parent, 'inspect_parent', 'inspect_gate').applied, isTrue);
    final fork = store.createCampaign(
      world.archiveHash, parentCampaignId: parent,
    );
    expect(take(fork, 'inspect_fork', 'inspect_gate').applied, isTrue);
    final forkHash = store.loadCampaign(fork).metadata.stateHash;
    final backup = store.exportPortable(parent);
    expect(() => store.deleteCampaign(parent, expectedRevision: 0),
        throwsFormatException);
    store.deleteCampaign(parent, expectedRevision: 1);
    expect(() => store.loadCampaign(parent), throwsFormatException);
    final child = store.loadCampaign(fork);
    expect(child.metadata.parentId, isNull);
    expect(child.metadata.revision, 2);
    expect(child.metadata.stateHash, forkHash);
    final restored = store.importPortable(backup);
    expect(restored, isNot(parent));
    expect(store.loadCampaign(restored).metadata.revision, 1);
  });

  test('BookWorld deletion rejects remaining campaigns and reinstalls', () {
    final backup = store.exportBookworld(world.archiveHash);
    expect(backup, orderedEquals(archive));
    final id = store.createCampaign(world.archiveHash);
    expect(() => store.deleteBookworld(world.archiveHash),
        throwsFormatException);
    expect(() => store.deleteCampaign(id, expectedRevision: 4),
        throwsFormatException);
    store.deleteCampaign(id, expectedRevision: 0);
    store.deleteBookworld(world.archiveHash);
    expect(store.installedWorlds(), isEmpty);
    expect(() => store.createCampaign(world.archiveHash),
        throwsFormatException);
    expect(store.installBookworld(backup).archiveHash, world.archiveHash);
  });


  test('read-only preview validates full replay, never creates a slot', () {
    final original = store.createCampaign(world.archiveHash);
    expect(take(original, 'before_preview', 'inspect_gate').applied, true);
    final portable = store.exportPortable(original);
    final oldHead = store.loadCampaign(original).metadata.stateHash;
    final verified = store.previewPortable(portable);
    expect(verified.worldHash, world.archiveHash);
    expect(verified.sourceCampaignId, original);
    expect(verified.revision, 1);
    expect(verified.stateHash, oldHead);
    expect(verified.isTerminal, isFalse);
    expect(store.campaigns().length, 1);

    final forged = jsonDecode(portable) as Map<String, dynamic>;
    (forged['checkpoint'] as Map<String, dynamic>)['revision'] = 900;
    forged.remove('checksum_sha256');
    forged['checksum_sha256'] =
        sha256.convert(utf8.encode(canonicalJson(forged))).toString();
    expect(() => store.previewPortable(jsonEncode(forged)),
        throwsFormatException);
    final damaged = portable.replaceFirst('"role":"PROTAGONIST"',
        '"role":"CUSTOM"');
    expect(() => store.previewPortable(damaged), throwsFormatException);
    expect(() => store.previewPortable('{broken'), throwsFormatException);
    expect(store.campaigns().length, 1);
    expect(store.loadCampaign(original).metadata.stateHash, oldHead);
  });

  test('Android-to-Windows offline files restore in independent SQLite DBs',
      () {
    final androidId = store.createCampaign(world.archiveHash);
    for (var i = 0; i < 24; i++) {
      expect(take(androidId, 'phone_$i', 'inspect_gate').applied, true);
    }
    final branch = store.createCampaign(
      world.archiveHash, parentCampaignId: androidId,
    );
    expect(take(branch, 'phone_branch', 'walk_market').applied, true);
    final source = store.loadCampaign(branch);
    expect(source.metadata.revision, 25);
    final transfer = Directory.systemTemp.createTempSync('rpg_transfer_');
    final sep = Platform.pathSeparator;
    final worldFile = File('${transfer.path}${sep}book.bworld');
    final saveFile = File('${transfer.path}${sep}progress.bwsave');
    final receiverPath = '${transfer.path}${sep}windows_private';
    worldFile.writeAsBytesSync(store.exportBookworld(world.archiveHash),
        flush: true);
    saveFile.writeAsStringSync(store.exportPortable(branch),
        encoding: utf8, flush: true);
    var receiver = BookworldCampaignStore.openPrivateDirectory(receiverPath);
    try {
      final transferred = saveFile.readAsStringSync(encoding: utf8);
      expect(() => receiver.previewPortable(transferred),
          throwsFormatException); // Exact world must be installed first.
      expect(receiver.campaigns(), isEmpty);
      receiver.installBookworld(
          Uint8List.fromList(worldFile.readAsBytesSync()));
      final preview = receiver.previewPortable(transferred);
      expect(preview.revision, 25);
      expect(preview.stateHash, source.metadata.stateHash);
      expect(preview.worldHash, world.archiveHash);
      expect(receiver.campaigns(), isEmpty); // Preflight is read-only.

      final destId = receiver.importPortable(transferred);
      expect(destId, isNot(branch));
      expect(receiver.loadCampaign(destId).metadata.stateHash,
          source.metadata.stateHash);
      receiver.close();
      receiver = BookworldCampaignStore.openPrivateDirectory(receiverPath);
      expect(receiver.loadCampaign(destId).metadata.revision, 25);
      expect(receiver.loadCampaign(destId).coordinator.events.length, 25);
      final advanced = receiver.commitChoice(
        destId, actionId: 'desktop_after_import',
        choiceId: 'return_gate', expectedRevision: 25,
      );
      expect(advanced.applied, isTrue);
      expect(receiver.loadCampaign(destId).metadata.revision, 26);
      expect(store.loadCampaign(branch).metadata.revision, 25);
      expect(store.loadCampaign(androidId).metadata.revision, 24);
      final duplicate = receiver.importPortable(transferred);
      expect(duplicate, isNot(destId));
      expect(receiver.loadCampaign(duplicate).metadata.stateHash,
          source.metadata.stateHash);
      expect(receiver.loadCampaign(destId).metadata.revision, 26);

      final corrupted = jsonDecode(transferred) as Map<String, dynamic>;
      corrupted['world_sha256'] = List.filled(64, 'a').join();
      final before = receiver.campaigns().length;
      expect(() => receiver.previewPortable(jsonEncode(corrupted)),
          throwsFormatException);
      expect(() => receiver.importPortable(jsonEncode(corrupted)),
          throwsFormatException);
      expect(receiver.campaigns().length, before);
    } finally {
      receiver.close();
      transfer.deleteSync(recursive: true);
    }
  });

  test('unknown DB version and modified world payload refuse to open', () {
    final path = temp.path + Platform.pathSeparator +
        'bookworld_campaigns_v1.sqlite';
    store.close();
    final connection = sqlite3.open(path);
    try {
      connection.execute('PRAGMA user_version=999');
    } finally {
      connection.close();
    }
    expect(() => BookworldCampaignStore.openPrivateDirectory(temp.path),
        throwsFormatException);
    // Restore so the normal teardown can cleanly close its connection.
    final cleanup = sqlite3.open(path);
    try {
      cleanup.execute('PRAGMA user_version=1');
    } finally {
      cleanup.close();
    }
    store = BookworldCampaignStore.openPrivateDirectory(temp.path);
    final mutated = sqlite3.open(path);
    try {
      mutated.execute("UPDATE bookworlds SET package=?",
          [Uint8List.fromList([1, 2, 3])]);
    } finally {
      mutated.close();
    }
    expect(() => store.createCampaign(world.archiveHash),
        throwsFormatException);
  });
}
