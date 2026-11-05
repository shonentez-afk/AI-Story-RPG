import 'package:ai_story_reader/act_dilemma_checkpoint_store.dart';
import 'package:ai_story_reader/book_act_draft_page.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_dilemma_gateway.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index() =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Локальный путь и отдельные согласия',
      author: 'Учебная книга',
      chapters: [
        List.filled(4, 'Однажды путник увидел большой '
            'сад с открытой калиткой. Прохожий предложил '
            'ему помощь, но ничего не подтвердил. ').join(' '),
        List.filled(4, 'На следующем пути он '
            'встретил лесника и увидел закрытую дверь. '
            'Впереди могло быть другое решение. ').join(' '),
      ],
    ));

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
                label: 'Возможное событие, ещё не канон',
                uncertainty: 'Причины ещё не проверены.',
              ),
          ],
        ),
        totalSuggestions: 2, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final review = await scan.analyze(
    index: index, approvedManifestDigest: consent.approvalDigest,
    explicitWholeBookConsent: true, maxWindowsPerRun: 64,
  );
  return NarrativeBookModel.fromExisting(
      index: index,
      outline: ZaiWholeBookEventOutline.build(review));
}

class _NoCandidateGateway extends ActDilemmaProposalGateway {
  int calls = 0;
  @override
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
    calls++;
    final manifest = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: bookMap, actId: actId);
    expect(explicitConsentForShownActQuotes, true);
    expect(approvedDigest, manifest.approvalDigest);
    return ActDilemmaCandidate(
      actId: actId,
      preview: ZaiStoryDilemmaPreview(
        proposal: null, plan: null,
        sampledEventCount: manifest.eventIds.length),
      quality: null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reopening multi-act editor makes ZERO cloud calls; '
      'declined quote consent sends nothing and explicit acceptance '
      'persists honest no-candidate outcome', (tester) async {
    final index = _index();
    final book = await _model(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final repository = MemorySourceAnalysisCheckpointRepository();
    final storage = ActDilemmaCheckpointStore(repository: repository);
    final gateway = _NoCandidateGateway();
    Widget page() => MaterialApp(
      home: BookActDraftPage(
        index: index, book: book, bookMap: map,
        gateway: gateway, checkpoint: storage),
    );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(gateway.calls, 0);
    expect(find.text('План по частям книги'), findsOneWidget);
    expect(find.textContaining('Никаких скрытых'), findsOneWidget);
    final button = find.byKey(const Key('act-draft-request-act_1_1'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Разрешить анализ этой части через Z.ai?'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('act-draft-approve'))).onPressed, isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(gateway.calls, 0);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('act-draft-quote-consent'));
    await tester.ensureVisible(consent);
    await tester.pumpAndSettle();
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('act-draft-approve')));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
    final saved = await storage.readAll(book: book, bookMap: map);
    expect(saved, hasLength(1));
    expect(saved.single.foundCandidate, false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
    expect((await storage.readAll(book: book, bookMap: map))
        .single.foundCandidate, false);
    expect(tester.takeException(), isNull);
  });
}
