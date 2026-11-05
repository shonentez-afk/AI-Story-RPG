import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/story_plan.dart';
import 'package:ai_story_reader/story_plan_dilemma_generator.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_source_locked_prose_preview.dart';
import 'package:ai_story_reader/source_locked_prose_checkpoint_store.dart';
import 'package:ai_story_reader/source_locked_prose_preview_page.dart';
import 'package:ai_story_reader/zai_source_locked_prose_batch.dart';
import 'package:ai_story_reader/source_locked_prose_batch_page.dart';
import 'package:ai_story_reader/reviewed_prose_scene_overlay.dart';
import 'package:ai_story_reader/zai_source_locked_prose_audit.dart';
import 'package:ai_story_reader/source_locked_prose_audit_checkpoint_store.dart';
import 'package:ai_story_reader/source_locked_prose_audit_page.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Preferences extends AiCloudPreferences {
  _Preferences(this.enabled);
  final bool enabled;
  @override
  Future<bool> isEnabled() async => enabled;
}

class _Vault implements AiApiKeyVault {
  _Vault(this.value);
  String? value;
  @override
  Future<void> write(String key) async { value = key; }
  @override
  Future<String?> read() async => value;
  @override
  Future<void> delete() async { value = null; }
  @override
  Future<bool> hasKey() async => value?.isNotEmpty == true;
}

class _Network implements AiHttpTransport {
  _Network(this.responses);
  final List<AiHttpResponse> responses;
  final List<String> bodies = [];
  final List<Uri> urls = [];
  final List<Map<String, String>> sentHeaders = [];
  @override
  Future<AiHttpResponse> send({
    required Uri uri, required Map<String, String> headers,
    required String body,
  }) async {
    urls.add(uri);
    bodies.add(body);
    sentHeaders.add(Map<String, String>.from(headers));
    return responses[bodies.length - 1];
  }
}

AiHttpResponse _answer(String scene, String prose, {
  String uncertainty = 'Смысл этой сцены требует отдельной проверки.',
  bool extra = false,
  String finishReason = 'stop',
}) => AiHttpResponse(200, jsonEncode({
  'choices': [{
    'finish_reason': finishReason,
    'message': {
      'content': jsonEncode({
        'scene_id': scene,
        'prose': prose,
        'uncertainty': uncertainty,
        if (extra) 'can_publish': true,
      }),
    },
  }],
}));

AiHttpResponse _auditResponse(String sceneId, {
  String verdict = 'needsRevision',
  String? evidenceQuote,
  bool withFinding = true,
  String kind = 'promise',
  String severity = 'high',
  bool extraField = false,
  String finishReason = 'stop',
}) => AiHttpResponse(200, jsonEncode({
  'choices': [{
    'finish_reason': finishReason,
    'message': {
      'content': jsonEncode({
        'scene_id': sceneId,
        'verdict': verdict,
        'findings': [
          if (withFinding)
            {
              'kind': kind,
              'severity': severity,
              'problem': 'В описании возможно появляется '
                  'обязательство, которое герой не принимал.',
              'evidence_quote': evidenceQuote,
            },
        ],
        'uncertainty': 'Неизвестно, имеются ли в других главах '
            'подтверждения этой причинно-следственной связи.',
        if (extraField) 'canon_confirmed': true,
      }),
    },
  }],
}));

SourceLockedProseDraft _draftFor(
    SourceLockedProseContext context) => SourceLockedProseDraft(
  sourceFingerprint: context.index.sourceFingerprint,
  situationId: context.situation.id,
  approvalDigest: context.approvalDigest,
  text: _prose,
  uncertainty: 'Связи событий пока не проверены по всей книге.',
  route: context.situation.route,
);

ZaiSourceLockedProseAuditService _auditService(_Network net, {
  bool enabled = true,
  String? key = 'SYNTHETIC-SECRET-KEY',
  Future<void> Function(Duration)? wait,
}) => ZaiSourceLockedProseAuditService(
  preferences: _Preferences(enabled),
  vault: _Vault(key),
  transport: net,
  retryWait: wait ?? (Duration duration) async {},
);

const _prose = 'Путник остановился у двери, прислушиваясь к словам '
    'собеседника. Тишина затянулась, и решение ещё не было принято. '
    'Перед ним лежали разные дороги; ни одна не обещала лёгкого пути.';

Future<(BookSourceIndex, NarrativeBookModel, StoryPlan)> _fixture() async {
  final index = BookSourceIndexer.index(const ImportedBook(
    title: 'СЕКРЕТНОЕ НАЗВАНИЕ ЭТОЙ КНИГИ',
    author: 'СЕКРЕТНЫЙ АВТОР',
    chapters: [
      'Путник увидел дверь и услышал предложение. Он ещё не принял '
          'никаких условий, хотя старик рассказал ему о ключе.',
      'Потом путник дошёл до другого берега и заметил две дороги. '
          'Он всё ещё не знал, какое условие ему предложат.',
    ],
  ));
  final analysis = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final event = SemanticCandidate.propose(
        source, chunk, category: SemanticCategory.event,
        startUtf16: chunk.startUtf16, endUtf16: chunk.startUtf16 + 70,
        label: 'Кандидат, не установленный канон',
        uncertainty: 'Причина и владение ключом пока неизвестны.',
      );
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [event],
        ),
        totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final result = await analysis.analyze(
    index: index, approvedManifestDigest: consent.approvalDigest,
    explicitWholeBookConsent: true, maxWindowsPerRun: 8,
  );
  final book = NarrativeBookModel.fromExisting(
    index: index, outline: ZaiWholeBookEventOutline.build(result));
  final plan = StoryPlanDilemmaGenerator.propose(book,
    StoryDilemmaProposal(
      sourceFingerprint: book.sourceFingerprint,
      setupEventId: book.events.first.id,
      outcomeEventId: book.events.last.id,
      kind: StoryDilemmaKind.agreement,
      dilemma: 'Принять предложенное условие или найти другой путь',
      acceptIntent: 'Добровольно согласиться на условие старика',
      refuseIntent: 'Отказаться и найти выход без обязательств',
      followupGoal: 'Рассмотреть последствия ранее принятого решения',
      finishOriginalIntent: 'Исполнить принятое игровое обещание',
      originalEnding: 'Путник завершил вымышленный первый путь',
      alternativeSearchGoal: 'Найти выход, не соглашаясь на сделку',
      searchIntent: 'Осмотреть дорогу и поискать другой способ',
      alternativeDiscovery: 'Путник заметил новый вариант развития',
      useDiscoveryIntent: 'Использовать альтернативный путь без обещания',
      alternativeEnding: 'Путник достиг другой вымышленной развязки',
    ));
  return (index, book, plan);
}

ZaiSourceLockedProsePreviewService _service(_Network net, {
  bool enabled = true,
  String? key = 'SYNTHETIC-SECRET-KEY',
  Future<void> Function(Duration)? wait,
}) => ZaiSourceLockedProsePreviewService(
  preferences: _Preferences(enabled),
  vault: _Vault(key),
  transport: net,
  retryWait: wait ?? (Duration delay) async {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('consented per-scene prose is a non-playable untrusted draft',
      () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    expect(context.sourceEvent!.id, book.events.first.id);
    expect(context.hasLiteraryMeaningVerification, false);
    expect(context.mayPublish, false);
    final net = _Network([_answer('turning_point', _prose)]);
    final draft = await _service(net).preview(
      context: context, approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true,
    );
    expect(draft.situationId, 'turning_point');
    expect(draft.text, _prose);
    expect(draft.sourceFingerprint, index.sourceFingerprint);
    expect(draft.isHumanReviewed, false);
    expect(draft.canInstallDirectly, false);
    expect(draft.canMutateCampaign, false);
    expect(draft.hasVerifiedLiteraryMeaning, false);
    expect(draft.toDiagnosticJson()['can_install'], false);
    expect(net.bodies, hasLength(1));
    expect(net.urls.single, ZaiModel.endpoint);
    final sent = net.bodies.single;
    expect(sent, contains(book.events.first.source.quote));
    expect(sent, isNot(contains(index.title)));
    expect(sent, isNot(contains(index.author)));
    expect(sent, isNot(contains(index.sourceFingerprint)));
    expect(sent, isNot(contains('SYNTHETIC-SECRET-KEY')));
    final body = jsonDecode(sent) as Map<String, dynamic>;
    expect(body['model'], ZaiModel.id);
    expect(body['thinking'], {'type': 'disabled'});
    expect(body['response_format'], {'type': 'json_object'});
    expect(body.containsKey('tools'), false);
    final shown = jsonDecode(
        (body['messages'] as List).last['content'] as String);
    expect(shown, context.consentPreview);
    expect(net.sentHeaders.single['Authorization'],
        'Bearer SYNTHETIC-SECRET-KEY');
  });

  test('draft fiction without source event never invents a quote', () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'search_path');
    expect(context.sourceEvent, isNull);
    expect(context.consentPreview.keys, isNot(contains('source_excerpt')));
    final net = _Network([_answer('search_path', _prose)]);
    final draft = await _service(net).preview(
      context: context, approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true,
    );
    expect(draft.route, StoryRoute.adaptationFiction);
    expect(net.bodies.single, isNot(contains(index.title)));
    expect(net.bodies.single, isNot(contains(index.sourceFingerprint)));
  });

  test('no cloud call without exact consent, account opt-in or key', () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final net = _Network([]);
    await expectLater(_service(net).preview(
        context: context, approvedContextDigest: context.approvalDigest,
        userReviewedExactContext: false),
        throwsA(isA<AiSetupException>()));
    await expectLater(_service(net).preview(
        context: context, approvedContextDigest: 'stale-digest',
        userReviewedExactContext: true),
        throwsA(isA<AiSetupException>()));
    await expectLater(_service(net, enabled: false).preview(
        context: context, approvedContextDigest: context.approvalDigest,
        userReviewedExactContext: true),
        throwsA(isA<AiSetupException>()));
    await expectLater(_service(net, key: null).preview(
        context: context, approvedContextDigest: context.approvalDigest,
        userReviewedExactContext: true),
        throwsA(isA<AiSetupException>()));
    expect(net.bodies, isEmpty);
  });

  test('a changed situation or another edition invalidates consent', () async {
    final (index, book, plan) = await _fixture();
    final first = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final second = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'search_path');
    final net = _Network([]);
    expect(first.approvalDigest, isNot(second.approvalDigest));
    await expectLater(_service(net).preview(
        context: second, approvedContextDigest: first.approvalDigest,
        userReviewedExactContext: true),
        throwsA(isA<AiSetupException>()));
    final foreign = BookSourceIndexer.index(const ImportedBook(
      title: 'Другая книга',
      author: 'Тест',
      chapters: ['Вторая книга не совпадает с исходной сценой.'],
    ));
    expect(() => SourceLockedProseContext.forSituation(
      index: foreign, book: book, plan: plan,
      situationId: 'turning_point'), throwsFormatException);
    expect(net.bodies, isEmpty);
  });

  test('extra publish fields, wrong scene, too short answer fail closed',
      () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final responses = [
      _answer('another_scene', _prose),
      _answer('turning_point', _prose, extra: true),
      _answer('turning_point', _prose, finishReason: 'length'),
      _answer('turning_point', 'Слишком коротко.'),
    ];
    for (final response in responses) {
      final net = _Network([response]);
      await expectLater(_service(net).preview(
        context: context, approvedContextDigest: context.approvalDigest,
        userReviewedExactContext: true),
        throwsA(isA<AiSetupException>()));
      expect(net.bodies, hasLength(1));
    }
  });

  test('429 retries the identical authorized payload, not more book text',
      () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final net = _Network([
      const AiHttpResponse(429, '{"error":429}', retryAfter: '0'),
      _answer('turning_point', _prose),
    ]);
    final delays = <Duration>[];
    final draft = await _service(net,
      wait: (duration) async { delays.add(duration); },
    ).preview(
      context: context, approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true,
    );
    expect(draft.text, _prose);
    expect(net.bodies, hasLength(2));
    expect(net.bodies[0], net.bodies[1]);
    expect(delays, [Duration.zero]);
  });

  test('explicit cancellation prevents any request', () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final token = ZaiPreviewCancellation()..cancel();
    final net = _Network([]);
    await expectLater(_service(net).preview(
      context: context, approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true, cancellation: token,
    ), throwsA(isA<AiSetupException>()));
    expect(net.bodies, isEmpty);
  });

  test('exact-scene prose survives restart without source quotation or key',
      () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final model = _Network([_answer('turning_point', _prose)]);
    final draft = await _service(model).preview(
      context: context, approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true,
    );
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = SourceLockedProseCheckpointStore(repository: repository);
    await store.save(context: context, draft: draft);
    final raw = (await repository.read(index.sourceFingerprint))!;
    expect(raw, contains(_prose));
    expect(raw, contains('PROSE_DRAFT_REVIEW_REQUIRED'));
    expect(raw, isNot(contains('SYNTHETIC-SECRET-KEY')));
    expect(raw, isNot(contains(index.title)));
    expect(raw, isNot(contains(book.events.first.source.quote)));
    expect(await SourceLockedProseCheckpointStore(
        repository: repository).read(context), isNotNull);
    final replay = await store.read(context);
    expect(replay!.text, _prose);
    expect(replay.isHumanReviewed, false);
    expect(replay.canInstallDirectly, false);
    await store.save(context: context, draft: draft);
    expect(await repository.read(index.sourceFingerprint), raw);
    expect(model.bodies, hasLength(1));
    await store.delete(context);
    expect(await store.read(context), isNull);
    expect(await repository.read(index.sourceFingerprint), isNull);
  });

  test('changed scene digest invalidates cache and forged status fails closed',
      () async {
    final (index, book, plan) = await _fixture();
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final nextContext = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'search_path');
    final net = _Network([_answer('turning_point', _prose)]);
    final draft = await _service(net).preview(
      context: context, approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true,
    );
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = SourceLockedProseCheckpointStore(repository: repo);
    await store.save(context: context, draft: draft);
    expect(await store.read(nextContext), isNull);
    final forgedDraft = SourceLockedProseDraft(
      sourceFingerprint: draft.sourceFingerprint,
      situationId: draft.situationId,
      approvalDigest: List.filled(64, '0').join(),
      text: draft.text,
      uncertainty: draft.uncertainty,
      route: draft.route,
    );
    await expectLater(
      store.save(context: context, draft: forgedDraft),
      throwsFormatException,
    );
    final record = jsonDecode((await repo.read(index.sourceFingerprint))!)
        as Map<String, dynamic>;
    final list = record['entries'] as List;
    (list.first as Map)['status'] = 'CANON_APPROVED';
    await repo.write(index.sourceFingerprint, jsonEncode(record));
    await expectLater(store.read(context), throwsFormatException);
    await expectLater(store.save(context: context, draft: draft),
        throwsFormatException);
  });

  testWidgets('scene preview never posts until exact consent; cached '
      'text returns on page reopen without a second GLM call',
      (tester) async {
    final (index, book, plan) = await _fixture();
    final storage = SourceLockedProseCheckpointStore(
      repository: MemorySourceAnalysisCheckpointRepository());
    final net = _Network([_answer('turning_point', _prose)]);
    await tester.pumpWidget(MaterialApp(home: SourceLockedProsePreviewPage(
      index: index, book: book, plan: plan,
      store: storage, previewService: _service(net),
    )));
    await tester.pumpAndSettle();
    expect(net.bodies, isEmpty);
    final action = find.byKey(const Key('prose-scene-generate'));
    await tester.scrollUntilVisible(action, 190,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(action).onPressed, isNull);
    final checkbox = find.byKey(const Key('prose-scene-approved'));
    await tester.scrollUntilVisible(checkbox, -160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(action, 190,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(net.bodies, hasLength(1));
    await tester.scrollUntilVisible(
        find.byKey(const Key('prose-scene-draft-text')), 160,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('prose-scene-draft-text')), findsOneWidget);
    final noPost = _Network([]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: SourceLockedProsePreviewPage(
      index: index, book: book, plan: plan,
      store: storage, previewService: _service(noPost),
    )));
    await tester.pumpAndSettle();
    expect(noPost.bodies, isEmpty);
    await tester.scrollUntilVisible(
        find.byKey(const Key('prose-scene-draft-text')), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('prose-scene-draft-text')), findsOneWidget);
    await tester.scrollUntilVisible(action, -150,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(action).onPressed, isNull);
  });

  testWidgets('local deletion is deliberate and does not call provider',
      (tester) async {
    final (index, book, plan) = await _fixture();
    final storage = SourceLockedProseCheckpointStore(
      repository: MemorySourceAnalysisCheckpointRepository());
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final initial = _Network([_answer('turning_point', _prose)]);
    final draft = await _service(initial).preview(
      context: context, approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true,
    );
    await storage.save(context: context, draft: draft);
    final noPost = _Network([]);
    await tester.pumpWidget(MaterialApp(home: SourceLockedProsePreviewPage(
      index: index, book: book, plan: plan,
      store: storage, previewService: _service(noPost),
    )));
    await tester.pumpAndSettle();
    final delete = find.byKey(const Key('prose-scene-delete'));
    await tester.scrollUntilVisible(delete, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    final confirmation = find.byKey(const Key('prose-scene-confirm-delete'));
    await tester.tap(confirmation);
    await tester.pumpAndSettle();
    expect(await storage.read(context), isNull);
    expect(noPost.bodies, isEmpty);
    expect(find.byKey(const Key('prose-scene-draft-text')), findsNothing);
  });


  testWidgets('accepting cached prose for game requires TWO separate '
      'confirmations; reopening never posts to cloud', (tester) async {
    final (index, book, plan) = await _fixture();
    final store = SourceLockedProseCheckpointStore(
      repository: MemorySourceAnalysisCheckpointRepository(),
    );
    final context = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan,
      situationId: 'turning_point',
    );
    final generated = _Network([_answer('turning_point', _prose)]);
    final draft = await _service(generated).preview(
      context: context,
      approvedContextDigest: context.approvalDigest,
      userReviewedExactContext: true,
    );
    await store.save(context: context, draft: draft);
    final noNetwork = _Network([]);
    ReviewedProseSceneApproval? accepted;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (parentContext) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              accepted = await Navigator.of(parentContext)
                  .push<ReviewedProseSceneApproval>(MaterialPageRoute(
                builder: (_) => SourceLockedProsePreviewPage(
                  index: index, book: book, plan: plan, store: store,
                  previewService: _service(noNetwork),
                ),
              ));
            },
            child: const Text('Открыть художественный черновик'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('Открыть художественный черновик'));
    await tester.pumpAndSettle();
    final accept = find.byKey(
        const Key('prose-scene-accept-for-private-game'));
    await tester.scrollUntilVisible(accept, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    final checkedText = find.byKey(
        const Key('prose-scene-text-reviewed-for-game'));
    await tester.scrollUntilVisible(checkedText, -120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(checkedText);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(accept, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    final fiction = find.byKey(
        const Key('prose-scene-fiction-acknowledged'));
    await tester.scrollUntilVisible(fiction, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(fiction);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(accept, 150,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
    await tester.tap(accept);
    await tester.pumpAndSettle();
    expect(accepted, isNotNull);
    expect(accepted!.prose, _prose);
    expect(accepted!.contextDigest, context.approvalDigest);
    expect(accepted!.canPublishAsCanon, false);
    expect(noNetwork.bodies, isEmpty);
  });


  test('a batch authorizes ONLY its exact edition, scenes and bounded count',
      () async {
    final (index, book, plan) = await _fixture();
    final ids = [
      plan.situations.first.id,
      plan.situations[1].id,
    ];
    final manifest = SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: ids, maxNewScenesPerRun: 2,
    );
    expect(manifest.contexts, hasLength(2));
    expect(manifest.maxModelAttempts, 6);
    expect(manifest.sentContextUtf8Bytes, greaterThan(0));
    expect(manifest.canClaimLiteraryCanon, false);
    expect(manifest.canInstallDraftsAutomatically, false);
    final differentCap = SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: ids, maxNewScenesPerRun: 1,
    );
    final differentOrder = SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: ids.reversed.toList(), maxNewScenesPerRun: 2,
    );
    expect(differentCap.approvalDigest, isNot(manifest.approvalDigest));
    expect(differentOrder.approvalDigest, isNot(manifest.approvalDigest));
    expect(() => SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: [ids.first, ids.first], maxNewScenesPerRun: 2,
    ), throwsFormatException);
    expect(() => SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: ids, maxNewScenesPerRun: 9,
    ), throwsFormatException);
    expect(() => SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: ['foreign_scene'], maxNewScenesPerRun: 1,
    ), throwsFormatException);
    final differentIndex = BookSourceIndexer.index(const ImportedBook(
      title: 'Чужая книга',
      author: 'Иной текст',
      chapters: ['Эти слова не принадлежат исходной редакции.'],
    ));
    expect(() => SourceLockedProseBatchManifest.fromSelection(
      index: differentIndex, book: book, plan: plan,
      sceneIds: ids, maxNewScenesPerRun: 2,
    ), throwsFormatException);
  });

  test('explicit batch consent sends only selected contexts; '
      'reopening cached scenes never calls provider again', () async {
    final (index, book, plan) = await _fixture();
    final ids = [
      plan.situations.first.id,
      plan.situations[1].id,
    ];
    final manifest = SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan, sceneIds: ids,
      maxNewScenesPerRun: 2,
    );
    final repository = MemorySourceAnalysisCheckpointRepository();
    final store = SourceLockedProseCheckpointStore(repository: repository);
    final net = _Network([
      _answer(ids.first, _prose),
      _answer(ids.last, _prose),
    ]);
    final service = SourceLockedProseBatchService(
      store: store, service: _service(net));
    final untouched = await service.inspect(manifest);
    expect(untouched.completed, 0);
    expect(net.bodies, isEmpty);
    await expectLater(service.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: false,
    ), throwsFormatException);
    await expectLater(service.generate(
      manifest: manifest,
      approvedManifestDigest: 'invalid',
      explicitBatchConsent: true,
    ), throwsFormatException);
    expect(net.bodies, isEmpty);
    final results = <SourceLockedProseBatchProgress>[];
    final finalState = await service.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
      onProgress: results.add,
    );
    expect(finalState.allReadyAsDrafts, true);
    expect(finalState.completed, 2);
    expect(finalState.newlyGenerated, 2);
    expect(results.map((p) => p.completed), [0, 1, 2]);
    expect(net.bodies, hasLength(2));
    for (var i = 0; i < ids.length; i++) {
      final body = net.bodies[i];
      expect(body, isNot(contains(index.title)));
      expect(body, isNot(contains(index.author)));
      expect(body, isNot(contains(index.sourceFingerprint)));
      expect(body, isNot(contains('SYNTHETIC-SECRET-KEY')));
      final sent = jsonDecode(body) as Map<String, dynamic>;
      final message = (sent['messages'] as List).last['content'];
      expect(jsonDecode(message as String),
          manifest.contexts[i].consentPreview);
    }
    final noNetwork = _Network([]);
    final reopened = SourceLockedProseBatchService(
      store: SourceLockedProseCheckpointStore(repository: repository),
      service: _service(noNetwork),
    );
    expect((await reopened.inspect(manifest)).recovered, 2);
    final skipped = await reopened.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(skipped.completed, 2);
    expect(skipped.newlyGenerated, 0);
    expect(noNetwork.bodies, isEmpty);
  });

  test('a failed second scene checkpoints first; new explicit consent '
      'resumes ONLY remaining request', () async {
    final (index, book, plan) = await _fixture();
    final ids = [plan.situations.first.id, plan.situations[1].id];
    final manifest = SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: ids, maxNewScenesPerRun: 2,
    );
    final repo = MemorySourceAnalysisCheckpointRepository();
    final store = SourceLockedProseCheckpointStore(repository: repo);
    final wrong = _Network([
      _answer(ids.first, _prose),
      _answer('other_scene', _prose),
    ]);
    final firstRun = SourceLockedProseBatchService(
      store: store, service: _service(wrong),
    );
    await expectLater(firstRun.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    ), throwsA(isA<AiSetupException>()));
    expect(wrong.bodies, hasLength(2));
    expect((await firstRun.inspect(manifest)).completed, 1);
    final freshNetwork = _Network([_answer(ids.last, _prose)]);
    final freshRun = SourceLockedProseBatchService(
      store: SourceLockedProseCheckpointStore(repository: repo),
      service: _service(freshNetwork),
    );
    final done = await freshRun.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
    );
    expect(done.completed, 2);
    expect(done.recovered, 1);
    expect(done.newlyGenerated, 1);
    expect(freshNetwork.bodies, hasLength(1));
    final sentPayload = jsonDecode(freshNetwork.bodies.single)
        as Map<String, dynamic>;
    final sentContext = jsonDecode(
        (sentPayload['messages'] as List).last['content'] as String)
        as Map<String, dynamic>;
    expect(sentContext['scene_id'], ids.last);
  });

  test('cancellation after first persisted scene stops ALL later requests',
      () async {
    final (index, book, plan) = await _fixture();
    final ids = [plan.situations.first.id, plan.situations[1].id];
    final manifest = SourceLockedProseBatchManifest.fromSelection(
      index: index, book: book, plan: plan,
      sceneIds: ids, maxNewScenesPerRun: 2,
    );
    final store = SourceLockedProseCheckpointStore(
      repository: MemorySourceAnalysisCheckpointRepository(),
    );
    final net = _Network([_answer(ids.first, _prose)]);
    final service = SourceLockedProseBatchService(
      store: store, service: _service(net));
    final token = ZaiPreviewCancellation();
    await expectLater(service.generate(
      manifest: manifest,
      approvedManifestDigest: manifest.approvalDigest,
      explicitBatchConsent: true,
      cancellation: token,
      onProgress: (p) {
        if (p.newlyGenerated == 1) token.cancel();
      },
    ), throwsA(isA<AiSetupException>()));
    expect((await service.inspect(manifest)).completed, 1);
    expect(net.bodies, hasLength(1));
  });

  testWidgets('batch UI never posts on open; one approval authorizes '
      'at most the displayed new-scene cap', (tester) async {
    final (index, book, plan) = await _fixture();
    final firstId = plan.situations.first.id;
    final net = _Network([_answer(firstId, _prose)]);
    final batch = SourceLockedProseBatchService(
      store: SourceLockedProseCheckpointStore(
        repository: MemorySourceAnalysisCheckpointRepository()),
      service: _service(net),
    );
    await tester.pumpWidget(MaterialApp(
      home: SourceLockedProseBatchPage(
        index: index, book: book, plan: plan,
        batchService: batch, initialMaxNewScenes: 1,
      ),
    ));
    await tester.pumpAndSettle();
    expect(net.bodies, isEmpty);
    final start = find.byKey(const Key('prose-batch-start'));
    await tester.scrollUntilVisible(start, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    final check = find.byKey(const Key('prose-batch-consent'));
    await tester.scrollUntilVisible(check, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(check);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(start, 160,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(net.bodies, hasLength(1));
    final ready = await batch.inspect(
      SourceLockedProseBatchManifest.fromSelection(
        index: index, book: book, plan: plan,
        sceneIds: [
          for (final s in plan.situations.take(
              SourceLockedProseBatchManifest.maxScenesInBatch)) s.id,
        ],
        maxNewScenesPerRun: 1,
      ),
    );
    expect(ready.completed, 1);
    expect(ready.allReadyAsDrafts, false);
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      home: SourceLockedProseBatchPage(
        index: index, book: book, plan: plan,
        batchService: batch, initialMaxNewScenes: 1,
      ),
    ));
    await tester.pumpAndSettle();
    expect(net.bodies, hasLength(1));
  });


  test('AI literary critique is consent-bound to EXACT generated prose',
      () async {
    final (index, book, plan) = await _fixture();
    final base = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final context = SourceLockedProseAuditContext.forDraft(
      index: index, book: book, plan: plan,
      draft: _draftFor(base),
    );
    final net = _Network([_auditResponse('turning_point')]);
    final review = await _auditService(net).review(
      context: context,
      approvedDigest: context.approvalDigest,
      explicitReviewConsent: true,
    );
    expect(review.verdict, AiProseAuditVerdict.needsRevision);
    expect(review.findings, hasLength(1));
    expect(review.findings.single.kind, AiProseFindingKind.promise);
    expect(review.hasHighRiskFinding, true);
    expect(review.literaryCanonConfirmed, false);
    expect(review.mayAutoApprove, false);
    expect(review.mayEditGameRules, false);
    expect(review.evidenceIsFullBook, false);
    expect(net.bodies, hasLength(1));
    final sent = net.bodies.single;
    final request = jsonDecode(sent) as Map<String, dynamic>;
    expect(request['model'], ZaiModel.id);
    expect(request['thinking'], {'type': 'disabled'});
    expect(request['response_format'], {'type': 'json_object'});
    expect(request.containsKey('tools'), false);
    final user = jsonDecode((request['messages'] as List).last['content']
        as String) as Map<String, dynamic>;
    expect(user, context.sentContext);
    expect(user['draft_prose'], _prose);
    expect(sent, contains(base.sourceEvent!.source.quote));
    expect(sent, isNot(contains(index.title)));
    expect(sent, isNot(contains(index.author)));
    expect(sent, isNot(contains(index.sourceFingerprint)));
    expect(sent, isNot(contains('SYNTHETIC-SECRET-KEY')));
    expect(net.sentHeaders.single['Authorization'],
        'Bearer SYNTHETIC-SECRET-KEY');
  });

  test('AI reviewer never posts without NEW consent, correct digest '
      'and existing provider opt-in/key', () async {
    final (index, book, plan) = await _fixture();
    final base = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final context = SourceLockedProseAuditContext.forDraft(
      index: index, book: book, plan: plan, draft: _draftFor(base));
    final net = _Network([]);
    await expectLater(_auditService(net).review(
      context: context, approvedDigest: context.approvalDigest,
      explicitReviewConsent: false), throwsA(isA<AiSetupException>()));
    await expectLater(_auditService(net).review(
      context: context, approvedDigest: 'stale',
      explicitReviewConsent: true), throwsA(isA<AiSetupException>()));
    await expectLater(_auditService(net, enabled: false).review(
      context: context, approvedDigest: context.approvalDigest,
      explicitReviewConsent: true), throwsA(isA<AiSetupException>()));
    await expectLater(_auditService(net, key: null).review(
      context: context, approvedDigest: context.approvalDigest,
      explicitReviewConsent: true), throwsA(isA<AiSetupException>()));
    expect(net.bodies, isEmpty);
    final different = SourceLockedProseDraft(
      sourceFingerprint: base.index.sourceFingerprint,
      situationId: base.situation.id,
      approvalDigest: base.approvalDigest,
      text: _prose + ' Он посмотрел назад.',
      uncertainty: 'Недостаточно сведений об обстоятельствах.',
      route: base.situation.route,
    );
    final changed = SourceLockedProseAuditContext.forDraft(
      index: index, book: book, plan: plan, draft: different);
    expect(changed.approvalDigest, isNot(context.approvalDigest));
    await expectLater(_auditService(net).review(
      context: changed, approvedDigest: context.approvalDigest,
      explicitReviewConsent: true), throwsA(isA<AiSetupException>()));
    expect(net.bodies, isEmpty);
  });

  test('AI critique rejects forged citation, invented canon claim, '
      'truncated result, wrong ID and unsupported verdict',
      () async {
    final (index, book, plan) = await _fixture();
    final base = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final context = SourceLockedProseAuditContext.forDraft(
      index: index, book: book, plan: plan, draft: _draftFor(base));
    final bad = [
      _auditResponse('foreign_scene'),
      _auditResponse('turning_point', evidenceQuote: 'ПРИДУМАННАЯ ЦИТАТА'),
      _auditResponse('turning_point', extraField: true),
      _auditResponse('turning_point', finishReason: 'length'),
      _auditResponse('turning_point', verdict: 'CANON_APPROVED'),
      _auditResponse('turning_point', verdict: 'possibleConsistency'),
    ];
    for (final response in bad) {
      final net = _Network([response]);
      await expectLater(_auditService(net).review(
        context: context,
        approvedDigest: context.approvalDigest,
        explicitReviewConsent: true,
      ), throwsA(isA<AiSetupException>()));
      expect(net.bodies, hasLength(1));
    }
  });

  test('absence of source quote forbids false positive '
      'even when model says "possibleConsistency"', () async {
    final (index, book, plan) = await _fixture();
    final base = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'search_path');
    final context = SourceLockedProseAuditContext.forDraft(
      index: index, book: book, plan: plan, draft: _draftFor(base));
    final wrong = _Network([_auditResponse('search_path',
      verdict: 'possibleConsistency', withFinding: false)]);
    await expectLater(_auditService(wrong).review(
      context: context, approvedDigest: context.approvalDigest,
      explicitReviewConsent: true), throwsA(isA<AiSetupException>()));
    final good = _Network([_auditResponse('search_path',
      verdict: 'insufficientEvidence', withFinding: false)]);
    final review = await _auditService(good).review(
      context: context, approvedDigest: context.approvalDigest,
      explicitReviewConsent: true);
    expect(review.verdict, AiProseAuditVerdict.insufficientEvidence);
    expect(review.literaryCanonConfirmed, false);
  });

  test('429 repeats exactly consented critique payload without extra text',
      () async {
    final (index, book, plan) = await _fixture();
    final base = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final context = SourceLockedProseAuditContext.forDraft(
      index: index, book: book, plan: plan, draft: _draftFor(base));
    final net = _Network([
      const AiHttpResponse(429, '{"error":"rate"}', retryAfter: '0'),
      _auditResponse('turning_point'),
    ]);
    final delays = <Duration>[];
    final review = await _auditService(net,
      wait: (duration) async { delays.add(duration); },
    ).review(
      context: context, approvedDigest: context.approvalDigest,
      explicitReviewConsent: true);
    expect(review.findings, hasLength(1));
    expect(net.bodies, hasLength(2));
    expect(net.bodies[0], net.bodies[1]);
    expect(delays, [Duration.zero]);
  });

  test('private reviewer checkpoint survives restart, rejects forged '
      'model status and never changes BookWorld', () async {
    final (index, book, plan) = await _fixture();
    final base = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final context = SourceLockedProseAuditContext.forDraft(
      index: index, book: book, plan: plan, draft: _draftFor(base));
    final net = _Network([_auditResponse('turning_point',
        evidenceQuote: base.sourceEvent!.source.quote)]);
    final report = await _auditService(net).review(
      context: context, approvedDigest: context.approvalDigest,
      explicitReviewConsent: true);
    final rawRepo = MemorySourceAnalysisCheckpointRepository();
    final store = SourceLockedProseAuditCheckpointStore(repository: rawRepo);
    await store.save(context: context, report: report);
    final saved = (await rawRepo.read(index.sourceFingerprint))!;
    expect(saved, contains('UNVERIFIED_MODEL_CRITIQUE'));
    expect(saved, isNot(contains('SYNTHETIC-SECRET-KEY')));
    expect(saved, isNot(contains(index.title)));
    expect(saved, isNot(contains(_prose)));
    final reopened = SourceLockedProseAuditCheckpointStore(
        repository: rawRepo);
    final recovered = await reopened.read(context);
    expect(recovered!.findings.single.evidenceQuote,
        base.sourceEvent!.source.quote);
    expect(recovered.mayAutoApprove, false);
    await reopened.save(context: context, report: report);
    expect(await rawRepo.read(index.sourceFingerprint), saved);
    final json = jsonDecode(saved) as Map<String, dynamic>;
    ((json['entries'] as List).first as Map)['status'] = 'CANON_APPROVED';
    await rawRepo.write(index.sourceFingerprint, jsonEncode(json));
    await expectLater(reopened.read(context), throwsFormatException);
  });

  testWidgets('literary AI screen never makes hidden POST; separate '
      'consent is required and cached result reopens offline',
      (tester) async {
    final (index, book, plan) = await _fixture();
    final base = SourceLockedProseContext.forSituation(
      index: index, book: book, plan: plan, situationId: 'turning_point');
    final draft = _draftFor(base);
    final store = SourceLockedProseAuditCheckpointStore(
        repository: MemorySourceAnalysisCheckpointRepository());
    final net = _Network([_auditResponse('turning_point')]);
    await tester.pumpWidget(MaterialApp(home: SourceLockedProseAuditPage(
      index: index, book: book, plan: plan, draft: draft,
      store: store, auditService: _auditService(net),
    )));
    await tester.pumpAndSettle();
    expect(net.bodies, isEmpty);
    final submit = find.byKey(const Key('literary-audit-submit'));
    await tester.scrollUntilVisible(submit, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    final check = find.byKey(const Key('literary-audit-consent'));
    await tester.scrollUntilVisible(check, -150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(check);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(submit, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(net.bodies, hasLength(1));
    await tester.scrollUntilVisible(
        find.byKey(const Key('literary-audit-verdict')), 160,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('literary-audit-verdict')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final noNetwork = _Network([]);
    await tester.pumpWidget(MaterialApp(home: SourceLockedProseAuditPage(
      index: index, book: book, plan: plan, draft: draft,
      store: store, auditService: _auditService(noNetwork),
    )));
    await tester.pumpAndSettle();
    expect(noNetwork.bodies, isEmpty);
    await tester.scrollUntilVisible(
        find.byKey(const Key('literary-audit-verdict')), 160,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('literary-audit-verdict')), findsOneWidget);
  });

}
