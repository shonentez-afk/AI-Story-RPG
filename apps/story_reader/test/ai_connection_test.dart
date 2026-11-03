import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
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
    if (failDelete) throw StateError('vault failure');
    value = null;
  }
}

class _Transport implements AiHttpTransport {
  int calls = 0;
  Uri? sentUri;
  Map<String, String>? sentHeaders;
  String? sentBody;
  int status = 200;
  String result = jsonEncode({
    'choices': [
      {'message': {'role': 'assistant', 'content': 'Готово'}},
    ],
  });

  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    calls++;
    sentUri = uri;
    sentHeaders = headers;
    sentBody = body;
    return AiHttpResponse(status, result);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_library_sentinel': 'book unchanged',
    });
  });

  test('cloud is opt-in and cannot probe with a saved key alone', () async {
    final preferences = AiCloudPreferences();
    final vault = _FakeVault()..value = 'synthetic-test-only-key';
    final network = _Transport();
    final service = ZaiConnectivityCheck(
        preferences: preferences, vault: vault, transport: network);
    expect(await preferences.isEnabled(), false);
    await expectLater(service.check(), throwsA(isA<AiSetupException>()));
    expect(network.calls, 0);
    final stored = await SharedPreferences.getInstance();
    expect(stored.getKeys(), isNot(contains('synthetic-test-only-key')));
    expect(stored.getString('user_library_sentinel'), 'book unchanged');
  });

  test('the ONLY M2f1 request uses free GLM-4.7-Flash, fixed TLS endpoint '
      'and synthetic text, no book or save content', () async {
    final preferences = AiCloudPreferences();
    final vault = _FakeVault()..value = 'synthetic-key';
    final network = _Transport();
    final service = ZaiConnectivityCheck(
        preferences: preferences, vault: vault, transport: network);
    await preferences.setEnabled(true);
    await service.check();
    expect(network.calls, 1);
    expect(network.sentUri.toString(),
        'https://api.z.ai/api/paas/v4/chat/completions');
    expect(network.sentHeaders!['Authorization'], 'Bearer synthetic-key');
    final payload = jsonDecode(network.sentBody!) as Map<String, dynamic>;
    expect(payload['model'], 'glm-4.7-flash');
    expect(payload['thinking'], {'type': 'disabled'});
    expect(payload['stream'], false);
    expect(payload.containsKey('tools'), isFalse);
    expect(network.sentBody, isNot(contains('Весь текст книги')));
    expect((payload['messages'] as List).length, 1);
    expect(await preferences.isEnabled(), true);

    await preferences.setEnabled(false);
    await expectLater(service.check(), throwsA(isA<AiSetupException>()));
    expect(network.calls, 1);
  });

  test('401, 403, 429 and 5xx errors never disclose key or response body',
      () async {
    final settings = AiCloudPreferences();
    await settings.setEnabled(true);
    final vault = _FakeVault()..value = 'VERY-SECRET-TEST-KEY';
    final network = _Transport()..result = 'PRIVATE SERVER BODY';
    final service = ZaiConnectivityCheck(
        preferences: settings, vault: vault, transport: network);
    for (final code in [401, 403, 429, 500, 503]) {
      network.status = code;
      try {
        await service.check();
        fail('HTTP $code must fail');
      } on AiSetupException catch (error) {
        expect(error.toString(), isNot(contains('VERY-SECRET-TEST-KEY')));
        expect(error.toString(), isNot(contains('PRIVATE SERVER BODY')));
        if (code == 429) expect(error.toString().toLowerCase(), contains('лимит'));
      }
    }
  });

  test('malformed provider payload is fail-closed and never shown to user',
      () async {
    final settings = AiCloudPreferences();
    await settings.setEnabled(true);
    final vault = _FakeVault()..value = 'test-key';
    final network = _Transport()..result = '{"choices": []}';
    final check = ZaiConnectivityCheck(
        preferences: settings, vault: vault, transport: network);
    await expectLater(check.check(),
        throwsA(isA<AiSetupException>()));
  });
}
