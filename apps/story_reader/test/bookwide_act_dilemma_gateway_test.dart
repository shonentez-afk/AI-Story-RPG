import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/bookwide_act_dilemma_gateway.dart';
import 'package:ai_story_reader/bookwide_act_planner.dart';
import 'package:ai_story_reader/narrative_book_model.dart';
import 'package:ai_story_reader/source_analysis_checkpoint_repository.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/zai_auto_whole_book_analysis.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:ai_story_reader/zai_story_dilemma_proposal.dart';
import 'package:ai_story_reader/zai_whole_book_event_outline.dart';
import 'package:flutter_test/flutter_test.dart';

class _Enabled extends AiCloudPreferences {
  @override
  Future<bool> isEnabled() async => true;
}

class _Key implements AiApiKeyVault {
  @override
  Future<String?> read() async => 'integration-test-only-placeholder';
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
  @override
  Future<bool> hasKey() async => true;
}

class _Transport implements AiHttpTransport {
  _Transport(this.responses);
  final List<AiHttpResponse> responses;
  final List<String> bodies = [];
  final List<Map<String, String>> sentHeaders = [];

  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    expect(uri, ZaiModel.endpoint);
    sentHeaders.add(Map<String, String>.from(headers));
    bodies.add(body);
    return responses[bodies.length - 1];
  }
}

BookSourceIndex _index({String variation = ''}) =>
    BookSourceIndexer.index(ImportedBook(
      title: 'Книга для теста согласий по актам',
      author: 'Тестовый автор',
      chapters: [
        List.filled(5, 'В первой части герой нашёл странную '
            'монету в старом саду. Ему предложили выбор, но '
            'он ничего пока не пообещал. ').join(' '),
        List.filled(5, 'Во второй части начался дождь '
            'и герой встретил незнакомую женщину на дороге. '
            'Решение зависело от сказанных слов. ').join(' '),
        List.filled(5, 'В третьей части путешествие '
            'привело героя к закрытым воротам у подножия горы. '
            'Он услышал другой вопрос и задумался. ').join(' ') + variation,
      ],
    ));

Future<NarrativeBookModel> _book(BookSourceIndex index) async {
  final service = ZaiAutoWholeBookAnalysis(
    repository: MemorySourceAnalysisCheckpointRepository(),
    preview: (source, window, token, includeTitle) async {
      final chunk = window.chunks.first;
      final candidates = <SemanticCandidate>[];
      for (var i = 0; i < 3; i++) {
        candidates.add(SemanticCandidate.propose(
          source, chunk,
          category: SemanticCategory.event,
          startUtf16: chunk.startUtf16 + i * 90,
          endUtf16: chunk.startUtf16 + i * 90 + 60,
          label: 'Непроверенное предложение события по точной цитате',
          uncertainty: 'Причинность и знание героя пока не доказаны.',
        ));
      }
      return ZaiSemanticPreviewResult(
        batch: SemanticCandidateBatch(
          providerId: ZaiSemanticPreviewService.providerId,
          providerVersion: ZaiSemanticPreviewService.providerVersion,
          sourceFingerprint: source.sourceFingerprint,
          chunkIds: [for (final c in window.chunks) c.id],
          candidates: candidates,
        ),
        totalSuggestions: candidates.length,
        rejectedCount: 0,
        rejectedNonRussian: 0,
      );
    },
  );
  final manifest = ZaiWholeBookConsentManifest.fromIndex(index);
  final result = await service.analyze(
    index: index,
    approvedManifestDigest: manifest.approvalDigest,
    explicitWholeBookConsent: true,
    maxWindowsPerRun: 64,
  );
  return NarrativeBookModel.fromExisting(
    index: index,
    outline: ZaiWholeBookEventOutline.build(result),
  );
}

Map<String, Object> _answer(ActDilemmaConsentManifest manifest) => {
  'applicable': true,
  'setup_event_id': manifest.eventIds.first,
  'outcome_event_id': manifest.eventIds.last,
  'kind': 'exchange',
  'dilemma': 'Принять условие помощи или продолжить самостоятельный поиск?',
  'accept_intent': 'Согласиться на обмен после проверки его условий',
  'refuse_intent': 'Отказаться от обмена и искать другие возможности',
  'followup_goal': 'Проследить последствия добровольно принятого условия',
  'finish_original_intent': 'Исполнить согласованное ранее обязательство',
  'original_ending': 'Герой завершает первую предложенную игровую линию',
  'alternative_search_goal': 'Искать самостоятельное решение без обещания',
  'search_intent': 'Осмотреть дорогу и расспросить встречных путников',
  'alternative_discovery': 'Герой находит другую игровую возможность',
  'use_discovery_intent': 'Использовать новое решение без прежнего договора',
  'alternative_ending': 'Герой завершает другой вымышленный игровой путь',
};

AiHttpResponse _ok(Map<String, Object> content) =>
    AiHttpResponse(200, jsonEncode({
      'choices': [{'message': {'content': jsonEncode(content)}}],
    }));

ActDilemmaProposalGateway _gateway(_Transport mock) =>
    ActDilemmaProposalGateway(
      service: ZaiStoryDilemmaProposalService(
        preferences: _Enabled(),
        vault: _Key(),
        transport: mock,
        retryWait: (delay) async {},
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('approved EXACT one-act quotes are the only excerpts in one POST',
      () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final target = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: map, actId: map.acts[1].id);
    expect(target.snippets, hasLength(3));
    expect(target.paidRequestCount, 1);
    expect(target.consentAlreadyGranted, false);
    expect(target.eventIds, [for (final e in target.snippets) e.id]);
    expect(() => target.snippets.clear(), throwsUnsupportedError);
    final transport = _Transport([_ok(_answer(target))]);
    final gateway = _gateway(transport);
    final response = await gateway.request(
      book: book, bookMap: map,
      actId: target.actId,
      approvedDigest: target.approvalDigest,
      explicitConsentForShownActQuotes: true,
    );
    expect(response.foundCandidate, true);
    expect(response.quality!.passedFormalPreflight, true);
    expect(response.quality!.plan.situations, hasLength(7));
    expect(response.readyToPlay, false);
    expect(transport.bodies, hasLength(1));
    final request = transport.bodies.single;
    final body = jsonDecode(request) as Map<String, dynamic>;
    final messages = body['messages'] as List;
    final payload = jsonDecode((messages.last as Map)['content'] as String)
        as Map<String, dynamic>;
    final samples = payload['event_samples'] as List;
    expect(samples.length, 3);
    expect(samples.every((s) =>
        !(s as Map).containsKey('suggested_label')), true);
    expect([for (final s in samples) (s as Map)['event_id']],
        target.eventIds);
    expect(request, contains(target.snippets.first.source.quote));
    expect(request, isNot(contains(book.events.first.source.quote)));
    expect(request, isNot(contains(book.events.last.source.quote)));
    expect(request, isNot(contains(book.title)));
    expect(request, isNot(contains(book.sourceFingerprint)));
    expect(request, isNot(contains('integration-test-only-placeholder')));
    expect(transport.sentHeaders.single['Authorization'],
        'Bearer integration-test-only-placeholder');
  });

  test('no unexpected request on cancelled or stale act consent',
      () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final first = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: map, actId: map.acts.first.id);
    final second = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: map, actId: map.acts[1].id);
    expect(first.approvalDigest, isNot(second.approvalDigest));
    final transport = _Transport([]);
    final gateway = _gateway(transport);
    await expectLater(gateway.request(
      book: book, bookMap: map, actId: second.actId,
      approvedDigest: second.approvalDigest,
      explicitConsentForShownActQuotes: false,
    ), throwsA(isA<AiSetupException>()));
    await expectLater(gateway.request(
      book: book, bookMap: map, actId: second.actId,
      approvedDigest: first.approvalDigest,
      explicitConsentForShownActQuotes: true,
    ), throwsA(isA<AiSetupException>()));
    expect(transport.bodies, isEmpty);
  });

  test('foreign edition, out-of-order or duplicate IDs fail before POST',
      () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final manifest = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: map, actId: map.acts.first.id);
    expect(() => ZaiStoryDilemmaProposalService.samples(
      book, exactEventIds: [manifest.eventIds.first,
        manifest.eventIds.first]), throwsA(isA<AiSetupException>()));
    expect(() => ZaiStoryDilemmaProposalService.samples(
      book, exactEventIds: manifest.eventIds.reversed.toList()),
      throwsA(isA<AiSetupException>()));
    expect(() => ZaiStoryDilemmaProposalService.samples(
      book, exactEventIds: ['event_from_other_book',
        manifest.eventIds.last]), throwsA(isA<AiSetupException>()));
    final wrongBook = await _book(_index(variation: 'Другой перевод.'));
    expect(() => ActDilemmaConsentManifest.fromAct(
      book: wrongBook, bookMap: map, actId: manifest.actId),
      throwsA(isA<AiSetupException>()));
  });

  test('an out-of-act model answer and a no-candidate result are safe',
      () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final a = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: map, actId: map.acts.first.id);
    final foreign = _answer(a)
      ..['outcome_event_id'] = book.events.last.id;
    final mock = _Transport([
      _ok(foreign), _ok({'applicable': false}),
    ]);
    final gateway = _gateway(mock);
    await expectLater(gateway.request(
      book: book, bookMap: map, actId: a.actId,
      approvedDigest: a.approvalDigest,
      explicitConsentForShownActQuotes: true,
    ), throwsA(isA<AiSetupException>()));
    final empty = await gateway.request(
      book: book, bookMap: map, actId: a.actId,
      approvedDigest: a.approvalDigest,
      explicitConsentForShownActQuotes: true,
    );
    expect(empty.foundCandidate, false);
    expect(empty.preview.plan, isNull);
    expect(empty.quality, isNull);
    expect(mock.bodies.length, 2);
    expect(mock.bodies[0], mock.bodies[1]);
  });

  test('two independently approved ACT suggestions form a LOCAL_ONLY '
      'cross-act draft with persistent flags', () async {
    final index = _index();
    final book = await _book(index);
    final map = BookwideActPlanner.build(index: index, book: book);
    final a = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: map, actId: map.acts[0].id);
    final b = ActDilemmaConsentManifest.fromAct(
        book: book, bookMap: map, actId: map.acts[1].id);
    final transport = _Transport([_ok(_answer(a)), _ok(_answer(b))]);
    final service = _gateway(transport);
    final aResult = await service.request(
      book: book, bookMap: map, actId: a.actId,
      approvedDigest: a.approvalDigest,
      explicitConsentForShownActQuotes: true,
    );
    expect(transport.bodies.length, 1); // No hidden second act request.
    final bResult = await service.request(
      book: book, bookMap: map, actId: b.actId,
      approvedDigest: b.approvalDigest,
      explicitConsentForShownActQuotes: true,
    );
    expect(transport.bodies.length, 2);
    final draft = service.composeLocal(
      index: index, bookMap: map, book: book,
      candidates: [aResult, bResult],
    );
    expect(draft.parts, hasLength(2));
    expect(draft.plan.situations, hasLength(14));
    expect(draft.fictionalBridges, hasLength(2));
    expect(draft.formalRulesPassed, true);
    expect(draft.formalAudit.counterexamples, isEmpty);
    expect(draft.coverage.referencedEvents, 4);
    expect(draft.coverage.allEvents, 9);
    expect(draft.coverage.eventIdsStillUnrepresented, hasLength(5));
    expect(draft.isFullBookRpg, false);
    expect(draft.isReadyToInstall, false);
    expect(draft.hasConfirmedWorldChronology, false);
    expect(() => service.composeLocal(
      index: index, bookMap: map, book: book,
      candidates: [bResult, aResult],
    ), throwsFormatException);
  });
}
