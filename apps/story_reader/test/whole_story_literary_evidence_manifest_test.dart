import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_evidence_graph.dart';
import 'package:ai_story_reader/source_semantic_catalog.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/whole_story_literary_evidence_manifest.dart';
import 'package:ai_story_reader/whole_story_literary_review.dart';
import 'package:ai_story_reader/whole_story_literary_batch.dart';
import 'package:ai_story_reader/whole_story_literary_review_page.dart';
import 'package:flutter/material.dart';
import 'package:ai_story_reader/ai_connection.dart';
import 'dart:convert';
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


StoryPlan _widePlan(NarrativeBookModel book) {
  final a = book.events.first;
  final b = book.events.last;
  StorySituation scene(String id, int chapter, List<StoryDecision> choices,
      {bool terminal = false, String? event}) =>
      StorySituation(id: id, goal: 'Цель игрового этапа ' + id,
          conflict: 'Действительность источника требует проверки.',
          chapterIndex: chapter, sourceEventId: event,
          terminal: terminal, decisions: choices);
  StoryDecision choice(String id, String next,
      {List<String> adds = const [], String? event}) =>
      StoryDecision(id: id, intent: 'Выбор ' + id,
          nextSituationId: next, sourceEventId: event, adds: adds);
  return StoryPlan(
    sourceFingerprint: book.sourceFingerprint,
    title: book.title, entrySituationId: 'start',
    flags: const ['accepted', 'refused'], initialFlags: const [],
    situations: [
      scene('start', 0, [
        choice('accept', 'stage_0', adds: ['accepted'], event: a.id),
        choice('refuse', 'free_end', adds: ['refused'], event: a.id),
      ], event: a.id),
      for (var i = 0; i < 18; i++)
        scene('stage_' + i.toString(), 2, [
          choice('advance_' + i.toString(),
              i == 17 ? 'accepted_end' : 'stage_' + (i + 1).toString(),
              event: b.id),
        ], event: b.id),
      scene('accepted_end', 2, const [], terminal: true, event: b.id),
      scene('free_end', 0, const [], terminal: true, event: a.id),
    ],
  );
}

Map<String, dynamic> _reviewRecord(LiteraryReviewWindow window, {
    String? choiceOverride, String? sourceOverride}) {
  final step = window.transitions.first;
  final source = step['choice_source_event_id'] ??
      step['scene_source_event_id'];
  return {
    'window_digest': window.approvalDigest,
    'verdict': 'insufficientEvidence',
    'uncertainty': 'Причинность не подтверждена полной книгой и знаниями героя.',
    'findings': [
      {
        'kind': 'actorKnowledge', 'severity': 'medium',
        'scene_id': step['scene_id'],
        'choice_id': choiceOverride ?? step['choice_id'],
        'source_event_id': sourceOverride ?? source,
        'problem': 'Персонажу может быть неизвестна важная информация.',
      },
    ],
    'status': 'UNVERIFIED_AI_REVIEW',
  };
}

class _AllowAi extends AiCloudPreferences {
  @override
  Future<bool> isEnabled() async => true;
}

class _TestKey implements AiApiKeyVault {
  @override
  Future<String?> read() async => 'MOCK_KEY_ONLY';
  @override
  Future<bool> hasKey() async => true;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

class _RetryTransport implements AiHttpTransport {
  _RetryTransport(this.ok);
  final String ok;
  final List<String> requests = [];
  @override
  Future<AiHttpResponse> send({
    required Uri uri, required Map<String, String> headers,
    required String body,
  }) async {
    expect(uri, ZaiModel.endpoint);
    expect(headers['Authorization'], 'Bearer MOCK_KEY_ONLY');
    requests.add(body);
    return requests.length == 1
        ? const AiHttpResponse(429, '{}', retryAfter: '0')
        : AiHttpResponse(200, ok);
  }
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

  test('literary review includes ALL reachable transitions or fails',
      () async {
    final index = _index();
    final book = await _book(index);
    final plan = _widePlan(book);
    final evidence = WholeStoryLiteraryEvidenceManifest.build(
        index: index, book: book, plan: plan);
    final manifest = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: index, book: book, plan: plan, evidence: evidence);
    expect(manifest.totalTransitions, 20);
    expect(manifest.totalWindows, 3);
    expect(manifest.windows.fold<int>(0,
        (n, w) => n + w.transitions.length), 20);
    expect(manifest.windows.every((w) =>
        w.sourceQuotes.length <= 8 && w.transitions.length <= 8), true);
    expect(manifest.claimsLiteraryCanon, false);
    expect(manifest.permitsGameMutation, false);
    expect(manifest.windows.every((w) =>
        w.sentContext['chapter_order_is_world_time'] == false), true);
    manifest.verifyUnchanged();
    expect(() => WholeStoryLiteraryReviewManifest.fromEvidence(
        index: index, book: book, plan: plan, evidence: evidence,
        maxNewRequestsPerRun: 3), throwsFormatException);
  });

  test('GLM critique rejects invented scene, source and truncated JSON',
      () async {
    final index = _index();
    final book = await _book(index);
    final plan = _plan(book);
    final manifest = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: index, book: book, plan: plan,
        evidence: WholeStoryLiteraryEvidenceManifest.build(
            index: index, book: book, plan: plan));
    final window = manifest.windows.single;
    final valid = _reviewRecord(window);
    final report = WholeLiteraryReviewReport.fromJson(window, valid);
    expect(report.findings, hasLength(1));
    expect(report.provesLiteraryCanon, false);
    expect(() => WholeLiteraryReviewReport.fromJson(
        window, _reviewRecord(window, choiceOverride: 'invented')),
        throwsFormatException);
    expect(() => WholeLiteraryReviewReport.fromJson(
        window, _reviewRecord(window, sourceOverride: 'unknown_source')),
        throwsFormatException);
    final response = jsonEncode({'choices': [
      {'finish_reason': 'length', 'message': {
        'content': jsonEncode(valid),
      }},
    ]});
    expect(() => ZaiWholeStoryLiteraryCritic.parse(window, response),
        throwsA(isA<AiSetupException>()));
  });

  test('explicit consent, at most two calls and local resume without re-pay',
      () async {
    final index = _index();
    final book = await _book(index);
    final plan = _widePlan(book);
    final manifest = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: index, book: book, plan: plan,
        evidence: WholeStoryLiteraryEvidenceManifest.build(
            index: index, book: book, plan: plan));
    final memory = MemorySourceAnalysisCheckpointRepository();
    var posts = 0;
    final service = WholeStoryLiteraryBatchService(
      repository: memory,
      previewOverride: (window, token) async {
        posts++;
        return WholeLiteraryReviewReport.fromJson(
            window, _reviewRecord(window));
      },
    );
    await expectLater(service.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: false), throwsFormatException);
    expect(posts, 0);
    final first = await service.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true);
    expect(first.newRequests, 2);
    expect(first.completed, 2);
    final resumed = WholeStoryLiteraryBatchService(
      repository: memory,
      previewOverride: (window, token) async {
        posts++;
        return WholeLiteraryReviewReport.fromJson(
            window, _reviewRecord(window));
      },
    );
    expect((await resumed.inspect(manifest)).completed, 2);
    final next = await resumed.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true);
    expect(next.recovered, 2);
    expect(next.newRequests, 1);
    expect(posts, 3);
    final again = await resumed.generate(
      manifest: manifest, approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true);
    expect(again.newRequests, 0);
    expect(posts, 3);
    final saved = await memory.read(index.sourceFingerprint);
    expect(saved, isNotNull);
    await memory.write(index.sourceFingerprint,
        saved!.replaceFirst('UNVERIFIED_AI_REVIEW', 'CANON_APPROVED'));
    await expectLater(resumed.inspect(manifest), throwsFormatException);
  });


  testWidgets('M2h8g1b UI does not call model until both checks',
      (tester) async {
    final index = _index();
    final book = await _book(index);
    final plan = _plan(book);
    var calls = 0;
    final service = WholeStoryLiteraryBatchService(
      repository: MemorySourceAnalysisCheckpointRepository(),
      previewOverride: (window, token) async {
        calls++;
        return WholeLiteraryReviewReport.fromJson(
            window, _reviewRecord(window));
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: WholeStoryLiteraryReviewPage(
        index: index, book: book, plan: plan, service: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, 0);
    final submit = find.byKey(const Key('whole-literary-submit'));
    final reviewed = find.byKey(const Key('whole-literary-reviewed'));
    final consent = find.byKey(const Key('whole-literary-consent'));
    // ListView builds lazily. Scroll instead of querying an offscreen button
    // before its render element exists.
    await tester.scrollUntilVisible(submit, 160);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(calls, 0);
    await tester.scrollUntilVisible(reviewed, -160);
    await tester.tap(reviewed);
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.scrollUntilVisible(consent, 160);
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(submit, 160);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(calls, 1);
    final complete = find.byKey(const Key('whole-literary-complete'));
    await tester.scrollUntilVisible(complete, -160);
    expect(complete, findsOneWidget);
  });


  test('real AI transport retries exact bytes after separate consent only',
      () async {
    final index = _index();
    final book = await _book(index);
    final plan = _plan(book);
    final manifest = WholeStoryLiteraryReviewManifest.fromEvidence(
        index: index, book: book, plan: plan,
        evidence: WholeStoryLiteraryEvidenceManifest.build(
            index: index, book: book, plan: plan));
    final window = manifest.windows.single;
    final envelope = jsonEncode({'choices': [
      {'finish_reason': 'stop', 'message': {
        'content': jsonEncode(_reviewRecord(window)),
      }},
    ]});
    final transport = _RetryTransport(envelope);
    final critic = ZaiWholeStoryLiteraryCritic(
      preferences: _AllowAi(), vault: _TestKey(),
      transport: transport, retryWait: (_) async {},
    );
    await expectLater(critic.review(
      window: window, approvedDigest: window.approvalDigest,
      explicitReviewConsent: false), throwsA(isA<AiSetupException>()));
    expect(transport.requests, isEmpty);
    final response = await critic.review(
      window: window, approvedDigest: window.approvalDigest,
      explicitReviewConsent: true);
    expect(response.findings, hasLength(1));
    expect(transport.requests, hasLength(2));
    expect(transport.requests[0], transport.requests[1]);
    expect(transport.requests[0].contains('MOCK_KEY_ONLY'), false);
  });

}
