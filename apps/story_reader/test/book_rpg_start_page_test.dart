import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/source_index_preview_page.dart';
import 'package:ai_story_reader/book_rpg_start_page.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:story_authoring/story_authoring.dart'
    show BookSourceSelection, BookChapter, BookBlock, BookBlockKind;
import 'package:ai_story_reader/quick_rpg_page.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_whole_book_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryCheckpoint implements SourceAnalysisCheckpointRepository {
  final saved = <String, String>{};

  @override
  Future<String?> read(String fingerprint) async => saved[fingerprint];

  @override
  Future<void> write(String fingerprint, String text) async {
    saved[fingerprint] = text;
  }

  @override
  Future<void> delete(String fingerprint) async {
    saved.remove(fingerprint);
  }
}

const _book = ImportedBook(
  title: 'Проверочная книга',
  author: 'Автор',
  chapters: [
    'Герой отправился в путешествие через далёкий лес, '
        'где его ждали совершенно новые испытания.',
    'Затем герой добрался до старого дома и встретил '
        'путешественника, который рассказал ему историю.',
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('one entry distinguishes honest offline and AI routes and '
      'never sends a network request on open', (tester) async {
    final index = BookSourceIndexer.index(_book);
    var indexingCalls = 0;
    var networkCalls = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: _MemoryCheckpoint(),
      preview: (index, window, token, includeTitle) async {
        networkCalls++;
        throw StateError('No cloud calls without consent.');
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: BookRpgStartPage(
        book: _book,
        gateway: const DeviceWorldLibraryGateway(background: false),
        indexer: (book) async {
          indexingCalls++;
          return index;
        },
        analysis: analysis,
      ),
    ));

    expect(find.byKey(const Key('rpg-start-unified-journey')),
        findsOneWidget);
    expect(find.byKey(const Key('rpg-start-primary-action')),
        findsOneWidget);
    expect(find.byKey(const Key('rpg-start-offline')), findsOneWidget);
    expect(find.byKey(const Key('rpg-start-ai')), findsOneWidget);
    expect(find.byKey(const Key('rpg-start-resume')), findsOneWidget);
    expect(find.byKey(const Key('rpg-start-literal-canon')),
        findsOneWidget);
    // Primary Resume must be physically tappable in the first viewport.
    final rect = tester.getRect(find.byKey(const Key('rpg-start-resume')));
    expect(rect.center.dy, lessThan(tester.view.physicalSize.height));
    expect(find.byKey(const Key('rpg-start-details')), findsOneWidget);
    expect(indexingCalls, 0);
    expect(networkCalls, 0);

    // The second card can be below the initial 600dp test viewport.
    await tester.ensureVisible(find.byKey(const Key('rpg-start-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rpg-start-ai')));
    await tester.pumpAndSettle();

    expect(find.byType(ZaiWholeBookAnalysisPage), findsOneWidget);
    expect(find.byKey(const Key('whole-book-start')), findsOneWidget);
    expect(networkCalls, 0);
    expect(indexingCalls, 1);
  });

  testWidgets('mode chosen at library entry reaches the real offline engine',
      (tester) async {
    final index = BookSourceIndexer.index(_book);
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (_) async => index,
    )));
    await tester.ensureVisible(find.byKey(const Key('rpg-start-quick-follow')));
    await tester.tap(find.byKey(const Key('rpg-start-quick-follow')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(
      find.byKey(const Key('rpg-start-quick-follow'))).selected, isTrue);
    await tester.ensureVisible(find.byKey(const Key('rpg-start-offline')));
    // The unified primary journey is above the legacy direct entry.
    // Scroll the actual screen, never tap an offscreen button.
    // This page eagerly builds its children, so a Finder already
    // matches the offscreen button and scrollUntilVisible stops too early.
    // Perform a physical viewport drag instead of relying on Finder presence.
    await tester.drag(find.byKey(const Key('rpg-start-scroll')),
        const Offset(0, -600));
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('rpg-start-offline'));
    expect(tester.getRect(action).center.dy,
        lessThan(tester.view.physicalSize.height));
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(QuickRpgPage), findsOneWidget);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const Key('quick-rpg-follow-book'))).selected, isTrue);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const Key('quick-rpg-change-fate'))).selected, isFalse);
  });

  testWidgets('offline path remains available without network or AI setup',
      (tester) async {
    final index = BookSourceIndexer.index(_book);
    await tester.pumpWidget(MaterialApp(
      home: BookRpgStartPage(
        book: _book,
        gateway: const DeviceWorldLibraryGateway(background: false),
        indexer: (_) async => index,
      ),
    ));
    await tester.tap(find.byKey(const Key('rpg-start-offline')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickRpgPage), findsOneWidget);
    expect(find.byKey(const Key('quick-rpg-follow-book')), findsOneWidget);
    expect(find.byKey(const Key('quick-rpg-change-fate')), findsOneWidget);
  });

  testWidgets('index failure is visible and retryable, not a hidden POST',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BookRpgStartPage(
        book: _book,
        gateway: const DeviceWorldLibraryGateway(background: false),
        indexer: (_) async => throw const FormatException('index broken'),
      ),
    ));
    // The second card can be below the initial 600dp test viewport.
    await tester.ensureVisible(find.byKey(const Key('rpg-start-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rpg-start-ai')));
    await tester.pumpAndSettle();
    // Error follows the two mode cards and must remain scroll-reachable.
    await tester.scrollUntilVisible(
        find.byKey(const Key('rpg-start-error')), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('rpg-start-error')), findsOneWidget);
    expect(find.byKey(const Key('rpg-start-ai')), findsOneWidget);
  });

  testWidgets('both routes remain reachable on a 320dp screen at 200% text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: BookRpgStartPage(
          book: _book,
          gateway: DeviceWorldLibraryGateway(background: false),
        ),
      ),
    ));
    final scroll = find.byType(Scrollable).first;
    // ListView is lazy: at 320dp and 200% text even the first button
    // can start below the viewport and is not yet built.
    final offline = find.byKey(const Key('rpg-start-offline'));
    await tester.scrollUntilVisible(offline, 120, scrollable: scroll);
    expect(offline, findsOneWidget);
    final ai = find.byKey(const Key('rpg-start-ai'));
    await tester.scrollUntilVisible(ai, 120, scrollable: scroll);
    expect(ai, findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('rpg-start-resume')), 120,
        scrollable: scroll);
    final resume = find.byKey(const Key('rpg-start-resume'));
    expect(resume, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume reads exact local checkpoint and never repeats a POST',
      (tester) async {
    final index = BookSourceIndexer.index(_book);
    final repository = _MemoryCheckpoint();
    var previewCalls = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: repository,
      preview: (source, window, token, includeTitle) async {
        previewCalls++;
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
                label: 'Встреча из книги',
                uncertainty: 'Редактор не проверил интерпретацию.'),
            ],
          ),
          totalSuggestions: 1,
          rejectedCount: 0, rejectedNonRussian: 0,
        );
      },
    );
    final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
    final previous = await analysis.analyze(index: index,
      approvedManifestDigest: manifest.approvalDigest,
      explicitWholeBookConsent: true, maxWindowsPerRun: 1);
    expect(previous.progress.completed, 1);
    expect(previewCalls, 1);
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (_) async => index,
      analysis: analysis,
    )));
    final resume = find.byKey(const Key('rpg-start-resume'));
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(find.byType(ZaiWholeBookAnalysisPage), findsOneWidget);
    expect(previewCalls, 1); // Reading is never a model POST.
    expect(repository.saved, contains(index.sourceFingerprint));
    expect(tester.takeException(), isNull);
  });

  testWidgets('absent and foreign edition checkpoints never claim Resume',
      (tester) async {
    final index = BookSourceIndexer.index(_book);
    final repository = _MemoryCheckpoint();
    var calls = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: repository,
      preview: (source, window, token, title) async {
        calls++;
        throw StateError('No silent model traffic');
      },
    );
    // Same title does not equate two source editions.
    final other = BookSourceIndexer.index(const ImportedBook(
      title: 'Проверочная книга', author: 'Автор',
      chapters: ['Совершенно другая редакция сказки.'],
    ));
    await repository.write(other.sourceFingerprint, '{"old":"edition"}');
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (_) async => index,
      analysis: analysis,
      manualCheckpointRepository: repository,
    )));
    await tester.ensureVisible(find.byKey(const Key('rpg-start-resume')));
    await tester.tap(find.byKey(const Key('rpg-start-resume')));
    await tester.pumpAndSettle();
    expect(find.byType(BookRpgStartPage), findsOneWidget);
    expect(find.textContaining('нет сохранённого анализа'), findsOneWidget);
    expect(calls, 0);
    expect(repository.saved[other.sourceFingerprint], '{"old":"edition"}');
    expect(tester.takeException(), isNull);
  });


  testWidgets('Resume reopens the same local editor if only offline source '
      'checkpoint exists, without Z.ai consent or model calls',
      (tester) async {
    final index = BookSourceIndexer.index(_book);
    final aiStore = _MemoryCheckpoint();
    final localStore = _MemoryCheckpoint();
    final session = SourceAnalysisSession.create(index)
        .processBatch(index, limit: 1);
    expect(session.processedCount, 1);
    await localStore.write(index.sourceFingerprint, session.encode());
    var cloudCalls = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: aiStore,
      preview: (source, window, token, title) async {
        cloudCalls++;
        throw StateError('Resume must be local');
      },
    );
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (_) async => index,
      analysis: analysis,
      manualCheckpointRepository: localStore,
      manualCheckpointDecoder: (source, raw) async =>
          SourceAnalysisSession.decode(source, raw),
    )));
    final resume = find.byKey(const Key('rpg-start-resume'));
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pump();
    // Workers validate the saved source evidence independently.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(SourceIndexPreviewPage), findsOneWidget);
    expect(await localStore.read(index.sourceFingerprint), session.encode());
    expect(cloudCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty local checkpoint is not misrepresented as progress',
      (tester) async {
    final index = BookSourceIndexer.index(_book);
    final localStore = _MemoryCheckpoint();
    final empty = SourceAnalysisSession.create(index).encode();
    await localStore.write(index.sourceFingerprint, empty);
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (_) async => index,
      analysis: ZaiAutoWholeBookAnalysis(repository: _MemoryCheckpoint()),
      manualCheckpointRepository: localStore,
      manualCheckpointDecoder: (source, raw) async =>
          SourceAnalysisSession.decode(source, raw),
    )));
    await tester.ensureVisible(find.byKey(const Key('rpg-start-resume')));
    await tester.tap(find.byKey(const Key('rpg-start-resume')));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(BookRpgStartPage), findsOneWidget);
    expect(find.textContaining('ещё не содержит сохранённых'), findsOneWidget);
    expect(await localStore.read(index.sourceFingerprint), empty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt same-edition checkpoint is preserved, never sent',
      (tester) async {
    final index = BookSourceIndexer.index(_book);
    final repository = _MemoryCheckpoint();
    await repository.write(index.sourceFingerprint, '{damaged');
    var calls = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: repository,
      preview: (source, window, token, title) async {
        calls++;
        throw StateError('No auto retry');
      },
    );
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book, indexer: (_) async => index,
      gateway: const DeviceWorldLibraryGateway(background: false),
      analysis: analysis,
    )));
    await tester.ensureVisible(find.byKey(const Key('rpg-start-resume')));
    await tester.tap(find.byKey(const Key('rpg-start-resume')));
    await tester.pumpAndSettle();
    expect(find.byType(BookRpgStartPage), findsOneWidget);
    expect(find.textContaining('Черновик не удалён'), findsOneWidget);
    expect(await repository.read(index.sourceFingerprint), '{damaged');
    expect(calls, 0);
  });

  testWidgets('numbered folklore variants default to one exact edition '
      'and keep the imported collection intact', (tester) async {
    const book = ImportedBook(
      title: 'Морозко', author: 'А. Н. Афанасьев',
      chapters: [
        'Первая редакция. Старик встретил Морозко и сделал выбор.',
        'Вторая редакция. Другой рассказ о морозном испытании.',
      ],
      structuredChapters: [
        BookChapter(id: 'one', blocks: [
          BookBlock(kind: BookBlockKind.heading,
              text: 'Морозко — вариант № 95'),
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Первая редакция. Старик встретил Морозко и сделал выбор.'),
        ]),
        BookChapter(id: 'two', blocks: [
          BookBlock(kind: BookBlockKind.heading,
              text: 'Морозко — вариант № 96'),
          BookBlock(kind: BookBlockKind.paragraph,
              text: 'Вторая редакция. Другой рассказ о морозном испытании.'),
        ]),
      ],
    );
    expect(BookSourceSelection.defaultChapter(book), 0);
    ImportedBook? passed;
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (selected) async {
        passed = selected;
        return BookSourceIndexer.index(selected);
      },
    )));
    expect(find.textContaining('Для RPG: Морозко — вариант № 95'),
        findsOneWidget);
    final ai = find.byKey(const Key('rpg-start-ai'));
    await tester.ensureVisible(ai);
    await tester.tap(ai);
    // The route below the newly pushed analysis screen keeps a real
    // LinearProgressIndicator while Navigator.push is pending. It must NOT
    // make this test wait for every animation on every route to settle.
    // Pump the route transition only; still inspect the actual destination,
    // the edition supplied to the indexer and the unmodified source book.
    for (var attempt = 0; attempt < 20 &&
        find.byType(ZaiWholeBookAnalysisPage).evaluate().isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ZaiWholeBookAnalysisPage), findsOneWidget);
    expect(passed, isNotNull);
    expect(passed!.chapters, hasLength(1));
    expect(passed!.chapters.single, book.chapters[0]);
    expect(passed!.title, contains('вариант № 95'));
    expect(book.chapters, hasLength(2));
  });


  testWidgets('literal CANON always reviews the full imported book '
      'before writing anything; cancel does not launch a campaign',
      (tester) async {
    var indexCount = 0;
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (book) async {
        indexCount++;
        expect(book.chapters.length, 2);
        return BookSourceIndexer.index(book);
      },
    )));
    final action = find.byKey(const Key('rpg-start-literal-canon'));
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    // The page deliberately shows an indeterminate progress animation
    // while the confirmation dialog is open. Never pumpAndSettle then.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(indexCount, 1);
    expect(find.text('Создать CANON всей книги?'), findsOneWidget);
    expect(find.textContaining('Глав: 2, фрагментов: 2'),
        findsOneWidget);
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(find.text('Создать CANON всей книги?'), findsNothing);
    expect(find.byKey(const Key('rpg-start-literal-canon')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one primary entry reuses the existing offline client',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: BookRpgStartPage(
      book: _book,
      gateway: const DeviceWorldLibraryGateway(background: false),
      indexer: (book) async => BookSourceIndexer.index(book),
    )));
    final chip = find.byKey(const Key('rpg-start-path-quick'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final primary = find.byKey(const Key('rpg-start-primary-action'));
    await tester.ensureVisible(primary);
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(find.byType(QuickRpgFromBookPage), findsOneWidget);
  });

}
