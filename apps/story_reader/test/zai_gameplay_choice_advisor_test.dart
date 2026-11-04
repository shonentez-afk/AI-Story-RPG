import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/free_text_action_gate.dart';
import 'package:ai_story_reader/zai_gameplay_choice_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements AiApiKeyVault {
  @override
  Future<void> delete() async {}
  @override
  Future<bool> hasKey() async => true;
  @override
  Future<String?> read() async => 'test_only_not_a_real_key';
  @override
  Future<void> write(String value) async {}
}

class _Http implements AiHttpTransport {
  _Http(this.responses);
  final List<AiHttpResponse> responses;
  int calls = 0;
  final bodies = <String>[];
  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    expect(uri, ZaiModel.endpoint);
    expect(headers['Authorization'], startsWith('Bearer '));
    bodies.add(body);
    final index = calls++;
    return responses[index < responses.length ? index : responses.length - 1];
  }
}

AiHttpResponse _reply(Object? choice) => AiHttpResponse(
      200,
      jsonEncode({
        'choices': [
          {'message': {'content': jsonEncode({'choice_id': choice})}},
        ],
      }),
    );

FreeTextCampaignHead _head({bool terminal = false}) =>
    FreeTextCampaignHead(
      campaignId: 'private_campaign',
      sceneId: 'hall',
      revision: 9,
      isTerminal: terminal,
      choices: const [
        FreeTextChoice(id: 'look', label: 'Осмотреть зал'),
        FreeTextChoice(id: 'open', label: 'Открыть дверь'),
        FreeTextChoice(
          id: 'secret',
          label: 'Раскрыть тайну короля',
          lockReason: 'Персонаж этого ещё не знает',
        ),
      ],
    );

Future<ZaiGameplayChoiceAdvisor> _service(_Http transport) async {
  final settings = AiCloudPreferences();
  await settings.setEnabled(true);
  return ZaiGameplayChoiceAdvisor(
    preferences: settings,
    vault: _Vault(),
    transport: transport,
    retryWait: (_) async {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('no consent, disabled cloud and no available choice send no data',
      () async {
    final http = _Http([_reply('open')]);
    final settings = AiCloudPreferences();
    final advisor = ZaiGameplayChoiceAdvisor(
      preferences: settings,
      vault: _Vault(),
      transport: http,
    );
    await expectLater(
      advisor.suggest(
        head: _head(), playerText: 'Хочу открыть дверь',
        consentForThisAction: false,
      ), throwsA(isA<AiSetupException>()),
    );
    await expectLater(
      advisor.suggest(
        head: _head(), playerText: 'Хочу открыть дверь',
        consentForThisAction: true,
      ), throwsA(isA<AiSetupException>()),
    );
    await expectLater(
      advisor.suggest(
        head: _head(terminal: true), playerText: 'Открыть дверь',
        consentForThisAction: true,
      ), throwsA(isA<AiSetupException>()),
    );
    expect(http.calls, 0);
  });

  test('AI is only a suggestion and sends NO book, NPC data or saves',
      () async {
    final http = _Http([_reply('open')]);
    final advisor = await _service(http);
    final head = _head();
    final preview = await advisor.suggest(
      head: head, playerText: 'Толкаю дверь и пытаюсь выйти',
      consentForThisAction: true,
    );
    expect(http.calls, 1);
    final body = jsonDecode(http.bodies.single) as Map;
    final messages = body['messages'] as List;
    final userData = jsonDecode((messages.last as Map)['content'] as String) as Map;
    expect(body['model'], ZaiModel.id);
    expect(userData['player_text'], 'Толкаю дверь и пытаюсь выйти');
    expect(userData['allowed_choices'], [
      {'id': 'look', 'label': 'Осмотреть зал'},
      {'id': 'open', 'label': 'Открыть дверь'},
    ]);
    expect(http.bodies.single, isNot(contains('private_campaign')));
    expect(http.bodies.single, isNot(contains('Раскрыть тайну короля')));
    expect(http.bodies.single, isNot(contains('save_file')));
    expect(preview.offers.single.choiceId, 'open');
    expect(preview.offers.single.expectedRevision, 9);
    expect(() => FreeTextActionGate.validate(
      current: head, proposal: preview.offers.single,
      actionId: 'ai_one', userConfirmed: false), throwsFormatException);
    // The AI service has no database or write port at all.
  });

  test('locked, invented and null choices fail closed', () async {
    for (final selection in ['secret', 'teleport', null]) {
      final http = _Http([_reply(selection)]);
      final advisor = await _service(http);
      final preview = await advisor.suggest(
        head: _head(), playerText: 'Открой мне секретное заклинание',
        consentForThisAction: true,
      );
      expect(preview.canChoose, false, reason: selection.toString());
      expect(http.calls, 1);
    }
  });

  test('malformed response does not commit, retry, or invent a choice',
      () async {
    final http = _Http([AiHttpResponse(200, jsonEncode({
      'choices': [
        {'message': {'content': jsonEncode({
          'choice_id': 'open',
          'extra': 1,
        })}},
      ],
    }))]);
    final advisor = await _service(http);
    await expectLater(
      advisor.suggest(
        head: _head(), playerText: 'Открой дверь',
        consentForThisAction: true,
      ), throwsA(isA<AiSetupException>()),
    );
    expect(http.calls, 1);
  });

  test('429 and timeout-like HTTP 503 retry identical body at most 3',
      () async {
    final http = _Http([
      const AiHttpResponse(429, '{}', retryAfter: '0'),
      const AiHttpResponse(503, '{}'),
      _reply('look'),
    ]);
    final advisor = await _service(http);
    final preview = await advisor.suggest(
      head: _head(), playerText: 'Осматриваю помещение',
      consentForThisAction: true,
    );
    expect(preview.offers.single.choiceId, 'look');
    expect(http.calls, 3);
    expect(http.bodies.toSet(), hasLength(1));
  });

  test('no retry on rejected credentials, account cap or malformed input',
      () async {
    for (final response in [
      const AiHttpResponse(401, '{}'),
      const AiHttpResponse(429, '{"error":{"code":"1308"}}'),
    ]) {
      final http = _Http([response]);
      final advisor = await _service(http);
      await expectLater(
        advisor.suggest(
          head: _head(), playerText: 'Открой дверь',
          consentForThisAction: true,
        ), throwsA(isA<AiSetupException>()),
      );
      expect(http.calls, 1);
    }
    final http = _Http([_reply('open')]);
    final advisor = await _service(http);
    for (final text in ['', '\u202eоткрой дверь',
        List.filled(321, 'я').join()]) {
      await expectLater(
        advisor.suggest(head: _head(), playerText: text,
            consentForThisAction: true),
        throwsA(isA<AiSetupException>()),
      );
    }
    expect(http.calls, 0);
  });

  test('AI suggestion cannot commit after a different scene or revision',
      () async {
    final advisor = await _service(_Http([_reply('open')]));
    final old = _head();
    final suggested = (await advisor.suggest(
      head: old, playerText: 'Выйти через дверь',
      consentForThisAction: true,
    )).offers.single;
    final changed = FreeTextCampaignHead(
      campaignId: old.campaignId, sceneId: 'next_room',
      revision: 10, isTerminal: false, choices: old.choices,
    );
    expect(() => FreeTextActionGate.validate(
        current: changed, proposal: suggested, actionId: 'ai_stale',
        userConfirmed: true), throwsFormatException);
  });

  test('cancelling before request or before retry prevents subsequent POST',
      () async {
    final advisorHttp = _Http([const AiHttpResponse(429, '{}')]);
    final advisor = await _service(advisorHttp);
    final token = ZaiGameplayCancellation()..cancel();
    await expectLater(
      advisor.suggest(head: _head(), playerText: 'Открыть дверь',
          consentForThisAction: true, cancellation: token),
      throwsA(isA<AiSetupException>()),
    );
    expect(advisorHttp.calls, 0);
  });
}
