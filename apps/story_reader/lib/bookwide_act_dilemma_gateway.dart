import 'ai_connection.dart';
import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'story_plan_quality_gate.dart';
import 'zai_semantic_preview.dart';
import 'zai_story_dilemma_proposal.dart';

/// EXACT excerpts of ONE act, for a single paid request. Display
/// manifest.snippets VERBATIM before any consent is collected.
/// No invisible batch, no blanket consent for the rest of the book.
class ActDilemmaConsentManifest {
  ActDilemmaConsentManifest._({
    required this.actId,
    required this.sourceFingerprint,
    required this.approvalDigest,
    required List<NarrativeEvent> snippets,
  }) : snippets = List.unmodifiable(snippets),
       eventIds = List.unmodifiable([
         for (final e in snippets) e.id,
       ]);

  final String actId, sourceFingerprint, approvalDigest;
  final List<NarrativeEvent> snippets;
  final List<String> eventIds;

  int get paidRequestCount => 1;
  bool get consentAlreadyGranted => false;

  static ActDilemmaConsentManifest fromAct({
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required String actId,
  }) {
    if (!book.analysisComplete ||
        bookMap.sourceFingerprint != book.sourceFingerprint ||
        bookMap.sourceEvents != book.events.length ||
        bookMap.chapters != book.chapterCount ||
        bookMap.acts.where((act) => act.id == actId).length != 1) {
      throw const AiSetupException(
          'Часть книги не совпадает с её завершённым анализом.');
    }
    final act = bookMap.acts.singleWhere((act) => act.id == actId);
    if (act.isCoverageGap || act.events.length < 2) {
      throw const AiSetupException(
          'В этой части нет двух независимых цитат для развилки.');
    }
    final allIds = {for (final e in book.events) e.id};
    final positions = <int>[];
    for (final event in act.events) {
      if (!allIds.contains(event.id) ||
          event.source.chapterIndex != act.chapterIndex ||
          positions.isNotEmpty &&
          event.narrativePosition <= positions.last) {
        throw const AiSetupException(
            'В части найдены чужие или переставленные события.');
      }
      positions.add(event.narrativePosition);
    }
    final take = act.events.length <=
            ZaiStoryDilemmaProposalService.maxEventsPerRequest
        ? act.events.length
        : ZaiStoryDilemmaProposalService.maxEventsPerRequest;
    final picked = <String>[];
    for (var i = 0; i < take; i++) {
      final ix = ((act.events.length - 1) * i / (take - 1)).round();
      picked.add(act.events[ix].id);
    }
    final snippets = ZaiStoryDilemmaProposalService.samples(
        book, exactEventIds: picked);
    return ActDilemmaConsentManifest._(
      actId: actId,
      sourceFingerprint: book.sourceFingerprint,
      approvalDigest: ZaiStoryDilemmaProposalService.excerptApprovalDigest(
          book, snippets),
      snippets: snippets,
    );
  }
}

/// One source-anchored model hypothesis. It is deliberately NOT canon,
/// even when formal state rules and every quotation ID are valid.
class ActDilemmaCandidate {
  const ActDilemmaCandidate({
    required this.actId,
    required this.preview,
    required this.quality,
  });

  final String actId;
  final ZaiStoryDilemmaPreview preview;
  final StoryPlanQualityReport? quality;
  bool get foundCandidate => preview.foundCandidate;
  bool get readyToPlay => false;
}

/// A one-act-only cloud gateway. It revalidates the previously displayed
/// exact excerpts BEFORE sending them. 429/timeouts may retry identical
/// POST bytes, but never advance to another act in the background.
class ActDilemmaProposalGateway {
  ActDilemmaProposalGateway({
    ZaiStoryDilemmaProposalService? service,
  }) : service = service ?? ZaiStoryDilemmaProposalService();

  final ZaiStoryDilemmaProposalService service;

  Future<ActDilemmaCandidate> request({
    required NarrativeBookModel book,
    required BookwideActPlan bookMap,
    required String actId,
    required String approvedDigest,
    required bool explicitConsentForShownActQuotes,
    bool consentForBookTitle = false,
    ZaiPreviewCancellation? cancellation,
    void Function(int attempt, int total, String status)? onProgress,
  }) async {
    if (!explicitConsentForShownActQuotes) {
      throw const AiSetupException(
          'Отправка цитат этого акта не разрешена.');
    }
    final manifest = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: bookMap, actId: actId);
    if (approvedDigest != manifest.approvalDigest) {
      throw const AiSetupException(
          'Цитаты этой части книги изменились. '
          'Покажите их заново перед отправкой.');
    }
    // Existing BYOK flow verifies API key, user preferences, request budget,
    // JSON schema, event IDs, retry invariants and edition fingerprint.
    final result = await service.propose(
      book: book,
      approvedExactEventIds: manifest.eventIds,
      approvedExcerptDigest: manifest.approvalDigest,
      consentForTheseSampledQuotes: true,
      consentForBookTitle: consentForBookTitle,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    final proposal = result.proposal;
    StoryPlanQualityReport? quality;
    if (result.foundCandidate && proposal != null) {
      if (!manifest.eventIds.contains(proposal.setupEventId) ||
          !manifest.eventIds.contains(proposal.outcomeEventId)) {
        throw const AiSetupException(
            'ИИ сослался на эпизод за пределами разрешённой части.');
      }
      try {
        quality = StoryPlanQualityGate.assess(
            book: book, preview: result);
      } catch (_) {
        throw const AiSetupException(
            'Игровая развилка не прошла формальный аудит.');
      }
      if (!quality.passedFormalPreflight) {
        throw const AiSetupException(
            'Развилка содержит противоречивые игровые условия.');
      }
    } else if (result.foundCandidate || proposal != null) {
      throw const AiSetupException(
          'ИИ вернул неполное или повреждённое предложение.');
    }
    return ActDilemmaCandidate(
      actId: manifest.actId, preview: result, quality: quality);
  }

  /// Local-only composition after two OR MORE separately approved acts.
  /// This is a NON-INSTALLABLE draft; arbitrary book text is never
  /// automatically considered the cause of the following game event.
  MultiActStoryPlanDraft composeLocal({
    required BookSourceIndex index,
    required BookwideActPlan bookMap,
    required NarrativeBookModel book,
    required List<ActDilemmaCandidate> candidates,
  }) {
    if (candidates.length < 2 ||
        candidates.length > BookwideStoryPlanComposer.maxDraftActs ||
        candidates.any((c) =>
            !c.foundCandidate || c.quality == null ||
            !c.quality!.passedFormalPreflight ||
            c.preview.proposal == null) ||
        candidates.map((c) => c.actId).toSet().length !=
            candidates.length) {
      throw const FormatException(
          'Для сборки нужно 2–6 подтверждённых формальной '
          'проверкой предложений для разных актов.');
    }
    final draft = BookwideStoryPlanComposer.compose(
      index: index,
      book: book,
      bookMap: bookMap,
      actProposals: [
        for (final c in candidates) c.preview.proposal!,
      ],
    );
    for (var i = 0; i < candidates.length; i++) {
      if (draft.parts[i].actId != candidates[i].actId) {
        throw const FormatException(
            'Предложение получено для другой части книги.');
      }
    }
    return draft;
  }
}
