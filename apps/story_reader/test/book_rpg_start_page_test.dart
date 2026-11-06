import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_rpg_start_page.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/quick_rpg_page.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_whole_book_analysis_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryCheckpoint implements SourceAnalysisCheckpointRepository {
  String? raw;

  @override
  Future<String?> read(String fingerprint) async => raw;

  @override
  Future<void> write(String fingerprint, String text) async {
    raw = text;
  }

  @override
  Future<void> delete(String fingerprint) async {
    raw = null;
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

    expect(find.byKey(const Key('rpg-start-offline')), findsOneWidget);
    expect(find.byKey(const Key('rpg-start-ai')), findsOneWidget);
    expect(indexingCalls, 0);
    expect(networkCalls, 0);

    await tester.tap(find.byKey(const Key('rpg-start-ai')));
    await tester.pumpAndSettle();

    expect(find.byType(ZaiWholeBookAnalysisPage), findsOneWidget);
    expect(find.byKey(const Key('whole-book-start')), findsOneWidget);
    expect(networkCalls, 0);
    expect(indexingCalls, 1);
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
    await tester.tap(find.byKey(const Key('rpg-start-ai')));
    await tester.pumpAndSettle();
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
    expect(find.byKey(const Key('rpg-start-offline')), findsOneWidget);
    final ai = find.byKey(const Key('rpg-start-ai'));
    await tester.scrollUntilVisible(ai, 160,
        scrollable: find.byType(Scrollable).first);
    expect(ai, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
