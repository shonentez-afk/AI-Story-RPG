import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/game_panels.dart';
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
    expect(find.textContaining('Пока нет найденных предметов'), findsOneWidget);
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
    // Pop the RPG route directly: tooltips and transient snackbars can
    // intercept the synthetic back-button tap in widget tests.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Продолжить'), findsOneWidget);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Тайна особняка: Войти и исследовать дом'),
        findsOneWidget);
  });

  testWidgets('character and inventory reflect actual story decisions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти и исследовать дом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Прочитать старое письмо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Герой'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Смелость: 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предметы'));
    await tester.pumpAndSettle();
    expect(find.text('• Старое письмо'), findsOneWidget);
  });

  testWidgets('new story creates its own slot instead of overwriting',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти и исследовать дом'));
    await tester.pumpAndSettle();
    var navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    expect(find.text('Заменить сохранение?'), findsNothing);
    navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Мои прохождения'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Удалить прохождение'), findsNWidgets(2));
  });

  testWidgets('choice reports acquired item in journal', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая история'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Войти и исследовать дом'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Прочитать старое письмо'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Найдено: Старое письмо'), findsOneWidget);
  });

  testWidgets('long RPG journal scrolls within bottom sheet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => GameInfoSheet(
            panel: GamePanel.journal,
            currentScene: 'Коридор',
            journalEntries: List.generate(150, (i) => 'Решение $i'),
          ),
        ),
        child: const Text('Открыть журнал'),
      ))),
    ));
    await tester.tap(find.text('Открыть журнал'));
    await tester.pumpAndSettle();
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new pilot explains a locked door and keeps the alternate route',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AIStoryApp());
    await tester.pumpAndSettle();
    Future<void> act(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }
    await act('Новая история');
    await act('Войти и исследовать дом');
    await act('Прочитать старое письмо');
    await act('Забрать план особняка');
    expect(find.text('Открыть дверь в подвал'), findsOneWidget);
    expect(find.textContaining('Нужен латунный ключ'), findsOneWidget);
    final locked = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Открыть дверь в подвал'));
    expect(locked.onPressed, isNull);
    await act('Подняться по лестнице');
    await act('Подойти к таинственной тени');
    expect(find.text('Рассказать миру правду'), findsOneWidget);
    expect(find.textContaining('Недоступно:'), findsNothing);
  });

}
