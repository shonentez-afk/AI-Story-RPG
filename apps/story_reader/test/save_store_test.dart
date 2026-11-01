import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/save_store.dart';

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

  test('invalid new envelope does not silently lose history', () async {
    SharedPreferences.setMockInitialValues({
      SaveStore.key: '{"format":"ai_story_save_envelope_v1","snapshot":"ok","journal":[42]}',
    });
    expect(() => SaveStore().readGame(), throwsFormatException);
  });
}
