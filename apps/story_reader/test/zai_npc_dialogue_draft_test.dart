import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/npc_dialogue_draft_page.dart';
import 'package:ai_story_reader/zai_npc_dialogue_draft.dart';
import 'package:bookworld_format/bookworld_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Prefs extends AiCloudPreferences {
  _Prefs(this.enabled);
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
  Future<bool> hasKey() async => key != null;
  @override
  Future<void> write(String value) async => key = value;
  @override
  Future<void> delete() async => key = null;
}

class _Net implements AiHttpTransport {
  _Net(this.responses);
  final List<AiHttpResponse> responses;
  final List<String> bodies = [];
  final List<Map<String, String>> headers = [];
  @override
  Future<AiHttpResponse> send({
    required Uri uri, required Map<String, String> headers,
    required String body,
  }) async {
    expect(uri, ZaiModel.endpoint);
    this.headers.add(Map.of(headers));
    bodies.add(body);
    return responses[bodies.length - 1];
  }
}

Map<String, dynamic> _obj(Object? value) =>
    Map<String, dynamic>.from(value as Map);

(NpcDialogueDraftContext, VerifiedRichPrivateBookworld) _context() {
  final sample = _obj(jsonDecode(
      File('../../shared_schemas/fixtures/private_classic_sample.json')
          .readAsStringSync()));
  final bp = _obj(sample['blueprint']);
  final provenance = _obj(sample['provenance']);
  final npc = 'npc_' + List.filled(32, 'c').join();
  (bp['actors'] as List).add(npc);
  (bp['facts'] as List).add('npc_secret');
  final initial = _obj(bp['initial_state']);
  (initial['knowledge'] as Map)[npc] = <String>[];
  bp['initial_state'] = initial;
  final entry = (bp['scenes'] as List).first as Map;
  final learning = (entry['choices'] as List).first as Map;
  (learning['effects'] as List).add({
    'op': 'learn_fact', 'id': 'npc_secret', 'actor': npc,
  });
  final encounter = (bp['scenes'] as List)[1] as Map;
  encounter['text'] = 'Мария: «Теперь я слышала историю.»\n'
      'Игрок: «Расскажи подробнее.»\n'
      'Мария: «Ты можешь выбрать свой путь.»';
  final source = (provenance['scene_origins'] as List).first as Map;
  final quote = (source['source_refs'] as List).first['quote_sha256'];
  provenance['format'] = 'ai_story_private_provenance_v2';
  provenance['model_provenance'] = <String, dynamic>{
    'provider': 'none', 'model_id': null,
    'model_id_status': 'not_applicable',
    'tool': 'none', 'method': 'local_fixture',
  };
  provenance['presentation'] = <String, dynamic>{
    'hero': {'name': 'Игрок', 'description': 'Частный герой'},
    'item_names': <String, String>{},
    'item_descriptions': <String, String>{},
    'stat_names': <String, String>{},
    'fact_names': {'npc_secret': 'Проверенный факт NPC'},
    'scene_names': {
      'entry': 'Начало', 'canon_end': 'Разговор',
      'alternate_end': 'Другой исход',
    },
    'scene_dialogues': {
      'canon_end':
          RichSceneDialogue.presentationFor(encounter['text'] as String),
    },
    'scene_dialogue_knowledge': {
      'canon_end': [
        {
          'turn_index': 0, 'speaker': 'Мария', 'actor_id': npc,
          'required_fact_ids': ['npc_secret'],
          'required_prior_choice_id': 'wait',
          'source_quote_sha256': quote,
          'private_fiction_confirmed': true,
        },
        {
          'turn_index': 1, 'speaker': 'Игрок', 'actor_id': 'player',
          'required_fact_ids': <String>[],
        },
        {
          'turn_index': 2, 'speaker': 'Мария', 'actor_id': npc,
          'required_fact_ids': <String>[],
        },
      ],
    },
  };
  provenance['npc_knowledge'] = {
    'format': RichPrivateBookworldImporter.npcKnowledgeFormat,
    'review_scope': 'user_declared_private_game_fiction',
    'source_fingerprint': bp['source_fingerprint'],
    'user_confirmed': true,
    'literary_canon_verified': false,
    'grants': [
      {
        'scene_id': 'entry', 'choice_id': 'wait',
        'actor_id': npc, 'fact_id': 'npc_secret',
        'source_quote_sha256': quote,
      },
    ],
  };
  final bytes = const RichPrivateBookworldWriter().build(
    blueprint: bp, provenance: provenance,
    sourceIndex: _obj(sample['source_index']),
  );
  final verified = const RichPrivateBookworldImporter().inspect(bytes);
  final origins = <String, dynamic>{
    for (final raw in provenance['scene_origins'] as List)
      (raw as Map)['scene_id'] as String: raw,
  };
  return (NpcDialogueDraftContext.fromVerifiedWorld(
    world: verified, sceneId: 'canon_end', sceneOrigins: origins,
    approvedMotivations: {
      npc: 'Пытается осторожно предупредить игрока о выборе.',
    },
    approvedFactDescriptions: {
      'npc_secret': 'Ранее услышанное сообщение о событиях.',
    },
  ), verified);
}

AiHttpResponse _answer({
  String sceneId = 'canon_end',
  List<Map<String, Object?>>? turns,
  String uncertainty =
      'Неизвестно, соответствует ли новая формулировка характеру.',
  bool extra = false,
  String finishReason = 'stop',
}) => AiHttpResponse(200, jsonEncode({
  'choices': [{
    'finish_reason': finishReason,
    'message': {
      'content': jsonEncode({
        'scene_id': sceneId,
        'turns': turns ?? [
          {'turn_index': 0, 'speaker': 'Мария',
           'text': 'Я помню тот рассказ и теперь могу ответить.'},
          {'turn_index': 1, 'speaker': 'Игрок',
           'text': 'Тогда скажи мне, что случилось.'},
          {'turn_index': 2, 'speaker': 'Мария',
           'text': 'Решение остаётся только за тобой.'},
        ],
        'uncertainty': uncertainty,
        if (extra) 'literary_canon_verified': true,
      }),
    },
  }],
}));

ZaiNpcDialogueDraftService _service(_Net net, {
  bool enabled = true, String? key = 'PRIVATE-KEY',
}) => ZaiNpcDialogueDraftService(
  preferences: _Prefs(enabled), vault: _Vault(key),
  transport: net, retryWait: (duration) async {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signed source+NPC context sends exact consented data only', () async {
    final (context, world) = _context();
    expect(context.originalTurns, hasLength(3));
    expect(context.approvalDigest, hasLength(64));
    expect(context.consentPreview['narrative_status'],
        'PRIVATE_GAME_FICTION_NOT_CANON');
    final preview = jsonEncode(context.consentPreview);
    expect(preview, contains('required_prior_choice_id'));
    expect(preview, contains('approved_motivations'));
    expect(preview, isNot(contains(world.sourceFingerprint)));
    expect(preview, isNot(contains('PRIVATE-KEY')));
    final net = _Net([_answer()]);
    final draft = await _service(net).preview(
      context: context, approvedDigest: context.approvalDigest,
      explicitCloudConsent: true,
    );
    expect(draft.sceneId, 'canon_end');
    expect(draft.sceneText, contains('Мария: «Я помню тот рассказ'));
    expect(draft.sceneText, contains('Игрок: «Тогда скажи'));
    expect(draft.isHumanReviewed, false);
    expect(draft.canInstallDirectly, false);
    expect(draft.canModifyCampaign, false);
    expect(draft.isLiteraryCanon, false);
    expect(world.requiresNetwork, false);
    expect(net.bodies, hasLength(1));
    final sent = jsonDecode(net.bodies.single) as Map<String, dynamic>;
    expect(sent['model'], ZaiModel.id);
    expect(sent['thinking'], {'type': 'disabled'});
    expect(sent['response_format'], {'type': 'json_object'});
    final content = jsonDecode(
        (sent['messages'] as List).last['content'] as String);
    expect(content, context.consentPreview);
    expect(net.headers.single['Authorization'], 'Bearer PRIVATE-KEY');
  });

  test('source binding and speaker guards reject unreviewed inputs', () {
    final (ctx, world) = _context();
    final source = world.blueprint.scenes.keys.toSet();
    expect(source, contains('canon_end'));
    expect(ctx.sceneId, 'canon_end');
    expect(() => NpcDialogueDraftContext.fromVerifiedWorld(
      world: world, sceneId: 'alternate_end', sceneOrigins: {},
    ), throwsFormatException);
    expect(() => NpcDialogueDraftContext.fromVerifiedWorld(
      world: world, sceneId: 'canon_end', sceneOrigins: {},
    ), throwsFormatException);
    expect(() => NpcDialogueDraftContext.fromVerifiedWorld(
      world: world, sceneId: 'canon_end',
      sceneOrigins: const {
        'canon_end': {'origin': 'EXPLICIT_ADAPTATION'},
      },
    ), throwsFormatException);
  });

  test('no cloud consent or key never sends request', () async {
    final (ctx, _) = _context();
    final net = _Net([]);
    await expectLater(_service(net).preview(
      context: ctx, approvedDigest: ctx.approvalDigest,
      explicitCloudConsent: false,
    ), throwsA(isA<AiSetupException>()));
    await expectLater(_service(net).preview(
      context: ctx, approvedDigest: List.filled(64, '0').join(),
      explicitCloudConsent: true,
    ), throwsA(isA<AiSetupException>()));
    await expectLater(_service(net, enabled: false).preview(
      context: ctx, approvedDigest: ctx.approvalDigest,
      explicitCloudConsent: true,
    ), throwsA(isA<AiSetupException>()));
    await expectLater(_service(net, key: null).preview(
      context: ctx, approvedDigest: ctx.approvalDigest,
      explicitCloudConsent: true,
    ), throwsA(isA<AiSetupException>()));
    expect(net.bodies, isEmpty);
  });

  test('AI cannot invent speakers, turn indices or game authority', () {
    final (ctx, _) = _context();
    String changed({
      String? speaker, int? index, String? line,
      bool extra = false, String? scene,
    }) => _answer(
      sceneId: scene ?? 'canon_end', extra: extra,
      turns: [
        {'turn_index': index ?? 0, 'speaker': speaker ?? 'Мария',
          'text': line ?? 'Я хорошо помню прошлую встречу.'},
        {'turn_index': 1, 'speaker': 'Игрок',
          'text': 'Что произошло на дороге?'},
        {'turn_index': 2, 'speaker': 'Мария',
          'text': 'Решение остаётся за тобой.'},
      ],
    ).body;
    for (final raw in [
      changed(speaker: 'Новый король'),
      changed(index: 2),
      changed(line: 'Чужая «секретная» реплика'),
      changed(line: 'Первая строка\nвторая строка'),
      changed(extra: true),
      changed(scene: 'alternate_end'),
      _answer(finishReason: 'length').body,
    ]) {
      expect(() => ZaiNpcDialogueDraftService.parseForTest(ctx, raw),
          throwsA(isA<AiSetupException>()));
    }
    expect(() => ZaiNpcDialogueDraftService.parseForTest(
        ctx, _answer().body), returnsNormally);
  });

  test('429 replays exact same approved payload then succeeds', () async {
    final (context, _) = _context();
    final net = _Net([
      const AiHttpResponse(429, '{}', retryAfter: '0'),
      _answer(),
    ]);
    final draft = await _service(net).preview(
      context: context, approvedDigest: context.approvalDigest,
      explicitCloudConsent: true,
    );
    expect(draft.canModifyCampaign, false);
    expect(net.bodies, hasLength(2));
    expect(net.bodies[0], net.bodies[1]);
  });

  testWidgets('cloud NPC authoring screen is opt-in and cannot install game',
      (tester) async {
    final (ctx, _) = _context();
    final net = _Net([_answer()]);
    await tester.pumpWidget(MaterialApp(home: NpcDialogueDraftPage(
      preview: ctx, service: _service(net),
    )));
    final consent = find.byKey(const Key('npc-dialogue-cloud-consent'));
    final generate = find.byKey(const Key('npc-dialogue-cloud-generate'));
    expect(find.byKey(const Key('npc-dialogue-cloud-payload')),
        findsOneWidget);
    expect(tester.widget<FilledButton>(generate).onPressed, isNull);
    expect(net.bodies, isEmpty);
    await tester.ensureVisible(consent);
    await tester.tap(consent);
    await tester.pump();
    expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('npc-dialogue-cloud-draft')),
        findsOneWidget);
    expect(find.textContaining('НЕ установлен в игру'), findsOneWidget);
    expect(net.bodies, hasLength(1));
  });
}
