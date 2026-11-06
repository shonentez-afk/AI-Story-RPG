import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_analysis_page.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/book_act_draft_page.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/story_plan_draft_checkpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PrivateStore implements SourceAnalysisCheckpointRepository {
  String? raw;
  int writes = 0;
  @override
  Future<String?> read(String fingerprint) async => raw;
  @override
  Future<void> write(String fingerprint, String text) async {
    writes++;
    raw = text;
  }
  @override
  Future<void> delete(String fingerprint) async { raw = null; }
}

BookSourceIndex _book() => BookSourceIndexer.index(ImportedBook(
  title: 'Тестовая сказка',
  author: 'Вымышленный автор',
  chapters: [
    'На поляне появились два путника, которые искали старую '
        'крепость и просили помощи у лесника в соседней деревне.',
    'На второй день путешествия путники вошли в замок '
        'и встретили стража, который знал дорогу к тайной башне.',
  ],
));

class _DilemmaStub extends ZaiStoryDilemmaProposalService {
  _DilemmaStub({this.returnDraft = false});
  final bool returnDraft;
  int requests = 0;

  @override
  Future<ZaiStoryDilemmaPreview> propose({
    required NarrativeBookModel book,
    required bool consentForTheseSampledQuotes,
    List<String>? approvedExactEventIds,
    String? approvedExcerptDigest,
    bool consentForBookTitle = false,
    ZaiPreviewCancellation? cancellation,
    void Function(int attempt, int total, String status)? onProgress,
  }) async {
    expect(consentForTheseSampledQuotes, true);
    expect(consentForBookTitle, false);
    expect(approvedExactEventIds, isNull);
    expect(approvedExcerptDigest, isNull);
    requests++;
    if (returnDraft) {
      final proposal = StoryDilemmaProposal(
        sourceFingerprint: book.sourceFingerprint,
        setupEventId: book.events.first.id,
        outcomeEventId: book.events.last.id,
        kind: StoryDilemmaKind.exchange,
        dilemma: 'Принять условие обмена или искать другую дорогу?',
        acceptIntent: 'Принять предложение и пообещать помочь',
        refuseIntent: 'Отказаться от условия и продолжить поиск',
        followupGoal: 'Разобраться с принятым обязательством',
        finishOriginalIntent: 'Исполнить согласованное ранее условие',
        originalEnding: 'Герой завершил предложенную линию истории',
        alternativeSearchGoal: 'Найти новый путь без обязательства',
        searchIntent: 'Осмотреть окрестности и спросить жителей',
        alternativeDiscovery: 'Найден иной вариант разрешения конфликта',
        useDiscoveryIntent: 'Воспользоваться возможностью без обещания',
        alternativeEnding: 'Другой исход без исполнения чужого условия',
      );
      return ZaiStoryDilemmaPreview(
        proposal: proposal,
        plan: StoryPlanDilemmaGenerator.propose(book, proposal),
        sampledEventCount: 2,
      );
    }
    return const ZaiStoryDilemmaPreview(
        proposal: null, plan: null, sampledEventCount: 2);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('whole-book upload needs informed active consent, cancel '
      'sends nothing and resume stays private', (tester) async {
    final index = _book();
    final store = _PrivateStore();
    var requests = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: store,
      preview: (index, window, token, includeTitle) async {
        requests++;
        expect(includeTitle, false);
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: ZaiSemanticPreviewService.providerId,
            providerVersion: ZaiSemanticPreviewService.providerVersion,
            sourceFingerprint: index.sourceFingerprint,
            chunkIds: [for (final chunk in window.chunks) chunk.id],
            candidates: const [],
          ),
          totalSuggestions: 0,
          rejectedCount: 0,
          rejectedNonRussian: 0,
        );
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: ZaiWholeBookAnalysisPage(index: index, analysis: analysis),
    ));
    await tester.pumpAndSettle();
    final go = find.byKey(const Key('whole-book-start'));
    expect(go, findsOneWidget);
    expect(find.textContaining('Обработано: 0 из 2'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(go);
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('whole-book-confirm-send'));
    final approve = find.byKey(const Key('whole-book-approve'));
    expect(consent, findsOneWidget);
    expect(tester.widget<FilledButton>(approve).onPressed, isNull);
    expect(find.textContaining('Внешний сервис Z.ai'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(store.raw, isNull);

    await tester.tap(go);
    await tester.pumpAndSettle();
    // AlertDialog content scrolls independently: the consent checkbox is
    // below the fold at the default 600dp test viewport.
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(approve).onPressed, isNotNull);
    await tester.tap(approve);
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(store.writes, 2);
    expect(find.textContaining('Обработано: 2 из 2'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('whole-book-notice')), 100,
      scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('не готовый сценарий'), findsWidgets);
    expect(find.byKey(const Key('whole-book-start')), findsNothing);
    final sourceMap = find.byKey(const Key('whole-book-act-summary'));
    await tester.scrollUntilVisible(
        sourceMap, 120, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(sourceMap);
    await tester.pumpAndSettle();
    expect(find.textContaining('все 0 найденных событий'),
        findsOneWidget);
    expect(find.byKey(const Key('whole-book-act-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed whole-book analysis opens the sequential plan '
      'without another cloud request', (tester) async {
    final index = BookSourceIndexer.index(ImportedBook(
      title: 'Книга с двумя частями',
      author: 'Тестовый автор',
      chapters: [
        List.filled(4, 'На поляне герои увидели мост, и незнакомец '
            'предложил помощь за обещание. ').join(' '),
        List.filled(4, 'После путешествия герои увидели замок, '
            'и страж показал другую дорогу. ').join(' '),
      ],
    ));
    var requests = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: _PrivateStore(),
      preview: (source, window, token, includeTitle) async {
        requests++;
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
                  label: 'Гипотеза события, не канон',
                  uncertainty: 'Смысл не подтверждён.',
                ),
            ],
          ),
          totalSuggestions: 2,
          rejectedCount: 0,
          rejectedNonRussian: 0,
        );
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: ZaiWholeBookAnalysisPage(index: index, analysis: analysis),
    ));
    await tester.pumpAndSettle();
    expect(requests, 0);
    await tester.tap(find.byKey(const Key('whole-book-start')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('whole-book-confirm-send'));
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-approve')));
    await tester.pumpAndSettle();
    expect(requests, greaterThanOrEqualTo(2));

    final continueButton = find.byKey(
        const Key('whole-book-act-draft-start'));
    await tester.scrollUntilVisible(continueButton, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Продолжить подготовку сценария'), findsOneWidget);
    final before = requests;
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.byType(BookActDraftPage), findsOneWidget);
    expect(requests, before);
    expect(find.byKey(const Key('act-draft-prepare-remaining')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen allows consent and disabled upload remains '
      'visible', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final index = _book();
    var requests = 0;
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: _PrivateStore(),
      preview: (i, w, t, title) async {
        requests++;
        throw StateError('Request must not be sent without consent');
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: ZaiWholeBookAnalysisPage(index: index, analysis: analysis),
      ),
    ));
    await tester.pumpAndSettle();
    final start = find.byKey(const Key('whole-book-start'));
    await tester.scrollUntilVisible(
      start, 120, scrollable: find.byType(Scrollable).first);
    // scrollUntilVisible may stop once the lazily built control exists,
    // even though its center is below the actual 760dp screen.
    // Move it fully into the hit-testable viewport before tapping.
    await tester.drag(
        find.byType(ListView).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(start.hitTestable(), findsOneWidget);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('whole-book-approve'))).onPressed, isNull);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('proposed routes show causal preflight while gameplay stays '
      'disabled pending semantic and prose review', (tester) async {
    final index = _book();
    final fake = _DilemmaStub(returnDraft: true);
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: _PrivateStore(),
      preview: (source, window, token, includeTitle) async {
        final chunk = window.chunks.first;
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: ZaiSemanticPreviewService.providerId,
            providerVersion: ZaiSemanticPreviewService.providerVersion,
            sourceFingerprint: source.sourceFingerprint,
            chunkIds: [for (final c in window.chunks) c.id],
            candidates: [
              SemanticCandidate.propose(
                source, chunk, category: SemanticCategory.event,
                startUtf16: chunk.startUtf16,
                endUtf16: chunk.startUtf16 + 60,
                label: 'Проверенная цитата для структурного черновика',
                uncertainty: 'Литературные связи не подтверждены.',
              ),
            ],
          ),
          totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
        );
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: ZaiWholeBookAnalysisPage(
          index: index, analysis: analysis, dilemmaService: fake,
          dilemmaCheckpoint: StoryPlanDraftCheckpointStore(
              repository: _PrivateStore())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-start')));
    await tester.pumpAndSettle();
    final initial = find.byKey(const Key('whole-book-confirm-send'));
    await tester.ensureVisible(initial);
    await tester.pumpAndSettle();
    await tester.tap(initial);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-approve')));
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('whole-book-propose-dilemma'));
    await tester.scrollUntilVisible(
      button, 120, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('whole-book-dilemma-consent'));
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-dilemma-approve')));
    await tester.pumpAndSettle();
    expect(fake.requests, 1);
    final preflight = find.byKey(const Key('whole-book-dilemma-preflight'));
    await tester.scrollUntilVisible(
      preflight, 100, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(preflight);
    await tester.pumpAndSettle();
    expect(find.textContaining('Проверка игровых условий: пройдена'),
        findsOneWidget);
    expect(find.textContaining('Готовность к установке и игре: НЕТ'),
        findsOneWidget);
    expect(find.byKey(const Key('whole-book-dilemma-readiness')),
        findsOneWidget);
    final coverage = find.byKey(const Key('whole-book-act-coverage'));
    await tester.scrollUntilVisible(
        coverage, 120, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(coverage);
    await tester.pumpAndSettle();
    expect(find.textContaining('использует 2 из 2'), findsOneWidget);
    expect(fake.requests, 1);
    final play = find.byKey(const Key('whole-book-quick-play'));
    // The CTA is ABOVE the report and was disposed by the lazy ListView.
    // Scroll upwards until the button is built before ensureVisible.
    await tester.scrollUntilVisible(
      play, -120, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    expect(find.text('Создать и играть в пробную RPG с развилкой'),
        findsOneWidget);
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(find.text('Пробная RPG по развилке'), findsOneWidget);
    expect(find.byKey(const Key('story-trial-review')), findsOneWidget);
    expect(find.byKey(const Key('story-trial-private-fiction')),
        findsOneWidget);
    // The new optional item-review control pushes Start below the small
    // viewport. Scroll to build it before reading the disabled state.
    final start = find.byKey(const Key('story-trial-start'));
    await tester.scrollUntilVisible(start, 120,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    expect(fake.requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft dilemma preview requires separate quote consent '
      'and never installs an invented game', (tester) async {
    final index = _book();
    final fake = _DilemmaStub();
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: _PrivateStore(),
      preview: (source, window, token, includeTitle) async {
        final chunk = window.chunks.first;
        final candidate = SemanticCandidate.propose(
          source, chunk,
          category: SemanticCategory.event,
          startUtf16: chunk.startUtf16,
          endUtf16: chunk.startUtf16 + 60,
          label: 'Предложенное событие по точной цитате',
          uncertainty: 'Смысл и причинность ещё не подтверждены.',
        );
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: ZaiSemanticPreviewService.providerId,
            providerVersion: ZaiSemanticPreviewService.providerVersion,
            sourceFingerprint: source.sourceFingerprint,
            chunkIds: [for (final c in window.chunks) c.id],
            candidates: [candidate],
          ),
          totalSuggestions: 1, rejectedCount: 0,
          rejectedNonRussian: 0,
        );
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: ZaiWholeBookAnalysisPage(
        index: index, analysis: analysis, dilemmaService: fake,
        dilemmaCheckpoint: StoryPlanDraftCheckpointStore(
            repository: _PrivateStore())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-start')));
    await tester.pumpAndSettle();
    final wholeConsent = find.byKey(const Key('whole-book-confirm-send'));
    await tester.ensureVisible(wholeConsent);
    await tester.pumpAndSettle();
    await tester.tap(wholeConsent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-approve')));
    await tester.pumpAndSettle();
    final trigger = find.byKey(const Key('whole-book-propose-dilemma'));
    await tester.scrollUntilVisible(
      trigger, 140, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    expect(fake.requests, 0);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byKey(const Key('whole-book-dilemma-consent')),
        findsOneWidget);
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('whole-book-dilemma-approve'))).onPressed,
        isNull);
    expect(fake.requests, 0);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(fake.requests, 0);

    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('whole-book-dilemma-consent'));
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('whole-book-dilemma-approve'))).onPressed,
        isNotNull);
    await tester.tap(find.byKey(const Key('whole-book-dilemma-approve')));
    await tester.pumpAndSettle();
    expect(fake.requests, 1);
    await tester.scrollUntilVisible(
      find.byKey(const Key('whole-book-notice')), 100,
      scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Подходящая причинная развилка'),
        findsWidgets);
    expect(find.byKey(const Key('whole-book-dilemma-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved GLM scenario survives reopening book with no repeat '
      'provider request and retains disabled full-game status',
      (tester) async {
    final index = _book();
    final sourceStore = _PrivateStore();
    final checkpointStore = _PrivateStore();
    final checkpoint = StoryPlanDraftCheckpointStore(
        repository: checkpointStore);
    final fake = _DilemmaStub(returnDraft: true);
    final analysis = ZaiAutoWholeBookAnalysis(
      repository: sourceStore,
      preview: (source, window, token, includeTitle) async {
        final chunk = window.chunks.first;
        return ZaiSemanticPreviewResult(
          batch: SemanticCandidateBatch(
            providerId: ZaiSemanticPreviewService.providerId,
            providerVersion: ZaiSemanticPreviewService.providerVersion,
            sourceFingerprint: source.sourceFingerprint,
            chunkIds: [for (final c in window.chunks) c.id],
            candidates: [
              SemanticCandidate.propose(
                source, chunk, category: SemanticCategory.event,
                startUtf16: chunk.startUtf16,
                endUtf16: chunk.startUtf16 + 60,
                label: 'Смысловое предложение с точной цитатой',
                uncertainty: 'Смысл ещё должен быть отдельно проверен.',
              ),
            ],
          ),
          totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
        );
      },
    );
    Widget page() => MaterialApp(
      home: ZaiWholeBookAnalysisPage(
        index: index,
        analysis: analysis,
        dilemmaService: fake,
        dilemmaCheckpoint: checkpoint,
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-start')));
    await tester.pumpAndSettle();
    final upload = find.byKey(const Key('whole-book-confirm-send'));
    await tester.ensureVisible(upload);
    await tester.pumpAndSettle();
    await tester.tap(upload);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-approve')));
    await tester.pumpAndSettle();
    final request = find.byKey(const Key('whole-book-propose-dilemma'));
    await tester.scrollUntilVisible(
      request, 120, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(request);
    await tester.pumpAndSettle();
    await tester.tap(request);
    await tester.pumpAndSettle();
    final approve = find.byKey(const Key('whole-book-dilemma-consent'));
    await tester.ensureVisible(approve);
    await tester.pumpAndSettle();
    await tester.tap(approve);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whole-book-dilemma-approve')));
    await tester.pumpAndSettle();
    expect(fake.requests, 1);
    expect(checkpointStore.raw, isNotNull);
    expect(checkpointStore.writes, 1);
    // Mimic closing then reopening the page. The new page gets only the
    // locally stored checkpoints; it MUST NOT make a new cloud request.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(fake.requests, 1);
    final restored = find.byKey(const Key('whole-book-notice'));
    await tester.scrollUntilVisible(restored, 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Повторная отправка книги в Z.ai не требуется'),
        findsWidgets);
    final readiness = find.byKey(const Key('whole-book-dilemma-preflight'));
    await tester.scrollUntilVisible(readiness, -100,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(readiness);
    await tester.pumpAndSettle();
    expect(find.textContaining('Проверка игровых условий: пройдена'),
        findsOneWidget);
    expect(fake.requests, 1);
    expect(tester.takeException(), isNull);
  });


}
