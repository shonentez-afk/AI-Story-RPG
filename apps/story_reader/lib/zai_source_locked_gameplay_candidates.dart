import 'dart:async';
import 'dart:convert';
import 'package:rpg_api/rpg_api.dart' show LocalRpgProposalReviewApi;
import 'ai_connection.dart';
import 'zai_semantic_preview.dart';
import 'package:story_authoring/source_locked_gameplay_candidates.dart'
    show SourceLockedGameplayContext,
        GameplayCandidateDraft;

export 'package:story_authoring/source_locked_gameplay_candidates.dart'
    show GameplayChoiceAnchor, SourceLockedGameplayContext,
        GameplayCandidate, GameplayCandidateDraft;

/// The Z.ai call is an explicitly consented PROPOSAL step, not gameplay
/// generation/installation. Only user-visible excerpts and known decisions
/// may leave the device. Unknown fields, forged evidence or fake items fail
/// closed. Retry sends the SAME payload at most three times.
class ZaiSourceLockedGameplayCandidateService {
  ZaiSourceLockedGameplayCandidateService({
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
  static const maxRequestBytes = 12 * 1024;
  static const maxAnswerBytes = 12 * 1024;
  static const requestTimeout = Duration(seconds: 150);

  static const _systemPrompt = LocalRpgProposalReviewApi.gameplaySystemPrompt;

  static GameplayCandidateDraft _read(
      SourceLockedGameplayContext context, String raw) {
    try {
      return const LocalRpgProposalReviewApi()
          .reviewGameplaySuggestions(context, raw);
    } on FormatException {
      throw const AiSetupException(
          'Предметы или знания от ИИ не прошли проверку цитат и правил.');
    }
  }

  static Duration _delay(AiHttpResponse response, int attempt) {
    final raw = response.retryAfter;
    if (raw != null) {
      final seconds = int.tryParse(raw.trim());
      if (seconds != null) {
        if (seconds < 0 || seconds > 60) {
          throw const AiSetupException(
              'Сервер запросил недопустимо долгую паузу.');
        }
        return Duration(seconds: seconds);
      }
    }
    return Duration(seconds: attempt == 1 ? 4 : 12);
  }

  Future<GameplayCandidateDraft> propose({
    required SourceLockedGameplayContext context,
    required bool explicitExcerptConsent,
    required String approvedDigest,
    ZaiPreviewCancellation? cancellation,
  }) async {
    final token = cancellation ?? ZaiPreviewCancellation();
    token.check();
    if (!explicitExcerptConsent ||
        approvedDigest != context.approvalDigest) {
      throw const AiSetupException(
          'Нет согласия на эти конкретные цитаты и решения.');
    }
    if (!await preferences.isEnabled()) {
      throw const AiSetupException('В настройках отключён облачный ИИ.');
    }
    final key = await vault.read();
    if (key == null || key.trim().isEmpty) {
      throw const AiSetupException('Для Z.ai не задан API-ключ.');
    }
    token.check();
    final body = jsonEncode({
      'model': ZaiModel.id,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': context.payloadJson},
      ],
      'thinking': {'type': 'disabled'},
      'max_tokens': 1400,
      'response_format': {'type': 'json_object'},
      'stream': false,
    });
    if (utf8.encode(body).length > maxRequestBytes) {
      throw const AiSetupException('Слишком много цитат для одного запроса.');
    }
    final headers = {
      'Authorization': 'Bearer ' + key.trim(),
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      token.check();
      AiHttpResponse? response;
      try {
        response = await transport.send(
          uri: ZaiModel.endpoint, headers: headers, body: body,
        ).timeout(requestTimeout);
      } on AiTransientConnectionException {
        if (attempt == maxAttempts) {
          throw const AiSetupException(
              'Соединение с Z.ai оборвалось. Игра не изменена.');
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw const AiSetupException(
              'Z.ai не ответил вовремя. Игра не изменена.');
        }
      }
      token.check();
      if (response == null) {
        await retryWait(Duration(seconds: attempt == 1 ? 4 : 12));
        continue;
      }
      if (response.statusCode == 200) {
        return _read(context, response.body);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiSetupException('Z.ai отклонил API-ключ.');
      }
      final transient = response.statusCode == 429 ||
          response.statusCode >= 500 && response.statusCode <= 599;
      if (!transient || attempt == maxAttempts) {
        throw const AiSetupException(
            'Z.ai не принял запрос. Игра и предметы не изменены.');
      }
      await retryWait(_delay(response, attempt));
    }
    throw const AiSetupException('Нет проверенного предложения предметов.');
  }
}
