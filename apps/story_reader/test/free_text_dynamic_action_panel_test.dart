import 'dart:convert';

import 'package:ai_story_reader/ai_connection.dart';
import 'package:ai_story_reader/free_text_action_panel.dart';
import 'package:ai_story_reader/zai_gameplay_choice_advisor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_api/rpg_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Key implements AiApiKeyVault {
  @override
  Future<void> delete() async {}
  @override
  Future<bool> hasKey() async => true;
  @override
  Future<String?> read() async => 'not_an_actual_key';
  @override
  Future<void> write(String value) async {}
}

class _Network implements AiHttpTransport {
  int calls = 0;
  String? sentBody;
  @override
  Future<AiHttpResponse> send({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    calls++;
    sentBody = body;
    expect(uri, ZaiModel.endpoint);
    return AiHttpResponse(200, jsonEncode({
      'choices': [{'message': {'content': jsonEncode({
        'narration': 'Игрок получил вымышленный речной камень.',
        'effects': [{'op': 'grant_item', 'id': 'gm_river_stone'}],
      })}}],
    }));
  }
}

WorldGameView _view(int revision) => WorldGameView(
  campaignId: 'c1', worldTitle: 'Книга', sceneId: 'canon_00000',
  sceneText: 'Книга начинается у реки.',
  revision: revision, tick: revision, isTerminal: false,
  stateHash: revision == 0 ? 'b' * 64 : 'c' * 64,
  stats: const {'gm_resolve': 50},
  inventory: revision == 0 ? const [] : const ['gm_river_stone'],
  flags: const {'gm_noted': false}, knownFacts: const [],
  choices: const [], journal: const [],
  freeformAvailable: true, sourceLiteralCanon: true,
  gmStats: const {'gm_resolve': 50},
  gmFlags: const {'gm_noted': false},
  gmItems: const ['gm_keepsake'], gmFacts: const ['gm_impression'],
);

class _Gateway implements WorldLibraryGateway, WorldDynamicActionGateway {
  int writes = 0;
  int previews = 0;
  @override
  Future<WorldGameView> load(String id) async => _view(writes);

  @override
  Future<FreeformActionPreview> previewDynamic(
      String campaignId, FreeformActionDraft draft,
      {required int expectedRevision}) async {
    previews++;
    expect(campaignId, 'c1');
    expect(draft.effects.single.id, 'gm_river_stone');
    expect(expectedRevision, 0);
    return FreeformActionPreview(
      campaignId: campaignId, expectedRevision: 0,
      stateHash: 'b' * 64, nextStateHash: 'c' * 64,
      narration: draft.narration, approvalDigest: 'a' * 64,
    );
  }

  @override
  Future<WorldChoiceResult> commitDynamic(String campaignId, {
    required String actionId,
    required FreeformActionDraft draft,
    required int expectedRevision,
    required String approvalDigest,
    required bool userConfirmed,
  }) async {
    expect(userConfirmed, true);
    expect(campaignId, 'c1');
    expect(approvalDigest, 'a' * 64);
    expect(expectedRevision, 0);
    expect(actionId.startsWith('free_'), true);
    writes++;
    return WorldChoiceResult(applied: true, view: _view(writes));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('CANON free text produces a NEW AI action only after '
      'network consent, native preview and second explicit commit',
      (tester) async {
    final preferences = AiCloudPreferences();
    await preferences.setEnabled(true);
    final transport = _Network();
    final ai = ZaiGameplayChoiceAdvisor(
      preferences: preferences,
      vault: _Key(),
      transport: transport,
      retryWait: (_) async {},
    );
    final gateway = _Gateway();
    var committed = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: FreeTextActionPanel(
          campaignId: 'c1', gateway: gateway,
          dynamicAvailable: true, aiAdvisor: ai,
          onCommitted: (_) => committed++,
        ),
      ),
    )));
    await tester.enterText(
        find.byKey(const Key('free-text-input')),
        'Поднять новый речной камень');
    final button = find.byKey(const Key('free-text-ai-dynamic'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(transport.calls, 0);
    expect(gateway.writes, 0);
    expect(find.text('Создать новое игровое действие с Z.ai?'),
        findsOneWidget);
    expect(find.textContaining('открытые обещания'), findsWidgets);
    expect(find.textContaining('альтернативной ветки'), findsWidgets);
    await tester.tap(find.byKey(const Key('free-text-dynamic-consent')));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    expect(gateway.previews, 1);
    expect(gateway.writes, 0);
    expect(find.byKey(const Key('free-text-dynamic-narration')),
        findsOneWidget);
    expect(find.byKey(const Key('free-text-dynamic-impact')),
        findsOneWidget);
    expect(find.text('Получить предмет: river stone'), findsOneWidget);
    expect(find.textContaining('не изменены'), findsWidgets);
    expect(find.textContaining('НЕ канон книги'), findsOneWidget);
    final commit = find.byKey(const Key('free-text-dynamic-confirm'));
    await tester.ensureVisible(commit);
    await tester.tap(commit);
    await tester.pumpAndSettle();
    expect(gateway.writes, 1);
    expect(committed, 1);
    expect(transport.sentBody, contains('gm_'));
    expect(transport.sentBody, contains('alternate_plot_continuity'));
    expect(transport.sentBody, contains('open_promise_ids'));
    expect(transport.sentBody, isNot(contains('not_an_actual_key')));
    expect(tester.takeException(), isNull);
  });
}
