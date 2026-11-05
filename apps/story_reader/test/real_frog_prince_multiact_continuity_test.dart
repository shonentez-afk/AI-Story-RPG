import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/cross_act_consequence_gate.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real PUBLIC-DOMAIN text, obtained by CI from Gutenberg 2591 and isolated
/// as a full single-tale FB2. Exact English quotations are fixture anchors,
/// never hard-coded into the application's planner, author rules, or prompts.
const _anchors = [
  'she missed catching it as it fell',
  'a frog put its head out of the water',
  'she said to the frog',
  'he came up again, with the ball in his mouth',
  'The frog called after her',
  'the princess ran to the door and opened it',
  'the frog hopped into the room',
  'instead of the frog, a handsome prince',
];

Future<BookSourceIndex> _frogSource() async {
  final file = Platform.environment['AI_RPG_FROG_PRINCE_FB2_PATH'];
  final manifestFile =
      Platform.environment['AI_RPG_FROG_PRINCE_MANIFEST_PATH'];
  if (file == null || file.isEmpty ||
      manifestFile == null || manifestFile.isEmpty) {
    throw StateError('Mandatory actual public-domain Frog-Prince FB2 '
        'missing. Generate with tools/build_grimm_public_domain_fb2.py.');
  }
  final raw = await File(file).readAsBytes();
  final data = jsonDecode(await File(manifestFile).readAsString())
      as Map<String, dynamic>;
  expect(data['gutenberg_id'], 2591);
  expect(data['tale'], 'THE FROG-PRINCE');
  expect(sha256.convert(raw).toString(), data['fb2_sha256']);
  final book = BookImporter.parse(
      'public_frog_prince.fb2', Uint8List.fromList(raw));
  expect(book.chapters, hasLength(1));
  final index = BookSourceIndexer.index(book);
  expect(index.textIndexCoverage, 1.0);
  for (final snippet in _anchors) {
    expect(index.chunks.where((c) => c.text.contains(snippet)),
        hasLength(1), reason: 'Real source quote missing: $snippet');
  }
  return index;
}

Future<NarrativeBookModel> _analyzeLocally(BookSourceIndex index) async {
  final scanner = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    // This is a deterministic exact-citation fixture, NOT a live GLM test.
    preview: (source, window, cancellation, title) async {
      final proposals = <SemanticCandidate>[];
      for (final quote in _anchors) {
        for (final chunk in window.chunks) {
          final offset = chunk.text.indexOf(quote);
          if (offset < 0) continue;
          proposals.add(SemanticCandidate.propose(
            source, chunk,
            category: SemanticCategory.event,
            startUtf16: chunk.startUtf16 + offset,
            endUtf16: chunk.startUtf16 + offset + quote.length,
            label: 'Предложение события на базе проверенной цитаты',
            uncertainty: 'Сюжетная причинность не доказана цитатой.',
          ));
        }
      }
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: proposals,
        ),
        totalSuggestions: proposals.length,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final scan = await scanner.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 64,
  );
  expect(scan.complete, true);
  return NarrativeBookModel.fromExisting(
      index: index,
      outline: ZaiWholeBookEventOutline.build(scan));
}

StoryDilemmaProposal _proposal(
    NarrativeBookModel book, BookActSegment part) =>
    StoryDilemmaProposal(
      sourceFingerprint: book.sourceFingerprint,
      setupEventId: part.events.first.id,
      outcomeEventId: part.events.last.id,
      kind: StoryDilemmaKind.disclosure,
      dilemma: 'Оставаться с предложенным решением или изменить путь',
      acceptIntent: 'Принять условие этого вымышленного игрового эпизода',
      refuseIntent: 'Отказаться и найти другую безопасную возможность',
      followupGoal: 'Разобраться с последствиями выбранного обязательства',
      finishOriginalIntent: 'Исполнить принятые ранее условия игрового пути',
      originalEnding: 'Завершение предлагаемого исходного игрового пути',
      alternativeSearchGoal: 'Открыть дальнейшие альтернативные возможности',
      searchIntent: 'Осмотреть окружение и найти другой вариант решения',
      alternativeDiscovery: 'Возникла другая вымышленная игровая возможность',
      useDiscoveryIntent: 'Использовать самостоятельный путь без обещания',
      alternativeEnding: 'Завершение иной вымышленной игровой линии',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('REAL one-chapter Frog-Prince FB2 spans two source-locked acts; '
      'earlier game choice changes later options without fake canon',
      () async {
    final index = await _frogSource();
    final book = await _analyzeLocally(index);
    expect(book.analysisComplete, true);
    expect(book.chapterCount, 1);
    expect(book.events, hasLength(_anchors.length));

    // Act segmentation follows source evidence, not chapter-count or book
    // title. The whole source is ONE chapter but still spans two ACT parts.
    final map = BookwideActPlanner.build(
        index: index, book: book, eventsPerPart: 4);
    expect(map.acts, hasLength(2));
    expect(map.acts.map((x) => x.events.length), [4, 4]);
    expect(map.chaptersWithoutEvents, isEmpty);
    final draft = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [
        _proposal(book, map.acts[0]),
        _proposal(book, map.acts[1]),
      ],
    );
    expect(draft.parts, hasLength(2));
    expect(draft.plan.validate(book).terminalSituations, 2);
    final link = CrossActConsequenceRule(
      id: 'frog_fixture_review',
      earlierActId: draft.parts[0].actId,
      laterActId: draft.parts[1].actId,
      earlierSourceEventId: draft.parts[0].outcomeEventId,
      laterSourceEventId: draft.parts[1].setupEventId,
      laterDecisionId: 'act_2_accept_offer',
      priorOutcome: CrossActPriorOutcome.original,
      mode: CrossActRuleMode.requiresPriorOutcome,
      reviewedAsGameFiction: true,
      privateReviewReason: 'Только в регрессионной проверке: '
          'имитирован отдельный редакторский выбор игровой адаптации.',
    );
    final result = CrossActConsequenceGate.apply(
      index: index, book: book, bookMap: map,
      draft: draft, rules: [link],
    );
    expect(result.hasEnforcedContinuity, true);
    expect(result.audit.counterexamples, isEmpty);
    expect(result.plan.validate(book).terminalSituations, 2);
    expect(result.coverage.allEvents, 8);
    expect(result.coverage.referencedEvents, 4);
    expect(result.coverage.allDetectedEventsReferenced, false);
    expect(result.readyForBookWorld, false);
    expect(result.hasVerifiedLiteraryCausality, false);
    expect(result.hasVerifiedNPCInformation, false);
    expect(result.fullBookReady, false);
    final details = jsonEncode(result.toDiagnosticJson());
    expect(details, isNot(contains(book.title)));
    expect(details, isNot(contains(_anchors.first)));
    expect(details, isNot(contains(index.sourceFingerprint)));
  });
}
