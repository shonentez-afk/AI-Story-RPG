import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/private_game_readiness.dart';
import 'package:ai_story_reader/reviewed_story_composer.dart';
import 'package:ai_story_reader/native_private_bookworld_compiler.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:ai_story_reader/private_game_readiness_panel.dart';
import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReadOnlyGateway extends DeviceWorldLibraryGateway {
  _ReadOnlyGateway(this.entries, {this.archive});
  final List<WorldLibraryItem> entries;
  final Uint8List? archive;
  int exportCalls = 0;
  @override
  Future<List<WorldLibraryItem>> worlds() async => entries;
  @override
  Future<Uint8List> exportWorld(String worldHash) async {
    exportCalls++;
    if (archive == null) throw StateError('Missing archive');
    return archive!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final index = BookSourceIndexer.index(const ImportedBook(
      title: 'Частная история', author: 'Автор',
      chapters: ['Дверь была закрыта. Мария открыла дверь.']));

  test('no stored world does not imply playable story', () async {
    final gateway = _ReadOnlyGateway([]);
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.status, PrivatePlayability.notReady);
    expect(result.canStartPrivateGame, false);
    expect(result.canSharePublicly, false);
    expect(result.hasAiAuthoring, false);
    expect(gateway.exportCalls, 0);
  });

  test('different book world is skipped without ZIP inspection', () async {
    final gateway = _ReadOnlyGateway([
      const WorldLibraryItem(
        archiveHash: 'unrelated', bookworldId: 'original_demo',
        title: 'Оригинальное демо',
      ),
    ]);
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.canStartPrivateGame, false);
    expect(gateway.exportCalls, 0);
  });

  test('corrupt matching ZIP fails closed with no play button', () async {
    final gateway = _ReadOnlyGateway([
      WorldLibraryItem(
        archiveHash: 'broken',
        bookworldId: 'book_${index.sourceFingerprint.substring(0, 12)}_bad',
        title: 'Повреждённая адаптация',
      ),
    ], archive: Uint8List.fromList([1, 2, 3]));
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.canStartPrivateGame, false);
    expect(gateway.exportCalls, 1);
  });

  test('unbounded matching variants fail closed without scanning archives',
      () async {
    final gateway = _ReadOnlyGateway([
      for (var i = 0;
          i < PrivateGameReadinessVerifier.maxCandidatePackages + 1;
          i++)
        WorldLibraryItem(
          archiveHash: 'invalid_$i',
          bookworldId:
              'book_${index.sourceFingerprint.substring(0, 12)}_$i',
          title: 'Вариант $i',
        ),
    ]);
    final result = await PrivateGameReadinessVerifier.assess(index, gateway);
    expect(result.canStartPrivateGame, false);
    expect(gateway.exportCalls, 0);
  });

  test('real source-verified compiled private world unlocks offline play',
      () async {
    const book = ImportedBook(
      title: 'Проверяемая история', author: 'Автор',
      chapters: [
        'Дверь была закрыта. Мария открыла дверь.',
        'Дверь была открыта. Мария встретила Ивана.',
      ],
    );
    final sourceIndex = BookSourceIndexer.index(book);
    var session = StoryEvidenceReviewSession.create(sourceIndex);
    while (session.scannedChunks < sourceIndex.chunks.length) {
      session = session.scanNext(sourceIndex);
    }
    for (final evidence in session.graph.records) {
      session = session.review(
          sourceIndex, evidence.id, EvidenceStatus.confirmed);
    }
    final catalog = SourceSemanticCatalog.fromLocalEvidence(
        sourceIndex, session.graph);
    final beginning = catalog.assertions.firstWhere((a) =>
        a.evidenceIds.any((id) => session.graph.records.any(
            (e) => e.id == id && e.chapterIndex == 0)));
    final ending = catalog.assertions.firstWhere((a) =>
        a.evidenceIds.any((id) => session.graph.records.any(
            (e) => e.id == id && e.chapterIndex == 1)));
    final editorial = SemanticEditorialReviewSession.create(
        sourceIndex, catalog)
      .decide(catalog, beginning.id, SemanticEditorialVerdict.canonCandidate)
      .decide(catalog, ending.id, SemanticEditorialVerdict.canonCandidate);
    final draft = ReviewedStoryComposer.compose(
      index: sourceIndex, evidence: session.graph,
      catalog: catalog, editorial: editorial,
      openingAssertionId: beginning.id,
      endingAssertionId: ending.id,
      openingText: 'Перед закрытой дверью.',
      endingText: 'Мария встретила Ивана.',
      alternateEndingText: 'Вы решаете оставить дверь.',
      followBookChoice: 'Следовать событиям',
      changeFateChoice: 'Изменить судьбу',
    );
    final archive = await compileReviewedPrivateBookworldInWorker(
        sourceIndex, session.graph, catalog, editorial, draft);
    final verified = const PrivateBookworldImporter().inspect(archive);
    final gateway = _ReadOnlyGateway([
      WorldLibraryItem(
        archiveHash: verified.archiveSha256,
        bookworldId: verified.bookworldId,
        title: verified.blueprint.title,
      ),
    ], archive: archive);
    final status = await PrivateGameReadinessVerifier.assess(
        sourceIndex, gateway);
    expect(status.canStartPrivateGame, true);
    expect(status.world!.archiveHash, verified.archiveSha256);
    expect(status.canSharePublicly, false);
    expect(status.hasAiAuthoring, false);
    expect(gateway.exportCalls, 1);
  });

  testWidgets('readiness panel never invents installed game', (tester) async {
    final gateway = _ReadOnlyGateway([]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        PrivateGameReadinessPanel(index: index, gateway: gateway))));
    await tester.pump();
    expect(find.textContaining('Что уже готово для игры?'), findsOneWidget);
    expect(find.byKey(const Key('prepare-open-verified-private-rpg')),
        findsNothing);
    await tester.tap(find.byKey(const Key('prepare-recheck-game')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Проверенной личной RPG'), findsOneWidget);
    expect(find.byKey(const Key('prepare-open-verified-private-rpg')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
