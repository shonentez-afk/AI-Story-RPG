import 'dart:async';
import 'dart:convert';

import 'package:rpg_api/rpg_api.dart' show LocalRpgProposalReviewApi;
import 'ai_connection.dart';
import 'zai_semantic_preview.dart';
import 'package:story_authoring/source_locked_prose_models.dart';
export 'package:story_authoring/source_locked_prose_models.dart';

/// Uses existing Z.ai credentials/HTTPS transport, with a NEW per-scene
/// consent digest. No request starts until all caller-side consent UI and
/// account settings pass. Each retry uses the identical approved payload.
class ZaiSourceLockedProsePreviewService {
  ZaiSourceLockedProsePreviewService({
    AiCloudPreferences? preferences,
    AiApiKeyVault? vault,
    AiHttpTransport? transport,
    Future<void> Function(Duration)? retryWait,
  }) : preferences = preferences ?? AiCloudPreferences(),
       vault = vault ?? DeviceAiApiKeyVault(),
       transport = transport ?? const ZaiHttpTransport(),
       retryWait = retryWait ?? _defaultRetryWait;

  final AiCloudPreferences preferences;
  final AiApiKeyVault vault;
  final AiHttpTransport transport;
  final Future<void> Function(Duration) retryWait;

  static Future<void> _defaultRetryWait(Duration delay) =>
      Future<void>.delayed(delay);

  static const maxAttempts = 3;
  static const maxInputBytes = 12 * 1024;
  static const maxOutputBytes = 12 * 1024;
  static const requestTimeout = Duration(seconds: 150);

  static const systemPrompt = LocalRpgProposalReviewApi.proseSystemPrompt;

  static Duration _backoff(AiHttpResponse response, int attempt) {
    if (response.retryAfter != null) {
      final seconds = int.tryParse(response.retryAfter!.trim());
      if (seconds != null && seconds >= 0 && seconds <= 60) {
        return Duration(seconds: seconds);
      }
      throw const AiSetupException(
          'Сервер запросил слишком длительное ожидание.');
    }
    return Duration(seconds: attempt == 1 ? 4 : 12);
  }

  static SourceLockedProseDraft _parse(
      SourceLockedProseContext context, String body) {
    try {
      return const LocalRpgProposalReviewApi().reviewSceneProse(context, body);
    } on FormatException {
      throw const AiSetupException(
          'Художественная сцена не прошла проверку JSON и привязки к игре.');
    }
  }

  Future<SourceLockedProseDraft> preview({
    required SourceLockedProseContext context,
    required String approvedContextDigest,
    required bool userReviewedExactContext,
    ZaiPreviewCancellation? cancellation,
    void Function(int, int, String)? onProgress,
  }) async {
    final token = cancellation ?? ZaiPreviewCancellation();
    token.check();
    if (!userReviewedExactContext ||
        approvedContextDigest != context.approvalDigest) {
      throw const AiSetupException(
          'Сначала подтвердите ровно показанные данные этой сцены.');
    }
    if (!await preferences.isEnabled()) {
      throw const AiSetupException(
          'Облачный ИИ не разрешён в настройках.');
    }
    final key = await vault.read();
    if (key == null || key.trim().isEmpty) {
      throw const AiSetupException('Не задан API-ключ Z.ai.');
    }
    token.check();

    // The precise content of this ONE scene is independently verified by
    // SourceLockedProseContext. No full book, title, fingerprint or save.
    final body = jsonEncode({
      'model': ZaiModel.id,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': jsonEncode(context.consentPreview)},
      ],
      'thinking': {'type': 'disabled'},
      'max_tokens': 1400,
      'response_format': {'type': 'json_object'},
      'stream': false,
    });
    if (utf8.encode(body).length > maxInputBytes) {
      throw const AiSetupException('Контекст одной сцены слишком большой.');
    }
    final headers = {
      'Authorization': 'Bearer ' + key.trim(),
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      token.check();
      onProgress?.call(attempt, maxAttempts, 'Создание черновика сцены');
      AiHttpResponse? response;
      try {
        response = await transport.send(
          uri: ZaiModel.endpoint, headers: headers, body: body,
        ).timeout(requestTimeout);
      } on AiTransientConnectionException {
        if (attempt == maxAttempts) {
          throw const AiSetupException(
              'Z.ai не ответил. Сцена и сохранения не изменены.');
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw const AiSetupException(
              'Ожидание Z.ai истекло. Сцена не изменена.');
        }
      }
      token.check();
      if (response == null) {
        await retryWait(Duration(seconds: attempt == 1 ? 4 : 12));
        continue;
      }
      if (response.statusCode == 200) {
        return _parse(context, response.body);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiSetupException('Z.ai отклонил API-ключ.');
      }
      final transient = response.statusCode == 429 ||
          response.statusCode >= 500 && response.statusCode <= 599;
      if (!transient || attempt == maxAttempts) {
        throw const AiSetupException('Z.ai не создал проверяемую сцену.');
      }
      final delay = _backoff(response, attempt);
      onProgress?.call(attempt, maxAttempts, 'Ожидание повторной попытки');
      await retryWait(delay);
    }
    throw const AiSetupException('Ответ ИИ для сцены отсутствует.');
  }
}
