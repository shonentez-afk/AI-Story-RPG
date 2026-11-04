import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_editorial_review.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_evidence_review_session.dart';
import 'package:ai_story_reader/zai_causal_choice_notebook.dart';
import 'package:ai_story_reader/zai_cross_window_evidence_graph.dart';
import 'package:ai_story_reader/zai_editorial_consistency.dart';
import 'package:ai_story_reader/zai_m2c_source_bridge.dart';
import 'package:ai_story_reader/zai_manual_source_alignment.dart';
import 'package:ai_story_reader/zai_private_bookworld_compilation.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_semantic_review_queue.dart';
import 'package:ai_story_reader/zai_source_scene_board.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:campaign_manager/campaign_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real, single-story FB2 derived from *Gutenberg 2591*, NOT an invented
/// Grimm-like test. In this scripted QA only, the explicit human-acceptance
/// actions are simulated. This does NOT mean a model autonomously understood
/// the story, or that a real reader's approval was collected.
typedef _Anchor = ({
  String quote, String subject, String predicate, String object,
});
const _quotes = <_Anchor>[
  (quote: 'she missed catching it as it fell',
   subject: 'princess', predicate: 'missed', object: 'golden ball'),
  (quote: 'a frog put its head out of the water',
   subject: 'frog', predicate: 'emerged from', object: 'spring'),
  (quote: 'she said to the frog',
   subject: 'princess', predicate: 'spoke to', object: 'frog'),
  (quote: 'he came up again, with the ball in his mouth',
   subject: 'frog', predicate: 'returned with', object: 'golden ball'),
  (quote: 'The frog called after her',
   subject: 'frog', predicate: 'called after', object: 'princess'),
  (quote: 'she heard a strange noise',
   subject: 'princess', predicate: 'heard', object: 'noise'),
  (quote: 'the princess ran to the door and opened it',
   subject: 'princess', predicate: 'opened', object: 'door'),
  (quote: 'the frog hopped into the room',
   subject: 'frog', predicate: 'entered', object: 'royal hall'),
  (quote: 'put him upon the pillow of her own bed',
   subject: 'princess', predicate: 'put frog on', object: 'pillow'),
  (quote: 'when night came again she heard the same',
   subject: 'princess', predicate: 'heard tapping', object: 'second night'),
  (quote: 'the frog came in, and slept upon',
   subject: 'frog', predicate: 'slept on', object: 'pillow'),
  (quote: 'the third night he did the same',
   subject: 'frog', predicate: 'returned', object: 'third night'),
  (quote: 'instead of the frog, a handsome prince',
   subject: 'princess', predicate: 'saw', object: 'prince'),
  (quote: 'a gay coach drove up',
   subject: 'coach', predicate: 'arrived at', object: 'palace'),
  (quote: 'all set out, full of joy and merriment',
   subject: 'party', predicate: 'set out for', object: 'prince kingdom'),
];

typedef _Selected = ({_Anchor anchor, SemanticCandidate candidate,
    int windowPosition, int chunkPosition});

Future<({_Selected Function(String) byQuote,
        List<_Selected> selected, ZaiWindowReviewQueue queue,
        BookSourceIndex index})> _realSource() async {
  final path = Platform.environment['AI_RPG_FROG_PRINCE_FB2_PATH'];
  final meta = Platform.environment['AI_RPG_FROG_PRINCE_MANIFEST_PATH'];
  if (path == null || meta == null || path.isEmpty || meta.isEmpty) {
    throw StateError('Real Frog-Prince source absent; run '
        'tools/build_grimm_public_domain_fb2.py and pass env variables.');
  }
  final bytes = await File(path).readAsBytes();
  final manifest = jsonDecode(await File(meta).readAsString())
      as Map<String, dynamic>;
  expect(manifest['gutenberg_id'], 2591);
  expect(manifest['tale'], 'THE FROG-PRINCE');
  expect(sha256.convert(bytes).toString(), manifest['fb2_sha256']);
  final book = BookImporter.parse('frog_prince_real.fb2',
      Uint8List.fromList(bytes));
  expect(book.chapters, hasLength(1));
  expect(book.chapters.single, contains('golden ball'));
  expect(book.chapters.single, contains('three nights'));
  expect(book.chapters.single, contains('faithful Heinrich'));
  final index = BookSourceIndexer.index(book);
  expect(index.chapterCount, 1);
  expect(index.textIndexCoverage, 1.0);

  var queue = ZaiWindowReviewQueue.empty(index);
  final found = <_Selected>[];
  final groups = <int, List<_Selected>>{};
  for (final anchor in _quotes) {
    final chunks = [
      for (final (i, chunk) in index.chunks.indexed)
        if (chunk.text.contains(anchor.quote)) i,
    ];
    expect(chunks, hasLength(1),
        reason: 'An exact scripted QA anchor must exist ONCE in '
            'the independently downloaded original edition.');
    final position = chunks.single;
    final chunk = index.chunks[position];
    final offset = chunk.text.indexOf(anchor.quote);
    final candidate = SemanticCandidate.propose(
      index, chunk, category: SemanticCategory.event,
      startUtf16: chunk.startUtf16 + offset,
      endUtf16: chunk.startUtf16 + offset + anchor.quote.length,
      label: anchor.quote,
      uncertainty: 'Independent editorial approval required.',
    );
    final window = queue.windows.indexWhere((w) =>
        w.chunks.any((c) => c.id == chunk.id));
    expect(window, greaterThanOrEqualTo(0));
    final entry = (
      anchor: anchor, candidate: candidate,
      windowPosition: window, chunkPosition: position,
    );
    groups.putIfAbsent(window, () => []).add(entry);
  }

  // Production Z.ai limits a window to eight proposals. QA scripts MUST use
  // exactly the same cap; never fabricate a 20-result model response.
  for (var position = 0; position < queue.windows.length; position++) {
    final candidates = groups[position] ?? <_Selected>[];
    // Reserve the exact original frog call for the explicit alternative
    // scene, and a late point in each window for chronology coverage.
    final chosen = <_Selected>[];
    final frogCall = candidates.where(
        (e) => e.anchor.quote == 'The frog called after her').firstOrNull;
    if (frogCall != null) chosen.add(frogCall);
    for (final entry in candidates.take(7)) {
      if (chosen.length >= 7) break;
      if (!chosen.any((e) => e.candidate.id == entry.candidate.id)) {
        chosen.add(entry);
      }
    }
    if (candidates.length > chosen.length) {
      final last = candidates.last;
      if (!chosen.any((e) => e.candidate.id == last.candidate.id)) {
        chosen.add(last);
      }
    }
    final ordered = [
      ...chosen,
    ]..sort((a, b) => a.chunkPosition != b.chunkPosition
        ? a.chunkPosition.compareTo(b.chunkPosition)
        : a.candidate.startUtf16.compareTo(b.candidate.startUtf16));
    expect(ordered.length, lessThanOrEqualTo(8));
    found.addAll(ordered);
    final window = queue.windows[position];
    if (!window.hasNarrativeText) {
      throw StateError('Source window must be explicitly reviewed.');
    }
    queue = queue.record(position, ZaiSemanticPreviewResult(
      batch: SemanticCandidateBatch(
        providerId: ZaiSemanticPreviewService.providerId,
        providerVersion: ZaiSemanticPreviewService.providerVersion,
        sourceFingerprint: index.sourceFingerprint,
        chunkIds: [for (final chunk in window.chunks) chunk.id],
        candidates: [for (final item in ordered) item.candidate],
      ),
      totalSuggestions: ordered.length,
      rejectedCount: 0,
      rejectedNonRussian: 0,
    ));
  }
  for (final event in found) {
    queue = queue.decide(event.candidate.id,
        ZaiEditorialDecision.keepForReview);
  }
  expect(queue.pendingCount, 0);
  expect(queue.pendingReviewCount, 0);
  found.sort((a, b) => a.chunkPosition != b.chunkPosition
      ? a.chunkPosition.compareTo(b.chunkPosition)
      : a.candidate.startUtf16.compareTo(b.candidate.startUtf16));
  expect(found.length, greaterThanOrEqualTo(9));
  expect(found.any((e) =>
      e.anchor.quote == 'The frog called after her'), true);
  expect(found.last.anchor.quote,
      'all set out, full of joy and merriment');
  return (
    selected: found, queue: queue, index: index,
    byQuote: (value) => found.singleWhere((e) => e.anchor.quote == value),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('REAL Grimm #2591 single tale: verified private .bworld, '
      'two endings and 20+ transactional CLASSIC choice actions', () async {
    final real = await _realSource();
    final graph = ZaiCrossWindowEvidenceGraph.fromQueue(real.queue);
    var board = ZaiSourceSceneBoard.empty(graph);
    // Reserve a real, separate anchor for a clearly marked AUTHOR'S
    // alternative rather than pretending the book contains that event.
    final alternative = real.byQuote('The frog called after her');
    final mainPath = [
      for (final finding in real.selected)
        if (finding.candidate.id != alternative.candidate.id) finding,
    ];
    for (final (i, item) in [...mainPath, alternative].indexed) {
      board = board.addScene(
        [item.candidate.id],
        'Grimm editorial scene ' + (i + 1).toString(),
        'Exact manually reviewed, edition-locked source candidate.',
      );
    }
    final mainIds = [
      for (final s in board.scenes.take(mainPath.length)) s.id,
    ];
    final alternativeId = board.scenes.last.id;
    var notebook = ZaiCausalChoiceNotebook.empty(board)
        .addFlag('golden_ball_returned');
    for (var i = 0; i < mainIds.length - 1; i++) {
      notebook = notebook.addChoice(
        from: mainIds[i], to: mainIds[i + 1],
        label: 'Continue the original fairy tale',
        reason: 'A separately confirmed next event follows in text order.',
        adds: i == 2 ? ['golden_ball_returned'] : const [],
      );
      // A read-only repeatable observation is an explicit QA move, not a
      // distinct canonical story event or an invented NPC disclosure.
      notebook = notebook.addChoice(
        from: mainIds[i], to: mainIds[i],
        label: 'Examine the current scene again',
        reason: 'Player chooses to inspect the current scene once more.',
      );
    }
    notebook = notebook.addChoice(
      from: mainIds[2], to: alternativeId,
      label: 'Choose a different promise',
      reason: 'This is an authored alternative, NOT a Grimm event.',
    );

    var narrative = StoryEvidenceReviewSession.create(real.index);
    while (narrative.scannedChunks < real.index.chunks.length) {
      narrative = narrative.scanNext(real.index, limit: 24);
    }
    final originalCatalog =
        SourceSemanticCatalog.fromLocalEvidence(real.index, narrative.graph);
    final originalEditor = SemanticEditorialReviewSession.create(
        real.index, originalCatalog);
    final baseline = ZaiSourceAlignmentBaseline(
      narrative: narrative, catalog: originalCatalog,
      editorial: originalEditor,
    );
    var ledger = ZaiManualSourceAlignment.empty(real.index, baseline);
    // Simulated manual QA approvals; production requires TWO real
    // unchecked-by-default acknowledgements in the human UI.
    for (final item in mainPath) {
      ledger = ledger.accept(
        queue: real.queue, baseline: baseline,
        findingId: item.candidate.id,
        subject: item.anchor.subject,
        predicate: item.anchor.predicate,
        object: item.anchor.object,
        quoteConfirmedByReader: true,
        narratorAssertionConfirmedByReader: true,
      );
    }
    final safe = ZaiManualSourceAlignment.decode(
      queue: real.queue, baseline: baseline,
      raw: ledger.encode(queue: real.queue, baseline: baseline));
    final linked = safe.apply(queue: real.queue, baseline: baseline);
    expect(linked.assertionByFinding, hasLength(mainPath.length));

    final sourceScenes = mainIds.toSet();
    final prose = <String, String>{
      for (var i = 0; i < mainPath.length; i++)
        mainIds[i]: 'Source-backed edition excerpt: ' +
            mainPath[i].anchor.quote + '.',
      alternativeId:
          'Authored alternative: the princess revisits the spring and '
          'makes a different choice about her promise.',
    };
    final editorialLinks = linked.assertionByFinding;
    final preflight = ZaiM2cSourceBridge.review(
      queue: real.queue, notebook: notebook,
      consistency: ZaiEditorialConsistencyNotebook.empty(graph),
      evidence: linked.evidence,
      catalog: linked.catalog,
      editorial: linked.editorial,
      sourceSceneIds: sourceScenes,
      eventAssertionIds: editorialLinks,
      authoredSceneTexts: prose,
      rights: PreparationRights.privateUse,
      consentForPrivateCompilation: true,
    );
    expect(preflight.blockers, isEmpty,
        reason: preflight.blockers.join('; '));
    expect(preflight.canStageForPrivateCompiler, true);
    expect(preflight.acceptance!.causal.reachableEndings, 2);

    final compiled = await ZaiPrivateBookworldCompilation.compile(
      queue: real.queue, notebook: notebook,
      consistency: ZaiEditorialConsistencyNotebook.empty(graph),
      evidence: linked.evidence, catalog: linked.catalog,
      editorial: linked.editorial,
      sourceSceneIds: sourceScenes,
      eventAssertionIds: editorialLinks,
      authoredSceneTexts: prose,
      consentForPrivateCompilation: true,
    );
    final inspected = const PrivateBookworldImporter().inspect(
        compiled.archive);
    expect(inspected.sourceFingerprint, real.index.sourceFingerprint);
    expect(inspected.canDistributePublicly, false);
    expect(inspected.requiresNetwork, false);
    expect(inspected.blueprint.scenes, hasLength(board.scenes.length));
    expect(inspected.blueprint.rightsStatus, 'private_adaptation');

    final temp = await Directory.systemTemp.createTemp(
        'source-locked-grimm-campaign-');
    try {
      var store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        final installed = store.installBookworld(compiled.archive);
        expect(installed.archiveHash, compiled.archiveSha256);
        final originalId = store.createCampaign(installed.archiveHash);
        var steps = 0;
        for (var i = 0; i < mainIds.length - 1; i++) {
          var game = store.loadCampaign(originalId);
          expect(game.coordinator.isTerminal, false);
          final inspect = game.coordinator.choices.singleWhere(
              (choice) => choice.label == 'Examine the current scene again');
          final inspectResult = store.commitChoice(originalId,
            actionId: 'inspection_' + i.toString(),
            choiceId: inspect.id, expectedRevision: game.metadata.revision);
          expect(inspectResult.applied, true);
          steps++;
          game = store.loadCampaign(originalId);
          final next = game.coordinator.choices.singleWhere(
              (choice) => choice.label == 'Continue the original fairy tale');
          final result = store.commitChoice(originalId,
            actionId: 'continue_' + i.toString(),
            choiceId: next.id, expectedRevision: game.metadata.revision);
          expect(result.applied, true);
          steps++;
        }
        final finished = store.loadCampaign(originalId);
        expect(finished.coordinator.isTerminal, true);
        expect(finished.metadata.revision, steps);
        expect(steps, greaterThanOrEqualTo(20),
            reason: '20+ real committed decisions, some intentionally '
                'repeatable observation actions, not 20 new plot events.');

        final alternateId = store.createCampaign(installed.archiveHash);
        for (var i = 0; i < 3; i++) {
          final state = store.loadCampaign(alternateId);
          final next = state.coordinator.choices.singleWhere((c) =>
              c.label == 'Continue the original fairy tale');
          expect(store.commitChoice(alternateId,
            actionId: 'alternate_step_' + i.toString(),
            choiceId: next.id,
            expectedRevision: state.metadata.revision).applied, true);
        }
        // The branch was authored at mainIds[2], so navigate it from
        // a separate fresh campaign instead of pretending it exists later.
        final branchId = store.createCampaign(installed.archiveHash);
        for (var i = 0; i < 2; i++) {
          final state = store.loadCampaign(branchId);
          final next = state.coordinator.choices.singleWhere((c) =>
              c.label == 'Continue the original fairy tale');
          expect(store.commitChoice(branchId,
            actionId: 'branch_step_' + i.toString(),
            choiceId: next.id, expectedRevision: state.metadata.revision)
              .applied, true);
        }
        final fork = store.loadCampaign(branchId);
        final changed = fork.coordinator.choices.singleWhere((c) =>
            c.label == 'Choose a different promise');
        expect(store.commitChoice(branchId,
          actionId: 'choose_authored_alternative',
          choiceId: changed.id,
          expectedRevision: fork.metadata.revision).applied, true);
        expect(store.loadCampaign(branchId).coordinator.isTerminal, true);
        expect(store.campaigns(), hasLength(3));
        expect(store.loadCampaign(originalId).metadata.revision, steps);
      } finally {
        store.close();
      }
      store = BookworldCampaignStore.openPrivateDirectory(temp.path);
      try {
        expect(store.installedWorlds(), hasLength(1));
        expect(store.campaigns(), hasLength(3));
        final replayed = store.campaigns()
            .where((c) => c.revision >= 20).single;
        final restored = store.loadCampaign(replayed.id);
        expect(restored.coordinator.isTerminal, true);
        expect(restored.coordinator.events, hasLength(replayed.revision));
      } finally {
        store.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
