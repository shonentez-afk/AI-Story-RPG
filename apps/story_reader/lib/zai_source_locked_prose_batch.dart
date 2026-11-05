import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'book_source_index.dart';
import 'ai_connection.dart';
import 'narrative_book_model.dart';
import 'source_locked_prose_checkpoint_store.dart';
import 'story_plan.dart';
import 'zai_semantic_preview.dart';
import 'zai_source_locked_prose_preview.dart';

/// A SINGLE foreground authorization over a bounded, fully displayed list
/// of one-scene requests. Reusing the list does not imply new consent.
class SourceLockedProseBatchManifest {
  SourceLockedProseBatchManifest._({
    required this.index,
    required this.book,
    required this.plan,
    required this.approvalDigest,
    required this.maxNewScenesPerRun,
    required List<String> sceneIds,
    required List<SourceLockedProseContext> contexts,
    required this.sentContextUtf8Bytes,
  }) : sceneIds = List.unmodifiable(sceneIds),
       contexts = List.unmodifiable(contexts);

  static const format = 'ai_story_prose_batch_consent_m2h7c4_v1';
  static const maxScenesInBatch = 8;

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final List<String> sceneIds;
  final List<SourceLockedProseContext> contexts;
  final int maxNewScenesPerRun;
  final int sentContextUtf8Bytes;
  final String approvalDigest;

  int get maxModelAttempts => maxNewScenesPerRun *
      ZaiSourceLockedProsePreviewService.maxAttempts;

  /// EXACT set of scene user messages. Neither titles nor fingerprints are
  /// included here; those are used only for LOCAL consent integrity.
  List<Map<String, Object>> get sentContexts =>
      List.unmodifiable([
        for (final context in contexts) context.consentPreview,
      ]);

  bool get canClaimLiteraryCanon => false;
  bool get canInstallDraftsAutomatically => false;

  static SourceLockedProseBatchManifest fromSelection({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required List<String> sceneIds,
    required int maxNewScenesPerRun,
  }) {
    if (sceneIds.isEmpty || sceneIds.length > maxScenesInBatch ||
        sceneIds.toSet().length != sceneIds.length ||
        maxNewScenesPerRun < 1 ||
        maxNewScenesPerRun > maxScenesInBatch ||
        maxNewScenesPerRun > sceneIds.length) {
      throw const FormatException(
          'Пакет сцен должен содержать 1–8 разных ситуаций '
          'с ограниченным числом запросов.');
    }
    final contexts = [
      for (final id in sceneIds)
        SourceLockedProseContext.forSituation(
          index: index, book: book, plan: plan, situationId: id,
        ),
    ];
    final messages = [
      for (final context in contexts) context.consentPreview,
    ];
    final bytes = messages.fold<int>(
        0, (sum, message) => sum + utf8.encode(jsonEncode(message)).length);
    final signature = {
      'format': format,
      'source_fingerprint': index.sourceFingerprint,
      'plan_sha256': sha256.convert(utf8.encode(plan.encode())).toString(),
      'model': ZaiModel.id,
      'max_new_scenes': maxNewScenesPerRun,
      'max_attempts_per_scene':
          ZaiSourceLockedProsePreviewService.maxAttempts,
      'scenes': [
        for (var i = 0; i < contexts.length; i++)
          {
            'scene_id': sceneIds[i],
            'context_digest': contexts[i].approvalDigest,
            'sent_context': messages[i],
          },
      ],
    };
    return SourceLockedProseBatchManifest._(
      index: index, book: book, plan: plan,
      sceneIds: sceneIds,
      contexts: contexts,
      sentContextUtf8Bytes: bytes,
      maxNewScenesPerRun: maxNewScenesPerRun,
      approvalDigest:
          sha256.convert(utf8.encode(jsonEncode(signature))).toString(),
    );
  }

  /// Fail closed if scenario, source edition or approved scene payload
  /// changed between the review screen and the first external request.
  void verifyUnchanged() {
    final fresh = fromSelection(
      index: index, book: book, plan: plan, sceneIds: sceneIds,
      maxNewScenesPerRun: maxNewScenesPerRun,
    );
    if (fresh.approvalDigest != approvalDigest) {
      throw const FormatException(
          'Контекст книги или игрового сценария изменился.');
    }
  }
}

class SourceLockedProseBatchProgress {
  const SourceLockedProseBatchProgress({
    required this.total,
    required this.completed,
    required this.newlyGenerated,
    required this.recovered,
  });

  final int total, completed, newlyGenerated, recovered;
  int get remaining => total - completed;
  bool get allReadyAsDrafts => completed == total;
  bool get literaryMeaningVerified => false;
  bool get canPublish => false;
}

typedef SourceLockedProseBatchPreview =
    Future<SourceLockedProseDraft> Function(
      SourceLockedProseContext context,
      ZaiPreviewCancellation cancellation,
    );

/// Bounded resumable foreground orchestration over the EXISTING per-scene
/// Z.ai service and the same source-locked, per-scene local checkpoint store.
/// The batch does not give the model permission to edit game rules or saves.
class SourceLockedProseBatchService {
  SourceLockedProseBatchService({
    SourceLockedProseCheckpointStore? store,
    ZaiSourceLockedProsePreviewService? service,
    SourceLockedProseBatchPreview? previewOverride,
  }) : store = store ?? SourceLockedProseCheckpointStore(),
       service = service ?? ZaiSourceLockedProsePreviewService(),
       previewOverride = previewOverride;

  final SourceLockedProseCheckpointStore store;
  final ZaiSourceLockedProsePreviewService service;
  final SourceLockedProseBatchPreview? previewOverride;

  Future<SourceLockedProseBatchProgress> inspect(
      SourceLockedProseBatchManifest manifest) async {
    manifest.verifyUnchanged();
    var recovered = 0;
    for (final context in manifest.contexts) {
      if (await store.read(context) != null) recovered++;
    }
    return SourceLockedProseBatchProgress(
      total: manifest.contexts.length,
      completed: recovered,
      recovered: recovered,
      newlyGenerated: 0,
    );
  }

  /// One explicit approval authorizes at most maxNewScenesPerRun requests.
  /// Each scene's internal 429/timeout retries are capped by the existing
  /// service; cancellation, error or store failure stops the whole batch.
  /// Future runs REQUIRE a NEW direct user interaction and fresh approval.
  Future<SourceLockedProseBatchProgress> generate({
    required SourceLockedProseBatchManifest manifest,
    required String approvedManifestDigest,
    required bool explicitBatchConsent,
    ZaiPreviewCancellation? cancellation,
    void Function(SourceLockedProseBatchProgress progress)? onProgress,
  }) async {
    if (!explicitBatchConsent ||
        approvedManifestDigest != manifest.approvalDigest) {
      throw const FormatException(
          'Не подтверждён точный список сцен и предел запросов.');
    }
    manifest.verifyUnchanged();
    final token = cancellation ?? ZaiPreviewCancellation();
    token.check();

    // Check ALL stored records before posting any request; a damaged
    // checkpoint must not be bypassed by an unexpected paid retry.
    final completedIds = <String>{};
    for (final context in manifest.contexts) {
      token.check();
      if (await store.read(context) != null) {
        completedIds.add(context.situation.id);
      }
    }
    final initiallyRecovered = completedIds.length;
    var generated = 0;
    SourceLockedProseBatchProgress report() =>
        SourceLockedProseBatchProgress(
          total: manifest.sceneIds.length,
          completed: completedIds.length,
          recovered: initiallyRecovered,
          newlyGenerated: generated,
        );
    onProgress?.call(report());
    for (final context in manifest.contexts) {
      token.check();
      if (completedIds.contains(context.situation.id)) continue;
      if (generated >= manifest.maxNewScenesPerRun) break;
      final draft = await (previewOverride?.call(context, token) ??
          service.preview(
            context: context,
            approvedContextDigest: context.approvalDigest,
            // Exact context was individually displayed as one member
            // of the independently signed, user-approved batch manifest.
            userReviewedExactContext: true,
            cancellation: token,
          ));
      token.check();
      if (draft.sourceFingerprint != manifest.index.sourceFingerprint ||
          draft.situationId != context.situation.id ||
          draft.approvalDigest != context.approvalDigest ||
          draft.route != context.situation.route) {
        throw const FormatException(
            'Ответ ИИ не принадлежит подтверждённой сцене.');
      }
      // Persistence is a hard gate. A failed write cannot count as success.
      await store.save(context: context, draft: draft);
      token.check();
      completedIds.add(context.situation.id);
      generated++;
      onProgress?.call(report());
    }
    return report();
  }
}
