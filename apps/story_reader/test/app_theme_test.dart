import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/app_theme.dart';
import 'package:ai_story_reader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('appearance can be changed in settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Внешний вид'), findsOneWidget);
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(AppAppearanceController.instance.value, AppAppearance.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ai_story_app_dark_v1'), isTrue);
    expect(prefs.getInt('ai_story_reading_v1_palette'), isNull);
    await AppAppearanceController.instance.change(AppAppearance.light);
    expect(prefs.getInt('ai_story_reading_v1_palette'), isNull);
    await AppAppearanceController.instance.change(AppAppearance.system);
    expect(AppAppearanceController.instance.value, AppAppearance.system);
    expect(prefs.getString('ai_story_app_appearance_v2'), 'system');
  });

  testWidgets('settings keep OLED reading palette when app theme changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_story_reading_v1_palette': 3,
    });
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тёмная').first);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('ai_story_reading_v1_palette'), 3);
    expect(find.text('Как в системе'), findsOneWidget);
    expect(find.text('Анализ книги и приватность'), findsOneWidget);
    expect(find.text('Сбросить оформление чтения'), findsOneWidget);
    await tester.tap(find.text('Как в системе'));
    await tester.pumpAndSettle();
    expect(AppAppearanceController.instance.value, AppAppearance.system);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading reset is confirmed and does not touch book positions',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_story_reading_v1_palette': 3,
      'ai_story_reading_v1_font': 26.0,
      'ai_story_book_state_v1_keep.json': '{"chapter":1}',
    });
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Сбросить оформление чтения'));
    await tester.tap(find.text('Сбросить оформление чтения'));
    await tester.pumpAndSettle();
    expect(find.text('Сбросить оформление чтения?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('ai_story_reading_v1_palette'), 3);
    await tester.tap(find.text('Сбросить оформление чтения'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить оформление').last);
    await tester.pumpAndSettle();
    expect(prefs.getInt('ai_story_reading_v1_palette'), 1);
    expect(prefs.getDouble('ai_story_reading_v1_font'), 18);
    expect(prefs.getString('ai_story_book_state_v1_keep.json'), '{"chapter":1}');
    expect(tester.takeException(), isNull);
  });

  test('reader and app colors remain independent', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
  testWidgets('reading preferences open directly from settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Оформление страниц'));
    await tester.pumpAndSettle();
    expect(find.text('Настройки чтения'), findsOneWidget);
    expect(find.text('OLED'), findsOneWidget);
  });

}
