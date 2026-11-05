import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/story_plan_draft_checkpoint.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

Future<NarrativeBookModel> _book({String suffix = ''}) async {
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Путь человека через неизвестный лес' + suffix,
    author: 'Тест',
    chapters: [
      'В начале путешествия путник нашёл старинный ключ возле '
          'колодца и услышал от незнакомца предложение помощи.',
      'Позднее герой увидел множество троп и решил '
          'найти иной выход, не принимая неизвестных условий.',
    ],
  ));
  final scan = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final candidate = SemanticCandidate.propose(
        source, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16,
        endUtf16: chunk.startUtf16 + 60,
        label: 'Возможное событие',
        uncertainty: 'Порядок рассказа не доказывает смысл или причину.',
      );
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [candidate],
        ),
        totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final reviewed = await scan.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 12,
  );
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(reviewed),
  );
}

ZaiStoryDilemmaPreview _preview(NarrativeBookModel book) {
  final proposal = StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: book.events.first.id,
    outcomeEventId: book.events.last.id,
    kind: StoryDilemmaKind.exchange,
    dilemma: 'Принять помощь с условием или искать другой способ',
    acceptIntent: 'Согласиться на условие ради немедленной помощи',
    refuseIntent: 'Отказаться от условия и выбрать самостоятельный путь',
    followupGoal: 'Выполнить обещанное действие по принятому условию',
    finishOriginalIntent: 'Исполнить принятое ранее обязательство',
    originalEnding: 'Герой пришёл к одному из возможных концов',
    alternativeSearchGoal: 'Искать другой путь без принятого условия',
    searchIntent: 'Осмотреть ближайшие тропы и расспросить странников',
    alternativeDiscovery: 'Открылась иная возможность решения задачи',
    useDiscoveryIntent: 'Воспользоваться открытой возможностью без обещания',
    alternativeEnding: 'История завершилась по самостоятельной линии',
  );
  return ZaiStoryDilemmaPreview(
    proposal: proposal,
    plan: StoryPlanDilemmaGenerator.propose(book, proposal),
    sampledEventCount: 2,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one paid GLM proposal can be restored after app restart, with no '
      'new provider call and no false READY status', () async {
    final book = await _book();
    final repository = MemorySourceAnalysisCheckpointRepository();
    final old = StoryPlanDraftCheckpointStore(repository: repository);
    final proposal = _preview(book);
    await old.save(book, proposal);
    final saved = await repository.read(book.sourceFingerprint);
    expect(saved, isNotNull);
    expect(saved, isNot(contains(book.events.first.source.quote)));
    expect(saved, isNot(contains(book.events.last.source.quote)));
    expect(saved, isNot(contains('READY_TO_PLAY')));
    final next = StoryPlanDraftCheckpointStore(repository: repository);
    final restored = await next.read(book);
    expect(restored!.foundCandidate, true);
    expect(restored.sampledEventCount, 2);
    expect(restored.proposal!.encode(), proposal.proposal!.encode());
    expect(restored.plan!.encode(), proposal.plan!.encode());
    expect(restored.isPlayableRpg, false);
    await next.delete(book);
    expect(await next.read(book), isNull);
  });

  test('a no-candidate result also persists without fabricating a story',
      () async {
    final book = await _book();
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = StoryPlanDraftCheckpointStore(repository: repo);
    await store.save(book, const ZaiStoryDilemmaPreview(
      proposal: null, plan: null, sampledEventCount: 2));
    final restored = await store.read(book);
    expect(restored!.foundCandidate, false);
    expect(restored.plan, isNull);
    expect(restored.proposal, isNull);
  });

  test('a different edition never inherits another book checkpoint',
      () async {
    final first = await _book();
    final other = await _book(suffix: ' другая редакция');
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = StoryPlanDraftCheckpointStore(repository: repo);
    await store.save(first, _preview(first));
    expect(await store.read(other), isNull);
    final raw = await repo.read(first.sourceFingerprint);
    await repo.write(other.sourceFingerprint, raw!);
    await expectLater(store.read(other), throwsFormatException);
  });

  test('forged READY bit and corrupted checksum are rejected locally',
      () async {
    final book = await _book();
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = StoryPlanDraftCheckpointStore(repository: repository);
    await store.save(book, _preview(book));
    final original = await repository.read(book.sourceFingerprint);
    final envelope = jsonDecode(original!) as Map<String, dynamic>;
    final body = Map<String, dynamic>.from(envelope['body'] as Map);
    body['ready_to_play'] = true;
    envelope['body'] = body;
    await repository.write(book.sourceFingerprint, jsonEncode(envelope));
    await expectLater(store.read(book), throwsFormatException);
    await repository.write(book.sourceFingerprint,
        original.substring(0, original.length - 1));
    await expectLater(store.read(book), throwsFormatException);
  });

  test('storage failure preserves prior draft, no phantom successful save',
      () async {
    final book = await _book();
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = StoryPlanDraftCheckpointStore(repository: repository);
    await store.save(book, _preview(book));
    final before = await repository.read(book.sourceFingerprint);
    repository.failNextWrite = true;
    await expectLater(store.save(book,
      const ZaiStoryDilemmaPreview(
          proposal: null, plan: null, sampledEventCount: 2)),
      throwsA(isA<FileSystemException>()));
    expect(await repository.read(book.sourceFingerprint), before);
    expect((await store.read(book))!.foundCandidate, true);
  });
}
