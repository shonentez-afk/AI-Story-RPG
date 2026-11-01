import 'package:flutter/material.dart';
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
    // One library destination on home; imported books live only inside it.
    expect(find.text('Моя библиотека'), findsNothing);
    expect(find.text('Все книги'), findsNothing);
    expect(find.text('Добавьте свою первую книгу'), findsNothing);
    expect(find.byTooltip('Настройки'), findsOneWidget);
    await tester.tap(find.text('Библиотека'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-import')), findsOneWidget);
    expect(find.text('Добавить книгу'), findsOneWidget);
    expect(find.text('Тайна особняка'), findsOneWidget);
    await tester.tap(find.text('Тайна особняка'));
    await tester.pumpAndSettle();
    expect(find.text('Войти и исследовать дом'), findsOneWidget);
  });
  testWidgets('library search can be cleared without hiding demo RPG', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Библиотека'));
    await tester.pumpAndSettle();
    expect(find.text('Поиск книг'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'несуществующая книга');
    await tester.pumpAndSettle();
    expect(find.text('Тайна особняка'), findsOneWidget);
    expect(find.text('А—Я'), findsOneWidget);
    await tester.tap(find.text('А—Я'));
    await tester.pumpAndSettle();
    expect(find.text('Я—А'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pumpAndSettle();
    expect(find.text('Тайна особняка'), findsOneWidget);
  });

}
