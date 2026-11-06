import 'dart:convert';

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
import 'package:ai_story_reader/zai_source_locked_gameplay_candidates.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Prefs extends AiCloudPreferences {
  _Prefs(this.enabled);
  final bool enabled;
  @override
  Future<bool> isEnabled() async => enabled;
}

class _Key implements AiApiKeyVault {
  _Key(this.token);
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async { token = value; }
  @override
  Future<void> delete() async { token = null; }
  @override
  Future<bool> hasKey() async => token?.isNotEmpty == true;
}

class _Http implements AiHttpTransport {
  _Http(this.responses);
  final List<AiHttpResponse> responses;
  final List<String> bodies = [];
  final List<Uri> urls = [];
  final List<Map<String, String>> headers = [];
  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    urls.add(uri);
    this.headers.add(Map<String, String>.from(headers));
    bodies.add(body);
    return responses[bodies.length - 1];
  }
}

Future<(BookSourceIndex, NarrativeBookModel, StoryPlan)> _fixture({
  String suffix = '',
}) async {
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Тестовая история про старый ключ' + suffix,
    author: 'Автор теста',
    chapters: [
      'Путник обнаружил старый ключ возле колодца. '
          'Сторож предложил помощь за обещание, но путник '
          'пока не согласился на условие.',
      'На следующий день путник увидел другую дорогу. '
          'Он мог отказаться от условия и искать собственный путь, '
          'а принадлежность ключа всё ещё оставалась неизвестной.',
    ],
  ));
  final scan = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, cancellation, includeTitle) async {
      final chunk = window.chunks.first;
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [
            SemanticCandidate.propose(
              source, chunk, category: SemanticCategory.event,
              startUtf16: chunk.startUtf16,
              endUtf16: chunk.startUtf16 + 60,
              label: 'Предложение события, ещё не канон',
              uncertainty: 'Смысл исходной книги пока не доказан.',
            ),
          ],
        ),
        totalSuggestions: 1, rejectedCount: 0, rejectedNonRussian: 0,
      );
    },
  );
  final consent = ZaiWholeBookConsentManifest.fromIndex(index);
  final reviewed = await scan.analyze(
    index: index, approvedManifestDigest: consent.approvalDigest,
    explicitWholeBookConsent: true, maxWindowsPerRun: 12,
  );
  final book = NarrativeBookModel.fromExisting(
    index: index, outline: ZaiWholeBookEventOutline.build(reviewed),
  );
  final proposal = StoryDilemmaProposal.decode(jsonEncode({
    'format': StoryDilemmaProposal.format,
    'status': 'UNREVIEWED_PROPOSAL',
    'source_fingerprint': book.sourceFingerprint,
    'setup_event_id': book.events.first.id,
    'outcome_event_id': book.events.last.id,
    'kind': 'agreement',
    'dilemma': 'Согласиться на помощь или выбрать самостоятельный путь?',
    'accept_intent': 'Принять помощь и предложенные условия',
    'refuse_intent': 'Отказаться от предложенного обещания',
    'followup_goal': 'Разобраться с ранее принятым условием',
    'finish_original_intent': 'Исполнить принятое условие',
    'original_ending': 'Путник закончил первую версию игрового пути',
    'alternative_search_goal': 'Найти путь без нового обещания',
    'search_intent': 'Исследовать местность и искать иной выход',
    'alternative_discovery': 'Путник увидел другую возможность',
    'use_discovery_intent': 'Выбрать альтернативный путь к цели',
    'alternative_ending': 'Путник завершил придуманную ветвь',
  }));
  final plan = StoryPlanDilemmaGenerator.propose(book, proposal);
  expect(plan.validate(book).isStructurallySound, true);
  return (index, book, plan);
}

SourceLockedGameplayContext _context(
    BookSourceIndex index, NarrativeBookModel book, StoryPlan plan) =>
    SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: plan,
      exactEventIds: [for (final e in book.events) e.id],
    );

Map<String, Object> _candidate(SourceLockedGameplayContext context) {
  final anchor = context.choices.firstWhere(
      (c) => c.sourceEventId == context.excerpts.first.id);
  return {
    'kind': 'item',
    'id': 'old_key',
    'label': 'ключ',
    'op': 'grant_item',
    'scene_id': anchor.sceneId,
    'choice_id': anchor.choiceId,
    'source_event_id': anchor.sourceEventId,
    'uncertainty': 'В цитате упомянут ключ, но владение не доказано.',
  };
}

AiHttpResponse _reply(List<Map<String, Object>> proposals) =>
    AiHttpResponse(200, jsonEncode({
      'choices': [{'message': {
        'content': jsonEncode({'proposals': proposals}),
      }}],
    }));

ZaiSourceLockedGameplayCandidateService _service(_Http http, {
  bool enabled = true, String? apiKey = 'synthetic-secret',
  Future<void> Function(Duration)? wait,
}) => ZaiSourceLockedGameplayCandidateService(
      preferences: _Prefs(enabled),
      vault: _Key(apiKey),
      transport: http,
      retryWait: wait ?? (delay) async {},
    );

Future<GameplayCandidateDraft> _propose(
    ZaiSourceLockedGameplayCandidateService service,
    SourceLockedGameplayContext context, {
    bool consent = true, String? digest,
}) => service.propose(
  context: context, explicitExcerptConsent: consent,
  approvedDigest: digest ?? context.approvalDigest,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit consent: literal source item yields ONLY nonexecutable draft',
      () async {
    final (index, book, plan) = await _fixture();
    final context = _context(index, book, plan);
    final choice = context.choices.first;
    expect(choice.sourceEventId, isNotEmpty);
    expect(context.canModifyBookworld, false);
    expect(context.independentlyConfirmsOwnership, false);
    expect(context.independentlyConfirmsKnowledge, false);
    expect(context.consentPreview.containsKey('source_fingerprint'), false);
    expect(context.consentPreview.containsKey('title'), false);
    // A mutable UI copy must never mutate the EXACT consented wire bytes.
    (context.consentPreview['source_excerpts'] as List).clear();
    expect((context.consentPreview['source_excerpts'] as List), isNotEmpty);
    final http = _Http([_reply([_candidate(context)])]);
    final result = await _propose(_service(http), context);
    expect(result.hasCandidate, true);
    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.id, 'old_key');
    expect(result.candidates.single.op, 'grant_item');
    expect(result.candidates.single.isReviewed, false);
    expect(result.candidates.single.mayChangeGameState, false);
    expect(result.mayChangeGameState, false);
    expect(result.isAcceptedIntoGame, false);
    expect(result.provesLiteraryMeaning, false);
    expect(http.urls.single, ZaiModel.endpoint);
    expect(http.bodies, hasLength(1));
    final request = http.bodies.single;
    final payload = jsonDecode(
        ((jsonDecode(request) as Map)['messages'] as List).last['content']
          as String);
    expect(payload, context.consentPreview);
    expect(request, contains(book.events.first.source.quote));
    expect(request, isNot(contains(book.title)));
    expect(request, isNot(contains(index.author)));
    expect(request, isNot(contains(index.sourceFingerprint)));
    expect(request, isNot(contains('synthetic-secret')));
    expect(http.headers.single['Authorization'], 'Bearer synthetic-secret');
  });

  test('no hidden request without exact digest, opt-in, or protected API key',
      () async {
    final (index, book, plan) = await _fixture();
    final context = _context(index, book, plan);
    final http = _Http([]);
    await expectLater(_propose(_service(http), context, consent: false),
        throwsA(isA<AiSetupException>()));
    await expectLater(_propose(_service(http), context, digest: 'stale'),
        throwsA(isA<AiSetupException>()));
    await expectLater(_propose(_service(http, enabled: false), context),
        throwsA(isA<AiSetupException>()));
    await expectLater(_propose(_service(http, apiKey: null), context),
        throwsA(isA<AiSetupException>()));
    expect(http.bodies, isEmpty);
  });

  test('nothing in the book means NO item or fact is fabricated', () async {
    final (index, book, plan) = await _fixture();
    final context = _context(index, book, plan);
    final result = await _propose(_service(_Http([_reply([])])), context);
    expect(result.hasCandidate, false);
    expect(result.candidates, isEmpty);
    expect(result.isAcceptedIntoGame, false);
  });

  test('rejects fake source item, foreign choice, forged canon and unknown op',
      () async {
    final (index, book, plan) = await _fixture();
    final context = _context(index, book, plan);
    final item = _candidate(context);
    final invalid = <Map<String, Object>>[
      {...item, 'label': 'волшебный меч'},
      {...item, 'choice_id': 'ghost_choice'},
      {...item, 'source_event_id': 'foreign_edition_event'},
      {...item, 'op': 'stat_delta'},
      {...item, 'kind': 'stat'},
      {...item, 'is_canon': true},
      {...item, 'id': 'invalid ID'},
      {...item, 'uncertainty': 'Да'},
    ];
    for (final data in invalid) {
      final http = _Http([_reply([data])]);
      await expectLater(_propose(_service(http), context),
          throwsA(isA<AiSetupException>()));
      expect(http.bodies, hasLength(1));
    }
    final http = _Http([_reply([item, item])]);
    await expectLater(_propose(_service(http), context),
        throwsA(isA<AiSetupException>()));
  });

  test('HTTP 429 retries only identical consented bytes at most three times',
      () async {
    final (index, book, plan) = await _fixture();
    final context = _context(index, book, plan);
    final http = _Http([
      const AiHttpResponse(429, '{"error":"rate"}', retryAfter: '0'),
      _reply([_candidate(context)]),
    ]);
    final waits = <Duration>[];
    final result = await _propose(
      _service(http, wait: (delay) async { waits.add(delay); }),
      context,
    );
    expect(result.hasCandidate, true);
    expect(http.bodies, hasLength(2));
    expect(http.bodies.first, http.bodies.last);
    expect(waits, [Duration.zero]);
  });

  test('wrong book, reordered quotes and ungrounded plan fail before request',
      () async {
    final (index, book, plan) = await _fixture();
    final alien = (await _fixture(suffix: ' другой перевод')).$1;
    expect(() => SourceLockedGameplayContext.forPlan(
      index: alien, book: book, plan: plan,
      exactEventIds: [for (final e in book.events) e.id],
    ), throwsFormatException);
    expect(() => SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: plan,
      exactEventIds: [book.events.last.id, book.events.first.id],
    ), throwsFormatException);
    expect(() => SourceLockedGameplayContext.forPlan(
      index: index, book: book, plan: plan,
      exactEventIds: ['a_different_book_event'],
    ), throwsFormatException);
  });
}
