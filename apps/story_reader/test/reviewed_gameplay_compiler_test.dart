import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/gameplay_candidate_reachability.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/reviewed_gameplay_compiler.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/story_plan_trial_compiler.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_source_locked_gameplay_candidates.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:story_core/story_core.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(BookSourceIndex, NarrativeBookModel, StoryPlan,
    ZaiStoryDilemmaPreview)> _source() async {
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Синтетическая история о ключе',
    author: 'Автор теста',
    chapters: [
      'Путник обнаружил старый ключ возле колодца. '
          'Сторож предложил помощь за обещание, но путник '
          'пока не согласился на условие.',
      'Ключ оставался у колодца. На следующий день путник увидел дорогу. '
          'Он мог отказаться от условия и искать собственный путь, '
          'а принадлежность ключа всё ещё оставалась неизвестной.',
    ],
  ));
  final scan = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (index, window, cancellation, includeTitle) async {
      final chunk = window.chunks.first;
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: index.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [
            SemanticCandidate.propose(
              index, chunk, category: SemanticCategory.event,
              startUtf16: chunk.startUtf16,
              endUtf16: chunk.startUtf16 + 60,
              label: 'Возможное событие: ключ и решение',
              uncertainty: 'Литературная причинность не подтверждена.',
            ),
          ],
        ),
        totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final reviewed = await scan.analyze(
      index: index, approvedManifestDigest: consent.approvalDigest,
      explicitWholeBookConsent: true, maxWindowsPerRun: 12);
  final book = NarrativeBookModel.fromExisting(
      index: index, outline: ZaiWholeBookEventOutline.build(reviewed));
  final p = StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: book.events.first.id,
    outcomeEventId: book.events.last.id,
    kind: StoryDilemmaKind.agreement,
    dilemma: 'Согласиться на помощь или искать другую дорогу',
    acceptIntent: 'Принять предложение и проверить ключ',
    refuseIntent: 'Отказаться и оставить ключ',
    followupGoal: 'Разобраться с обещанием и ключом',
    finishOriginalIntent: 'Использовать ключ для исполнения договора',
    originalEnding: 'Изначальный игровой путь завершён',
    alternativeSearchGoal: 'Найти выход без обещания',
    searchIntent: 'Поискать другую дорогу',
    alternativeDiscovery: 'Герой нашёл запасной путь',
    useDiscoveryIntent: 'Продолжить запасной путь',
    alternativeEnding: 'Альтернативный игровой путь завершён',
  );
  final plan = StoryPlanDilemmaGenerator.propose(book, p);
  expect(plan.validate(book).isStructurallySound, true);
  return (index, book, plan, ZaiStoryDilemmaPreview(
    proposal: p, plan: plan, sampledEventCount: 2,
  ));
}

GameplayCandidate _item(SourceLockedGameplayContext ctx, String choice,
    String op) {
  final anchor = ctx.choices.singleWhere((c) => c.choiceId == choice);
  return GameplayCandidate(
    kind: 'item', id: 'old_key', label: 'ключ',
    op: op, sceneId: anchor.sceneId, choiceId: anchor.choiceId,
    sourceEventId: anchor.sourceEventId,
    uncertainty: 'Текст упоминает ключ, но владение не доказано.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real source-locked two-act choice sequence becomes reviewed v3 '
      'with true inventory, journal and SQLite restart', () async {
    final (index, book, plan, proposal) = await _source();
    final original = await StoryPlanTrialCompiler.compile(
      index: index, book: book, preview: proposal,
      sourceEventIdsReviewedByUser: {
        book.events.first.id, book.events.last.id,
      },
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    final ctx = SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: plan,
      exactEventIds: [for (final event in book.events) event.id],
    );
    final candidates = [
      _item(ctx, 'accept_offer', 'grant_item'),
      _item(ctx, 'honor_condition', 'consume_item'),
    ];
    final draft = GameplayCandidateDraft(
      sourceFingerprint: ctx.sourceFingerprint,
      approvalDigest: ctx.approvalDigest,
      candidates: candidates,
    );
    final report = const GameplayCandidateReachabilityAuditor().audit(
        plan: plan, context: ctx, draft: draft);
    expect(report.issues, isEmpty);

    final notes = {
      for (final c in candidates)
        ReviewedGameplayCompiler.signature(c):
            'Читатель одобрил игровую выдумку, но не утверждает канон.',
    };
    final approved = ReviewedGameplayCompiler.preview(
      currentRichBookworld: original.archive,
      index: index, book: book, plan: plan, context: ctx,
      proposals: draft, selectedUserReviewNotes: notes,
    );
    expect(approved.literaryCanonVerified, false);
    expect(approved.isAlreadyInstalled, false);
    expect(approved.verifiedRoutes, 2);
    (approved.shownReview['effects'] as List).clear();
    expect((approved.shownReview['effects'] as List), hasLength(2));
    await expectLater(ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: approved,
      currentRichBookworld: original.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: false,
      approvedReviewDigest: approved.approvalDigest,
    ), throwsFormatException);
    await expectLater(ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: approved,
      currentRichBookworld: original.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: true,
      approvedReviewDigest: 'wrong_reviewed_contents',
    ), throwsFormatException);
    final rich = await ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: approved,
      currentRichBookworld: original.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: true,
      approvedReviewDigest: approved.approvalDigest,
    );
    final imported = const RichPrivateBookworldImporter().inspect(rich);
    expect(imported.bookworldId, isNot(original.bookworldId));
    expect(imported.sourceFingerprint, index.sourceFingerprint);
    expect(imported.presentation['item_names'],
        containsPair('old_key', 'ключ'));
    expect(imported.canDistributePublicly, false);
    expect(imported.requiresNetwork, false);

    final canon = StoryWorld(imported.blueprint);
    for (final choice in ['accept_offer', 'honor_condition']) {
      expect(canon.apply(
        actionId: 'story_' + choice, choiceId: choice,
        expectedRevision: canon.state.revision,
      ).status, DecisionStatus.applied);
    }
    expect(canon.isTerminal, true);
    expect(canon.state.inventory, isEmpty);
    expect(canon.events, hasLength(2));
    final alt = StoryWorld(imported.blueprint);
    for (final choice in [
      'refuse_offer', 'explore', 'use_discovery', 'end_alternative',
    ]) {
      expect(alt.apply(
        actionId: 'alt_' + choice, choiceId: choice,
        expectedRevision: alt.state.revision,
      ).status, DecisionStatus.applied);
    }
    expect(alt.isTerminal, true);
    expect(alt.state.inventory, isEmpty);

    final folder = await Directory.systemTemp.createTemp(
        'ai_story_reviewed_gameplay_');
    try {
      var store = BookworldCampaignStore.openPrivateDirectory(folder.path);
      late String canonId, altId;
      try {
        final installed = store.installBookworld(rich);
        canonId = store.createCampaign(installed.archiveHash);
        altId = store.createCampaign(installed.archiveHash);
        for (final (id, path) in [
          (canonId, ['accept_offer', 'honor_condition']),
          (altId, ['refuse_offer', 'explore',
                   'use_discovery', 'end_alternative']),
        ]) {
          var revision = 0;
          for (final choice in path) {
            final result = store.commitChoice(id,
              actionId: id + '_' + revision.toString(),
              choiceId: choice, expectedRevision: revision);
            expect(result.applied, true);
            revision++;
          }
          expect(store.loadCampaign(id).coordinator.isTerminal, true);
        }
      } finally {
        store.close();
      }
      store = BookworldCampaignStore.openPrivateDirectory(folder.path);
      try {
        expect(store.installedWorlds(), hasLength(1));
        expect(store.campaigns(), hasLength(2));
        expect(store.loadCampaign(canonId).metadata.revision, 2);
        expect(store.loadCampaign(altId).metadata.revision, 4);
      } finally {
        store.close();
      }
    } finally {
      await folder.delete(recursive: true);
    }
  });

  test('a private-game review does not accept foreign book or fake item',
      () async {
    final (index, book, plan, preview) = await _source();
    final world = await StoryPlanTrialCompiler.compile(
      index: index, book: book, preview: preview,
      sourceEventIdsReviewedByUser: {
        book.events.first.id, book.events.last.id,
      },
      privateUseConfirmed: true, fictionalTrialAcknowledged: true,
    );
    final ctx = SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: plan,
      exactEventIds: [for (final e in book.events) e.id],
    );
    final item = _item(ctx, 'accept_offer', 'grant_item');
    final draft = GameplayCandidateDraft(
      sourceFingerprint: ctx.sourceFingerprint,
      approvalDigest: ctx.approvalDigest,
      candidates: [item],
    );
    final fake = GameplayCandidate(
      kind: 'item', id: 'magic_sword', label: 'волшебный меч',
      op: 'grant_item', sceneId: item.sceneId,
      choiceId: item.choiceId, sourceEventId: item.sourceEventId,
      uncertainty: item.uncertainty,
    );
    expect(() => ReviewedGameplayCompiler.preview(
      currentRichBookworld: world.archive,
      index: index, book: book, plan: plan, context: ctx,
      proposals: GameplayCandidateDraft(
        sourceFingerprint: ctx.sourceFingerprint,
        approvalDigest: ctx.approvalDigest,
        candidates: [fake],
      ),
      selectedUserReviewNotes: {
        ReviewedGameplayCompiler.signature(fake):
            'Выдуманный предмет без дословной цитаты неприемлем.',
      },
    ), throwsFormatException);
    final valid = ReviewedGameplayCompiler.preview(
      currentRichBookworld: world.archive,
      index: index, book: book, plan: plan, context: ctx,
      proposals: draft,
      selectedUserReviewNotes: {
        ReviewedGameplayCompiler.signature(item):
            'Это отдельное решение только для частной игровой адаптации.',
      },
    );
    expect(valid.verifiedRoutes, 2);
    await expectLater(ReviewedGameplayCompiler.compileAfterUserConfirmation(
      preview: valid,
      currentRichBookworld: world.archive,
      index: index, explicitlyConfirmedPrivateGameFiction: true,
      approvedReviewDigest: 'not_approved',
    ), throwsFormatException);
  });
}
