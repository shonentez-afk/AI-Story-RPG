import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/story_plan_causal_audit.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memory implements SourceAnalysisCheckpointRepository {
  String? value;
  @override
  Future<String?> read(String fingerprint) async => value;
  @override
  Future<void> write(String fingerprint, String text) async { value = text; }
  @override
  Future<void> delete(String fingerprint) async { value = null; }
}

Future<NarrativeBookModel> _book() async {
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Два сообщения из одной истории',
    author: 'Тест',
    chapters: [
      'В первом эпизоде герой хотел получить помощь, но вспомнил, '
          'что обещание может потребовать исполнения позже.',
      'В другом эпизоде встретился хранитель тайны. '
          'Рассказчик не доказал, кто действительно знал секрет.',
    ],
  ));
  final analysis = ZaiAutoWholeBookAnalysis(
    repository: _Memory(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final proposal = SemanticCandidate.propose(
        source, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16,
        endUtf16: chunk.startUtf16 + 60,
        label: 'Возможное событие, требующее смысловой проверки',
        uncertainty: 'Порядок текста не доказывает причины и знания героя.',
      );
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [proposal],
        ),
        totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final result = await analysis.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 12,
  );
  return NarrativeBookModel.fromExisting(
      index: index, outline: ZaiWholeBookEventOutline.build(result));
}

StorySituation _s(String id, List<StoryDecision> decisions,
    {bool terminal = false}) => StorySituation(
      id: id,
      goal: 'Игровая ситуация с явным последствием',
      conflict: 'Выбор зависит от накопленных состояний',
      chapterIndex: 0,
      terminal: terminal,
      decisions: decisions,
    );

StoryDecision _d(String id, String next, {
  List<String> requires = const [],
  List<String> adds = const [],
  String? event,
}) => StoryDecision(
    id: id,
    intent: 'Выбрать следующий осмысленный вариант',
    nextSituationId: next,
    requires: requires,
    adds: adds,
    sourceEventId: event,
  );

StoryPlan _plan(NarrativeBookModel book, {
  bool guardHonor = false,
  bool guardKnowledge = false,
  bool duplicateOwnership = false,
}) {
  final flags = [
    'accepted', 'declined', 'secret_known', 'owner_a', 'owner_b',
  ];
  return StoryPlan(
    sourceFingerprint: book.sourceFingerprint,
    title: book.title,
    entrySituationId: 'start',
    flags: flags, initialFlags: const [],
    situations: [
      _s('start', [
        _d('accept', 'crossroads', adds: ['accepted', 'secret_known'],
            event: book.events.last.id),
        _d('decline', 'crossroads',
            adds: duplicateOwnership
                ? ['declined', 'owner_a', 'owner_b'] : ['declined']),
      ]),
      _s('crossroads', [
        _d('honor', 'canon_end', requires: guardHonor
            ? ['accepted'] : const []),
        _d('mention_secret', 'canon_end', requires: guardKnowledge
            ? ['secret_known'] : const []),
        _d('explore', 'alt_end'),
      ]),
      _s('canon_end', const [], terminal: true),
      _s('alt_end', const [], terminal: true),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an invalid demand to honor a refused promise has a shortest path',
      () async {
    final book = await _book();
    final plan = _plan(book);
    expect(plan.validate(book).isStructurallySound, true);
    final result = StoryPlanCausalAuditor.audit(
      plan: plan, book: book,
      contract: StoryCausalContract(
        decisionInvariants: [
          StoryDecisionInvariant(
            id: 'promise_gate', decisionId: 'honor',
            requires: ['accepted'], forbids: ['declined'],
          ),
        ],
      ),
    );
    expect(result.passedFormalContracts, false);
    expect(result.counterexamples, hasLength(1));
    final issue = result.counterexamples.single;
    expect(issue.code, 'CAUSAL_PRECONDITION');
    expect(issue.invariantId, 'promise_gate');
    expect(issue.pathChoiceIds, ['decline', 'honor']);
    expect(issue.activeFlagsBefore, contains('declined'));
    expect(issue.activeFlagsBefore, isNot(contains('accepted')));
    expect(result.meaningVerified, false);
    expect(result.canPublish, false);
  });

  test('guarded promise path is structurally safe but not proven canonical',
      () async {
    final book = await _book();
    final plan = _plan(book, guardHonor: true);
    final audit = StoryPlanCausalAuditor.audit(
      plan: plan, book: book,
      contract: StoryCausalContract(
        decisionInvariants: [
          StoryDecisionInvariant(id: 'promise_gate',
              decisionId: 'honor', requires: ['accepted'],
              forbids: ['declined']),
        ],
      ),
    );
    expect(audit.counterexamples, isEmpty);
    expect(audit.passedFormalContracts, true);
    expect(audit.isPlayable, false);
  });

  test('knowledge of an event is blocked until a specific source event '
      'decision is performed, not merely a chapter is reached', () async {
    final book = await _book();
    final gate = StoryEventKnowledgeGate(
      id: 'secret_after_event',
      revealEventId: book.events.last.id,
      grantDecisionId: 'accept',
      knowledgeFlag: 'secret_known',
      protectedDecisionIds: ['mention_secret'],
    );
    final leaking = StoryPlanCausalAuditor.audit(
      plan: _plan(book), book: book,
      contract: StoryCausalContract(knowledgeGates: [gate]),
    );
    expect(leaking.counterexamples.map((e) => e.code),
        contains('PREMATURE_REVEAL'));
    final witness = leaking.counterexamples.firstWhere(
        (e) => e.code == 'PREMATURE_REVEAL');
    expect(witness.pathChoiceIds, ['decline', 'mention_secret']);
    expect(witness.activeFlagsBefore, isNot(contains('secret_known')));
    final safe = StoryPlanCausalAuditor.audit(
      plan: _plan(book, guardKnowledge: true),
      book: book,
      contract: StoryCausalContract(knowledgeGates: [gate]),
    );
    expect(safe.counterexamples, isEmpty);
    final wrong = StoryEventKnowledgeGate(
      id: 'other_reveal', revealEventId: book.events.first.id,
      grantDecisionId: 'accept', knowledgeFlag: 'secret_known',
      protectedDecisionIds: ['mention_secret'],
    );
    expect(() => StoryPlanCausalAuditor.audit(
        plan: _plan(book), book: book,
        contract: StoryCausalContract(knowledgeGates: [wrong])),
        throwsFormatException);
  });

  test('mutually exclusive ownership flags catch one item in two places',
      () async {
    final book = await _book();
    final result = StoryPlanCausalAuditor.audit(
      plan: _plan(book, duplicateOwnership: true), book: book,
      contract: StoryCausalContract(exclusiveGroups: [
        StoryExclusiveFlags(id: 'single_owner',
            flags: ['owner_a', 'owner_b']),
      ]),
    );
    final issue = result.counterexamples.single;
    expect(issue.code, 'EXCLUSIVE_STATE_COLLISION');
    expect(issue.pathChoiceIds, ['decline']);
    expect(issue.invariantId, 'single_owner');
  });

  test('unknown flags and event IDs cannot manufacture verified knowledge',
      () async {
    final book = await _book();
    expect(() => StoryPlanCausalAuditor.audit(
      plan: _plan(book), book: book,
      contract: StoryCausalContract(decisionInvariants: [
        StoryDecisionInvariant(
          id: 'made_up', decisionId: 'honor', requires: ['not_declared'],
        ),
      ]),
    ), throwsFormatException);
    expect(() => StoryPlanCausalAuditor.audit(
      plan: _plan(book), book: book,
      contract: StoryCausalContract(knowledgeGates: [
        StoryEventKnowledgeGate(id: 'false_event',
          revealEventId: 'other_edition_event',
          grantDecisionId: 'accept',
          knowledgeFlag: 'secret_known',
          protectedDecisionIds: ['mention_secret'],
        ),
      ]),
    ), throwsFormatException);
  });
}
