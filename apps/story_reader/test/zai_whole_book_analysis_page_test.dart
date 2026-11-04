import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_analysis_page.dart';
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
}
