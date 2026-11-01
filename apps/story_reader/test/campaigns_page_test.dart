import 'package:flutter/material.dart';
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
