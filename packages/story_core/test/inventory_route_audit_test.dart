import 'package:story_core/story_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> choice(String id, String next, {
  List<Map<String, dynamic>> conditions = const [],
  List<Map<String, dynamic>> effects = const [],
}) => {'id': id, 'label': id, 'next_scene_id': next,
       'conditions': conditions, 'effects': effects};

Map<String, dynamic> scene(String id, List<Map<String, dynamic>> choices) =>
    {'id': id, 'text': 'Original test scene $id.',
     'terminal': choices.isEmpty, 'choices': choices};

StoryBlueprint fixture({bool optionalLoop = false, bool unreachable = false,
    bool forcePickup = false}) => StoryBlueprint.fromJson({
  'format': 'ai_story_blueprint_v1', 'schema_version': 1,
  'book_id': 'inventory_evidence', 'title': 'Inventory route evidence',
  'rights_status': 'original_demo', 'source_fingerprint': null,
  'entry_scene_id': 'start',
  'supported_modes': {'roles': ['PROTAGONIST'], 'plots': ['CANON'],
    'interactions': ['CLASSIC']},
  'items': ['key', 'token', 'sword'], 'facts': ['secret'], 'actors': ['player'],
  'initial_state': WorldState(sceneId: 'start', inventory: {'token'},
    flags: {'sealed': false}, knowledge: {'player': {'secret'}}).toJson(),
  'scenes': [
    scene('start', [
      choice('take_key', 'meeting', effects: [{'op': 'grant_item', 'id': 'key'}]),
      if (!forcePickup) choice('skip_key', 'meeting'),
      if (unreachable) choice('impossible', 'sealed_room',
        conditions: [{'op': 'flag_is', 'id': 'sealed', 'value': true}]),
    ]),
    scene('meeting', [
      choice('use_key', 'spent', conditions: [{'op': 'has_item', 'id': 'key'}],
        effects: [{'op': 'consume_item', 'id': 'key'}]),
      choice('leave', 'ending'),
      if (optionalLoop) choice('wait', 'meeting'),
    ]),
    scene('spent', [choice('finish', 'ending')]),
    if (unreachable) scene('sealed_room', [choice('sealed_exit', 'ending')]),
    scene('ending', []),
  ],
});

void main() {
  test('merge distinguishes guaranteed, branch-dependent and impossible inventory', () {
    final report = StoryInventoryRouteAudit.inspect(blueprint: fixture(),
      sceneIds: ['start', 'meeting', 'spent', 'ending']);
    final meeting = report.scenes['meeting']!;
    expect(meeting.presenceOf('token'), RouteItemPresence.always);
    expect(meeting.presenceOf('key'), RouteItemPresence.sometimes);
    expect(meeting.presenceOf('sword'), RouteItemPresence.never);
    expect(report.scenes['start']!.presenceOf('key'), RouteItemPresence.never);
    expect(meeting.reachableStateCount, 2);
    expect(report.exhaustive, true);
    expect(report.describesCurrentSave, false);
    expect(report.verifiesLiteraryCanon, false);
  });

  test('consumed key is absent even though its pickup is declared in the world', () {
    final report = StoryInventoryRouteAudit.inspect(blueprint: fixture(),
      sceneIds: ['spent', 'ending']);
    expect(report.scenes['spent']!.presenceOf('key'), RouteItemPresence.never);
    expect(report.scenes['ending']!.presenceOf('key'), RouteItemPresence.sometimes);
  });

  test('always present requires every executable incoming route to own the item', () {
    final report = StoryInventoryRouteAudit.inspect(blueprint: fixture(forcePickup: true),
      sceneIds: ['meeting']);
    expect(report.scenes['meeting']!.presenceOf('key'), RouteItemPresence.always);
  });

  test('audit never mutates a real world or exposes player secrets', () {
    final blueprint = fixture();
    final world = StoryWorld(blueprint);
    final before = world.state.stateHash;
    final report = StoryInventoryRouteAudit.inspect(blueprint: blueprint,
      sceneIds: ['meeting']);
    expect(world.state.stateHash, before);
    expect(world.events, isEmpty);
    expect(report.blueprintHash, blueprint.blueprintHash);
    expect(canonicalJson(report.scenes['meeting']!.toJson()), isNot(contains('secret')));
    expect(() => report.scenes.clear(), throwsUnsupportedError);
    expect(() => report.scenes['meeting']!.alwaysPresent.add('key'), throwsUnsupportedError);
  });

  test('finite optional cycles use the shared causal equivalence without invented ownership', () {
    final plain = StoryInventoryRouteAudit.inspect(blueprint: fixture(), sceneIds: ['meeting']);
    final loop = StoryInventoryRouteAudit.inspect(blueprint: fixture(optionalLoop: true), sceneIds: ['meeting']);
    expect(loop.scenes['meeting']!.toJson(), plain.scenes['meeting']!.toJson());
    expect(loop.exploredStates, plain.exploredStates);
  });

  test('state and move limits never return a partial always-or-never claim', () {
    expect(() => StoryInventoryRouteAudit.inspect(blueprint: fixture(),
      sceneIds: ['meeting'], maxStates: 2), throwsFormatException);
    expect(() => StoryInventoryRouteAudit.inspect(blueprint: fixture(),
      sceneIds: ['meeting'], maxMoves: 1), throwsFormatException);
  });

  test('unreachable scene is rejected rather than reported as empty inventory', () {
    expect(() => StoryInventoryRouteAudit.inspect(blueprint: fixture(unreachable: true),
      sceneIds: ['sealed_room']), throwsFormatException);
  });

  test('unknown scenes, item queries, empty scope and oversized budgets fail closed', () {
    for (final scenes in <List<String>>[[], ['not_a_scene']]) {
      expect(() => StoryInventoryRouteAudit.inspect(blueprint: fixture(),
        sceneIds: scenes), throwsFormatException);
    }
    expect(() => StoryInventoryRouteAudit.inspect(blueprint: fixture(),
      sceneIds: ['start'], maxStates: 8193), throwsFormatException);
    final report = StoryInventoryRouteAudit.inspect(blueprint: fixture(), sceneIds: ['start']);
    expect(() => report.scenes['start']!.presenceOf('invented'), throwsFormatException);
  });
}
