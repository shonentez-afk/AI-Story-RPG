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
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Оформление приложения'), findsOneWidget);
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(AppAppearanceController.instance.value, AppAppearance.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ai_story_app_dark_v1'), isTrue);
  });

  test('reader and app colors remain independent', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
}
