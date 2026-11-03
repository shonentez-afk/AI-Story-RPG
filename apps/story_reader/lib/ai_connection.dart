import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// M2f1: a narrow, opt-in connectivity gate. Nothing in the book reader or
/// game engine calls this service. No book text or player data can enter its
/// fixed, synthetic test message.
class ZaiModel {
  static const id = 'glm-4.7-flash';
  static final endpoint =
      Uri.parse('https://api.z.ai/api/paas/v4/chat/completions');
  static const apiKeysPage = 'https://z.ai/manage-apikey/apikey-list';
}

/// Consent is local and defaults to OFF, even when an API key is present.
/// Do not store any secret, response or book text in SharedPreferences.
class AiCloudPreferences {
  static const _enabledKey = 'ai_story_m2f1_zai_cloud_enabled';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) == true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_enabledKey, enabled)) {
      throw const AiSetupException(
          'Не удалось сохранить согласие. Облачный ИИ не включён.');
    }
  }
}

abstract class AiApiKeyVault {
  Future<void> write(String key);
  Future<String?> read();
  Future<void> delete();
  Future<bool> hasKey();
}

/// Uses the OS-provided protected storage, not a plain preferences/file key.
/// Failure never falls back to plaintext.
class DeviceAiApiKeyVault implements AiApiKeyVault {
  DeviceAiApiKeyVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'ai_story_zai_standard_api_key_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty || trimmed.length > 2048 ||
        trimmed.contains(RegExp(r'[\r\n\x00-\x1f]'))) {
      throw const AiSetupException('Некорректный формат API-ключа.');
    }
    await _storage.write(key: _keyName, value: trimmed);
  }

  @override
  Future<String?> read() => _storage.read(key: _keyName);

  @override
  Future<bool> hasKey() => _storage.containsKey(key: _keyName);

  @override
  Future<void> delete() => _storage.delete(key: _keyName);
}

class AiSetupException implements Exception {
  const AiSetupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiHttpResponse {
  const AiHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

abstract class AiHttpTransport {
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  });
}

/// HTTP implementation for the ONLY supported provider endpoint. No redirects,
/// untrusted base URLs, request/body logs, tools or background retries.
class ZaiHttpTransport implements AiHttpTransport {
  const ZaiHttpTransport();

  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    if (uri != ZaiModel.endpoint || uri.scheme != 'https') {
      throw const AiSetupException('Недопустимый адрес сервера ИИ.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'AI-Story-RPG/M2f1';
    try {
      final request = await client.postUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.add(utf8.encode(body));
      final response = await request.close()
          .timeout(const Duration(seconds: 25));
      final received = <int>[];
      await for (final bytes in response.timeout(const Duration(seconds: 25))) {
        if (received.length + bytes.length > 64 * 1024) {
          throw const AiSetupException(
              'Ответ сервера превышает безопасный размер.');
        }
        received.addAll(bytes);
      }
      return AiHttpResponse(response.statusCode, utf8.decode(received));
    } on AiSetupException {
      rethrow;
    } on TimeoutException {
      throw const AiSetupException(
          'Время ожидания Z.ai истекло. Проверьте сеть и повторите.');
    } on SocketException {
      throw const AiSetupException(
          'Нет соединения с Z.ai. Проверьте интернет.');
    } on HandshakeException {
      throw const AiSetupException(
          'Ошибка защищённого соединения с Z.ai.');
    } catch (_) {
      // Never expose request headers, API keys or server response bodies.
      throw const AiSetupException(
          'Не удалось обратиться к Z.ai. Повторите проверку позже.');
    } finally {
      client.close(force: true);
    }
  }
}

abstract class AiConnectivityCheck {
  Future<void> check();
}

/// The sole cloud request in M2f1 is a manually triggered, fixed text test.
/// Later book analysis needs ANOTHER explicit per-book permission boundary.
/// A saved API key alone does not grant access to the network.
class ZaiConnectivityCheck implements AiConnectivityCheck {
  ZaiConnectivityCheck({
    AiCloudPreferences? preferences,
    AiApiKeyVault? vault,
    AiHttpTransport? transport,
  })  : preferences = preferences ?? AiCloudPreferences(),
        vault = vault ?? DeviceAiApiKeyVault(),
        transport = transport ?? const ZaiHttpTransport();

  final AiCloudPreferences preferences;
  final AiApiKeyVault vault;
  final AiHttpTransport transport;

  @override
  Future<void> check() async {
    if (!await preferences.isEnabled()) {
      throw const AiSetupException(
          'Сначала явно разрешите проверочное обращение к Z.ai.');
    }
    final key = await vault.read();
    if (key == null || key.trim().isEmpty) {
      throw const AiSetupException('Сначала сохраните API-ключ Z.ai.');
    }

    // A tiny synthetic connectivity probe. No imported book, NPC, save, user
    // message or document bytes are available on this code path.
    final payload = jsonEncode({
      'model': ZaiModel.id,
      'messages': [
        {
          'role': 'user',
          'content': 'Проверка соединения. Ответь одним словом: готово.',
        },
      ],
      'thinking': {'type': 'disabled'},
      'max_tokens': 48,
      'stream': false,
    });
    final AiHttpResponse response;
    try {
      response = await transport.send(
        uri: ZaiModel.endpoint,
        headers: {
          'Authorization': 'Bearer ' + key.trim(),
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: payload,
      ).timeout(const Duration(seconds: 40));
    } on AiSetupException {
      rethrow;
    } on TimeoutException {
      throw const AiSetupException('Z.ai не ответил вовремя.');
    } catch (_) {
      throw const AiSetupException(
          'Проверка соединения не удалась. Ключ не передан в журнал.');
    }

    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw const AiSetupException('Z.ai отклонил API-ключ (401).');
      case 403:
        throw const AiSetupException(
            'Z.ai запретил доступ (403). Проверьте права ключа.');
      case 429:
        throw const AiSetupException(
            'Лимит запросов GLM-4.7-Flash (429). Повторите позже.');
      case >= 500:
        throw const AiSetupException(
            'Сервер Z.ai временно недоступен. Повторите позже.');
      default:
        throw const AiSetupException(
            'Z.ai вернул ошибку запроса. Проверьте доступ к модели.');
    }
    try {
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = root['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        throw const FormatException('empty');
      }
      final message = (choices.first as Map)['message'] as Map;
      final content = message['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const FormatException('empty content');
      }
    } catch (_) {
      throw const AiSetupException(
          'Ответ Z.ai не содержит текста. Попробуйте ещё раз.');
    }
  }
}
