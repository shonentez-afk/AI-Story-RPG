import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/save_store.dart';
import 'package:ai_story_reader/game_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new save preserves snapshot and exact journal entries', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SaveStore();
    await store.writeGame('{"engine":"snapshot"}', [
      'Ворота: Войти в дом',
      'Библиотека: Прочитать письмо',
    ]);
    final restored = await store.readGame();
    expect(restored!.snapshot, '{"engine":"snapshot"}');
    expect(restored.journal, [
      'Ворота: Войти в дом',
      'Библиотека: Прочитать письмо',
    ]);
    expect(await store.read(), '{"engine":"snapshot"}');
  });

  test('old snapshot remains readable and starts with an empty journal', () async {
    const old = '{"schema":1,"engine":"legacy"}';
    SharedPreferences.setMockInitialValues({SaveStore.key: old});
    final saved = await SaveStore().readGame();
    expect(saved!.snapshot, old);
    expect(saved.journal, isEmpty);
    await SaveStore().writeGame(saved.snapshot, saved.journal);
    expect((await SaveStore().readGame())!.snapshot, old);
  });

  test('new pilot rules survive save and restore with world progress', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = const GameProgress().apply('enter').apply('search_drawer');
    final store = SaveStore();
    await store.writeGame('snapshot', ['entered', 'found key'], progress, 1);
    final restored = await store.readGame();
    expect(restored!.rulesVersion, 1);
    expect(restored.progress.items, ['key']);
    expect(restored.progress.choiceLockReason('unlock_cellar'), isNull);
    expect(restored.progress.choiceLockReason('open_secret'), isNotNull);
    expect(restored.journal, ['entered', 'found key']);
  });

  test('legacy envelope defaults to rules version zero', () async {
    SharedPreferences.setMockInitialValues({
      SaveStore.key:
          '{"format":"ai_story_save_envelope_v1","snapshot":"legacy",'
          '"journal":["earlier"],"progress":{"courage":0,"insight":0,"items":[]}}',
    });
    final save = await SaveStore().readGame();
    expect(save!.rulesVersion, 0);
    expect(save.snapshot, 'legacy');
    expect(save.journal, ['earlier']);
    await SaveStore().writeGame(save.snapshot, save.journal, save.progress,
        save.rulesVersion);
    expect((await SaveStore().readGame())!.rulesVersion, 0);
  });

  test('unknown rules version fails instead of silently changing choices', () async {
    SharedPreferences.setMockInitialValues({
      SaveStore.key:
          '{"format":"ai_story_save_envelope_v1","snapshot":"ok",'
          '"journal":[],"rulesVersion":42}',
    });
    expect(() => SaveStore().readGame(), throwsFormatException);
  });

  test('invalid new envelope does not silently lose history', () async {
    SharedPreferences.setMockInitialValues({
      SaveStore.key: '{"format":"ai_story_save_envelope_v1","snapshot":"ok","journal":[42]}',
    });
    expect(() => SaveStore().readGame(), throwsFormatException);
  });
}
