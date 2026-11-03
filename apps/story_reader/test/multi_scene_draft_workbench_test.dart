import 'dart:io';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/multi_scene_draft_workbench.dart';
import 'package:ai_story_reader/native_private_bookworld_compiler.dart';
import 'package:ai_story_reader/private_adaptation_preflight.dart';
import 'package:ai_story_reader/reviewed_story_composer.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const book = ImportedBook(
    title: 'Три главы перед развилкой',
    author: 'Автор',
    chapters: [
      'Дверь была закрыта. Мария открыла дверь.',
      'Мария нашла ключ. Дверь была открыта.',
      'Мария встретила Ивана. Дверь была закрыта.',
    ],
  );
  late BookSourceIndex index;
  late StoryEvidenceReviewSession review;
  late SourceSemanticCatalog catalog;
  late SemanticEditorialReviewSession editorial;
  late SourceSemanticAssertion first;
  late SourceSemanticAssertion middle;
  late SourceSemanticAssertion last;
  late IntermediateStoryBlueprint shortDraft;

  int chapter(SourceSemanticAssertion claim) {
    final byEvidence = {for (final e in review.graph.records) e.id: e};
    return byEvidence[claim.evidenceIds.first]!.chapterIndex;
  }

  setUp(() {
    index = BookSourceIndexer.index(book);
    review = StoryEvidenceReviewSession.create(index);
    while (review.scannedChunks < index.chunks.length) {
      review = review.scanNext(index);
    }
    for (final evidence in review.graph.records) {
      review = review.review(index, evidence.id, EvidenceStatus.confirmed);
    }
    catalog = SourceSemanticCatalog.fromLocalEvidence(index, review.graph);
    first = catalog.assertions.firstWhere((c) =>
        c.kind == SemanticAssertionKind.event && chapter(c) == 0);
    middle = catalog.assertions.firstWhere((c) =>
        c.kind == SemanticAssertionKind.event && chapter(c) == 1);
    last = catalog.assertions.firstWhere((c) =>
        c.kind == SemanticAssertionKind.event && chapter(c) == 2);
    editorial = SemanticEditorialReviewSession.create(index, catalog);
    for (final claim in [first, middle, last]) {
      editorial = editorial.decide(
          catalog, claim.id, SemanticEditorialVerdict.canonCandidate);
    }
    shortDraft = ReviewedStoryComposer.compose(
      index: index, evidence: review.graph, catalog: catalog,
      editorial: editorial,
      openingAssertionId: first.id, endingAssertionId: last.id,
      openingText: 'Вы перед закрытой дверью.',
      endingText: 'Мария встречает Ивана.',
      alternateEndingText: 'Вы уходите и меняете судьбу.',
      followBookChoice: 'Продолжить события книги',
      changeFateChoice: 'Изменить судьбу',
    );
  });

  IntermediateStoryBlueprint expanded() {
    var draft = MultiSceneDraftWorkbench.fromReviewedShortDraft(
        index, review.graph, catalog, editorial, shortDraft);
    draft = MultiSceneDraftWorkbench.addSourceScene(
        draft, index, review.graph, catalog, editorial, middle.id);
    final middleScene = draft.scenes.last.id;
    draft = MultiSceneDraftWorkbench.addAuthoredScene(
        draft, chapterIndex: 1);
    final alternate = draft.scenes.last;
    final altId = alternate.id;
    draft = MultiSceneDraftWorkbench.replaceScene(draft,
        MultiSceneDraftWorkbench.sceneCopy(
            alternate, text: 'Игрок уходит в другую долину.'));
    final entry = draft.scenes.first;
    draft = MultiSceneDraftWorkbench.replaceChoice(
        draft, entry.id,
        MultiSceneDraftWorkbench.choiceCopy(
            entry.choices.first, nextSceneId: middleScene));
    draft = MultiSceneDraftWorkbench.replaceChoice(
        draft, entry.id,
        MultiSceneDraftWorkbench.choiceCopy(
            entry.choices.last, nextSceneId: altId));
    draft = MultiSceneDraftWorkbench.addChoice(
        draft, middleScene, 'canon_end');
    draft = MultiSceneDraftWorkbench.addChoice(
        draft, altId, 'alternate_end');
    var mid = draft.scenes.firstWhere((s) => s.id == middleScene);
    draft = MultiSceneDraftWorkbench.replaceChoice(
        draft, mid.id, MultiSceneDraftWorkbench.choiceCopy(
            mid.choices.single, label: 'Встретиться с Иваном'));
    var alt = draft.scenes.firstWhere((s) => s.id == altId);
    draft = MultiSceneDraftWorkbench.replaceChoice(
        draft, alt.id, MultiSceneDraftWorkbench.choiceCopy(
            alt.choices.single, label: 'Продолжить другой путь'));
    draft = MultiSceneDraftWorkbench.addFlag(draft, 'found_key');
    draft = MultiSceneDraftWorkbench.replaceChoice(
        draft, 'entry', MultiSceneDraftWorkbench.choiceCopy(
            draft.scenes.first.choices.first,
            adds: ['found_key']));
    mid = draft.scenes.firstWhere((s) => s.id == middleScene);
    draft = MultiSceneDraftWorkbench.replaceChoice(
        draft, mid.id, MultiSceneDraftWorkbench.choiceCopy(
            mid.choices.single, requires: ['found_key']));
    return draft;
  }

  test('two reviewed source and authored branches compile to real 5-scene ZIP',
      () async {
    final draft = expanded();
    MultiSceneDraftWorkbench.checkSafeCheckpoint(index, draft);
    final checked = PrivateAdaptationPreflight.evaluate(
        index, review.graph, catalog, editorial, draft);
    expect(checked.isStructurallyReady, true);
    expect(checked.causal.reachableScenes, 5);
    expect(checked.causal.reachableEndings, 2);
    expect(checked.causal.reachableStates, greaterThanOrEqualTo(5));
    expect(checked.reviewedSourceScenes, 3);
    expect(checked.explicitAdaptationScenes, 2);
    final bytes = await compileReviewedPrivateBookworldInWorker(
        index, review.graph, catalog, editorial, draft);
    final world = const PrivateBookworldImporter().inspect(bytes);
    expect(world.blueprint.scenes.length, 5);
    expect(world.sourceFingerprint, index.sourceFingerprint);
    expect(world.canDistributePublicly, false);
    expect(world.requiresNetwork, false);
    expect(shortDraft.scenes.length, 3);
  });

  test('unfinished scene can resume but cannot be compiled', () {
    final base = MultiSceneDraftWorkbench.fromReviewedShortDraft(
        index, review.graph, catalog, editorial, shortDraft);
    final incomplete = MultiSceneDraftWorkbench.addAuthoredScene(
        base, chapterIndex: 1);
    expect(incomplete.scenes.last.text, isEmpty);
    MultiSceneDraftWorkbench.checkSafeCheckpoint(index, incomplete);
    final restored = IntermediateStoryBlueprint.decode(incomplete.encode());
    expect(restored.scenes.length, 4);
    expect(() => PrivateAdaptationPreflight.evaluate(
        index, review.graph, catalog, editorial, restored),
        throwsFormatException);
  });

  test('no silent promotion of unreviewed claims or changed source', () {
    final base = MultiSceneDraftWorkbench.fromReviewedShortDraft(
        index, review.graph, catalog, editorial, shortDraft);
    final blank = SemanticEditorialReviewSession.create(index, catalog);
    expect(() => MultiSceneDraftWorkbench.addSourceScene(
        base, index, review.graph, catalog, blank, middle.id),
        throwsFormatException);
    final modified = BookSourceIndexer.index(const ImportedBook(
      title: 'Иная редакция', author: 'Автор',
      chapters: ['Совсем другая история.'],
    ));
    expect(() => MultiSceneDraftWorkbench.checkSafeCheckpoint(
        modified, base), throwsFormatException);
    expect(() => MultiSceneDraftWorkbench.fromReviewedShortDraft(
        modified, review.graph, catalog, editorial, shortDraft),
        throwsFormatException);
  });

  test('invalid causal states and linked deletion fail closed', () {
    final draft = expanded();
    final middleNode = draft.scenes[3];
    expect(() => MultiSceneDraftWorkbench.removeScene(
        draft, middleNode.id), throwsFormatException);
    final alternate = draft.scenes.last;
    final loop = MultiSceneDraftWorkbench.replaceChoice(
        draft, alternate.id,
        MultiSceneDraftWorkbench.choiceCopy(
            alternate.choices.single, nextSceneId: alternate.id));
    MultiSceneDraftWorkbench.checkSafeCheckpoint(index, loop);
    expect(() => PrivateAdaptationPreflight.evaluate(
        index, review.graph, catalog, editorial, loop),
        throwsFormatException);
  });

  test('flag edits are explicit and cannot leave missing declarations', () {
    var draft = expanded();
    expect(() => MultiSceneDraftWorkbench.removeFlag(
        draft, 'found_key'), throwsFormatException);
    draft = MultiSceneDraftWorkbench.setInitiallyActive(
        draft, 'found_key', true);
    expect(draft.initialFlags, ['found_key']);
    draft = MultiSceneDraftWorkbench.setInitiallyActive(
        draft, 'found_key', false);
    expect(draft.initialFlags, isEmpty);
    expect(() => MultiSceneDraftWorkbench.addFlag(
        draft, 'found_key'), throwsFormatException);
    expect(() => MultiSceneDraftWorkbench.addFlag(
        draft, 'invalid flag'), throwsFormatException);
  });

  test('multi-scene disk checkpoint never overwrites short draft or old data',
      () async {
    final root = await Directory.systemTemp.createTemp('story_m2e5a_');
    addTearDown(() => root.delete(recursive: true));
    FileSourceAnalysisCheckpointRepository store(SourceCheckpointScope scope) =>
        FileSourceAnalysisCheckpointRepository(
          rootDirectory: () async => root, scope: scope);
    final short = store(SourceCheckpointScope.intermediateDraft);
    final multi = store(SourceCheckpointScope.multiSceneDraft);
    final evidence = store(SourceCheckpointScope.narrativeEvidence);
    await short.write(index.sourceFingerprint, shortDraft.encode());
    await evidence.write(index.sourceFingerprint, review.encode());
    final expandedDraft = expanded();
    await multi.write(index.sourceFingerprint, expandedDraft.encode());
    expect(await short.read(index.sourceFingerprint), shortDraft.encode());
    expect(await evidence.read(index.sourceFingerprint), review.encode());
    final restored = IntermediateStoryBlueprint.decode(
        (await multi.read(index.sourceFingerprint))!);
    MultiSceneDraftWorkbench.checkSafeCheckpoint(index, restored);
    expect(restored.scenes.length, 5);
    await multi.delete(index.sourceFingerprint);
    expect(await multi.read(index.sourceFingerprint), isNull);
    expect(await short.read(index.sourceFingerprint), shortDraft.encode());
    expect(await evidence.read(index.sourceFingerprint), review.encode());
  });
}
