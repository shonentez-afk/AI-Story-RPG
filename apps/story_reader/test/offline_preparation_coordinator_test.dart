import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/offline_preparation_coordinator.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:ai_story_reader/source_index_preview_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const book = ImportedBook(
    title: 'Короткий авторский рассказ', author: 'Тест',
    chapters: [
      'Его звали Артем. Дверь была закрыта. Мария открыла дверь.',
      'В городе Тула дверь была открыта. Мария встретила Ивана.',
      'Её звали Ольга. Мария покинула город.',
    ],
  );

  late BookSourceIndex index;
  late MemorySourceAnalysisCheckpointRepository names;
  late MemorySourceAnalysisCheckpointRepository events;
  late MemorySourceAnalysisCheckpointRepository semantics;
  late OfflinePreparationCoordinator coordinator;

  setUp(() {
    index = BookSourceIndexer.index(book);
    names = MemorySourceAnalysisCheckpointRepository();
    events = MemorySourceAnalysisCheckpointRepository();
    semantics = MemorySourceAnalysisCheckpointRepository();
    coordinator = OfflinePreparationCoordinator(
      mentionsRepository: names, narrativeRepository: events,
      catalogRepository: semantics,
      mentionsProcessor: (i, current) async =>
          current.processBatch(i, limit: 1),
      narrativeProcessor: (i, current) async =>
          current.scanNext(i, limit: 1),
      catalogProcessor: (i, graph) async =>
          SourceSemanticCatalog.fromLocalEvidence(i, graph),
      mentionsEncoder: (current) async => current.encode(),
      mentionsDecoder: (i, raw) async =>
          SourceAnalysisSession.decode(i, raw),
      narrativeEncoder: (current) async => current.encode(),
      narrativeDecoder: (i, raw) async =>
          StoryEvidenceReviewSession.decode(i, raw),
      catalogDecoder: (i, graph, raw) async =>
          SourceSemanticCatalog.decode(i, graph, raw),
    );
  });

  test('single action safely resumes in ordered durable stages', () async {
    final recorded = <OfflinePreparationProgress>[];
    var stop = false;
    final partial = await coordinator.run(index,
      shouldPause: () => stop,
      onProgress: (progress) {
        recorded.add(progress);
        if (progress.stage == OfflinePreparationStage.names &&
            progress.completed == 1) {
          stop = true;
        }
      },
    );
    expect(partial.paused, isTrue);
    expect(partial.mentions.processedCount, 1);
    expect(partial.mentions.canPublishBookworld, isFalse);
    expect(await names.read(index.sourceFingerprint), isNotNull);
    expect(await events.read(index.sourceFingerprint), isNull);
    expect(await semantics.read(index.sourceFingerprint), isNull);
    expect(recorded.any((x) => x.stage == OfflinePreparationStage.paused), true);

    stop = false;
    final resumed = await coordinator.run(index,
      shouldPause: () => stop,
      onProgress: (progress) {
        if (progress.stage == OfflinePreparationStage.narrative &&
            progress.completed == 1) stop = true;
      },
    );
    expect(resumed.paused, isTrue);
    expect(resumed.mentions.pendingCount, 0);
    expect(resumed.narrative?.scannedChunks, 1);
    expect(await events.read(index.sourceFingerprint), isNotNull);
    expect(await semantics.read(index.sourceFingerprint), isNull);
    stop = false;
    final complete = await coordinator.run(index);
    expect(complete.complete, isTrue);
    expect(complete.catalog, isNotNull);
    expect(complete.catalog!.assertions, isNotEmpty);
    expect(complete.catalog!.canPublishBookworld, isFalse);
    expect(complete.canPublishBookworld, isFalse);
    expect(complete.narrative!.scannedChunks, index.chunks.length);
    expect(await semantics.read(index.sourceFingerprint),
        complete.catalog!.encode());

    final repeat = await coordinator.run(index);
    expect(repeat.complete, isTrue);
    expect(repeat.catalog!.encode(), complete.catalog!.encode());
  });

  test('failed write creates no phantom progress and retry starts correctly',
      () async {
    names.failNextWrite = true;
    await expectLater(coordinator.run(index),
        throwsA(isA<Exception>()));
    expect(await names.read(index.sourceFingerprint), isNull);
    expect(await events.read(index.sourceFingerprint), isNull);
    expect(await semantics.read(index.sourceFingerprint), isNull);
    final recovered = await coordinator.run(index);
    expect(recovered.complete, isTrue);
  });

  test('corrupt historical narrative checkpoint remains unchanged',
      () async {
    await events.write(index.sourceFingerprint, 'not narrative JSON');
    await expectLater(coordinator.run(index), throwsFormatException);
    expect(await events.read(index.sourceFingerprint), 'not narrative JSON');
    expect(await semantics.read(index.sourceFingerprint), isNull);
    expect(await names.read(index.sourceFingerprint), isNotNull);
  });

  test('existing manual mention decisions survive complete run', () async {
    final initial = SourceAnalysisSession.create(index)
        .processBatch(index);
    final candidate = initial.mentions.first;
    final reviewed = initial.decide(candidate.id, MentionDecision.accepted);
    await names.write(index.sourceFingerprint, reviewed.encode());
    final result = await coordinator.run(index);
    expect(result.complete, true);
    expect(result.mentions.mentions.where(
        (m) => m.decision == MentionDecision.accepted).length, 1);
    expect(result.narrative?.graph.records, isNotEmpty);
  });

  test('no stage may silently overwrite a corrupt/stale semantic catalog',
      () async {
    await semantics.write(index.sourceFingerprint, 'spoofed');
    await expectLater(coordinator.run(index), throwsFormatException);
    expect(await semantics.read(index.sourceFingerprint), 'spoofed');
    expect(await events.read(index.sourceFingerprint), isNotNull);
  });


  test('source-backed aliases, characters, locations and meetings stay inferred',
      () {
    const namedBook = ImportedBook(
      title: 'Имена и отношения', author: 'Собственный тест',
      chapters: [
        'Алексей по прозвищу Серый. Его звали Антон. '
        'В городе Москва Маша встретила Ивана.',
      ],
    );
    final indexed = BookSourceIndexer.index(namedBook);
    final mentions = SourceAnalysisSession.create(indexed)
        .processBatch(indexed);
    var approved = mentions;
    for (final candidate in mentions.mentions) {
      approved = approved.decide(candidate.id, MentionDecision.accepted);
    }
    final evidence = StoryEvidenceReviewSession.create(indexed)
        .syncAcceptedMentions(indexed, approved)
        .scanNext(indexed);
    final result =
        SourceSemanticCatalog.fromLocalEvidence(indexed, evidence.graph);
    final kinds = result.assertions.map((a) => a.kind.name).toSet();
    expect(kinds.contains('character'), true);
    expect(kinds.contains('location'), true);
    expect(kinds.contains('alias'), true);
    expect(kinds.contains('relation'), true);
    expect(result.assertions.every((a) => !a.isVerifiedWorldTruth), true);
    expect(result.canPublishBookworld, false);
  });

  testWidgets('main page offers one local action, not a playable RPG button',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: SourceIndexPreviewPage(
        book: book,
        indexer: (b) async => BookSourceIndexer.index(b),
        checkpointRepository: names,
        checkpointEncoder: (value) async => value.encode(),
        checkpointDecoder: (i, raw) async =>
            SourceAnalysisSession.decode(i, raw),
        batchProcessor: (i, value) async => value.processBatch(i),
        localPreparationCoordinator: coordinator,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Локальная подготовка книги'), findsOneWidget);
    expect(find.text('Выполнить локальную подготовку'), findsOneWidget);
    expect(find.text('Полная RPG по всей книге'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prepare-offline-all')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Локальный анализ завершён'), findsOneWidget);
    expect(find.textContaining('Это ещё не готовая RPG'), findsWidgets);
    expect((await semantics.read(index.sourceFingerprint)), isNotNull);
    expect(tester.takeException(), isNull);
  });
}
