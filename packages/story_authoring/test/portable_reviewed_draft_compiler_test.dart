import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookworld_format/bookworld_format.dart';
import 'package:story_authoring/story_authoring.dart';
import 'package:test/test.dart';

void main() {
  const engine = BookAuthoringEngine();
  const compiler = PortableReviewedDraftCompiler();

  ({SourceLockedBook source, Map<String, dynamic> review})
      reviewedSyntheticBook() {
    const book = ImportedBook(
      title: 'Дверь и Волк', author: 'Автор',
      chapters: [
        'Артем по прозвищу Волк открыл дверь. Дверь была закрыта.',
        'Артем встретил Марию. Дверь была открыта.',
      ],
    );
    final source = engine.indexImported(book);
    final index = source.index;
    var evidence = StoryEvidenceReviewSession.create(index);
    while (evidence.scannedChunks < index.chunks.length) {
      evidence = evidence.scanNext(index);
    }
    for (final item in evidence.graph.records) {
      evidence = evidence.review(index, item.id, EvidenceStatus.confirmed);
    }
    final graph = evidence.graph;
    final catalog = SourceSemanticCatalog.fromLocalEvidence(index, graph);
    final events = catalog.assertions.where(
        (c) => c.kind == SemanticAssertionKind.event).toList();
    final byId = {for (final e in graph.records) e.id: e};
    final first = events.firstWhere(
        (c) => byId[c.evidenceIds.first]!.chapterIndex == 0);
    final last = events.firstWhere(
        (c) => byId[c.evidenceIds.first]!.chapterIndex == 1);
    final editorial = SemanticEditorialReviewSession.create(index, catalog)
        .decide(catalog, first.id, SemanticEditorialVerdict.canonCandidate)
        .decide(catalog, last.id, SemanticEditorialVerdict.canonCandidate);
    final draft = ReviewedStoryComposer.compose(
      index: index, evidence: graph, catalog: catalog,
      editorial: editorial, openingAssertionId: first.id,
      endingAssertionId: last.id,
      openingText: 'Игрок стоит у запертой двери.',
      endingText: 'Игрок встречает друга.',
      alternateEndingText: 'Игрок уходит другой дорогой.',
      followBookChoice: 'Продолжить путь',
      changeFateChoice: 'Повернуть назад',
    );
    return (
      source: source,
      review: <String, dynamic>{
        'format': PortableReviewedDraftCompiler.format,
        'source_fingerprint': index.sourceFingerprint,
        'evidence': evidence.encode(),
        'catalog': catalog.encode(),
        'editorial': editorial.encode(),
        'draft': draft.encode(),
        'hero_name': 'Игрок',
      },
    );
  }

  test('source + reviewed checkpoints -> offline v3 without Flutter or model',
      () async {
    final fixture = reviewedSyntheticBook();
    final archive = await compiler.build(
        source: fixture.source, review: fixture.review);
    final inspected = const RichPrivateBookworldImporter().inspect(archive);
    expect(inspected.sourceFingerprint, fixture.source.index.sourceFingerprint);
    expect(inspected.blueprint.actors, {'player'});
    expect(inspected.blueprint.scenes.length, 3);
    expect(inspected.canDistributePublicly, false);
    expect(inspected.requiresNetwork, false);
    final out = File(
        '../../artifacts/bookworld/story_authoring_review_bundle_fixture.bworld');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(archive);
  });

  test('edition mismatch, missing review and fabricated NPC consent fail closed',
      () async {
    final fixture = reviewedSyntheticBook();
    final foreign = engine.parseAndIndex('other.txt',
        Uint8List.fromList(utf8.encode('Другой текст')));
    await expectLater(compiler.build(
        source: foreign, review: fixture.review), throwsFormatException);
    final missing = Map<String, dynamic>.from(fixture.review)
      ..remove('editorial');
    await expectLater(compiler.build(
        source: fixture.source, review: missing), throwsFormatException);
    final fakeNpc = Map<String, dynamic>.from(fixture.review)
      ..['npc'] = {
        'notebook': 'not-reviewed',
        'rules': 'not-reviewed',
        'source_quotes_by_rule_id': <String, String>{},
        'user_confirmed': false,
      };
    await expectLater(compiler.build(
        source: fixture.source, review: fakeNpc), throwsFormatException);
    expect(jsonDecode(fixture.review['draft'] as String), isA<Map>());
  });
}
