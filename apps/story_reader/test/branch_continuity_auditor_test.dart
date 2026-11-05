import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/branch_continuity_auditor.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _source({String extra = ''}) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Договор, тайна и находка',
      author: 'Синтетический тест',
      chapters: [
        List.filled(5, 'Путник стоял у ворот. Он пока не давал обещаний. '
            'Второй человек предложил сделку у реки. ').join(' ') + extra,
      ],
    ));

Future<NarrativeBookModel> _book(BookSourceIndex index) async {
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
              SemanticCandidate.propose(source, chunk,
                category: SemanticCategory.event,
                startUtf16: chunk.startUtf16 + i * 96,
                endUtf16: chunk.startUtf16 + i * 96 + 64,
                label: 'Кандидат события в исходном тексте',
                uncertainty: 'Смысл не подтверждён редактором.'),
          ],
        ), totalSuggestions: 2, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final analysis = await scan.analyze(
    index: index, approvedManifestDigest: consent.approvalDigest,
    explicitWholeBookConsent: true, maxWindowsPerRun: 10,
  );
  return NarrativeBookModel.fromExisting(
    index: index, outline: ZaiWholeBookEventOutline.build(analysis),
  );
}

StoryPlan _dilemma(NarrativeBookModel book) {
  final events = book.events;
  return StoryPlanDilemmaGenerator.propose(book,
    StoryDilemmaProposal(
      sourceFingerprint: book.sourceFingerprint,
      setupEventId: events.first.id,
      outcomeEventId: events.last.id,
      kind: StoryDilemmaKind.agreement,
      dilemma: 'Согласиться на условие или уйти собственным путём',
      acceptIntent: 'Согласиться на предложенное условие добровольно',
      refuseIntent: 'Отказаться от обязательства и найти иной путь',
      followupGoal: 'Проверить последствия принятого условия в игре',
      finishOriginalIntent: 'Выполнить принятое игровое обещание героя',
      originalEnding: 'Вымышленная концовка принятого обязательства',
      alternativeSearchGoal: 'Найти новый путь без ранее принятого обещания',
      searchIntent: 'Осмотреть местность и найти обходную дорогу',
      alternativeDiscovery: 'Обнаружена отдельная безопасная возможность',
      useDiscoveryIntent: 'Использовать найденную другую возможность',
      alternativeEnding: 'Другая вымышленная развязка без договора',
    ),
  );
}

BranchContinuityRule _promise(
    BookSourceIndex index, NarrativeBookModel book, {
    List<String> protect = const ['honor_condition'],
    List<String> protectedScenes = const [],
    String? fingerprint,
    String? eventId,
  }) => BranchContinuityRule(
    id: 'accepted_agreement',
    sourceFingerprint: fingerprint ?? index.sourceFingerprint,
    kind: ContinuityLedgerKind.promise,
    subjectId: 'player',
    resourceId: 'game_agreement',
    sourceEventId: eventId ?? book.events.first.id,
    stateFlag: 'agreement_accepted',
    grantDecisionId: 'accept_offer',
    protectedDecisionIds: protect,
    protectedSituationIds: protectedScenes,
    refusalDecisionIds: const ['refuse_offer'],
    reviewedAsGameFiction: true,
  );

StoryPlan _transfer(NarrativeBookModel book, {bool removesOwner = true}) {
  final first = book.events.first.id;
  final second = book.events.last.id;
  StoryDecision d(String id, String next, {
    List<String> requires = const [],
    List<String> adds = const [],
    List<String> removes = const [],
    String? sourceId,
  }) => StoryDecision(
    id: id, intent: 'Игровое действие ' + id,
    nextSituationId: next, requires: requires, adds: adds,
    removes: removes, sourceEventId: sourceId,
  );
  StorySituation s(String id, List<StoryDecision> choices, {
    bool terminal = false,
  }) => StorySituation(
    id: id, goal: 'Развитие состояния ' + id,
    conflict: 'Правила относятся только к частной адаптации',
    chapterIndex: 0, terminal: terminal, decisions: choices,
  );
  return StoryPlan(
    sourceFingerprint: book.sourceFingerprint, title: book.title,
    entrySituationId: 'start', flags: ['owner_a', 'owner_b', 'declined'],
    initialFlags: const [], situations: [
      s('start', [
        d('acquire_a', 'offer', adds: ['owner_a'], sourceId: first),
        d('decline', 'ending_alt', adds: ['declined']),
      ]),
      s('offer', [
        d('transfer', 'after_transfer',
          requires: ['owner_a'], adds: ['owner_b'],
          removes: removesOwner ? ['owner_a'] : [], sourceId: second),
        d('stay', 'ending_original', requires: ['owner_a']),
      ]),
      s('after_transfer', [
        d('use_b', 'ending_original', requires: ['owner_b']),
      ]),
      s('ending_original', [], terminal: true),
      s('ending_alt', [], terminal: true),
    ],
  );
}

List<BranchContinuityRule> _items(
    BookSourceIndex index, NarrativeBookModel book, {
    bool revoke = true,
    String? transferRequiresFlag = 'owner_a',
  }) => [
    BranchContinuityRule(
      id: 'owner_a_rule', sourceFingerprint: index.sourceFingerprint,
      kind: ContinuityLedgerKind.item,
      subjectId: 'player', resourceId: 'ring_item',
      sourceEventId: book.events.first.id,
      stateFlag: 'owner_a', grantDecisionId: 'acquire_a',
      protectedDecisionIds: const ['stay', 'transfer'],
      revokeDecisionIds: revoke ? const ['transfer'] : const [],
      reviewedAsGameFiction: true,
    ),
    BranchContinuityRule(
      id: 'owner_b_rule', sourceFingerprint: index.sourceFingerprint,
      kind: ContinuityLedgerKind.item,
      subjectId: 'npc_other', resourceId: 'ring_item',
      sourceEventId: book.events.last.id,
      stateFlag: 'owner_b', grantDecisionId: 'transfer',
      protectedDecisionIds: const ['use_b'],
      requiresFlagAtGrant: transferRequiresFlag,
      reviewedAsGameFiction: true,
    ),
  ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('agreement accepted and refusal routes keep obligations separate', () async {
    final index = _source();
    final book = await _book(index);
    final plan = _dilemma(book);
    final result = BranchContinuityAuditor.audit(
      index: index, book: book, plan: plan, rules: [_promise(index, book)],
    );
    expect(result.exploredStates, greaterThan(2));
    expect(result.passedFormalStateAudit, true);
    expect(result.counterexamples, isEmpty);
    expect(result.verifiesBookMeaning, false);
    expect(result.canPublishCanonicalRpg, false);
    expect(result.toDiagnosticJson()['ready_for_canon'], false);
  });

  test('refusal path cannot honor a promise it never accepted', () async {
    final index = _source();
    final book = await _book(index);
    final result = BranchContinuityAuditor.audit(
      index: index, book: book, plan: _dilemma(book),
      rules: [_promise(index, book, protect: ['explore'])],
    );
    final example = result.counterexamples
        .singleWhere((c) => c.code == 'USE_WITHOUT_GRANT');
    expect(example.pathChoiceIds, ['refuse_offer', 'explore']);
    expect(result.passedFormalStateAudit, false);
  });

  test('unrevealed NPC knowledge cannot be used in a reachable scene', () async {
    final index = _source();
    final book = await _book(index);
    final rule = BranchContinuityRule(
      id: 'npc_secret', sourceFingerprint: index.sourceFingerprint,
      kind: ContinuityLedgerKind.npcKnowledge,
      subjectId: 'npc_other', resourceId: 'source_secret',
      sourceEventId: book.events.first.id,
      stateFlag: 'agreement_accepted',
      grantDecisionId: 'accept_offer',
      protectedDecisionIds: const ['honor_condition'],
      protectedSituationIds: const ['search_path'],
      reviewedAsGameFiction: true,
    );
    final report = BranchContinuityAuditor.audit(
      index: index, book: book, plan: _dilemma(book), rules: [rule],
    );
    expect(report.counterexamples.any((x) =>
        x.code == 'PREMATURE_SCENE' &&
        x.pathChoiceIds.contains('refuse_offer')), true);
    expect(report.verifiesCharacterIdentity, false);
  });

  test('a transfer removes former owner before granting new owner', () async {
    final index = _source();
    final book = await _book(index);
    final plan = _transfer(book);
    final result = BranchContinuityAuditor.audit(
      index: index, book: book, plan: plan, rules: _items(index, book),
    );
    expect(result.passedFormalStateAudit, true);
    expect(result.counterexamples, isEmpty);
  });

  test('transfer without removing previous owner is caught', () async {
    final index = _source();
    final book = await _book(index);
    final result = BranchContinuityAuditor.audit(
      index: index, book: book, plan: _transfer(book, removesOwner: false),
      rules: _items(index, book, revoke: false),
    );
    expect(result.counterexamples.any((x) =>
        x.code == 'MULTIPLE_ITEM_OWNERS' &&
        x.pathChoiceIds.contains('transfer')), true);
  });

  test('transfer source cannot be silently switched to another event', () async {
    final index = _source();
    final book = await _book(index);
    final wrong = BranchContinuityRule(
      id: 'wrong_source', sourceFingerprint: index.sourceFingerprint,
      kind: ContinuityLedgerKind.item,
      subjectId: 'player', resourceId: 'ring_item',
      sourceEventId: book.events.last.id, stateFlag: 'owner_a',
      grantDecisionId: 'acquire_a',
      protectedDecisionIds: const ['stay'],
      reviewedAsGameFiction: true,
    );
    expect(() => BranchContinuityAuditor.audit(
      index: index, book: book, plan: _transfer(book), rules: [wrong],
    ), throwsFormatException);
  });

  test('foreign edition and forged initial ownership fail closed', () async {
    final index = _source();
    final book = await _book(index);
    expect(() => BranchContinuityAuditor.audit(
      index: index, book: book, plan: _dilemma(book),
      rules: [_promise(index, book, fingerprint: 'wrong_edition')],
    ), throwsFormatException);
    final base = _dilemma(book);
    final invented = StoryPlan(
      sourceFingerprint: base.sourceFingerprint, title: base.title,
      entrySituationId: base.entrySituationId, flags: base.flags,
      initialFlags: const ['agreement_accepted'],
      situations: base.situations,
    );
    expect(() => BranchContinuityAuditor.audit(
      index: index, book: book, plan: invented,
      rules: [_promise(index, book)],
    ), throwsFormatException);
  });
}
