import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/bookwide_storyplan_composer.dart';
import 'package:ai_story_reader/cross_act_consequence_gate.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index([String editionChange = '']) {
  const excerpt = 'Одинокий путник стоял у старой дороги '
      'и услышал незнакомое предложение помощи. '
      'Он не давал обещаний, пока не рассмотрел разные пути. ';
  return BookSourceIndexer.index(ImportedBook(
    title: 'Зависимые многоактовые выборы',
    author: 'Синтетический тест',
    chapters: [
      List.filled(4, excerpt).join(' '),
      List.filled(4, excerpt).join(' '),
      List.filled(4, excerpt).join(' ') + editionChange,
    ],
  ));
}

Future<NarrativeBookModel> _book(BookSourceIndex index) async {
  final scanner = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, withTitle) async {
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
                source, chunk, category: SemanticCategory.event,
                startUtf16: chunk.startUtf16 + 85 * i,
                endUtf16: chunk.startUtf16 + 85 * i + 60,
                label: 'Предположенное моделью событие',
                uncertainty: 'Причинность и смысл ещё не подтверждены.',
              ),
          ],
        ),
        totalSuggestions: 2, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final m = ZaiWholeBookConsentManifest.fromIndex(index);
  final result = await scanner.analyze(
    index: index, approvedManifestDigest: m.approvalDigest,
    explicitWholeBookConsent: true, maxWindowsPerRun: 64,
  );
  return NarrativeBookModel.fromExisting(
    index: index, outline: ZaiWholeBookEventOutline.build(result));
}

StoryDilemmaProposal _proposal(NarrativeBookModel book, int chapter) {
  final events = book.events.where(
      (e) => e.source.chapterIndex == chapter).toList();
  return StoryDilemmaProposal(
    sourceFingerprint: book.sourceFingerprint,
    setupEventId: events.first.id,
    outcomeEventId: events.last.id,
    kind: StoryDilemmaKind.disclosure,
    dilemma: 'Принять предложенные условия или искать альтернативный путь',
    acceptIntent: 'Добровольно согласиться на предложенное игровое условие',
    refuseIntent: 'Отказаться от предложения и искать другой путь',
    followupGoal: 'Проверить последствия принятого ранее решения',
    finishOriginalIntent: 'Выполнить принятое игровое обязательство',
    originalEnding: 'Закончить первую линию игрового эпизода',
    alternativeSearchGoal: 'Исследовать варианты без прежнего обещания',
    searchIntent: 'Исследовать дорогу и поговорить с другими путниками',
    alternativeDiscovery: 'Появилась новая вымышленная возможность',
    useDiscoveryIntent: 'Использовать другую возможность без обязательств',
    alternativeEnding: 'Завершить альтернативный игровой путь',
  );
}

CrossActConsequenceRule _rule(
    MultiActStoryPlanDraft draft, {
    String id = 'review_1',
    String decision = 'act_2_accept_offer',
    bool approved = true,
    String? priorEvidence,
    String? laterEvidence,
    String? earlierAct,
    String? laterAct,
    CrossActRuleMode mode = CrossActRuleMode.requiresPriorOutcome,
    CrossActPriorOutcome outcome = CrossActPriorOutcome.original,
  }) => CrossActConsequenceRule(
    id: id,
    earlierActId: earlierAct ?? draft.parts.first.actId,
    laterActId: laterAct ?? draft.parts[1].actId,
    earlierSourceEventId: priorEvidence ??
        draft.parts.first.outcomeEventId,
    laterSourceEventId: laterEvidence ??
        draft.parts[1].setupEventId,
    laterDecisionId: decision,
    priorOutcome: outcome,
    mode: mode,
    reviewedAsGameFiction: approved,
    privateReviewReason: 'Согласованный игровой вариант: '
        'первое решение изменяет доступность выбора во втором акте.',
  );

/// Returns state before entering a scene, following a concrete sequence of
/// choices and maintaining ALL earlier flags.
(String, Set<String>) _step(StoryPlan plan, List<String> decisions) {
  final byId = {for (final s in plan.situations) s.id: s};
  var scene = plan.entrySituationId;
  final flags = <String>{...plan.initialFlags};
  for (final id in decisions) {
    final option = byId[scene]!.decisions.singleWhere((d) => d.id == id);
    expect(flags.containsAll(option.requires), true);
    expect(flags.intersection(option.forbids.toSet()), isEmpty);
    flags.removeAll(option.removes);
    flags.addAll(option.adds);
    scene = option.nextSituationId;
  }
  return (scene, flags);
}

bool _enabled(StoryDecision choice, Set<String> flags) =>
    flags.containsAll(choice.requires) &&
    flags.intersection(choice.forbids.toSet()).isEmpty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an explicitly reviewed earlier outcome changes LATER choices '
      'on real player paths, but never certifies literary truth', () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final base = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [_proposal(book, 0), _proposal(book, 1),
        _proposal(book, 2)],
    );
    final output = CrossActConsequenceGate.apply(
      index: index, book: book, bookMap: map, draft: base,
      rules: [_rule(base)],
    );
    expect(output.hasEnforcedContinuity, true);
    expect(output.impacts, hasLength(1));
    expect(output.impacts.single.allowedEarlierOutcomeStates,
        greaterThan(0));
    expect(output.impacts.single.blockedOppositeOutcomeStates,
        greaterThan(0));
    expect(output.audit.counterexamples, isEmpty);
    expect(output.plan.validate(book).terminalSituations, 2);
    expect(output.coverage.referencedEvents, 6);
    expect(output.hasVerifiedLiteraryCausality, false);
    expect(output.hasVerifiedNPCInformation, false);
    expect(output.hasVerifiedWorldChronology, false);
    expect(output.readyForBookWorld, false);
    expect(output.fullBookReady, false);

    final accepted = _step(output.plan, [
      'act_1_accept_offer', 'act_1_honor_condition',
      'act_1_continue_original',
    ]);
    expect(accepted.$1, 'act_2_turning_point');
    final refusal = _step(output.plan, [
      'act_1_refuse_offer', 'act_1_explore',
      'act_1_use_discovery', 'act_1_end_alternative',
      'act_1_continue_alternative',
    ]);
    expect(refusal.$1, 'act_2_turning_point');
    final fork = output.plan.situations.singleWhere(
        (s) => s.id == 'act_2_turning_point');
    final acceptSecond = fork.decisions.singleWhere(
        (d) => d.id == 'act_2_accept_offer');
    final refuseSecond = fork.decisions.singleWhere(
        (d) => d.id == 'act_2_refuse_offer');
    expect(acceptSecond.requires, contains('act_1_original_outcome'));
    expect(_enabled(acceptSecond, accepted.$2), true);
    expect(_enabled(acceptSecond, refusal.$2), false);
    expect(_enabled(refuseSecond, accepted.$2), true);
    expect(_enabled(refuseSecond, refusal.$2), true);
    // No accidental fulfilment of an offer when the previous act refused.
    expect(refusal.$2, isNot(contains('act_1_disclosure_accepted')));
    final diagnostic = jsonEncode(output.toDiagnosticJson());
    expect(diagnostic, contains('REVIEWED_GAME_FICTION_DRAFT_ONLY'));
    expect(diagnostic, isNot(contains(book.title)));
    expect(diagnostic, isNot(contains(book.events.first.source.quote)));
    expect(diagnostic, isNot(contains(book.sourceFingerprint)));
    expect(() => output.impacts.clear(), throwsUnsupportedError);
  });

  test('forbidding a later decision based on previous alternative '
      'also has a measurable impact, without NPC knowledge inference',
      () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final base = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [_proposal(book, 0), _proposal(book, 1)],
    );
    final result = CrossActConsequenceGate.apply(
      index: index, book: book, bookMap: map, draft: base,
      rules: [
        _rule(base,
          mode: CrossActRuleMode.forbidsPriorOutcome,
          outcome: CrossActPriorOutcome.alternative),
      ],
    );
    final fork = result.plan.situations.singleWhere(
        (s) => s.id == 'act_2_turning_point');
    final action = fork.decisions.singleWhere(
        (d) => d.id == 'act_2_accept_offer');
    expect(action.forbids, contains('act_1_alternate_outcome'));
    expect(result.hasEnforcedContinuity, true);
    expect(result.audit.counterexamples, isEmpty);
  });

  test('unreviewed, wrong edition, wrong source anchor, backward act or '
      'an unreviewable target cannot silently create game facts',
      () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final base = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [_proposal(book, 0), _proposal(book, 1)],
    );
    void rejected(CrossActConsequenceRule rule) {
      expect(() => CrossActConsequenceGate.apply(
        index: index, book: book, bookMap: map,
        draft: base, rules: [rule]), throwsFormatException);
    }
    rejected(_rule(base, approved: false));
    rejected(_rule(base, priorEvidence: book.events.first.id));
    rejected(_rule(base, laterEvidence: book.events.last.id));
    rejected(_rule(base, earlierAct: base.parts[1].actId,
        laterAct: base.parts[0].actId));
    rejected(_rule(base, decision: 'act_2_honor_condition'));
    rejected(_rule(base, decision: 'act_1_accept_offer'));
    expect(() => CrossActConsequenceGate.apply(
      index: _index('Изменённый перевод.'),
      book: book, bookMap: map, draft: base,
      rules: [_rule(base)]), throwsFormatException);
  });

  test('over-restricting both second-act choices is rejected as '
      'a real game-state dead end rather than published or repaired',
      () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final base = BookwideStoryPlanComposer.compose(
      index: index, book: book, bookMap: map,
      actProposals: [_proposal(book, 0), _proposal(book, 1)],
    );
    expect(() => CrossActConsequenceGate.apply(
      index: index, book: book, bookMap: map, draft: base,
      rules: [
        _rule(base, id: 'rule_a', decision: 'act_2_accept_offer'),
        _rule(base, id: 'rule_b', decision: 'act_2_refuse_offer'),
      ],
    ), throwsFormatException);
    expect(() => CrossActConsequenceGate.apply(
      index: index, book: book, bookMap: map, draft: base,
      rules: [_rule(base, id: 'same'), _rule(base, id: 'same')],
    ), throwsFormatException);
  });
}
