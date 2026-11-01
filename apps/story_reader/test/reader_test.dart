import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/main.dart';

void main() {
  testWidgets('reader shows choices and navigates to library', (tester) async {
    await tester.pumpWidget(const AIStoryApp());
    expect(find.text('Новая история'), findsOneWidget);
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    expect(find.text('Тайна особняка'), findsOneWidget);
    expect(find.text('Войти и исследовать дом'), findsOneWidget);
    await tester.tap(find.text('Войти и исследовать дом'));
    await tester.pumpAndSettle();
    expect(find.text('Библиотека'), findsOneWidget);
    expect(find.text('Завершить пролог'), findsOneWidget);
  });
}
