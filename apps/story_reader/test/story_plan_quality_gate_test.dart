import 'dart:convert';

import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/story_plan_quality_gate.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memory implements SourceAnalysisCheckpointRepository {
  String? raw;
  @override
  Future<String?> read(String fingerprint) async => raw;
  @override
  Future<void> write(String fingerprint, String text) async { raw = text; }
  @override
  Future<void> delete(String fingerprint) async { raw = null; }
}

Future<NarrativeBookModel> _book({String title = 'Новая история'}) async {
  final index = BookSourceIndexer.index(ImportedBook(
    title: title,
    author: 'Тест',
    chapters: [
      'У ворот герой обнаружил незнакомую вещь и услышал '
          'предложение помочь ему в обмен на обещание.',
      'Когда герой встретил стража, тот предложил иной путь. '
          'В тексте ещё не сказано, чем закончится его решение.',
    ],
  ));
  final preview = ZaiAutoWholeBookAnalysis(
    repository: _Memory(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [
            SemanticCandidate.propose(
              source, chunk,
              category: SemanticCategory.event,
              startUtf16: chunk.startUtf16,
              endUtf16: chunk.startUtf16 + 60,
              label: 'Возможное событие для сценария',
              uncertainty: 'Последствия ещё не доказаны.',
            ),
          ],
        ),
        totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final result = await preview.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 12,
  );
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(result),
  );
}

StoryDilemmaProposal _proposal(NarrativeBookModel book,
    {StoryDilemmaKind kind = StoryDilemmaKind.agreement,
    String? fingerprint}) => StoryDilemmaProposal(
  sourceFingerprint: fingerprint ?? book.sourceFingerprint,
  setupEventId: book.events.first.id,
  outcomeEventId: book.events.last.id,
  kind: kind,
  dilemma: 'Выбрать предложенное условие или искать другой путь',
  acceptIntent: 'Согласиться на предложение и взять обязательство',
  refuseIntent: 'Отказаться от условия и продолжить поиск',
  followupGoal: 'Подумать о последствиях принятого обязательства',
  finishOriginalIntent: 'Выполнить ранее принятое обязательство',
  originalEnding: 'Герой завершил историю по предложенной линии',
  alternativeSearchGoal: 'Отправиться на поиски другого решения',
  searchIntent: 'Осмотреть местность и спросить окружающих',
  alternativeDiscovery: 'Поиск даёт другую возможность продолжения',
  useDiscoveryIntent: 'Воспользоваться найденным решением',
  alternativeEnding: 'Герой завершил историю альтернативным способом',
);

ZaiStoryDilemmaPreview _preview(NarrativeBookModel book,
    StoryDilemmaProposal proposal) => ZaiStoryDilemmaPreview(
  proposal: proposal,
  plan: StoryPlanDilemmaGenerator.propose(book, proposal),
  sampledEventCount: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('complete source-locked plan passes formal rules but cannot be '
      'installed as a game or treated as confirmed book canon', () async {
    final book = await _book();
    final proposal = _proposal(book);
    final report = StoryPlanQualityGate.assess(
      book: book,
      preview: _preview(book, proposal),
    );
    expect(report.passedFormalPreflight, true);
    expect(report.repair.before.counterexamples, isEmpty);
    expect(report.repair.after.counterexamples, isEmpty);
    expect(report.repair.appliedChanges, isEmpty);
    expect(report.plan.situations, hasLength(7));
    expect(report.intermediateDraft.scenes, hasLength(7));
    expect(report.intermediateDraft.canPublishBookworld, false);
    expect(report.meaningConfirmed, false);
    expect(report.chronologyConfirmed, false);
    expect(report.sceneProseApproved, false);
    expect(report.readyToInstall, false);
    expect(report.readyToPlay, false);
    expect(report.canPublish, false);
    expect(report.reviewRequirements, isNotEmpty);
    final summary = report.toReadinessJson();
    expect(summary['status'], 'DRAFT_ONLY');
    expect(summary['formal_preflight_passed'], true);
    expect(summary['ready_to_install'], false);
    expect(summary['ready_to_play'], false);
    expect(jsonEncode(summary), isNot(contains(book.title)));
    expect(jsonEncode(summary), isNot(contains(book.sourceFingerprint)));
    expect(jsonEncode(summary), isNot(contains(book.events.first.source.quote)));
    expect(() => report.reviewRequirements.clear(), throwsUnsupportedError);
  });

  test('all supported dilemma kinds get distinct exclusive state contracts',
      () async {
    final book = await _book();
    for (final kind in StoryDilemmaKind.values) {
      final proposal = _proposal(book, kind: kind);
      final report = StoryPlanQualityGate.assess(
          book: book, preview: _preview(book, proposal));
      expect(report.passedFormalPreflight, true);
      final prefix = kind.name;
      expect(report.causalContract.exclusiveGroups.first.flags,
          ['' + prefix + '_accepted', '' + prefix + '_declined']);
      expect(report.causalContract.decisionInvariants, hasLength(4));
    }
  });

  test('cannot turn an AI-revised plan with lost acceptance conditions '
      'into an approved blueprint', () async {
    final book = await _book();
    final proposal = _proposal(book);
    final generated = StoryPlanDilemmaGenerator.propose(book, proposal);
    final data = jsonDecode(generated.encode()) as Map<String, dynamic>;
    final situations = data['situations'] as List<dynamic>;
    final acceptedPath = situations.firstWhere(
        (dynamic raw) => (raw as Map)['id'] == 'accept_path') as Map;
    final choices = acceptedPath['decisions'] as List;
    final honor = choices.first as Map;
    honor['requires'] = <String>[];
    honor['forbids'] = <String>[];
    final corrupted = StoryPlan.decode(jsonEncode(data));
    // The altered draft is still structurally reachable but fails the
    // source-bound regeneration check; no automatic trust escalation.
    expect(corrupted.validate(book).isStructurallySound, true);
    expect(() => StoryPlanQualityGate.assess(
      book: book,
      preview: ZaiStoryDilemmaPreview(
        proposal: proposal, plan: corrupted, sampledEventCount: 2),
    ), throwsFormatException);
  });

  test('an absent proposal, another edition, and another source title '
      'cannot be accepted', () async {
    final book = await _book();
    expect(() => StoryPlanQualityGate.assess(
      book: book,
      preview: const ZaiStoryDilemmaPreview(
        proposal: null, plan: null, sampledEventCount: 2),
    ), throwsFormatException);
    final wrong = _proposal(book, fingerprint: 'different-edition');
    expect(() => StoryPlanQualityGate.assess(
      book: book,
      preview: ZaiStoryDilemmaPreview(
        proposal: wrong,
        plan: StoryPlanDilemmaGenerator.propose(book,
            _proposal(book)),
        sampledEventCount: 2,
      ),
    ), throwsFormatException);
    final other = await _book(title: 'Другая книга');
    expect(other.sourceFingerprint, isNot(book.sourceFingerprint));
    expect(() => StoryPlanQualityGate.assess(
      book: other,
      preview: _preview(book, _proposal(book)),
    ), throwsFormatException);
  });
}
