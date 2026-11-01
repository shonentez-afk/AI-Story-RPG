import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RPG bottom panel opens inventory without inventing items', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    expect(find.text('ВАШЕ ДЕЙСТВИЕ'), findsOneWidget);
    expect(find.text('Предметы'), findsOneWidget);
    expect(find.text('Герой'), findsOneWidget);
    expect(find.text('Журнал'), findsOneWidget);
    await tester.tap(find.text('Предметы'));
    await tester.pumpAndSettle();
    expect(find.text('Инвентарь'), findsOneWidget);
    expect(find.textContaining('демонстрационный сюжет'), findsOneWidget);
  });

  testWidgets('journal records actual choice in current game session', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти и исследовать дом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Тайна особняка: Войти и исследовать дом'),
        findsOneWidget);
  });
  testWidgets('saved game restores journal after reopening', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти и исследовать дом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Тайна особняка: Войти и исследовать дом'),
        findsOneWidget);
  });

}
