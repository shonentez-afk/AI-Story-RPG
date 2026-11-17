import 'dart:convert';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:crypto/crypto.dart';
import 'dart:isolate';
import 'dart:typed_data';

import 'book_source_index.dart';
import 'gameplay_candidate_reachability.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'source_locked_gameplay_candidates.dart';
import 'whole_plan_gameplay_manifest.dart';

/// The reviewed data stay LOCAL until an explicit confirmation. No API call,
/// publishing or campaign mutation occurs in either phase.
class ReviewedGameplayApprovalPreview {
  ReviewedGameplayApprovalPreview._({
    required this.reviewJson,
    required this.approvalDigest,
    required this.baseArchiveSha256,
    required this.sourceFingerprint,
    required this.verifiedRoutes,
  });

  final String reviewJson, approvalDigest, baseArchiveSha256;
  final String sourceFingerprint;
  final int verifiedRoutes;

  /// Return a fresh UI copy; changing it never changes the approved bytes.
  Map<String, dynamic> get shownReview =>
      Map<String, dynamic>.from(jsonDecode(reviewJson) as Map);

  /// Local report only: never asserts canon, human authorship or model ID.
  bool get literaryCanonVerified => false;
  bool get isAlreadyInstalled => false;
}

/// Two explicit stages: preview -> exact digest approval -> new rich world.
/// A typed AI candidate becomes *private user-approved game fiction*, NOT
/// canonical literary evidence. Every runtime effect must pass both the
/// original source index check and the exhaustive runtime importer.
class ReviewedGameplayCompiler {
  const ReviewedGameplayCompiler._();

  static final _control = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

  static String signature(GameplayCandidate candidate) =>
      candidate.sceneId + '/' + candidate.choiceId +
      '/' + candidate.op + '/' + candidate.id;

  static ReviewedGameplayApprovalPreview preview({
    required Uint8List currentRichBookworld,
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required SourceLockedGameplayContext context,
    required GameplayCandidateDraft proposals,
    required Map<String, String> selectedUserReviewNotes,
  }) {
    if (book.sourceFingerprint != index.sourceFingerprint ||
        book.title != index.title ||
        !book.analysisComplete ||
        context.sourceFingerprint != index.sourceFingerprint ||
        proposals.sourceFingerprint != index.sourceFingerprint ||
        proposals.approvalDigest != context.approvalDigest ||
        selectedUserReviewNotes.isEmpty ||
        selectedUserReviewNotes.length > 6) {
      throw const FormatException('Чужая редакция или нет одобренных предметов');
    }
    final base = const RichPrivateBookworldImporter()
        .inspect(currentRichBookworld);
    if (base.sourceFingerprint != index.sourceFingerprint ||
        base.requiresNetwork || base.canDistributePublicly ||
        base.blueprint.items.isNotEmpty || base.blueprint.facts.isNotEmpty ||
        base.blueprint.initial.stats.isNotEmpty) {
      throw const FormatException('Нужен свежий частный мир этой же книги');
    }
    final available = {
      for (final candidate in proposals.candidates)
        signature(candidate): candidate,
    };
    if (available.length != proposals.candidates.length ||
        !available.keys.toSet().containsAll(selectedUserReviewNotes.keys)) {
      throw const FormatException('Выбран несуществующий эффект ИИ');
    }
    final selected = [
      for (final candidate in proposals.candidates)
        if (selectedUserReviewNotes.containsKey(signature(candidate)))
          candidate,
    ];
    if (selected.length != selectedUserReviewNotes.length) {
      throw const FormatException('Дублированное подтверждение');
    }
    final report = const GameplayCandidateReachabilityAuditor().audit(
      plan: plan,
      context: context,
      draft: GameplayCandidateDraft(
        sourceFingerprint: proposals.sourceFingerprint,
        approvalDigest: proposals.approvalDigest,
        candidates: selected,
      ),
    );
    if (!report.hasNoRouteConflicts) {
      final bad = report.issues.first;
      throw FormatException('Игровой эффект противоречит маршруту: ' +
          bad.code + ' / ' + bad.pathChoiceIds.join(' → '));
    }
    final excerpts = {
      for (final e in context.excerpts) e.id: e,
    };
    final effects = <Map<String, dynamic>>[];
    for (final candidate in selected) {
      final note = selectedUserReviewNotes[signature(candidate)];
      if (note == null || note.trim() != note ||
          note.length < 18 || note.length > 350 ||
          _control.hasMatch(note)) {
        throw const FormatException(
            'Читатель должен отдельно объяснить игровое решение');
      }
      final sourceEvent = excerpts[candidate.sourceEventId];
      if (sourceEvent == null) {
        throw const FormatException('Цитата другого произведения');
      }
      sourceEvent.source.validate(index);
      final quoteSha = sha256.convert(
          utf8.encode(sourceEvent.source.quote)).toString();
      effects.add({
        'scene_id': candidate.sceneId,
        'choice_id': candidate.choiceId,
        'op': candidate.op,
        'kind': candidate.kind,
        'id': candidate.id,
        'label': candidate.label,
        'source_quote_sha256': quoteSha,
        'review_note': note,
      });
    }
    final review = <String, dynamic>{
      'format': 'ai_story_private_gameplay_review_m2h8e1_v1',
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': index.sourceFingerprint,
      'base_archive_sha256': base.archiveSha256,
      'source_payload_digest': context.approvalDigest,
      'user_confirmed': true,
      'literary_canon_verified': false,
      'effects': effects,
    };
    final rawReview = jsonEncode(review);
    // The consent digest binds the ORIGINAL validated world, the precise
    // excerpts/plan and every user-review note. No mutable Map is retained.
    final reviewDigest = sha256.convert(
      utf8.encode('private-gameplay-v1:' + rawReview)).toString();
    return ReviewedGameplayApprovalPreview._(
      reviewJson: rawReview,
      approvalDigest: reviewDigest,
      baseArchiveSha256: base.archiveSha256,
      sourceFingerprint: base.sourceFingerprint,
      verifiedRoutes: report.reachedEndingIds.length,
    );
  }

  /// A SELECTED, separately reviewed subset of every consented source batch.
  /// The model's suggestions remain non-canonical private game FICTION.
  ///
  /// All decisions are checked in ONE inventory/knowledge route graph before
  /// being offered for a separate exact-digest confirmation and local build.
  static ReviewedGameplayApprovalPreview previewAcrossBatches({
    required Uint8List currentRichBookworld,
    required BookSourceIndex index,
    required NarrativeBookModel book,
    required StoryPlan plan,
    required WholePlanGameplayBatchManifest manifest,
    required List<GameplayCandidateDraft> proposals,
    required Map<String, String> selectedUserReviewNotes,
  }) {
    manifest.verifyUnchanged();
    if (index.sourceFingerprint != manifest.index.sourceFingerprint ||
        book.sourceFingerprint != index.sourceFingerprint ||
        index.title != book.title || !book.analysisComplete ||
        manifest.plan.encode() != plan.encode() ||
        manifest.totalBatches != proposals.length ||
        selectedUserReviewNotes.isEmpty ||
        selectedUserReviewNotes.length > 6) {
      throw const FormatException(
          'Нужна проверенная редакция и 1–6 одобренных действий.');
    }
    final base = const RichPrivateBookworldImporter()
        .inspect(currentRichBookworld);
    if (base.sourceFingerprint != index.sourceFingerprint ||
        base.requiresNetwork || base.canDistributePublicly ||
        base.blueprint.items.isNotEmpty ||
        base.blueprint.facts.isNotEmpty ||
        base.blueprint.initial.stats.isNotEmpty) {
      throw const FormatException(
          'Нужен новый частный мир без прежних игровых предметов.');
    }

    final available = <String, GameplayCandidate>{};
    final origins = <String, NarrativeEvent>{};
    for (var n = 0; n < proposals.length; n++) {
      final context = manifest.contexts[n];
      final draft = proposals[n];
      if (draft.sourceFingerprint != context.sourceFingerprint ||
          draft.approvalDigest != context.approvalDigest ||
          draft.candidates.length >
              SourceLockedGameplayContext.maxProposals) {
        throw const FormatException('Подменён исходный пакет предложений');
      }
      for (final event in context.excerpts) {
        if (origins.containsKey(event.id)) {
          throw const FormatException('Повторный исходный фрагмент');
        }
        origins[event.id] = event;
      }
      for (final candidate in draft.candidates) {
        if (available.containsKey(signature(candidate))) {
          throw const FormatException(
              'Повторная операция между разными пакетами');
        }
        available[signature(candidate)] = candidate;
      }
    }
    if (!available.keys.toSet()
        .containsAll(selectedUserReviewNotes.keys)) {
      throw const FormatException(
          'Читатель выбрал отсутствующий игровой эффект.');
    }
    final selectedDrafts = <GameplayCandidateDraft>[];
    final selected = <GameplayCandidate>[];
    for (final draft in proposals) {
      final accepted = [
        for (final candidate in draft.candidates)
          if (selectedUserReviewNotes.containsKey(signature(candidate)))
            candidate,
      ];
      selected.addAll(accepted);
      selectedDrafts.add(GameplayCandidateDraft(
        sourceFingerprint: draft.sourceFingerprint,
        approvalDigest: draft.approvalDigest,
        candidates: List.unmodifiable(accepted),
      ));
    }
    if (selected.length != selectedUserReviewNotes.length ||
        selected.isEmpty || selected.length > 6) {
      throw const FormatException(
          'Недопустимое число выбранных эффектов или их дублирование.');
    }
    final report = const GameplayCandidateReachabilityAuditor()
        .auditAcrossBatches(
          plan: plan, manifest: manifest, drafts: selectedDrafts,
        );
    if (!report.hasNoRouteConflicts) {
      final bad = report.issues.first;
      throw FormatException(
          'Эффект противоречит маршруту: ' + bad.code + ' / ' +
          bad.pathChoiceIds.join(' → '));
    }

    final effects = <Map<String, dynamic>>[];
    for (final candidate in selected) {
      final note = selectedUserReviewNotes[signature(candidate)];
      if (note == null || note.trim() != note ||
          note.length < 18 || note.length > 350 ||
          _control.hasMatch(note)) {
        throw const FormatException(
            'Нужно отдельное пояснение для каждого игрового эффекта.');
      }
      final source = origins[candidate.sourceEventId];
      if (source == null) {
        throw const FormatException('Чужая цитата в редакторском выборе.');
      }
      source.source.validate(index);
      effects.add({
        'scene_id': candidate.sceneId,
        'choice_id': candidate.choiceId,
        'op': candidate.op,
        'kind': candidate.kind,
        'id': candidate.id,
        'label': candidate.label,
        'source_quote_sha256':
            sha256.convert(utf8.encode(source.source.quote)).toString(),
        'review_note': note,
      });
    }
    final review = <String, dynamic>{
      'format': 'ai_story_private_gameplay_review_m2h8e1_v1',
      'review_scope': 'user_declared_private_game_fiction',
      'source_fingerprint': index.sourceFingerprint,
      'base_archive_sha256': base.archiveSha256,
      // Bind the WHOLE request plan/budget, not only one GLM window.
      'source_payload_digest': manifest.approvalDigest,
      'user_confirmed': true,
      'literary_canon_verified': false,
      'effects': effects,
    };
    final encoded = jsonEncode(review);
    return ReviewedGameplayApprovalPreview._(
      reviewJson: encoded,
      approvalDigest: sha256.convert(
        utf8.encode('private-gameplay-v1:' + encoded)).toString(),
      baseArchiveSha256: base.archiveSha256,
      sourceFingerprint: base.sourceFingerprint,
      verifiedRoutes: report.reachedEndingIds.length,
    );
  }

  static Uint8List _compileInWorker(Map<String, dynamic> data) =>
      const ReviewedGameplayBookworldWriter().build(
        verifiedBaseArchive: data['base_archive'] as Uint8List,
        sourceIndex: Map<String, dynamic>.from(data['source_index'] as Map),
        userReview: Map<String, dynamic>.from(data['review'] as Map),
      );

  static Future<Uint8List> compileAfterUserConfirmation({
    required ReviewedGameplayApprovalPreview preview,
    required Uint8List currentRichBookworld,
    required BookSourceIndex index,
    required bool explicitlyConfirmedPrivateGameFiction,
    required String approvedReviewDigest,
  }) async {
    if (!explicitlyConfirmedPrivateGameFiction ||
        approvedReviewDigest != preview.approvalDigest ||
        sha256.convert(currentRichBookworld).toString() !=
            preview.baseArchiveSha256 ||
        index.sourceFingerprint != preview.sourceFingerprint ||
        sha256.convert(utf8.encode(
            'private-gameplay-v1:' + preview.reviewJson)).toString() !=
            preview.approvalDigest) {
      throw const FormatException(
          'Подтвердите точно показанные частные игровые эффекты');
    }
    final payload = <String, dynamic>{
      'base_archive': Uint8List.fromList(currentRichBookworld),
      'source_index': Map<String, dynamic>.from(index.toJson()),
      'review': preview.shownReview,
    };
    final archive = await Isolate.run(() => _compileInWorker(payload));
    final inspected = const RichPrivateBookworldImporter().inspect(archive);
    if (inspected.sourceFingerprint != index.sourceFingerprint ||
        inspected.canDistributePublicly || inspected.requiresNetwork ||
        inspected.archiveSha256 == preview.baseArchiveSha256) {
      throw const FormatException('Новая RPG не прошла независимый импорт');
    }
    // Installation and starting a campaign are separate, explicit UI steps.
    return archive;
  }
}
