import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_story_reader/campaign_store.dart';
import 'package:ai_story_reader/game_progress.dart';
import 'package:ai_story_reader/main.dart' show makePilotStory;
import 'package:ai_story_reader/pilot_save_codec.dart';
import 'package:ai_story_reader/save_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_engine/story_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GameSaveRecord fixture() {
    final engine = StoryEngine(project: makePilotStory())..start();
    engine.choose(StoryChoiceId('enter'));
    engine.choose(StoryChoiceId('search_drawer'));
    return GameSaveRecord(
      StoryRuntimeSnapshotCodec().encodeJson(engine.createSnapshot()),
      const ['gate: Войти', 'library: Осмотреть ящик'],
      const GameProgress().apply('enter').apply('search_drawer'),
      1,
    );
  }

  Uint8List export(GameSaveRecord game, {String id = 'campaign_source'}) =>
      PilotSaveCodec.encode(
        sourceCampaignId: id,
        game: game,
        project: makePilotStory(),
      );

  PilotSaveImport parse(Uint8List bytes) =>
      PilotSaveCodec.decode(bytes, project: makePilotStory());

  test('roundtrip validates snapshot, items, rules and original source ID', () {
    final original = fixture();
    final bytes = export(original);
    final imported = parse(bytes);
    expect(imported.sourceCampaignId, 'campaign_source');
    expect(imported.sceneTitle, 'Кабинет хранителя');
    expect(imported.game.journal,
        ['gate: Войти', 'library: Осмотреть ящик']);
    expect(imported.game.progress.courage, 1);
    expect(imported.game.progress.insight, 1);
    expect(imported.game.progress.items, ['key']);
    expect(imported.game.rulesVersion, 1);
    expect(imported.game.snapshot, original.snapshot);
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final payload = decoded['payload'] as Map<String, dynamic>;
    expect(payload['book_id'], PilotSaveCodec.bookId);
    expect(payload['bookworld_hash'], isNull);
    expect(payload['rng_seed'], isNull);
    expect(payload['role'], isNull);
    expect(payload['plot'], isNull);
    expect(payload['interaction'], 'CLASSIC');
    expect(payload['decision_journal'], hasLength(2));
    expect(decoded['payload_sha256'], hasLength(64));
  });

  test('checksum uses canonical keys and rejects changed game data', () {
    final bytes = export(fixture());
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final payload = root['payload'] as Map<String, dynamic>;
    // Key reordering must not invalidate the stable checksum.
    root['payload'] = <String, dynamic>{
      for (final key in payload.keys.toList().reversed) key: payload[key],
    };
    expect(parse(Uint8List.fromList(utf8.encode(jsonEncode(root))))
        .game.progress.items, ['key']);
    (payload['world_state'] as Map<String, dynamic>)['courage'] = 999;
    root['payload'] = payload;
    expect(() => parse(Uint8List.fromList(utf8.encode(jsonEncode(root)))),
        throwsFormatException);
  });

  test('invalid schema, wrong book, invalid utf8 and size fail closed', () {
    final original = export(fixture());
    final changed = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
    changed['schema_version'] = 2;
    expect(() => parse(Uint8List.fromList(utf8.encode(jsonEncode(changed)))),
        throwsFormatException);
    changed['schema_version'] = 1;
    (changed['payload'] as Map<String, dynamic>)['book_id'] = 'other_book';
    expect(() => parse(Uint8List.fromList(utf8.encode(jsonEncode(changed)))),
        throwsFormatException);
    expect(() => parse(Uint8List.fromList([0xff, 0xfe])),
        throwsFormatException);
    expect(() => parse(Uint8List(PilotSaveCodec.maxFileBytes + 1)),
        throwsFormatException);
  });

  test('engine snapshot must restore before export or import', () {
    const broken = GameSaveRecord('invalid snapshot', []);
    expect(() => export(broken), throwsFormatException);
    final good = fixture();
    expect(() => export(good, id: '../unsafe'), throwsFormatException);
  });

  test('old pilot rules stay 0 and are not silently upgraded', () {
    final old = fixture();
    final legacy = GameSaveRecord(old.snapshot, old.journal, old.progress, 0);
    final decoded = parse(export(legacy, id: CampaignStore.legacyId));
    expect(decoded.sourceCampaignId, CampaignStore.legacyId);
    expect(decoded.game.rulesVersion, 0);
  });

  test('import creates a new slot and never overwrites the source', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CampaignStore();
    final original = fixture();
    await store.write('campaign_source', original, sceneTitle: 'Кабинет');
    final recovered = parse(export((await store.read('campaign_source'))!));
    final importedId = await store.importNew(
      recovered.game, sceneTitle: recovered.sceneTitle);
    expect(importedId, isNot('campaign_source'));
    expect((await store.read('campaign_source'))!.snapshot, original.snapshot);
    expect((await store.read(importedId))!.journal, original.journal);
    final copyId = await store.importNew(
      recovered.game, sceneTitle: recovered.sceneTitle);
    expect(copyId, isNot(importedId));
    expect((await store.all()).length, 3);
  });
}
