import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/campaign_store.dart';
import 'package:ai_story_reader/game_progress.dart';
import 'package:ai_story_reader/save_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two independent slots hold exact journal, stats and version', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CampaignStore();
    const a = 'campaign_one';
    const b = 'campaign_two';
    final stateA = const GameProgress().apply('enter').apply('search_drawer');
    final stateB = const GameProgress().apply('enter').apply('inspect_letter');
    await store.write(a, GameSaveRecord('first', ['gate', 'drawer'], stateA, 1),
        sceneTitle: 'Кабинет');
    await store.write(b, GameSaveRecord('second', ['gate', 'letter'], stateB, 1),
        sceneTitle: 'Библиотека');
    final restoredA = (await store.read(a))!;
    final restoredB = (await store.read(b))!;
    expect(restoredA.snapshot, 'first');
    expect(restoredA.progress.items, ['key']);
    expect(restoredA.journal, ['gate', 'drawer']);
    expect(restoredA.rulesVersion, 1);
    expect(restoredB.snapshot, 'second');
    expect(restoredB.progress.items, ['letter']);
    expect((await store.all()).length, 2);

    await store.write(a, GameSaveRecord('third', ['new'], stateA, 1),
        sceneTitle: 'Подвал');
    expect((await store.read(b))!.snapshot, 'second');
    expect((await store.read(a))!.snapshot, 'third');
    expect((await store.all()).first.id, a);
    await store.delete(a);
    expect(await store.read(a), isNull);
    expect((await store.read(b))!.snapshot, 'second');
    expect((await store.all()).single.id, b);
  });

  test('legacy slot remains intact, readable and independent', () async {
    SharedPreferences.setMockInitialValues({});
    const legacy = '{"schema":1,"engine":"old"}';
    await SaveStore().write(legacy);
    final store = CampaignStore();
    await store.write('campaign_new', const GameSaveRecord('new', []),
        sceneTitle: 'Ворота');
    expect((await store.read(CampaignStore.legacyId))!.snapshot, legacy);
    expect((await store.all()).length, 2);
    await store.delete('campaign_new');
    expect(await SaveStore().read(), legacy);
    final old = (await store.read(CampaignStore.legacyId))!;
    expect(old.rulesVersion, 0);
    await store.write(CampaignStore.legacyId, old, sceneTitle: 'Старый ход');
    expect((await SaveStore().readGame())!.snapshot, legacy);
    expect((await store.all()).single.id, CampaignStore.legacyId);
  });

  test('invalid IDs cannot address other preference keys', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CampaignStore();
    expect(() => store.read('../other'), throwsFormatException);
    expect(() => store.delete('campaign/../../other'), throwsFormatException);
    expect(() => store.write('bad id',
        const GameSaveRecord('x', []), sceneTitle: 'X'), throwsFormatException);
  });

  test('damaged campaign remains visible but cannot be restored', () async {
    SharedPreferences.setMockInitialValues({
      'ai_story_campaign_v1_campaign_bad': '{"format":"unknown"}',
    });
    final store = CampaignStore();
    final item = (await store.all()).single;
    expect(item.damaged, isTrue);
    expect(() => store.read(item.id), throwsFormatException);
    await store.delete(item.id);
    expect(await store.all(), isEmpty);
  });

  test('IDs are generated for independent campaigns', () {
    final a = CampaignStore.newId();
    final b = CampaignStore.newId();
    expect(a, isNot(b));
    expect(a, startsWith('c_'));
  });
}
