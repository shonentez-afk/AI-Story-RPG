import 'dart:async';
import 'dart:convert';


import 'ai_connection.dart';
import 'zai_semantic_preview.dart';

import 'package:rpg_api/rpg_api.dart' show
    LocalRpgProposalReviewApi, SourceLockedProseAuditContext,
    AiProseFindingKind, AiProseFindingSeverity, AiProseAuditVerdict,
    AiProseAuditFinding, AiProseAuditReport;
export 'package:rpg_api/rpg_api.dart' show
    SourceLockedProseAuditContext,
    AiProseFindingKind, AiProseFindingSeverity, AiProseAuditVerdict,
    AiProseAuditFinding, AiProseAuditReport;

class ZaiSourceLockedProseAuditService {
  ZaiSourceLockedProseAuditService({
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
  static const maxInputBytes = 20 * 1024;
  static const maxOutputBytes = 16 * 1024;
  static const requestTimeout = Duration(seconds: 150);
  static const systemPrompt = LocalRpgProposalReviewApi.auditSystemPrompt;

  static Duration _backoff(AiHttpResponse response, int attempt) {
    if (response.retryAfter != null) {
      final seconds = int.tryParse(response.retryAfter!.trim());
      if (seconds != null && seconds >= 0 && seconds <= 60) {
        return Duration(seconds: seconds);
      }
      throw const AiSetupException(
          'Сервер запросил слишком долгое ожидание для проверки.');
    }
    return Duration(seconds: attempt == 1 ? 4 : 12);
  }

  static AiProseAuditReport parse(
      SourceLockedProseAuditContext context, String body) {
    try {
      return const LocalRpgProposalReviewApi()
          .reviewLiteraryCritique(context, body);
    } on FormatException {
      throw const AiSetupException(
          'Ответ литературной проверки не прошёл сверку '
          'с источником, форматом или идентификатором сцены.');
    }
  }

  Future<AiProseAuditReport> review({
    required SourceLockedProseAuditContext context,
    required String approvedDigest,
    required bool explicitReviewConsent,
    ZaiPreviewCancellation? cancellation,
    void Function(int, int, String)? onProgress,
  }) async {
    final token = cancellation ?? ZaiPreviewCancellation();
    token.check();
    if (!explicitReviewConsent ||
        approvedDigest != context.approvalDigest) {
      throw const AiSetupException(
          'Нет отдельного согласия на передачу текста сцены '
          'для литературной проверки.');
    }
    if (!await preferences.isEnabled()) {
      throw const AiSetupException('Облачный ИИ не разрешён в настройках.');
    }
    final key = await vault.read();
    if (key == null || key.trim().isEmpty) {
      throw const AiSetupException('Нет ключа Z.ai для проверки сцены.');
    }
    final body = jsonEncode({
      'model': ZaiModel.id,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': jsonEncode(context.sentContext)},
      ],
      'thinking': {'type': 'disabled'},
      'max_tokens': 1600,
      'response_format': {'type': 'json_object'},
      'stream': false,
    });
    if (utf8.encode(body).length > maxInputBytes) {
      throw const AiSetupException(
          'Контекст проверки слишком велик. Ничего не отправлено.');
    }
    token.check();
    final headers = {
      'Authorization': 'Bearer ' + key.trim(),
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      token.check();
      onProgress?.call(attempt, maxAttempts, 'Литературная ИИ-проверка');
      AiHttpResponse? response;
      try {
        response = await transport.send(
          uri: ZaiModel.endpoint, headers: headers, body: body,
        ).timeout(requestTimeout);
      } on AiTransientConnectionException {
        if (attempt == maxAttempts) {
          throw const AiSetupException(
              'Сеть недоступна. Сцена и игра не изменены.');
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw const AiSetupException(
              'Время ожидания ИИ-проверки истекло.');
        }
      }
      token.check();
      if (response == null) {
        await retryWait(Duration(seconds: attempt == 1 ? 4 : 12));
        continue;
      }
      if (response.statusCode == 200) {
        return parse(context, response.body);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiSetupException('Z.ai отклонил API-ключ.');
      }
      final temporary = response.statusCode == 429 ||
          response.statusCode >= 500 && response.statusCode <= 599;
      if (!temporary || attempt == maxAttempts) {
        throw const AiSetupException(
            'Литературная проверка не получила надёжного ответа Z.ai.');
      }
      onProgress?.call(attempt, maxAttempts, 'Ожидание перед повтором');
      await retryWait(_backoff(response, attempt));
    }
    throw const AiSetupException('Литературная проверка не завершена.');
  }
}
