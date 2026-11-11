import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'source_locked_gameplay_candidates.dart';

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
  /// Same bounded provider retry count as the connected Z.ai adapter.
  static const maxModelAttempts = 3;

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
      maxModelAttempts;
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
      'model': SourceLockedGameplayContext.defaultModelId,
      'max_new_requests': maxNewRequestsPerRun,
      'max_attempts_each':
          maxModelAttempts,
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

