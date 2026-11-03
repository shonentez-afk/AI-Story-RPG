import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_preview_page.dart';

class _Vault implements AiApiKeyVault {
  @override
  Future<String?> read() async => 'SYNTHETIC-KEY';
  @override
  Future<bool> hasKey() async => true;
  @override
  Future<void> write(String _) async {}
  @override
  Future<void> delete() async {}
}

class _Network implements AiHttpTransport {
  int calls = 0;
  @override
  Future<AiHttpResponse> send({
    required Uri uri, required Map<String, String> headers,
    required String body,
  }) async {
    calls++;
    return AiHttpResponse(200, jsonEncode({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {
            'content': jsonEncode({
              'candidates': [
                {
                  'category': 'character',
                  'quote': 'Анна',
                  'label': 'Имя Анна',
                  'uncertainty': 'Проверить персонажа',
                },
              ],
            }),
          },
        },
      ],
    }));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sample = ImportedBook(
    title: 'Личная книга', author: 'Приватный автор',
    chapters: ['Анна вошла в дом. После этого наступил вечер.'],
  );

  testWidgets('one request requires explicit unchecked-by-default consent; '
      'cancel does not send or change saves', (tester) async {
    SharedPreferences.setMockInitialValues({'game-sentinel': 'intact'});
    final preferences = AiCloudPreferences();
    await preferences.setEnabled(true);
    final network = _Network();
    final index = BookSourceIndexer.index(sample);
    final service = ZaiSemanticPreviewService(
      preferences: preferences, vault: _Vault(), transport: network,
    );
    await tester.pumpWidget(MaterialApp(home: ZaiSemanticPreviewPage(
      index: index, service: service,
    )));
    await tester.pumpAndSettle();
    final send = find.byKey(const Key('zai-send-single-chunk'));
    await tester.scrollUntilVisible(send, 170,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Передать этот фрагмент в Z.ai?'), findsOneWidget);
    expect(find.textContaining('Анна вошла в дом.'), findsWidgets);
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('zai-consent-confirm'))).onPressed, isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(network.calls, 0);

    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zai-consent-exact-checkbox')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('zai-consent-confirm'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('zai-consent-confirm')));
    await tester.pumpAndSettle();
    expect(network.calls, 1);
    await tester.scrollUntilVisible(find.text('Имя Анна'), 170,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Имя Анна'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('не перенесена в редакторы'), 140,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    await tester.pumpAndSettle();
    expect(find.textContaining('не перенесена в редакторы'), findsOneWidget);
    expect((await SharedPreferences.getInstance())
        .getString('game-sentinel'), 'intact');
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp and 200% text keep excerpt and send accessible',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final index = BookSourceIndexer.index(sample);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: ZaiSemanticPreviewPage(
        index: index,
        service: ZaiSemanticPreviewService(
          vault: _Vault(), transport: _Network(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final text = find.byKey(const Key('zai-chunk-text'));
    await tester.scrollUntilVisible(text, 140,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    expect(tester.takeException(), isNull);
    final send = find.byKey(const Key('zai-send-single-chunk'));
    await tester.scrollUntilVisible(send, 150,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    expect(find.byKey(const Key('zai-send-single-chunk')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
