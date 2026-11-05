import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/story_plan_trial_compiler.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memory implements SourceAnalysisCheckpointRepository {
  String? data;
  @override
  Future<String?> read(String fingerprint) async => data;
  @override
  Future<void> write(String fingerprint, String text) async { data = text; }
  @override
  Future<void> delete(String fingerprint) async { data = null; }
}

BookSourceIndex _index({String suffix = ''}) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'История с двумя реальными цитатами' + suffix,
      author: 'Учебный пример',
      chapters: [
        'Путник нашёл старую вещь возле колодца и услышал '
            'условие помощи от незнакомца. Ему предстояло решить, '
            'соглашаться ли на неожиданное обещание.',
        'Встреча с другим человеком вызвала новую возможность. '
            'Рассказчик пока не подтверждает, какой путь привёл '
            'к благополучному исходу и кто владеет находкой.',
      ],
    ));

Future<NarrativeBookModel> _model(BookSourceIndex index) async {
  final scan = ZaiAutoWholeBookAnalysis(
    repository: _Memory(),
    preview: (source, window, token, title) async {
      final chunk = window.chunks.first;
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [
            SemanticCandidate.propose(source, chunk,
              category: SemanticCategory.event,
              startUtf16: chunk.startUtf16,
              endUtf16: chunk.startUtf16 + 60,
              label: 'Возможное смысловое событие',
              uncertainty: 'Причина и знание ещё не доказаны.',
            ),
          ],
        ),
        totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final review = await scan.analyze(
      index: index,
      approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true,
      maxWindowsPerRun: 12);
  return NarrativeBookModel.fromExisting(
      index: index, outline: ZaiWholeBookEventOutline.build(review));
}

StoryDilemmaProposal _candidate(NarrativeBookModel book) =>
    StoryDilemmaProposal(
      sourceFingerprint: book.sourceFingerprint,
      setupEventId: book.events.first.id,
      outcomeEventId: book.events.last.id,
      kind: StoryDilemmaKind.agreement,
      dilemma: 'Принять предложение о помощи или искать иной путь',
      acceptIntent: 'Согласиться на предложенное условие',
      refuseIntent: 'Отказаться и продолжить самостоятельный поиск',
      followupGoal: 'Решить, как исполнить данное обязательство',
      finishOriginalIntent: 'Исполнить ранее принятое условие',
      originalEnding: 'Герой завершил первый выбранный игровой маршрут',
      alternativeSearchGoal: 'Искать другой способ решить проблему',
      searchIntent: 'Осмотреть местность и поискать других помощников',
      alternativeDiscovery: 'Найдена новая возможность продолжения пути',
      useDiscoveryIntent: 'Применить новое решение вместо прежнего условия',
      alternativeEnding: 'Герой завершил другой придуманный игровой путь',
    );

ZaiStoryDilemmaPreview _preview(NarrativeBookModel book) {
  final p = _candidate(book);
  return ZaiStoryDilemmaPreview(
    proposal: p,
    plan: StoryPlanDilemmaGenerator.propose(book, p),
    sampledEventCount: 2,
  );
}

Future<StoryPlanTrialCompilation> _compile(
    BookSourceIndex index, NarrativeBookModel book, {
    bool reviewed = true,
    bool privateUse = true,
    bool fiction = true,
}) => StoryPlanTrialCompiler.compile(
  index: index,
  book: book,
  preview: _preview(book),
  sourceEventIdsReviewedByUser: reviewed
      ? {book.events.first.id, book.events.last.id}
      : {book.events.first.id},
  privateUseConfirmed: privateUse,
  fictionalTrialAcknowledged: fiction,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a GLM-shaped causal plan compiles a PRIVATE OFFLINE BookWorld '
      'and two DIFFERENT multi-turn SQLite campaigns survive restart',
      () async {
    final index = _index();
    final book = await _model(index);
    final built = await _compile(index, book);
    expect(built.isPrivateTrial, true);
    expect(built.isFullBookAdaptation, false);
    expect(built.sourceMeaningIsVerified, false);
    expect(built.requiresCloudToPlay, false);
    expect(built.canDistributePublicly, false);
    expect(built.sceneCount, 7);
    expect(built.sourceQuoteCount, 2);
    final check = const PrivateBookworldImporter().inspect(built.archive);
    expect(check.sourceFingerprint, index.sourceFingerprint);
    expect(check.requiresNetwork, false);
    expect(check.canDistributePublicly, false);
    final temp = await Directory.systemTemp.createTemp('storyplan-trial-');
    late String originalCampaign;
    late String alternativeCampaign;
    try {
      var store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        final world = store.installBookworld(built.archive);
        originalCampaign = store.createCampaign(world.archiveHash);
        alternativeCampaign = store.createCampaign(world.archiveHash);
        var revision = 0;
        for (final id in ['accept_offer', 'honor_condition']) {
          final current = store.loadCampaign(originalCampaign);
          expect(current.metadata.revision, revision);
          expect(current.coordinator.choices.any(
              (choice) => choice.id == id), true);
          final result = store.commitChoice(originalCampaign,
            actionId: 'original_' + revision.toString(),
            choiceId: id,
            expectedRevision: revision);
          expect(result.applied, true);
          revision++;
        }
        expect(store.loadCampaign(originalCampaign).coordinator.isTerminal,
            true);
        var alternativeRevision = 0;
        for (final id in [
          'refuse_offer', 'explore', 'use_discovery', 'end_alternative',
        ]) {
          final current = store.loadCampaign(alternativeCampaign);
          expect(current.metadata.revision, alternativeRevision);
          expect(current.coordinator.choices.any(
              (choice) => choice.id == id), true);
          final result = store.commitChoice(alternativeCampaign,
            actionId: 'alternative_' + alternativeRevision.toString(),
            choiceId: id,
            expectedRevision: alternativeRevision);
          expect(result.applied, true);
          alternativeRevision++;
        }
        expect(store.loadCampaign(alternativeCampaign).coordinator.isTerminal,
            true);
        expect(store.loadCampaign(originalCampaign).metadata.revision, 2);
        expect(store.loadCampaign(alternativeCampaign).metadata.revision, 4);
      } finally {
        store.close();
      }
      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        expect(store.installedWorlds(), hasLength(1));
        expect(store.campaigns(), hasLength(2));
        expect(store.loadCampaign(originalCampaign).coordinator.isTerminal,
            true);
        expect(store.loadCampaign(alternativeCampaign).coordinator.isTerminal,
            true);
        expect(store.loadCampaign(originalCampaign).metadata.revision, 2);
        expect(store.loadCampaign(alternativeCampaign).metadata.revision, 4);
      } finally {
        store.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('no compilation without review of BOTH exact quotes and permissions',
      () async {
    final index = _index();
    final book = await _model(index);
    await expectLater(_compile(index, book, reviewed: false),
        throwsFormatException);
    await expectLater(_compile(index, book, privateUse: false),
        throwsFormatException);
    await expectLater(_compile(index, book, fiction: false),
        throwsFormatException);
  });

  test('wrong edition or no model proposal cannot be installed', () async {
    final index = _index();
    final book = await _model(index);
    final changed = _index(suffix: ' другой перевод');
    await expectLater(_compile(changed, book), throwsFormatException);
    await expectLater(StoryPlanTrialCompiler.compile(
      index: index, book: book,
      preview: const ZaiStoryDilemmaPreview(
          proposal: null, plan: null, sampledEventCount: 2),
      sourceEventIdsReviewedByUser: {
        book.events.first.id, book.events.last.id,
      },
      privateUseConfirmed: true,
      fictionalTrialAcknowledged: true,
    ), throwsFormatException);
  });
}
