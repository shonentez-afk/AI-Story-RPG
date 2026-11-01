import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home provides library, settings and new story', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    expect(find.text('Новая история'), findsOneWidget);
    expect(find.text('Библиотека'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    await tester.tap(find.text('Библиотека'));
    await tester.pumpAndSettle();
    expect(find.text('Тайна особняка'), findsOneWidget);
    await tester.tap(find.text('Тайна особняка'));
    await tester.pumpAndSettle();
    expect(find.text('Войти и исследовать дом'), findsOneWidget);
  });
}
