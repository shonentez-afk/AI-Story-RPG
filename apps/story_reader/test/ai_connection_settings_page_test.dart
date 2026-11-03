import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/ai_connection_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeVault implements AiApiKeyVault {
  String? value;
  bool failDelete = false;
  @override
  Future<void> write(String key) async { value = key; }
  @override
  Future<String?> read() async => value;
  @override
  Future<bool> hasKey() async => value != null;
  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('synthetic vault error');
    value = null;
  }
}

class _FakeCheck implements AiConnectivityCheck {
  int calls = 0;
  @override
  Future<void> check() async { calls++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cloud setup requires key, explicit consent and separate test; '
      'deletion does not touch books', (tester) async {
    SharedPreferences.setMockInitialValues({'library_save': 'unchanged'});
    final vault = _FakeVault();
    final checker = _FakeCheck();
    final preferences = AiCloudPreferences();
    await tester.pumpWidget(MaterialApp(home: AiConnectionSettingsPage(
      vault: vault, connectivity: checker, preferences: preferences,
    )));
    await tester.pumpAndSettle();

    expect(await preferences.isEnabled(), isFalse);
    expect(find.text('Ключ пока не сохранён'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(
        find.byKey(const Key('ai-test-connection'))).onPressed, isNull);
    expect(checker.calls, 0);

    await tester.enterText(find.byKey(const Key('ai-api-key-input')),
        'SYNTHETIC-KEY');
    await tester.ensureVisible(find.byKey(const Key('ai-save-key')));
    await tester.tap(find.byKey(const Key('ai-save-key')));
    await tester.pumpAndSettle();
    expect(vault.value, 'SYNTHETIC-KEY');
    expect(tester.widget<TextField>(
        find.byKey(const Key('ai-api-key-input'))).controller!.text, isEmpty);
    expect(await preferences.isEnabled(), false);
    expect(checker.calls, 0);

    await tester.ensureVisible(find.byKey(const Key('ai-cloud-consent')));
    await tester.tap(find.byKey(const Key('ai-cloud-consent')));
    await tester.pumpAndSettle();
    expect(find.text('Разрешить подключение к Z.ai?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await preferences.isEnabled(), false);
    expect(checker.calls, 0);

    await tester.tap(find.byKey(const Key('ai-cloud-consent')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Разрешаю проверку'));
    await tester.pumpAndSettle();
    expect(await preferences.isEnabled(), true);
    expect(checker.calls, 0);

    await tester.ensureVisible(find.byKey(const Key('ai-test-connection')));
    await tester.tap(find.byKey(const Key('ai-test-connection')));
    await tester.pumpAndSettle();
    expect(checker.calls, 1);
    expect(find.textContaining('Текст книги не отправлялся'), findsOneWidget);

    final delete = find.byKey(const Key('ai-delete-key'));
    await tester.scrollUntilVisible(delete, -180,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    await tester.ensureVisible(delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(vault.value, isNotNull);

    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить ключ'));
    await tester.pumpAndSettle();
    expect(vault.value, isNull);
    expect(await preferences.isEnabled(), false);
    expect(checker.calls, 1);
    final persisted = await SharedPreferences.getInstance();
    expect(persisted.getString('library_save'), 'unchanged');
    expect(persisted.getKeys().any((key) => key.contains('SYNTHETIC-KEY')),
        false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI setup is scrollable at 320dp with 200% text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: AiConnectionSettingsPage(
        vault: _FakeVault(), connectivity: _FakeCheck(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final url = find.byKey(const Key('ai-copy-key-url'));
    await tester.ensureVisible(url);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.text('Локальная модель'), 150,
        scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Локальная модель'), findsOneWidget);
  });
}
