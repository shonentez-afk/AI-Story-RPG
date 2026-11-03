import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/book_import.dart';
import 'package:ai_story_reader/book_model.dart';
import 'package:ai_story_reader/book_source_index.dart';
import 'package:ai_story_reader/source_semantic_provider.dart';
import 'package:ai_story_reader/source_semantic_window.dart';
import 'package:ai_story_reader/zai_semantic_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements AiApiKeyVault {
  @override
  Future<String?> read() async => 'FAKE-TEST-KEY';
  @override
  Future<bool> hasKey() async => true;
  @override
  Future<void> write(String _) async {}
  @override
  Future<void> delete() async {}
}

class _Network implements AiHttpTransport {
  final requests = <String>[];
  List<dynamic> suggestions = [];
  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    expect(uri, ZaiModel.endpoint);
    requests.add(body);
    return AiHttpResponse(200, jsonEncode({
      'choices': [{
        'finish_reason': 'stop',
        'message': {
          'content': jsonEncode({'candidates': suggestions}),
        },
      }],
    }));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const story = 'Жил-был бедный принц. '
      'Королевство у него было маленькое-премаленькое. '
      'Принц хотел жениться на дочери императора.';
  const book = ImportedBook(
    title: 'Свинопас',
    author: 'НЕ ПЕРЕДАВАТЬ',
    chapters: [story],
    structuredChapters: [
      BookChapter(id: 'chapter_0', blocks: [
        BookBlock(kind: BookBlockKind.heading, text: 'СВИНОПАС'),
        BookBlock(kind: BookBlockKind.paragraph, text: story),
        BookBlock(kind: BookBlockKind.paragraph,
            text: 'Послушаем же, как было дело.'),
      ]),
    ],
  );

  late BookSourceIndex index;
  late SourceSemanticWindow window;
  late _Network transport;
  late AiCloudPreferences preferences;
  late ZaiSemanticPreviewService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'game_save': 'intact'});
    index = BookSourceIndexer.index(book);
    window = SourceSemanticWindowPlanner.plan(index).single;
    transport = _Network();
    preferences = AiCloudPreferences();
    await preferences.setEnabled(true);
    service = ZaiSemanticPreviewService(
      preferences: preferences,
      transport: transport,
      vault: _Vault(),
      retryWait: (d) async {},
    );
  });

  test('source window rejects header-as-character, generic place and '
      'static state wrongly labelled event', () async {
    final heading = window.chunks[0].id;
    final paragraph = window.chunks[1].id;
    transport.suggestions = [
      {
        'category': 'character',
        'source_id': heading,
        'quote': 'СВИНОПАС',
        'label': 'Свинопас',
        'uncertainty': 'Название может быть персонажем.',
      },
      {
        'category': 'location',
        'source_id': paragraph,
        'quote': 'Королевство',
        'label': 'Королевство',
        'uncertainty': 'Не указано имя королевства.',
      },
      {
        'category': 'event',
        'source_id': paragraph,
        'quote': 'Королевство у него было маленькое-премаленькое.',
        'label': 'Королевство было маленьким',
        'uncertainty': 'Нужна проверка исходного состояния.',
      },
      {
        'category': 'state',
        'source_id': paragraph,
        'quote': 'Королевство у него было маленькое-премаленькое.',
        'label': 'Королевство принца маленькое',
        'uncertainty': 'Это состояние, а не событие.',
      },
      {
        'category': 'fact',
        'source_id': paragraph,
        'quote': 'Принц хотел жениться на дочери императора.',
        'label': 'Принц желает жениться на дочери императора',
        'uncertainty': 'Это намерение, а не совершившийся брак.',
      },
      {
        'category': 'character',
        'source_id': paragraph,
        'quote': 'бедный принц',
        'label': 'Принц',
        'uncertainty': 'Имя принца неизвестно.',
      },
    ];
    final result = await service.preview(
      index: index, chunk: window.chunks.first, window: window,
      consentForThisChunk: true, consentForBookTitle: true,
    );
    expect(result.totalSuggestions, 6);
    expect(result.rejectedCount, 3);
    expect(result.rejectionReasons.length, 3);
    expect(result.rejectionReasons.join(' '), contains('заголовок'));
    expect(result.rejectionReasons.join(' '),
        contains('Обычное обозначение места'));
    expect(result.rejectionReasons.join(' '),
        contains('Статическое свойство'));
    expect(result.batch.candidates.length, 3);
    expect(result.batch.candidates.map((c) => c.category).toSet(), {
      SemanticCategory.character,
      SemanticCategory.fact,
      SemanticCategory.state,
    });
    final saved = await SharedPreferences.getInstance();
    expect(saved.getString('game_save'), 'intact');
    expect(result.batch.canPublishBookworld, false);
    expect(result.batch.gameplayCoverage, 0);

    expect(transport.requests.length, 1);
    final req = jsonDecode(transport.requests.single) as Map<String, dynamic>;
    final payload = jsonDecode(
        (req['messages'] as List<dynamic>)[1]['content'] as String)
        as Map<String, dynamic>;
    expect(payload.keys.toSet(), {'book_title', 'source_chunks'});
    expect(payload['book_title'], 'Свинопас');
    expect(transport.requests.single, isNot(contains('НЕ ПЕРЕДАВАТЬ')));
    final sourcePieces = payload['source_chunks'] as List<dynamic>;
    expect(sourcePieces.length, 3);
    expect(sourcePieces[0], {
      'source_id': heading,
      'kind': 'heading',
      'text': 'СВИНОПАС',
    });
    expect(sourcePieces[1]['source_id'], paragraph);
    expect(sourcePieces[1]['text'], story);
    expect(sourcePieces[2]['kind'], 'paragraph');
    for (final candidate in result.batch.candidates) {
      final c = index.chunks.firstWhere((x) => x.id == candidate.chunkId);
      expect(candidate.quote,
          c.text.substring(candidate.startUtf16 - c.startUtf16,
              candidate.endUtf16 - c.startUtf16));
    }
  });

  test('source_id points to exact chunk; forged, missing and '
      'ambiguous citations are rejected without changing the world',
      () async {
    final paragraph = window.chunks[1].id;
    transport.suggestions = [
      {
        'category': 'fact', 'source_id': 'NOT-SOURCE',
        'quote': 'бедный принц', 'label': 'Принц беден',
        'uncertainty': 'Проверка цитаты.',
      },
      {
        'category': 'fact', 'source_id': window.chunks[0].id,
        'quote': 'бедный принц', 'label': 'Принц беден',
        'uncertainty': 'В заголовке цитаты нет.',
      },
      {
        'category': 'fact', 'source_id': paragraph,
        'quote': 'и', 'label': 'Повторяющаяся частица',
        'uncertainty': 'Слово встречается повторно.',
      },
    ];
    final result = await service.preview(
      index: index, chunk: window.chunks.first, window: window,
      consentForThisChunk: true,
    );
    expect(result.totalSuggestions, 3);
    expect(result.rejectedCount, 3);
    expect(result.batch.candidates, isEmpty);
  });

  test('refuse sending a forged, cross-chapter or non-reviewed window '
      'before any HTTP call', () async {
    final forged = SourceSemanticWindow([window.chunks[1], window.chunks[0]]);
    await expectLater(
      service.preview(
        index: index, chunk: forged.chunks.first, window: forged,
        consentForThisChunk: true, consentForBookTitle: true,
      ),
      throwsA(isA<AiSetupException>()),
    );
    await expectLater(
      service.preview(
        index: index, chunk: window.chunks.first, window: window,
        consentForThisChunk: false, consentForBookTitle: true,
      ),
      throwsA(isA<AiSetupException>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('model is not allowed to elevate an unsupported proof status', () async {
    transport.suggestions = [
      {
        'category': 'state', 'source_id': window.chunks[1].id,
        'quote': 'бедный принц', 'label': 'Принц беден',
        'uncertainty': 'Состояние требует проверки.',
        'status': 'CONFIRMED',
      },
    ];
    await expectLater(
      service.preview(
        index: index, chunk: window.chunks.first, window: window,
        consentForThisChunk: true, consentForBookTitle: true,
      ),
      throwsA(isA<AiSetupException>()),
    );
    expect(transport.requests.length, 1);
  });

  test('retries preserve identical whole-window body and source mappings',
      () async {
    final queued = <String>[];
    final flaky = _FlakyNetwork(queued);
    final instance = ZaiSemanticPreviewService(
      preferences: preferences, transport: flaky,
      vault: _Vault(), retryWait: (d) async {},
    );
    final result = await instance.preview(
      index: index, chunk: window.chunks.first, window: window,
      consentForThisChunk: true, consentForBookTitle: true,
    );
    expect(result.batch.chunkIds, window.chunks.map((x) => x.id).toList());
    expect(queued.length, 2);
    expect(queued[0], queued[1]);
  });
}

class _FlakyNetwork implements AiHttpTransport {
  _FlakyNetwork(this.bodies);
  final List<String> bodies;
  @override
  Future<AiHttpResponse> send({
    required Uri uri, required Map<String, String> headers,
    required String body,
  }) async {
    bodies.add(body);
    if (bodies.length == 1) {
      return const AiHttpResponse(429, '{"error":{"code":"1302"}}');
    }
    return AiHttpResponse(200, jsonEncode({
      'choices': [{
        'finish_reason': 'stop',
        'message': {'content': '{"candidates":[]}'},
      }],
    }));
  }
}
