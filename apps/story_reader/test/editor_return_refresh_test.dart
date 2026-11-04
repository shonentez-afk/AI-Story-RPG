import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_analysis.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_index_preview_page.dart';
import 'package:ai_story_reader/source_editorial_review_page.dart';
import 'package:ai_story_reader/reviewed_story_editor_page.dart';
import 'package:ai_story_reader/multi_scene_editor_page.dart';
import 'package:ai_story_reader/private_game_readiness_panel.dart';
import 'package:ai_story_reader/source_narrative_review_panel.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingWorldGateway extends DeviceWorldLibraryGateway {
  int scans = 0;

  @override
  Future<List<WorldLibraryItem>> worlds() async {
    scans++;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('return from each preparation editor refreshes dependent panels '
      'without deleting the names checkpoint', (tester) async {
    tester.view.physicalSize = const Size(1000, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const book = ImportedBook(
      title: 'Контроль возврата', author: 'Тест',
      chapters: ['Мария открыла дверь.', 'Мария встретила Ивана.'],
    );
    final index = BookSourceIndexer.index(book);
    final mentions = MemorySourceAnalysisCheckpointRepository();
    final gateway = _RecordingWorldGateway();
    final initial = SourceAnalysisSession.create(index);
    await mentions.write(index.sourceFingerprint, initial.encode());
    await tester.pumpWidget(MaterialApp(
      home: SourceIndexPreviewPage(
        book: book,
        indexer: (_) async => index,
        checkpointRepository: mentions,
        worldGateway: gateway,
        checkpointDecoder: (i, raw) async =>
            SourceAnalysisSession.decode(i, raw),
      ),
    ));
    await tester.pumpAndSettle();

    // Advanced source and multi-scene editors are intentionally collapsed.
    // Open them explicitly before verifying the old checkpoint refresh flow.
    final advanced = find.byKey(const Key('prepare-advanced-mode'));
    await tester.scrollUntilVisible(advanced, 180,
        scrollable: find.byType(Scrollable).first, maxScrolls: 45);
    await tester.ensureVisible(advanced);
    await tester.pumpAndSettle();
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    for (final groupKey in ['prepare-advanced-evidence',
        'prepare-advanced-story']) {
      final group = find.byKey(Key(groupKey));
      await tester.scrollUntilVisible(group, 150,
          scrollable: find.byType(Scrollable).first, maxScrolls: 45);
      await tester.ensureVisible(group);
      await tester.pumpAndSettle();
      await tester.tap(group);
      await tester.pumpAndSettle();
    }

    final routes = <(String, Type)>[
      ('prepare-open-expanded-source-editor', SourceEditorialReviewPage),
      ('prepare-open-story-editor', ReviewedStoryEditorPage),
      ('prepare-open-multi-scene-editor', MultiSceneEditorPage),
    ];
    for (var revision = 0; revision < routes.length; revision++) {
      final (key, pageType) = routes[revision];
      final route = find.byKey(Key(key));
      await tester.scrollUntilVisible(route, 160,
          scrollable: find.byType(Scrollable).first, maxScrolls: 55);
      await tester.ensureVisible(route);
      await tester.pumpAndSettle();

      final priorNarrative = tester.widget<SourceNarrativeReviewPanel>(
          find.byType(SourceNarrativeReviewPanel)).key;
      final priorReadiness = tester.widget<PrivateGameReadinessPanel>(
          find.byType(PrivateGameReadinessPanel)).key;
      final tile = tester.widget<ListTile>(route);
      expect(tile.enabled, isTrue);
      tile.onTap!();
      tile.onTap!(); // Rapid double press cannot create a second route.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(pageType), findsOneWidget);

      // Close exactly one editor. The parent must rebuild from persisted
      // checkpoints and re-run the optional game package check.
      Navigator.of(tester.element(find.byType(pageType))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(pageType), findsNothing);
      final nextNarrative = tester.widget<SourceNarrativeReviewPanel>(
          find.byType(SourceNarrativeReviewPanel)).key;
      final nextReadiness = tester.widget<PrivateGameReadinessPanel>(
          find.byType(PrivateGameReadinessPanel)).key;
      expect(nextNarrative, isNot(priorNarrative));
      expect(nextReadiness, isNot(priorReadiness));
      expect(tester.widget<PrivateGameReadinessPanel>(
          find.byType(PrivateGameReadinessPanel)).checkOnOpen, isTrue);
      await tester.pumpAndSettle();
      expect(gateway.scans, revision + 1);
      expect(find.textContaining('Проверенной личной RPG'), findsOneWidget);
      expect(await mentions.read(index.sourceFingerprint), initial.encode());
    }
    expect(tester.takeException(), isNull);
  });
}
