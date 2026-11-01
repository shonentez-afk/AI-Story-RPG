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
    await tester.tap(find.text('Предметы'));
    await tester.pumpAndSettle();
    expect(find.text('Инвентарь'), findsOneWidget);
    expect(find.textContaining('демонстрационный сюжет'), findsOneWidget);
  });
}
