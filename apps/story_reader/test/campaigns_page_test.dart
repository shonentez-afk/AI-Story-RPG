import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_engine/story_engine.dart';
import 'package:ai_story_reader/campaign_store.dart';
import 'package:ai_story_reader/game_progress.dart';
import 'package:ai_story_reader/main.dart';
import 'package:ai_story_reader/save_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens a chosen campaign and restores its engine scene',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = CampaignStore();
    final engine = StoryEngine(project: makePilotStory())..start();
    final snapshot = StoryRuntimeSnapshotCodec()
        .encodeJson(engine.createSnapshot());
    await store.write('campaign_first',
        GameSaveRecord(snapshot, const [], const GameProgress(), 1),
        sceneTitle: 'Ворота');
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мои прохождения'));
    await tester.pumpAndSettle();
    expect(find.text('Тайна особняка · 1'), findsOneWidget);
    await tester.tap(find.text('Тайна особняка · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Войти и исследовать дом'), findsOneWidget);
  });

  testWidgets('old single-slot save resumes without new-game overwrite',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final engine = StoryEngine(project: makePilotStory())..start();
    engine.choose(StoryChoiceId('enter'));
    final originalSnapshot = StoryRuntimeSnapshotCodec()
        .encodeJson(engine.createSnapshot());
    await SaveStore().writeGame(originalSnapshot,
        ['Тайна особняка: Войти и исследовать дом'],
        const GameProgress().apply('enter'), 0);
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Прочитать старое письмо'), findsOneWidget);
    await tester.tap(find.text('Герой'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Смелость: 1'), findsOneWidget);
    expect((await SaveStore().readGame())!.snapshot, originalSnapshot);
    expect((await CampaignStore().all()).single.isLegacy, isTrue);
  });

  testWidgets('deletion requires confirmation and preserves other slot',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = CampaignStore();
    await store.write('campaign_first',
        const GameSaveRecord('one', []), sceneTitle: 'Ворота');
    await store.write('campaign_second',
        const GameSaveRecord('two', []), sceneTitle: 'Подвал');
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мои прохождения'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Удалить прохождение'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Удалить прохождение').first);
    await tester.pumpAndSettle();
    expect(find.text('Удалить прохождение?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect((await store.all()).length, 2);
    await tester.tap(find.byTooltip('Удалить прохождение').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();
    expect((await store.all()).length, 1);
    expect(find.byTooltip('Удалить прохождение'), findsOneWidget);
  });

  testWidgets('corrupt engine snapshot never becomes a writable new story',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = CampaignStore();
    const id = 'campaign_broken';
    await store.write(id,
        const GameSaveRecord('invalid engine snapshot', []),
        sceneTitle: 'Кабинет');
    final before = (await store.read(id))!.snapshot;
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    expect(find.text('Сохранение не удалось открыть'), findsOneWidget);
    expect(find.text('Войти и исследовать дом'), findsNothing);
    expect(find.textContaining('не перезаписать ваши данные'), findsOneWidget);
    expect((await store.read(id))!.snapshot, before);
  });

  testWidgets('autosave writes a choice without manual save action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти и исследовать дом'));
    await tester.pumpAndSettle();
    final store = CampaignStore();
    final all = await store.all();
    expect(all.length, 1);
    final restored = (await store.read(all.single.id))!;
    expect(restored.rulesVersion, 1);
    expect(restored.progress.courage, 1);
    expect(restored.journal, contains(
      'Тайна особняка: Войти и исследовать дом',
    ));
    expect(restored.snapshot, isNotEmpty);
  });
}

// Negative scenario: invalid engine snapshots must remain immutable on load.
