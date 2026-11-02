import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_story_reader/reading_preferences.dart';
import 'package:ai_story_reader/reading_settings_sheet.dart';

void main() {
  testWidgets('reading preferences have a visible Done action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ReadingSettingsSheet(
            preferences: const ReadingPreferences(),
            onChanged: (_) {},
          ),
        ),
        child: const Text('Настроить чтение'),
      ))),
    ));
    await tester.tap(find.text('Настроить чтение'));
    await tester.pumpAndSettle();
    expect(find.text('Размер текста: 18'), findsOneWidget);
    await tester.ensureVisible(find.text('Готово'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Настройки чтения'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
