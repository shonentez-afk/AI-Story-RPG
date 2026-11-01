import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('game offers shared book controls and immersive mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Настройки чтения'), findsOneWidget);
    await tester.tap(find.byTooltip('Настройки чтения'));
    await tester.pumpAndSettle();
    expect(find.text('Размер текста: 18'), findsOneWidget);
    expect(find.text('Сепия'), findsOneWidget);
    await tester.tap(find.text('Тёмная').last);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('ai_story_reading_v1_palette'), 2);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Скрыть управление'));
    await tester.pumpAndSettle();
    expect(find.text('Предметы'), findsOneWidget);
    expect(find.byTooltip('Показать управление'), findsOneWidget);
    await tester.longPress(find.byTooltip('Показать управление'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Полный экран'));
    await tester.pumpAndSettle();
    expect(find.text('Предметы'), findsNothing);
    expect(find.text('Войти и исследовать дом'), findsOneWidget);
    await tester.tap(find.text('Тайна особняка').last);
    await tester.pump();
    expect(find.text('Предметы'), findsOneWidget);
    expect(find.byTooltip('Настройки чтения'), findsNothing);
    await tester.tap(find.byTooltip('Показать управление'));
    await tester.pumpAndSettle();
    expect(find.text('Предметы'), findsOneWidget);
    expect(find.byTooltip('Настройки чтения'), findsOneWidget);
  });
}
