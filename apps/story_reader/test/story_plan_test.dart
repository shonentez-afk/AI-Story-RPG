import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/intermediate_story_blueprint.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
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
    title: 'История о помощи и выборе',
    author: 'Тест',
    chapters: [
      'Путник обнаружил утраченную вещь рядом с колодцем и '
          'встретил незнакомца, который попросил о помощи.',
      'Он задумался над обещанием и нашёл иной путь к цели. '
          'Рассказчик пока не сообщает, кто владеет вещью.',
    ],
  ));
  final analysis = ZaiAutoWholeBookAnalysis(
    repository: _Memory(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final candidate = SemanticCandidate.propose(
        source, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16,
        endUtf16: chunk.startUtf16 + 60,
        label: 'Предполагаемое событие',
        uncertainty: 'Модель не может доказать причинность по цитате.',
      );
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [candidate],
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

StoryPlan _plan(NarrativeBookModel book, {bool noEffects = false}) {
  StoryDecision d(String id, String label, String next,
      {List<String> requires = const [], List<String> forbids = const [],
      List<String> adds = const []}) => StoryDecision(
        id: id, intent: label, nextSituationId: next,
        requires: requires, forbids: forbids,
        adds: noEffects ? const [] : adds,
      );
  StorySituation s(String id, String goal, List<StoryDecision> decisions,
      {bool terminal = false}) => StorySituation(
        id: id, goal: goal, conflict: 'Решение меняет возможные продолжения.',
        chapterIndex: 0, terminal: terminal, decisions: decisions,
      );
  return StoryPlan(
    sourceFingerprint: book.sourceFingerprint, title: book.title,
    entrySituationId: 'start',
    flags: const ['promised', 'refused', 'found_help'],
    initialFlags: const [],
    situations: [
      s('start', 'Выбрать отношение к просьбе.', [
        d('accept', 'Дать обещание помощи', 'promise',
            adds: ['promised']),
        d('decline', 'Отказаться от условия', 'search',
            adds: ['refused']),
      ]),
      s('promise', 'Исполнить взятое обязательство.', [
        d('honor', 'Исполнить обещание', 'canonical_end',
            requires: ['promised'], forbids: ['refused']),
      ]),
      s('search', 'Найти способ без обещания.', [
        d('explore', 'Искать другую возможность', 'discovery',
            requires: ['refused'], forbids: ['promised'],
            adds: ['found_help']),
      ]),
      s('discovery', 'Решить, как применить находку.', [
        d('finish_other', 'Воспользоваться новой возможностью', 'other_end',
            requires: ['found_help', 'refused'],
            forbids: ['promised']),
      ]),
      s('canonical_end', 'Обязательство выполнено.', const [], terminal: true),
      s('other_end', 'Найден другой результат.', const [], terminal: true),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M2g3b typed contract preserves multi-step mutually exclusive paths',
      () async {
    final book = await _book();
    final plan = _plan(book);
    final report = plan.validate(book);
    expect(report.isStructurallySound, true);
    expect(report.reachableSituations, 6);
    expect(report.terminalSituations, 2);
    expect(report.branchChangesState, true);
    expect(report.isSemanticallyApproved, false);
    expect(report.isReadyToPlay, false);
    expect(plan.isPlayable, false);
    expect(plan.hasVerifiedCausality, false);
    expect(plan.canPublish, false);
    final decoded = StoryPlan.decode(plan.encode());
    expect(decoded.encode(), plan.encode());
    final draft = decoded.toIntermediateDraft(book,
        rights: PreparationRights.privateUse);
    expect(draft.scenes, hasLength(6));
    expect(draft.flags, contains('promised'));
    expect(draft.scenes[2].choices.single.requires, contains('refused'));
    expect(draft.scenes[2].choices.single.forbids, contains('promised'));
    expect(draft.scenes.every(
        (scene) => scene.origin == DraftSceneOrigin.explicitAdaptation), true);
    expect(draft.canPublishBookworld, false);
    expect(() => plan.flags.add('hack'), throwsUnsupportedError);
    expect(() => plan.situations.first.decisions.clear(),
        throwsUnsupportedError);
  });

  test('a cosmetic-only graph is rejected before M2c translation', () async {
    final book = await _book();
    final plan = _plan(book, noEffects: true);
    // Without the promised/refused flags the required follow-up actions
    // cannot be taken. Reject the dead end instead of counting two endings.
    expect(() => plan.validate(book), throwsFormatException);
    expect(() => plan.toIntermediateDraft(book), throwsFormatException);
  });

  test('unknown source edition, forged status and missing targets fail',
      () async {
    final book = await _book();
    final plan = _plan(book);
    final tampered = plan.encode().replaceFirst(
        '"status":"DRAFT_ONLY"', '"status":"READY"');
    expect(() => StoryPlan.decode(tampered), throwsFormatException);
    final wrong = StoryPlan(
      sourceFingerprint: 'not-the-book',
      title: plan.title,
      entrySituationId: plan.entrySituationId,
      flags: plan.flags,
      initialFlags: plan.initialFlags,
      situations: plan.situations,
    );
    expect(() => wrong.validate(book), throwsFormatException);
    final dangling = StoryPlan(
      sourceFingerprint: plan.sourceFingerprint,
      title: plan.title,
      entrySituationId: plan.entrySituationId,
      flags: plan.flags, initialFlags: plan.initialFlags,
      situations: [
        StorySituation(
          id: 'start', goal: 'Начало', conflict: 'Выбор пути',
          chapterIndex: 0, terminal: false,
          decisions: [StoryDecision(
            id: 'unknown', intent: 'Невозможная цель',
            nextSituationId: 'missing')],
        ),
      ],
    );
    expect(() => dangling.validate(book), throwsFormatException);
  });
}
