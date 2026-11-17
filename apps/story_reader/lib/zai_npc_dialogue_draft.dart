import 'dart:async';
import 'dart:convert';


import 'ai_connection.dart';
import 'zai_semantic_preview.dart';

import 'package:rpg_api/rpg_api.dart' show
    LocalRpgProposalReviewApi, NpcDialogueDraftContext, NpcDialogueCloudDraft;
export 'package:rpg_api/rpg_api.dart' show
    NpcDialogueDraftContext, NpcDialogueCloudDraft;

/// Only explicit single-scene consent can use the existing Z.ai transport.
/// Independent offline gameplay never imports or calls this service.
class ZaiNpcDialogueDraftService {
  ZaiNpcDialogueDraftService({
    AiCloudPreferences? preferences,
    AiApiKeyVault? vault,
    AiHttpTransport? transport,
    Future<void> Function(Duration)? retryWait,
  }) : preferences = preferences ?? AiCloudPreferences(),
       vault = vault ?? DeviceAiApiKeyVault(),
       transport = transport ?? const ZaiHttpTransport(),
       retryWait = retryWait ?? ((d) => Future<void>.delayed(d));

  final AiCloudPreferences preferences;
  final AiApiKeyVault vault;
  final AiHttpTransport transport;
  final Future<void> Function(Duration) retryWait;

  static const maxAttempts = 3;
  static const requestTimeout = Duration(seconds: 150);
  static const systemPrompt = LocalRpgProposalReviewApi.npcSystemPrompt;

  static NpcDialogueCloudDraft parseForTest(
      NpcDialogueDraftContext context, String responseBody) {
    try {
      return const LocalRpgProposalReviewApi()
          .reviewNpcDialogue(context, responseBody);
    } on FormatException {
      throw const AiSetupException(
          'Ответ ИИ не прошёл проверку порядка и говорящих NPC');
    }
  }

  static Duration _backoff(AiHttpResponse response, int attempt) {
    if (response.retryAfter != null) {
      final wait = int.tryParse(response.retryAfter!.trim());
      if (wait == null || wait < 0 || wait > 60) {
        throw const AiSetupException('Недопустимый Retry-After от Z.ai');
      }
      return Duration(seconds: wait);
    }
    return Duration(seconds: attempt == 1 ? 4 : 12);
  }

  Future<NpcDialogueCloudDraft> preview({
    required NpcDialogueDraftContext context,
    required String approvedDigest,
    required bool explicitCloudConsent,
    ZaiPreviewCancellation? cancellation,
  }) async {
    final token = cancellation ?? ZaiPreviewCancellation();
    token.check();
    if (!explicitCloudConsent || approvedDigest != context.approvalDigest) {
      throw const AiSetupException('Нет согласия на эти реплики NPC');
    }
    if (!await preferences.isEnabled()) {
      throw const AiSetupException('Облачный ИИ выключен');
    }
    final key = await vault.read();
    if (key == null || key.trim().isEmpty) {
      throw const AiSetupException('Нет ключа Z.ai');
    }
    token.check();
    final body = jsonEncode({
      'model': ZaiModel.id,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': jsonEncode(context.consentPreview)},
      ],
      'thinking': {'type': 'disabled'},
      'max_tokens': 1600,
      'response_format': {'type': 'json_object'},
      'stream': false,
    });
    if (utf8.encode(body).length > 12 * 1024) {
      throw const AiSetupException('Слишком большой запрос для NPC');
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
          throw const AiSetupException('Соединение с Z.ai оборвалось');
        }
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw const AiSetupException('Ожидание Z.ai истекло');
        }
      }
      token.check();
      if (response == null) {
        await retryWait(Duration(seconds: attempt == 1 ? 4 : 12));
        continue;
      }
      if (response.statusCode == 200) {
        return parseForTest(context, response.body);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiSetupException('Z.ai отклонил ключ');
      }
      if (response.statusCode != 429 &&
          (response.statusCode < 500 || response.statusCode > 599)) {
        throw const AiSetupException('Z.ai отклонил запрос');
      }
      if (attempt == maxAttempts) {
        throw const AiSetupException('Z.ai не создал диалог NPC');
      }
      await retryWait(_backoff(response, attempt));
    }
    throw const AiSetupException('Нет черновика NPC');
  }
}
