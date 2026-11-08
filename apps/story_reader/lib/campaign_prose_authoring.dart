import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:rpg_api/rpg_api.dart';

import 'ai_connection.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'zai_semantic_preview.dart';

export 'package:rpg_api/rpg_api.dart' show
    CampaignProseManifest, CampaignProseEntry, CampaignProseSession,
    CampaignProseRequest, campaignProseHash;

/// Flutter selects an isolate, the headless API performs every world check.
Uint8List _compileCampaignProse(Map<String, dynamic> data) =>
    const LocalRpgCampaignProseApi().compileReviewed(
      verifiedArchive: data['archive'] as Uint8List,
      sourceIndex: Map<String, dynamic>.from(data['source_index'] as Map),
      reviewJson: data['review'] as String,
      approvedDigest: data['digest'] as String,
      fullTextReviewed: data['full_text_reviewed'] as bool,
      privateFictionConfirmed: data['private_fiction_confirmed'] as bool,
    );

/// File/CAS adapter; format, checksums and source validation belong to API.
class CampaignProseStore {
  CampaignProseStore({SourceAnalysisCheckpointRepository? repository})
      : repository = repository ?? const FileSourceAnalysisCheckpointRepository();
  final SourceAnalysisCheckpointRepository repository;
  static final _queues = <String, Future<void>>{};

  Future<CampaignProseSession> load(CampaignProseManifest manifest) async =>
      const LocalRpgCampaignProseApi().decodeCheckpoint(
          manifest, await repository.read(manifest.storageKey));

  Future<CampaignProseSession> save({
    required CampaignProseManifest manifest,
    required CampaignProseSession expected,
    required Iterable<CampaignProseEntry> entries,
  }) async {
    final frozen = List<CampaignProseEntry>.unmodifiable(entries);
    final previous = _queues[manifest.storageKey] ?? Future<void>.value();
    final release = Completer<void>();
    _queues[manifest.storageKey] = release.future;
    await previous;
    try {
      await manifest.verifyCurrent();
      final before = await load(manifest);
      if (before.recordHash != expected.recordHash ||
          before.revision != expected.revision) {
        throw const FormatException('Художественный текст изменён в другом окне.');
      }
      final api = const LocalRpgCampaignProseApi();
      final raw = api.encodeCheckpoint(
          manifest: manifest,
          revision: before.revision + 1,
          entries: frozen);
      await repository.write(manifest.storageKey, raw);
      return api.decodeCheckpoint(manifest, raw);
    } finally {
      release.complete();
      if (identical(_queues[manifest.storageKey], release.future)) {
        _queues.remove(manifest.storageKey);
      }
    }
  }
}

/// Foreground, resumable authoring; fixed endpoint and existing protected key.
/// Each retry and saved packet must still match the current author revision.
class ZaiCampaignProse {
  ZaiCampaignProse({AiCloudPreferences? preferences, AiApiKeyVault? vault,
    AiHttpTransport? transport, Future<void> Function(Duration)? retryWait})
      : preferences = preferences ?? AiCloudPreferences(),
        vault = vault ?? DeviceAiApiKeyVault(),
        transport = transport ?? const ZaiHttpTransport(),
        retryWait = retryWait ?? ((d) => Future<void>.delayed(d));
  final AiCloudPreferences preferences;
  final AiApiKeyVault vault;
  final AiHttpTransport transport;
  final Future<void> Function(Duration) retryWait;
  static final _running = <String>{};
  static const systemPrompt = LocalRpgCampaignProseApi.systemPrompt;

  Future<CampaignProseSession> generate({required CampaignProseManifest manifest,
    required CampaignProseStore store, required CampaignProseRequest request,
    required String approvedDigest, required bool explicitCloudConsent,
    ZaiPreviewCancellation? cancellation,
    void Function(CampaignProseSession)? onSaved}) async {
    final token = cancellation ?? ZaiPreviewCancellation(); token.check();
    if (!explicitCloudConsent || approvedDigest != request.approvalDigest ||
        request.manifestDigest != manifest.digest) {
      throw const AiSetupException('Нет согласия на показанные сцены этой кампании.');
    }
    if (!_running.add(manifest.storageKey)) throw const AiSetupException('Текст этой игры уже готовится.');
    try {
      var session = await store.load(manifest);
      if (session.recordHash != request.recordHash) throw const FormatException('Текст изменился после согласия.');
      final freshRequest = CampaignProseRequest.prepare(manifest, session);
      if (freshRequest.approvalDigest != request.approvalDigest) throw const FormatException('Изменён список сцен.');
      final key = await vault.read();
      if (key == null || key.trim().isEmpty || !await preferences.isEnabled()) {
        throw const AiSetupException('Разрешите облачный ИИ и сохраните ключ в настройках.');
      }
      Future<void> guard(CampaignProseSession expected) async {
        token.check(); await manifest.verifyCurrent(); token.check();
        if ((await store.load(manifest)).recordHash != expected.recordHash) {
          throw const FormatException('Ручная правка новее ответа ИИ; отправка и запись остановлены.');
        }
      }
      for (final batch in request.batches) {
        final expected = session;
        final body = jsonEncode({'model': ZaiModel.id,
          'messages': [{'role': 'system', 'content': systemPrompt}, {'role': 'user', 'content': batch}],
          'thinking': {'type': 'disabled'}, 'max_tokens': 8192,
          'response_format': {'type': 'json_object'}, 'stream': false});
        AiHttpResponse? success;
        for (var attempt = 1; attempt <= 3; attempt++) {
          await guard(expected);
          if (!await preferences.isEnabled()) throw const AiSetupException('Облачный ИИ выключен.');
          token.check();
          AiHttpResponse? reply;
          try {
            reply = await transport.send(uri: ZaiModel.endpoint, headers: {
              'Authorization': 'Bearer ${key.trim()}',
              'Content-Type': 'application/json; charset=utf-8', 'Accept': 'application/json',
            }, body: body).timeout(const Duration(seconds: 150));
          } on AiTransientConnectionException { /* Bounded retry below. */ }
          on TimeoutException { /* Bounded retry below. */ }
          token.check(); await guard(expected);
          if (reply?.statusCode == 200) { success = reply; break; }
          var quota = false;
          if (reply != null) {
            try { final error = (jsonDecode(reply.body) as Map)['error'];
              quota = error is Map && const {'1113', '1310'}.contains('${error['code']}');
            } catch (_) { /* Status still controls retries. */ }
          }
          if (quota || (reply != null && reply.statusCode != 429 &&
              (reply.statusCode < 500 || reply.statusCode > 599))) {
            throw const AiSetupException('Z.ai отклонил запрос. Готовые сцены сохранены.');
          }
          if (attempt == 3) throw const AiSetupException('ИИ занят или соединение прервано. Продолжение использует сохранённые сцены.');
          var seconds = attempt == 1 ? 4 : 12;
          if (reply?.retryAfter != null) {
            final requested = int.tryParse(reply!.retryAfter!.trim());
            if (requested == null || requested < 0 || requested > 60) {
              throw const AiSetupException('Длительная пауза сервера не сокращается.');
            }
            seconds = requested;
          }
          await Future.any<void>([retryWait(Duration(seconds: seconds)), token.whenCancelled]);
        }
        final entries = const LocalRpgCampaignProseApi().parseBatch(batch, success!.body);
        await guard(expected);
        session = await store.save(manifest: manifest, expected: expected,
            entries: [...expected.entries.values, ...entries]);
        onSaved?.call(session); token.check();
      }
      return session;
    } finally { _running.remove(manifest.storageKey); }
  }


}


/// Live source/revision guard only. All narrative rules are pure Dart.
class CampaignProseAcceptance {
  const CampaignProseAcceptance._();

  static String review(
      CampaignProseManifest manifest, CampaignProseSession session) =>
      const LocalRpgCampaignProseApi().review(manifest, session);

  static Future<Uint8List> build({
    required CampaignProseManifest manifest,
    required CampaignProseStore store,
    required CampaignProseSession session,
    required String approvedDigest,
    required bool fullTextReviewed,
    required bool privateFictionConfirmed,
  }) async {
    final reviewJson = review(manifest, session);
    await manifest.verifyCurrent();
    if ((await store.load(manifest)).recordHash != session.recordHash) {
      throw const FormatException('Текст изменился перед сборкой.');
    }
    final bytes = await compute(_compileCampaignProse, <String, dynamic>{
      'archive': manifest.originalArchive,
      'source_index': manifest.source.index.toJson(),
      'review': reviewJson,
      'digest': approvedDigest,
      'full_text_reviewed': fullTextReviewed,
      'private_fiction_confirmed': privateFictionConfirmed,
    });
    await manifest.verifyCurrent();
    if ((await store.load(manifest)).recordHash != session.recordHash) {
      throw const FormatException('Текст изменился во время сборки.');
    }
    return bytes;
  }
}
