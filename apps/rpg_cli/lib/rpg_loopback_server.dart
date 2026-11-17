/// Local HTTP transport for third-party clients. No game rules here.
/// It owns only a private SQLite session and forwards JSON to rpg_api.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:campaign_manager/campaign_manager.dart';
import 'package:rpg_api/rpg_api.dart';

final class RpgLoopbackServer {
  RpgLoopbackServer._(this._server, this._store, this.token)
      : _protocol = RpgClientProtocol(LocalRpgGameApi(_store));

  static const maxRequestBytes = 24 * 1024 * 1024;

  final HttpServer _server;
  final BookworldCampaignStore _store;
  final RpgClientProtocol _protocol;
  final String token;
  late final Future<void> _serving;

  Uri get endpoint => Uri(
      scheme: 'http', host: '127.0.0.1', port: _server.port, path: '/v1/rpg');

  static Future<RpgLoopbackServer> bind({
    required String privateStoreDirectory,
    int port = 0,
    String? token,
  }) async {
    if (port < 0 || port > 65535) {
      throw const FormatException('Invalid loopback port');
    }
    if (token != null && token.length < 32) {
      throw const FormatException('Token must have at least 32 characters');
    }
    final random = Random.secure();
    final privateToken = token ?? base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)));
    final store = BookworldCampaignStore.openPrivateDirectory(
        privateStoreDirectory);
    try {
      // Never bind to 0.0.0.0 or another interface, even at caller request.
      final socket = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      final result = RpgLoopbackServer._(socket, store, privateToken);
      result._serving = result._serve();
      return result;
    } catch (_) {
      store.close();
      rethrow;
    }
  }

  /// The synchronous SQLite game interface must not receive overlapping
  /// HTTP operations. This sequential loop serializes all state mutations.
  Future<void> _serve() async {
    try {
      await for (final request in _server) {
        try {
          await _handle(request);
        } catch (_) {
          try {
            await _write(request, HttpStatus.internalServerError, {
              'ok': false, 'error': {'code': 'transport_error'},
            });
          } catch (_) {
            // A client may have disconnected; never log private payloads.
          }
        }
      }
    } catch (_) {
      // Closing the process-owned socket is not a game-state failure.
    }
  }

  static bool _sameToken(String supplied, String expected) {
    final left = utf8.encode(supplied);
    final right = utf8.encode(expected);
    var difference = left.length ^ right.length;
    final count = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < count; i++) {
      difference |=
          (i < left.length ? left[i] : 0) ^
          (i < right.length ? right[i] : 0);
    }
    return difference == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.connectionInfo?.remoteAddress.isLoopback != true ||
        request.headers.value('origin') != null) {
      await _write(request, HttpStatus.forbidden, {
        'ok': false, 'error': {'code': 'forbidden_origin'},
      });
      return;
    }
    if (request.uri.path != '/v1/rpg' || request.uri.hasQuery) {
      await _write(request, HttpStatus.notFound, {
        'ok': false, 'error': {'code': 'not_found'},
      });
      return;
    }
    if (request.method != 'POST') {
      await _write(request, HttpStatus.methodNotAllowed, {
        'ok': false, 'error': {'code': 'method_not_allowed'},
      });
      return;
    }
    if (!_sameToken(request.headers.value('x-rpg-token') ?? '', token)) {
      await _write(request, HttpStatus.unauthorized, {
        'ok': false, 'error': {'code': 'unauthorized'},
      });
      return;
    }
    if (request.headers.contentType?.mimeType != 'application/json') {
      await _write(request, HttpStatus.unsupportedMediaType, {
        'ok': false, 'error': {'code': 'invalid_content_type'},
      });
      return;
    }
    if (request.contentLength > maxRequestBytes) {
      await _write(request, HttpStatus.requestEntityTooLarge, {
        'ok': false, 'error': {'code': 'request_too_large'},
      });
      return;
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxRequestBytes) {
        await _write(request, HttpStatus.requestEntityTooLarge, {
          'ok': false, 'error': {'code': 'request_too_large'},
        });
        return;
      }
    }
    Object? payload;
    try {
      payload = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      await _write(request, HttpStatus.badRequest, {
        'ok': false, 'error': {'code': 'invalid_json'},
      });
      return;
    }
    final reply = await _protocol.handle(payload);
    await _write(request, HttpStatus.ok, reply);
  }

  static Future<void> _write(
      HttpRequest request, int code, Map<String, Object?> data) async {
    request.response.statusCode = code;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('cache-control', 'no-store');
    request.response.headers.set('x-content-type-options', 'nosniff');
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  Future<void> close() async {
    await _server.close(force: true);
    await _serving;
    _store.close();
  }
}
