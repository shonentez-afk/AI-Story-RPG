import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ai_story_reader/act_dilemma_checkpoint_store.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_dilemma_gateway.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/story_plan_quality_gate.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index([String change = '']) {
  const line = 'История рассказывает о путнике, который заметил '
      'новую тропу и спросил стража, какие условия ждут '
      'его на этой дороге. Он ещё не принимал решений. ';
  return BookSourceIndexer.index(ImportedBook(
    title: 'События по частям и их сохранение',
    author: 'Тест',
    chapters: [
      List.filled(4, line).join(' '),
      List.filled(4, line).join(' '),
      List.filled(4, line).join(' ') + change,
    ],
  ));
}

Future<NarrativeBookModel> _model(BookSourceIndex index) async {
  final scan = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, title) async {
      final chunk = window.chunks.first;
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [
            for (var i = 0; i < 2; i++)
              SemanticCandidate.propose(
                source, chunk,
                category: SemanticCategory.event,
                startUtf16: chunk.startUtf16 + i * 86,
                endUtf16: chunk.startUtf16 + i * 86 + 60,
                label: 'Событие, ещё не проверенное по смыслу',
                uncertainty: 'Причина и время в мире неизвестны.',
              ),
          ],
        ),
        totalSuggestions: 2, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final analyzed = await scan.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 64,
  );
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(analyzed),
  );
}

ActDilemmaCandidate _draft(
    NarrativeBookModel book, BookwideActPlan map, int index,
    {bool noCandidate = false}) {
  final manifest = ActDilemmaConsentManifest.fromAct(
    book: book, bookMap: map, actId: map.acts[index].id,
  );
  if (noCandidate) {
    return ActDilemmaCandidate(
      actId: manifest.actId,
      preview: ZaiStoryDilemmaPreview(
        proposal: null,
        plan: null,
        sampledEventCount: manifest.eventIds.length,
      ),
      quality: null,
    );
  }
  final proposal = StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: manifest.eventIds.first,
    outcomeEventId: manifest.eventIds.last,
    kind: StoryDilemmaKind.disclosure,
    dilemma: 'Согласиться на предложение или найти другой игровой путь?',
    acceptIntent: 'Согласиться на предлагаемое игровое условие',
    refuseIntent: 'Отказаться от условий и продолжить поиск',
    followupGoal: 'Разобраться с последствиями принятого игрового выбора',
    finishOriginalIntent: 'Исполнить только добровольно принятое решение',
    originalEnding: 'Завершить одну из предлагаемых игровых линий',
    alternativeSearchGoal: 'Искать альтернативный путь без обещания',
    searchIntent: 'Исследовать окружение и задавать вопросы путникам',
    alternativeDiscovery: 'Возникает новая игровая возможность для героя',
    useDiscoveryIntent: 'Применить новую возможность без прежнего условия',
    alternativeEnding: 'Завершить другую вымышленную игровую линию',
  );
  final preview = ZaiStoryDilemmaPreview(
    proposal: proposal,
    plan: StoryPlanDilemmaGenerator.propose(book, proposal),
    sampledEventCount: manifest.eventIds.length,
  );
  return ActDilemmaCandidate(
    actId: manifest.actId, preview: preview,
    quality: StoryPlanQualityGate.assess(book: book, preview: preview),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two separately generated act candidates survive reopening '
      'in a private per-book checkpoint with no original quotes', () async {
    final index = _index();
    final book = await _model(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = ActDilemmaCheckpointStore(repository: repository);
    await store.save(book: book, bookMap: map,
        candidate: _draft(book, map, 1));
    await store.save(book: book, bookMap: map,
        candidate: _draft(book, map, 0));
    final record = await repository.read(book.sourceFingerprint);
    expect(record, isNotNull);
    expect(record, isNot(contains(book.events.first.source.quote)));
    expect(record, isNot(contains(book.title)));
    expect(record, isNot(contains('READY_TO_PLAY')));
    final restarted = ActDilemmaCheckpointStore(repository: repository);
    final recovered = await restarted.readAll(book: book, bookMap: map);
    expect(recovered, hasLength(2));
    expect(recovered.map((c) => c.actId).toList(),
        [map.acts[0].id, map.acts[1].id]);
    expect(recovered.every((c) =>
        c.foundCandidate && c.quality!.passedFormalPreflight &&
        !c.readyToPlay), true);
    expect(() => recovered.clear(), throwsUnsupportedError);
    final rebuilt = ActDilemmaProposalGateway().composeLocal(
      index: index, bookMap: map, book: book,
      candidates: recovered,
    );
    expect(rebuilt.plan.situations, hasLength(14));
    expect(rebuilt.isReadyToInstall, false);
    await restarted.delete(book);
    expect(await restarted.readAll(book: book, bookMap: map), isEmpty);
  });

  test('no-suitable-dilemma is persisted as no candidate, never invented',
      () async {
    final index = _index();
    final book = await _model(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = ActDilemmaCheckpointStore(repository: repository);
    await store.save(book: book, bookMap: map,
        candidate: _draft(book, map, 1, noCandidate: true));
    final recovered = await store.readAll(book: book, bookMap: map);
    expect(recovered, hasLength(1));
    expect(recovered.single.foundCandidate, false);
    expect(recovered.single.quality, isNull);
    expect(recovered.single.preview.proposal, isNull);
  });

  test('wrong source edition and changed quote digest reject a reused file',
      () async {
    final index = _index();
    final book = await _model(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = ActDilemmaCheckpointStore(repository: repository);
    await store.save(book: book, bookMap: map,
        candidate: _draft(book, map, 0));
    final changedIndex = _index('Другая редакция');
    final changedBook = await _model(changedIndex);
    final changedMap = BookwideActPlanner.build(
        index: changedIndex, book: changedBook);
    expect(await store.readAll(book: changedBook, bookMap: changedMap),
        isEmpty);
    final old = await repository.read(book.sourceFingerprint);
    await repository.write(changedBook.sourceFingerprint, old!);
    await expectLater(store.readAll(
      book: changedBook, bookMap: changedMap,
    ), throwsFormatException);
  });

  test('tampering with candidate anchors is rejected even when checksum '
      'is recalculated; old saved checkpoint survives write failure',
      () async {
    final index = _index();
    final book = await _model(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = ActDilemmaCheckpointStore(repository: repository);
    await store.save(book: book, bookMap: map,
        candidate: _draft(book, map, 0));
    final previous = (await repository.read(book.sourceFingerprint))!;
    repository.failNextWrite = true;
    await expectLater(store.save(
      book: book, bookMap: map,
      candidate: _draft(book, map, 1),
    ), throwsA(isA<FileSystemException>()));
    expect(await repository.read(book.sourceFingerprint), previous);
    final envelope = jsonDecode(previous) as Map<String, dynamic>;
    final body = Map<String, dynamic>.from(envelope['body'] as Map);
    final entries = body['entries'] as List;
    final first = Map<String, dynamic>.from(entries.first as Map);
    first['excerpt_digest'] = 'not-the-approved-text';
    entries[0] = first;
    body['entries'] = entries;
    envelope['body'] = body;
    envelope['sha256'] =
        sha256.convert(utf8.encode(jsonEncode(body))).toString();
    await repository.write(book.sourceFingerprint, jsonEncode(envelope));
    await expectLater(store.readAll(
      book: book, bookMap: map,
    ), throwsFormatException);
  });
}
