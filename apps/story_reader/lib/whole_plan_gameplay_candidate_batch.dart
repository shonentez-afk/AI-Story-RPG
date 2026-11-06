import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ai_connection.dart';
import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'story_plan.dart';
import 'zai_semantic_preview.dart';
import 'zai_source_locked_gameplay_candidates.dart';

/// A source-exact, explicit consent manifest over ALL SOURCE-ANCHORED
/// decisions in a completed plan, not just the first six book excerpts.
/// Unanchored book events are counted, never silently declared covered.
///
/// This is still a model PROPOSAL stage, NOT a literary truth claim, and
/// cannot change a BookWorld or install/modify a campaign.
class WholePlanGameplayBatchManifest {
  WholePlanGameplayBatchManifest._({
    required this.index,
    required this.book,
    required this.plan,
    required this.approvalDigest,
    required this.maxNewRequestsPerRun,
    required this.unanchoredBookEvents,
    required this.sentContextBytes,
    required List<SourceLockedGameplayContext> contexts,
  }) : contexts = List.unmodifiable(contexts);

  static const format = 'ai_story_gameplay_whole_plan_m2h8f1_v1';
  static const maxBatches = 32;
  static const maxRequestsPerRun = 4;

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final String approvalDigest;
  final int maxNewRequestsPerRun;
  final int unanchoredBookEvents;
  final int sentContextBytes;
  final List<SourceLockedGameplayContext> contexts;

  int get totalBatches => contexts.length;
  int get totalReferencedSourceEvents =>
      contexts.fold<int>(0, (sum, ctx) => sum + ctx.excerpts.length);
  int get maxHttpAttempts =>
      maxNewRequestsPerRun *
      ZaiSourceLockedGameplayCandidateService.maxAttempts;
  bool get literaryCanonVerified => false;
  bool get mayInstallGame => false;
  bool get coversUnanchoredEvents => false;

  /// Exact request payloads to show BEFORE the user approves the batch.
  /// One foreground approval covers at most maxNewRequestsPerRun NEW calls.
  List<Map<String, Object>> get sentContexts => List.unmodifiable([
    for (final context in contexts) context.consentPreview,
  ]);

  static WholePlanGameplayBatchManifest fromPlan({
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required int maxNewRequestsPerRun,
  }) {
    if (maxNewRequestsPerRun < 1 ||
        maxNewRequestsPerRun > maxRequestsPerRun ||
        !book.analysisComplete ||
        index.sourceFingerprint != book.sourceFingerprint ||
        index.title != book.title ||
        index.indexedChapterCount != index.chapterCount ||
        index.indexedTextUtf16 != index.totalTextUtf16 ||
        plan.sourceFingerprint != index.sourceFingerprint ||
        plan.title != index.title ||
        !plan.validate(book).isStructurallySound) {
      throw const FormatException(
          'Нужна полностью проиндексированная книга, план и лимит запросов.');
    }
    final referenced = <String>{};
    for (final situation in plan.situations) {
      for (final decision in situation.decisions) {
        final id = decision.sourceEventId ?? situation.sourceEventId;
        if (id != null) referenced.add(id);
      }
    }
    if (referenced.isEmpty) {
      throw const FormatException(
          'В плане нет решений, привязанных к цитатам книги.');
    }
    final ordered = [
      for (final event in book.events)
        if (referenced.contains(event.id)) event,
    ]..sort((a, b) => a.narrativePosition.compareTo(b.narrativePosition));
    if (ordered.length != referenced.length) {
      throw const FormatException('План содержит ссылку на чужое событие.');
    }
    for (var i = 1; i < ordered.length; i++) {
      if (ordered[i].narrativePosition <= ordered[i - 1].narrativePosition) {
        throw const FormatException(
            'Нельзя определённо упорядочить выбранные цитаты.');
      }
    }

    final groups = <SourceLockedGameplayContext>[];
    var window = <String>[];
    SourceLockedGameplayContext? current;
    for (final event in ordered) {
      if (window.isEmpty) {
        window = [event.id];
        // Every referenced event must independently support at least one
        // choice and fit the existing safe 8KB/16-choice request limits.
        current = SourceLockedGameplayContext.forPlan(
          index: index, book: book, plan: plan,
          exactEventIds: window,
        );
        continue;
      }
      try {
        final selected = [...window, event.id];
        final next = SourceLockedGameplayContext.forPlan(
          index: index, book: book, plan: plan,
          exactEventIds: selected,
        );
        window = selected;
        current = next;
      } on FormatException {
        // Only the per-request capacity may cause this fallback. A fresh
        // singleton context must independently validate the next source.
        groups.add(current!);
        if (groups.length >= maxBatches) {
          throw const FormatException('Слишком много пакетов исходной книги.');
        }
        window = [event.id];
        current = SourceLockedGameplayContext.forPlan(
          index: index, book: book, plan: plan,
          exactEventIds: window,
        );
      }
    }
    if (current != null) groups.add(current);
    if (groups.isEmpty || groups.length > maxBatches) {
      throw const FormatException('Нет допустимых пакетов игровых решений.');
    }
    final sent = groups.fold<int>(
        0, (sum, context) =>
            sum + utf8.encode(context.payloadJson).length);
    final planSha = sha256.convert(utf8.encode(plan.encode())).toString();
    final signature = jsonEncode({
      'format': format,
      'source_fingerprint': index.sourceFingerprint,
      'plan_sha256': planSha,
      'model': ZaiModel.id,
      'max_new_requests': maxNewRequestsPerRun,
      'max_attempts_each':
          ZaiSourceLockedGameplayCandidateService.maxAttempts,
      'batches': [
        for (final context in groups)
          {
            'context_digest': context.approvalDigest,
            'exact_request': context.consentPreview,
          },
      ],
    });
    return WholePlanGameplayBatchManifest._(
      index: index,
      book: book,
      plan: plan,
      contexts: groups,
      maxNewRequestsPerRun: maxNewRequestsPerRun,
      unanchoredBookEvents: book.events.length - ordered.length,
      sentContextBytes: sent,
      approvalDigest: sha256.convert(utf8.encode(signature)).toString(),
    );
  }

  void verifyUnchanged() {
    final fresh = fromPlan(
      index: index, book: book, plan: plan,
      maxNewRequestsPerRun: maxNewRequestsPerRun,
    );
    if (fresh.approvalDigest != approvalDigest ||
        fresh.totalReferencedSourceEvents != totalReferencedSourceEvents) {
      throw const FormatException(
          'Изменилась редакция, версия сюжета или состав запросов.');
    }
  }
}

class WholePlanGameplayBatchProgress {
  const WholePlanGameplayBatchProgress({
    required this.total,
    required this.completed,
    required this.recovered,
    required this.newRequests,
    required this.unanchoredBookEvents,
  });

  final int total, completed, recovered, newRequests;
  final int unanchoredBookEvents;
  int get remaining => total - completed;
  bool get allProposalsCollected => remaining == 0;
  bool get literaryCanonVerified => false;
  bool get canInstallGame => false;
}

typedef WholePlanGameplayPreview = Future<GameplayCandidateDraft> Function(
    SourceLockedGameplayContext context,
    ZaiPreviewCancellation cancellation);

/// Stores proposal IDs, source bindings and short suggested names; NEVER
/// saves raw chapter text, original quotes, an API token or a game campaign.
/// A failed atomic write leaves the previous checkpoint readable.
class WholePlanGameplayBatchService {
  WholePlanGameplayBatchService({
    SourceAnalysisCheckpointRepository? repository,
    ZaiSourceLockedGameplayCandidateService? service,
    WholePlanGameplayPreview? previewOverride,
  }) : repository = repository ??
            const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.zaiGameplayBatchDrafts,
            ),
       service = service ?? ZaiSourceLockedGameplayCandidateService(),
       previewOverride = previewOverride;

  final SourceAnalysisCheckpointRepository repository;
  final ZaiSourceLockedGameplayCandidateService service;
  final WholePlanGameplayPreview? previewOverride;

  static const _checkpointFormat = 'ai_story_gameplay_batch_checkpoint_m2h8f1_v1';
  static final _id = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final _controls =
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static Map<String, Object> _candidateRecord(GameplayCandidate c) => {
    'kind': c.kind,
    'id': c.id,
    'label': c.label,
    'op': c.op,
    'scene_id': c.sceneId,
    'choice_id': c.choiceId,
    'source_event_id': c.sourceEventId,
    'uncertainty': c.uncertainty,
  };

  static GameplayCandidate _parseCandidate(Map<String, dynamic> raw) {
    const fields = {
      'kind', 'id', 'label', 'op', 'scene_id',
      'choice_id', 'source_event_id', 'uncertainty',
    };
    if (raw.length != fields.length ||
        !raw.keys.toSet().containsAll(fields) ||
        raw.values.any((value) => value is! String)) {
      throw const FormatException('Повреждена запись предложения ИИ.');
    }
    return GameplayCandidate(
      kind: raw['kind'] as String,
      id: raw['id'] as String,
      label: raw['label'] as String,
      op: raw['op'] as String,
      sceneId: raw['scene_id'] as String,
      choiceId: raw['choice_id'] as String,
      sourceEventId: raw['source_event_id'] as String,
      uncertainty: raw['uncertainty'] as String,
    );
  }

  static void _verifyDraft(
      SourceLockedGameplayContext ctx, GameplayCandidateDraft draft) {
    if (draft.sourceFingerprint != ctx.sourceFingerprint ||
        draft.approvalDigest != ctx.approvalDigest ||
        draft.candidates.length > SourceLockedGameplayContext.maxProposals) {
      throw const FormatException(
          'Предложения ИИ относятся к другой книге или другому запросу.');
    }
    final anchors = {
      for (final anchor in ctx.choices)
        anchor.sceneId + '/' + anchor.choiceId: anchor.sourceEventId,
    };
    final excerpts = {
      for (final e in ctx.excerpts)
        e.id: e.source.quote.toLowerCase(),
    };
    final unique = <String>{};
    final names = <String, (String, String)>{};
    for (final c in draft.candidates) {
      final anchor = c.sceneId + '/' + c.choiceId;
      final old = names[c.id];
      final sign = anchor + '/' + c.op + '/' + c.id;
      final label = c.label;
      final note = c.uncertainty;
      if (!_id.hasMatch(c.id) ||
          anchors[anchor] != c.sourceEventId ||
          !excerpts.containsKey(c.sourceEventId) ||
          !((c.kind == 'item' &&
                (c.op == 'grant_item' || c.op == 'consume_item')) ||
            (c.kind == 'fact' && c.op == 'learn_fact')) ||
          label.trim() != label || label.length < 2 ||
          label.length > 120 || _controls.hasMatch(label) ||
          note.trim() != note || note.length < 10 ||
          note.length > 350 || _controls.hasMatch(note) ||
          c.kind == 'item' &&
              !excerpts[c.sourceEventId]!.contains(label.toLowerCase()) ||
          old != null && (old.$1 != c.kind || old.$2 != label) ||
          !unique.add(sign)) {
        throw const FormatException(
            'Предложение не связано с показанной цитатой и выбором.');
      }
      names[c.id] = (c.kind, label);
    }
  }

  Future<List<GameplayCandidateDraft>> _load(
      WholePlanGameplayBatchManifest manifest) async {
    manifest.verifyUnchanged();
    final content = await repository.read(manifest.index.sourceFingerprint);
    if (content == null) return const [];
    try {
      final raw = jsonDecode(content) as Map<String, dynamic>;
      const keys = {
        'format', 'source_fingerprint', 'manifest_digest',
        'plan_sha256', 'saved', 'sha256',
      };
      if (raw.length != keys.length ||
          !raw.keys.toSet().containsAll(keys) ||
          raw['format'] != _checkpointFormat ||
          raw['source_fingerprint'] != manifest.index.sourceFingerprint ||
          raw['manifest_digest'] != manifest.approvalDigest ||
          raw['plan_sha256'] !=
              sha256.convert(utf8.encode(manifest.plan.encode())).toString()) {
        throw const FormatException('Checkpoint другой книги или плана.');
      }
      final checksum = raw.remove('sha256');
      if (checksum != sha256.convert(utf8.encode(jsonEncode(raw))).toString()) {
        throw const FormatException('Контрольная сумма checkpoint неверна.');
      }
      final saved = raw['saved'];
      if (saved is! List || saved.length > manifest.contexts.length) {
        throw const FormatException('Недопустимое число сохранённых ответов.');
      }
      final collected = <GameplayCandidateDraft>[];
      for (var n = 0; n < saved.length; n++) {
        final entry = saved[n];
        final ctx = manifest.contexts[n];
        if (entry is! Map ||
            entry.length != 2 ||
            entry['context_digest'] != ctx.approvalDigest ||
            entry['proposals'] is! List) {
          throw const FormatException('Запись не относится к этому запросу.');
        }
        final proposals = <GameplayCandidate>[];
        for (final item in entry['proposals'] as List) {
          if (item is! Map) {
            throw const FormatException('Повреждён игровой черновик.');
          }
          proposals.add(_parseCandidate(Map<String, dynamic>.from(item)));
        }
        final draft = GameplayCandidateDraft(
          sourceFingerprint: ctx.sourceFingerprint,
          approvalDigest: ctx.approvalDigest,
          candidates: List.unmodifiable(proposals),
        );
        _verifyDraft(ctx, draft);
        collected.add(draft);
      }
      return List.unmodifiable(collected);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Повреждён приватный checkpoint предметов.');
    }
  }

  Future<void> _save(
      WholePlanGameplayBatchManifest manifest,
      List<GameplayCandidateDraft> drafts) async {
    final payload = <String, dynamic>{
      'format': _checkpointFormat,
      'source_fingerprint': manifest.index.sourceFingerprint,
      'manifest_digest': manifest.approvalDigest,
      'plan_sha256':
          sha256.convert(utf8.encode(manifest.plan.encode())).toString(),
      'saved': [
        for (var n = 0; n < drafts.length; n++)
          {
            'context_digest': manifest.contexts[n].approvalDigest,
            'proposals': [
              for (final c in drafts[n].candidates) _candidateRecord(c),
            ],
          },
      ],
    };
    final hash = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    await repository.write(
      manifest.index.sourceFingerprint,
      jsonEncode({...payload, 'sha256': hash}),
    );
  }

  Future<WholePlanGameplayBatchProgress> inspect(
      WholePlanGameplayBatchManifest manifest) async {
    final completed = (await _load(manifest)).length;
    return WholePlanGameplayBatchProgress(
      total: manifest.totalBatches,
      completed: completed,
      recovered: completed,
      newRequests: 0,
      unanchoredBookEvents: manifest.unanchoredBookEvents,
    );
  }

  Future<List<GameplayCandidateDraft>> readReviewedProposals(
      WholePlanGameplayBatchManifest manifest) =>
      _load(manifest);

  /// One explicit consent authorizes a strict number of NEW bounded requests.
  /// 429/timeout retries have the SAME bytes; each is capped by the existing
  /// Z.ai service at three. No background job, hidden next-batch or auto-play.
  Future<WholePlanGameplayBatchProgress> generate({
    required WholePlanGameplayBatchManifest manifest,
    required String approvedManifestDigest,
    required bool explicitBatchConsent,
    ZaiPreviewCancellation? cancellation,
    void Function(WholePlanGameplayBatchProgress progress)? onProgress,
  }) async {
    if (!explicitBatchConsent ||
        approvedManifestDigest != manifest.approvalDigest) {
      throw const FormatException(
          'Не подтверждены точные отрывки или лимит запросов.');
    }
    final token = cancellation ?? ZaiPreviewCancellation();
    token.check();
    final saved = [...await _load(manifest)];
    final recovered = saved.length;
    var newRequests = 0;
    WholePlanGameplayBatchProgress progress() =>
        WholePlanGameplayBatchProgress(
          total: manifest.totalBatches,
          completed: saved.length,
          recovered: recovered,
          newRequests: newRequests,
          unanchoredBookEvents: manifest.unanchoredBookEvents,
        );
    onProgress?.call(progress());
    for (var n = saved.length; n < manifest.contexts.length; n++) {
      token.check();
      if (newRequests >= manifest.maxNewRequestsPerRun) break;
      final ctx = manifest.contexts[n];
      final result = await (previewOverride?.call(ctx, token) ??
          service.propose(
            context: ctx,
            approvedDigest: ctx.approvalDigest,
            explicitExcerptConsent: true,
            cancellation: token,
          ));
      token.check();
      _verifyDraft(ctx, result);
      await _save(manifest, [...saved, result]);
      token.check();
      saved.add(result);
      newRequests++;
      onProgress?.call(progress());
    }
    return progress();
  }
}
