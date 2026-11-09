import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/zai_gameplay_choice_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:story_core/story_core.dart';

class _SecretVault implements AiApiKeyVault {
  @override
  Future<void> delete() async {}
  @override
  Future<bool> hasKey() async => true;
  @override
  Future<String?> read() async => 'test_secret_not_exportable';
  @override
  Future<void> write(String value) async {}
}

class _FakeTransport implements AiHttpTransport {
  _FakeTransport(this.responses);
  final List<AiHttpResponse> responses;
  final List<String> bodies = [];
  int sent = 0;
  @override
  Future<AiHttpResponse> send({
    required Uri uri, required Map<String, String> headers,
    required String body,
  }) async {
    expect(uri, ZaiModel.endpoint);
    expect(headers['Authorization'], 'Bearer test_secret_not_exportable');
    bodies.add(body);
    final i = sent++;
    return responses[i < responses.length ? i : responses.length - 1];
  }
}

AiHttpResponse _proposal({Object? effects, String? narration}) =>
    AiHttpResponse(200, jsonEncode({
      'choices': [{'message': {
        'content': jsonEncode({
          'narration': narration ??
              'Игрок записал догадку. Это вымышленное игровое действие.',
          'effects': effects ?? [
            {'op': 'set_flag', 'id': 'gm_noted', 'value': true},
          ],
        }),
      }}],
    }));

WorldGameView _view({bool available = true, bool terminal = false}) =>
    WorldGameView(
      campaignId: 'canon_test_campaign',
      worldTitle: 'Закрытая книга',
      sceneId: 'canon_00000',
      sceneText: 'Один герой шёл по дороге, оставляя тайну в следующей главе.',
      revision: 3, tick: 7, isTerminal: terminal,
      stateHash: 'a' * 64,
      stats: const {'gm_resolve': 50},
      inventory: const [],
      flags: const {'gm_noted': false},
      knownFacts: const [],
      choices: const [],
      journal: const [],
      gmStats: const {'gm_resolve': 50},
      gmFlags: const {'gm_noted': false},
      gmItems: const ['gm_keepsake'],
      gmFacts: const ['gm_impression'],
      freeformAvailable: available,
      sourceLiteralCanon: true,
    );

Future<ZaiGameplayChoiceAdvisor> _service(_FakeTransport transport) async {
  final prefs = AiCloudPreferences();
  await prefs.setEnabled(true);
  return ZaiGameplayChoiceAdvisor(
      preferences: prefs,
      vault: _SecretVault(),
      transport: transport,
      retryWait: (_) async {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('model authors a genuinely NEW typed event proposal without '
      'choosing a preexisting choice and never writes a campaign', () async {
    final http = _FakeTransport([_proposal()]);
    final advisor = await _service(http);
    final proposal = await advisor.suggestDynamic(
      view: _view(),
      playerText: 'Я оставляю свой знак на дороге.',
      consentForThisAction: true,
    );
    expect(proposal.effects.single.op, 'set_flag');
    expect(proposal.effects.single.id, 'gm_noted');
    expect(proposal.narration, contains('вымышленное'));
    expect(proposal.toJson()['scope'], FreeformActionDraft.fictionScope);
    expect(http.sent, 1);
    final request = jsonDecode(http.bodies.single) as Map;
    final body = jsonDecode(((request['messages'] as List).last as Map)
        ['content'] as String) as Map;
    expect(body['player_text'], contains('оставляю'));
    expect(body['gm_resources']['flags'], {'gm_noted': false});
    expect(body.containsKey('world_save'), false);
    expect(http.bodies.single, isNot(contains('test_secret_not_exportable')));
    expect(http.bodies.single, isNot(contains('canon_test_campaign')));
    expect(http.bodies.single, isNot(contains('future_chapter')));
  });

  test('no separate consent, no dynamic source world and invalid text '
      'never call the model', () async {
    final http = _FakeTransport([_proposal()]);
    final ai = await _service(http);
    for (final input in [
      (view: _view(), text: 'Хочу идти', consent: false),
      (view: _view(available: false), text: 'Хочу идти', consent: true),
      (view: _view(terminal: true), text: 'Хочу идти', consent: true),
      (view: _view(), text: 'запрос\u202e', consent: true),
    ]) {
      await expectLater(ai.suggestDynamic(
        view: input.view, playerText: input.text,
        consentForThisAction: input.consent,
      ), throwsA(isA<AiSetupException>()));
    }
    expect(http.sent, 0);
  });

  test('malicious effects cannot change source/NPC facts or make up '
      'entity IDs; an invalid reply never becomes a turn', () async {
    for (final raw in [
      [{'op': 'learn_fact', 'id': 'book_secret', 'actor': 'player'}],
      [{'op': 'learn_fact', 'id': 'gm_impression', 'actor': 'npc_hidden'}],
      [{'op': 'grant_item', 'id': 'canonical_crown'}],
      [{'op': 'exec_shell', 'id': 'gm_noted'}],
    ]) {
      final http = _FakeTransport([_proposal(effects: raw)]);
      final ai = await _service(http);
      await expectLater(ai.suggestDynamic(
        view: _view(), playerText: 'Осмотреть место',
        consentForThisAction: true,
      ), throwsA(isA<AiSetupException>()));
      expect(http.sent, 1);
    }
    final http = _FakeTransport([
      const AiHttpResponse(200, '{"choices":[{"message":{"content":"not json"}}]}'),
    ]);
    final ai = await _service(http);
    await expectLater(ai.suggestDynamic(
        view: _view(), playerText: 'Посмотреть',
        consentForThisAction: true),
        throwsA(isA<AiSetupException>()));
  });

  test('temporary 429 retries identical request, cancellation '
      'stops additional calls', () async {
    final http = _FakeTransport([
      const AiHttpResponse(429, '{}', retryAfter: '0'),
      _proposal(),
    ]);
    final ai = await _service(http);
    await ai.suggestDynamic(
        view: _view(), playerText: 'Осмотреть камень',
        consentForThisAction: true);
    expect(http.sent, 2);
    expect(http.bodies.toSet(), hasLength(1));
    final stopped = ZaiGameplayCancellation()..cancel();
    final blocked = _FakeTransport([_proposal()]);
    final second = await _service(blocked);
    await expectLater(second.suggestDynamic(
        view: _view(), playerText: 'Исследовать',
        consentForThisAction: true, cancellation: stopped),
        throwsA(isA<AiSetupException>()));
    expect(blocked.sent, 0);
  });
}
