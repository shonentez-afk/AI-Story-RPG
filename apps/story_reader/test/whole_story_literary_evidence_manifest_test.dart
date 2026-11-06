import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/whole_story_literary_evidence_manifest.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

BookSourceIndex _index({String extra = ''}) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Литературный аудит решений',
      author: 'Синтетический тест',
      chapters: [
        List.filled(6, 'Путник услышал просьбу помочь и '
            'не давал никаких обещаний. ').join(' '),
        List.filled(6, 'Прохожий утверждал, что ключ уже '
            'принадлежит путнику; рассказчик не подтвердил это. ').join(' '),
        List.filled(6, 'После путешествия рассказчик '
            'возвращается к более раннему дню. ').join(' ') + extra,
      ],
    ));

Future<NarrativeBookModel> _book(BookSourceIndex index, {
  SourceSemanticCatalog? catalog,
  SourceEvidenceGraph? evidence,
}) async {
  final preview = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final candidates = [
        for (final chunk in window.chunks)
          SemanticCandidate.propose(source, chunk,
            category: SemanticCategory.event,
            startUtf16: chunk.startUtf16,
            endUtf16: chunk.startUtf16 + 60,
            label: 'Предположение, не подтверждённое каноном',
            uncertainty: 'Текст не доказывает смысл, знания и причинность.',
          ),
      ];
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final chunk in window.chunks) chunk.id],
          candidates: candidates,
        ),
        totalSuggestions: candidates.length,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final review = await preview.analyze(
    index: index, approvedManifestDigest: consent.approvalDigest,
    explicitWholeBookConsent: true, maxWindowsPerRun: 64,
  );
  return NarrativeBookModel.fromExisting(index: index,
      outline: ZaiWholeBookEventOutline.build(review),
      catalog: catalog, evidence: evidence);
}

StoryPlan _plan(NarrativeBookModel book, {String accept = 'Согласиться'}) {
  final first = book.events.first;
  final last = book.events.last;
  StoryDecision decision(String id, String next, {
    List<String> requires = const [],
    List<String> adds = const [],
    String? sourceEventId,
  }) => StoryDecision(
    id: id, intent: id == 'accept' ? accept : 'Выбор ' + id,
    nextSituationId: next,
    sourceEventId: sourceEventId,
    requires: requires, adds: adds,
  );
  StorySituation situation(String id, int chapter,
      List<StoryDecision> decisions, {
        String? sourceId, bool terminal = false,
      }) => StorySituation(
    id: id, goal: 'Результат ' + id,
    conflict: 'Причинность художественной адаптации не доказана.',
    chapterIndex: chapter, sourceEventId: sourceId,
    terminal: terminal, decisions: decisions,
  );
  return StoryPlan(
    sourceFingerprint: book.sourceFingerprint,
    title: book.title, entrySituationId: 'start',
    flags: const ['promised', 'refused', 'not_available'],
    initialFlags: const [],
    situations: [
      situation('start', first.source.chapterIndex, [
        decision('accept', 'accept_path', adds: ['promised'],
            sourceEventId: first.id),
        decision('refuse', 'refuse_path', adds: ['refused'],
            sourceEventId: first.id),
        decision('disabled_choice', 'accept_path',
            requires: ['not_available']),
      ], sourceId: first.id),
      situation('accept_path', last.source.chapterIndex, [
        decision('keep_promise', 'promise_end',
            requires: ['promised'], sourceEventId: last.id),
      ], sourceId: last.id),
      situation('refuse_path', last.source.chapterIndex, [
        decision('seek_other', 'free_end',
            requires: ['refused'], sourceEventId: last.id),
      ], sourceId: last.id),
      situation('promise_end', last.source.chapterIndex,
          [], sourceId: last.id, terminal: true),
      situation('free_end', last.source.chapterIndex,
          [], sourceId: last.id, terminal: true),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('replays ALL reachable transitions and keeps uncovered events honest',
      () async {
    final index = _index();
    final book = await _book(index);
    final plan = _plan(book);
    expect(book.events.length, greaterThanOrEqualTo(3));
    expect(plan.validate(book).isStructurallySound, true);

    final manifest = WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: plan);
    final data = manifest.toJson();
    expect(manifest.reachableStates, 5);
    expect(manifest.reachableTransitions, 4);
    expect(manifest.reachableEndings, 2);
    expect(manifest.disabledDecisions, 1);
    expect(data['decisions_never_enabled'], ['disabled_choice']);
    expect(manifest.sourceEventsTotal, book.events.length);
    expect(manifest.reachableSourceEvents, 2);
    expect(manifest.uncoveredSourceEvents, book.events.length - 2);
    expect(data['events_not_used_by_game'], isNotEmpty);
    expect(data['chapters_with_reachable_source_events'], 2);
    expect((data['two_shortest_complete_routes'] as List), hasLength(2));
    final steps = data['all_reachable_transitions'] as List;
    expect(steps.map((s) => (s as Map)['choice_id']),
        containsAll(['accept', 'refuse', 'keep_promise', 'seek_other']));
    expect(steps.every((s) => (s as Map)['meaning_verified'] == false),
        true);
    expect(data['literary_canon_verified'], false);
    expect(data['cloud_consent_granted'], false);
    expect(manifest.verifiesLiteraryCanon, false);
    expect(manifest.mayChangeBookWorld, false);
    expect(manifest.maySendToCloudWithoutSeparateConsent, false);
    expect(manifest.encode().contains('Путник услышал просьбу'), false);
    manifest.verifyUnchanged(index: index, book: book, plan: plan);
  });

  test('source and plan changes invalidate original evidence digest',
      () async {
    final index = _index();
    final book = await _book(index);
    final plan = _plan(book);
    final manifest = WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: plan);
    final modified = _plan(book, accept: 'Согласиться на иной договор');
    expect(() => manifest.verifyUnchanged(
        index: index, book: book, plan: modified), throwsFormatException);
    expect(() => WholeStoryLiteraryEvidenceManifest.build(
        index: _index(extra: ' Другая редакция.'),
        book: book, plan: plan), throwsFormatException);
    final escaped = manifest.toJson();
    escaped['literary_canon_verified'] = true;
    expect(manifest.toJson()['literary_canon_verified'], false);
    expect(manifest.approvalDigest,
        WholeStoryLiteraryEvidenceManifest.build(
            index: index, book: book, plan: plan).approvalDigest);
  });


  test('reported NPC speech stays an untrusted claim, even with exact quote',
      () async {
    final index = _index();
    final chunk = index.chunks.firstWhere((c) => c.chapterIndex == 1);
    const quote = 'Прохожий утверждал, что ключ';
    final at = chunk.text.indexOf(quote);
    expect(at, greaterThanOrEqualTo(0));
    final source = SourceEvidence.propose(index,
      chunkId: chunk.id, kind: EvidenceKind.fact,
      startUtf16: chunk.startUtf16 + at,
      endUtf16: chunk.startUtf16 + at + quote.length,
    );
    final evidence = SourceEvidenceGraph.empty(index)
        .addAll(index, [source]);
    final claim = SourceSemanticAssertion.propose(index, evidence,
      kind: SemanticAssertionKind.fact,
      evidenceIds: [source.id],
      subject: 'прохожий', predicate: 'утверждал',
      object: 'ключ принадлежит путнику',
      voice: AssertionVoice.reported,
      polarity: AssertionPolarity.ambiguous,
      time: AssertionTime.flashbackPossible,
      uncertainty: 'Речь свидетеля не устанавливает владение ключом.',
    );
    final catalog = SourceSemanticCatalog.checked(
        index, evidence, [claim]);
    final book = await _book(index,
        catalog: catalog, evidence: evidence);
    final plan = _plan(book);
    expect(() => WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: plan), throwsFormatException);
    final manifest = WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: plan, claimEvidence: evidence);
    expect(manifest.claimsWithVerifiedQuotes, 1);
    final listed = manifest.toJson()['source_claims'] as List;
    expect(listed, hasLength(1));
    expect((listed.single as Map)['voice'],
        'REPORTED_SPEECH_NOT_WORLD_TRUTH');
    expect(listed.single['world_time_inferred'], false);
    expect(listed.single['is_canon'], false);
  });

  test('no narrator claim or chapter order is promoted to literary canon',
      () async {
    final index = _index();
    final book = await _book(index);
    final manifest = WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: _plan(book));
    final data = manifest.toJson();
    expect(data['world_chronology_verified'], false);
    expect(data['npc_knowledge_verified'], false);
    expect(data['character_motivation_verified'], false);
    expect(data['source_claims'], isEmpty);
    expect(data['status'], 'LITERARY_REVIEW_REQUIRED');
  });
}
