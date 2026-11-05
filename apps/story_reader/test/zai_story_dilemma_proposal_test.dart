import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memory implements SourceAnalysisCheckpointRepository {
  String? data;
  @override
  Future<String?> read(String fingerprint) async => data;
  @override
  Future<void> write(String fingerprint, String text) async { data = text; }
  @override
  Future<void> delete(String fingerprint) async { data = null; }
}

class _Preferences extends AiCloudPreferences {
  _Preferences(this.enabled);
  final bool enabled;
  @override
  Future<bool> isEnabled() async => enabled;
}

class _Vault implements AiApiKeyVault {
  _Vault(this.key);
  String? key;
  @override
  Future<String?> read() async => key;
  @override
  Future<void> write(String value) async { key = value; }
  @override
  Future<void> delete() async { key = null; }
  @override
  Future<bool> hasKey() async => key?.isNotEmpty == true;
}

class _Transport implements AiHttpTransport {
  _Transport(this.responses);
  final List<AiHttpResponse> responses;
  final List<String> requests = [];
  final List<Uri> targets = [];
  final List<Map<String, String>> headers = [];

  @override
  Future<AiHttpResponse> send({
    required Uri uri, required Map<String, String> headers,
    required String body,
  }) async {
    targets.add(uri);
    requests.add(body);
    this.headers.add(Map<String, String>.from(headers));
    return responses[requests.length - 1];
  }
}

Future<NarrativeBookModel> _book() async {
  final index = BookSourceIndexer.index(ImportedBook(
    title: 'Название проверяемой сказки',
    author: 'Тестовый автор',
    chapters: [
      'Путник обнаружил старый ключ возле колодца. Рядом стоял '
          'сторож, который предложил помощь за неизвестную услугу.',
      'Путник подумал о возможном обещании и о другом пути. '
          'Рассказчик пока не объяснил, кому принадлежит найденный ключ.',
    ],
  ));
  final review = ZaiAutoWholeBookAnalysis(
    repository: _Memory(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final candidate = SemanticCandidate.propose(
        source, chunk,
        category: SemanticCategory.event,
        startUtf16: chunk.startUtf16,
        endUtf16: chunk.startUtf16 + 60,
        label: 'Возможное событие, но не подтверждённая причинность',
        uncertainty: 'Здесь можно ошибиться в описании условий обмена.',
      );
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: [candidate],
        ),
        totalSuggestions: 1,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final analysis = await review.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 12,
  );
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(analysis),
  );
}

Map<String, Object> _answer(NarrativeBookModel book) => {
  'applicable': true,
  'setup_event_id': book.events.first.id,
  'outcome_event_id': book.events.last.id,
  'kind': 'agreement',
  'dilemma': 'Принять условие помощи или найти другой способ?',
  'accept_intent': 'Согласиться на помощь в обмен на обещание',
  'refuse_intent': 'Отказаться от условия и не давать обещания',
  'followup_goal': 'Понять последствия уже принятого обещания',
  'finish_original_intent': 'Исполнить ранее данное обещание',
  'original_ending': 'Герой выполнил обещание и завершил исходную линию',
  'alternative_search_goal': 'Найти другой способ решить задачу',
  'search_intent': 'Исследовать окрестности и искать другой способ',
  'alternative_discovery': 'Герой нашёл иной вариант продолжения',
  'use_discovery_intent': 'Воспользоваться найденной возможностью без обещания',
  'alternative_ending': 'Герой завершил историю без прежнего обязательства',
};

AiHttpResponse _response(Map<String, Object> answer) =>
    AiHttpResponse(200, jsonEncode({
      'choices': [{'message': {'content': jsonEncode(answer)}}],
    }));

ZaiStoryDilemmaProposalService _service(_Transport transport, {
  bool enabled = true,
  String? apiKey = 'test-placeholder-only',
  Future<void> Function(Duration)? retryWait,
}) => ZaiStoryDilemmaProposalService(
  preferences: _Preferences(enabled),
  vault: _Vault(apiKey),
  transport: transport,
  retryWait: retryWait ?? (duration) async {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit two-excerpt consent yields a SOURCE-LOCKED draft only',
      () async {
    final book = await _book();
    final events = ZaiStoryDilemmaProposalService.samples(book);
    expect(events, hasLength(2));
    expect(() => events.clear(), throwsUnsupportedError);
    final transport = _Transport([_response(_answer(book))]);
    final result = await _service(transport).propose(
      book: book,
      consentForTheseSampledQuotes: true,
    );
    expect(result.foundCandidate, true);
    expect(result.isPlayableRpg, false);
    expect(result.hasVerifiedLiteraryMeaning, false);
    expect(result.sampledEventCount, 2);
    expect(result.proposal!.sourceFingerprint, book.sourceFingerprint);
    expect(result.plan!.validate(book).terminalSituations, 2);
    expect(result.plan!.situations, hasLength(7));
    expect(result.plan!.canPublish, false);
    expect(transport.requests, hasLength(1));
    expect(transport.targets.single, ZaiModel.endpoint);
    final request = transport.requests.single;
    expect(request, contains(book.events.first.source.quote));
    expect(request, contains(book.events.last.source.quote));
    expect(request, isNot(contains(book.title)));
    expect(request, isNot(contains(book.sourceFingerprint)));
    expect(request, isNot(contains('test-placeholder-only')));
    expect(transport.headers.single['Authorization'],
        'Bearer test-placeholder-only');
    final data = jsonDecode(request) as Map<String, dynamic>;
    final messages = data['messages'] as List;
    final sent = jsonDecode((messages.last as Map)['content'] as String)
        as Map<String, dynamic>;
    expect(sent.keys, contains('event_samples'));
    expect(sent.keys, isNot(contains('book_title')));
  });

  test('no request without fresh excerpt consent, cloud enabled or key',
      () async {
    final book = await _book();
    final transport = _Transport([]);
    expect(() => _service(transport).propose(
        book: book, consentForTheseSampledQuotes: false),
        throwsA(isA<AiSetupException>()));
    expect(() => _service(transport, enabled: false).propose(
        book: book, consentForTheseSampledQuotes: true),
        throwsA(isA<AiSetupException>()));
    expect(() => _service(transport, apiKey: null).propose(
        book: book, consentForTheseSampledQuotes: true),
        throwsA(isA<AiSetupException>()));
    expect(transport.requests, isEmpty);
  });

  test('the model can decline to invent a causal dilemma', () async {
    final book = await _book();
    final transport = _Transport([
      _response({'applicable': false}),
    ]);
    final result = await _service(transport).propose(
        book: book, consentForTheseSampledQuotes: true);
    expect(result.foundCandidate, false);
    expect(result.plan, isNull);
    expect(result.proposal, isNull);
    expect(transport.requests, hasLength(1));
  });

  test('unknown event, extra fields, and forged semantic canon are rejected',
      () async {
    final book = await _book();
    final wrongId = _answer(book)
      ..['setup_event_id'] = 'event_from_another_book';
    final extra = _answer(book)..['is_playable'] = true;
    for (final answer in [wrongId, extra]) {
      final transport = _Transport([_response(answer)]);
      expect(() => _service(transport).propose(
          book: book, consentForTheseSampledQuotes: true),
          throwsA(isA<AiSetupException>()));
    }
  });

  test('429 retries identical approved payload, never invents a new excerpt',
      () async {
    final book = await _book();
    final transport = _Transport([
      const AiHttpResponse(429, '{"error":{"code":429}}', retryAfter: '0'),
      _response(_answer(book)),
    ]);
    final delays = <Duration>[];
    final result = await _service(transport,
      retryWait: (duration) async { delays.add(duration); },
    ).propose(book: book, consentForTheseSampledQuotes: true);
    expect(result.foundCandidate, true);
    expect(transport.requests, hasLength(2));
    expect(transport.requests[0], transport.requests[1]);
    expect(delays, [Duration.zero]);
  });
}
