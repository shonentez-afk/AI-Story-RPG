import 'package:ai_story_reader/world_library_gateway.dart';
import 'package:story_core/story_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final yes = BlueprintChoice.fromJson({
    'id': 'help', 'label': 'Помочь Марии', 'next_scene_id': 'canon_end',
    'conditions': <Map<String, dynamic>>[],
    'effects': <Map<String, dynamic>>[],
  });
  final gated = BlueprintChoice.fromJson({
    'id': 'promise', 'label': 'Раскрыть обещание',
    'next_scene_id': 'canon_end',
    'conditions': [
      {'op': 'knows_fact', 'id': 'npc_secret', 'actor': 'player'},
    ],
    'effects': <Map<String, dynamic>>[],
  });

  test('signed NPC reply appears as a spoken player choice', () {
    final choice = WorldChoiceView.fromVerifiedRules(
      signedChoice: yes, lockReason: null,
      verifiedKnowledge: const {}, reviewedSpokenReply: 'Я помогу тебе.',
    );
    expect(choice.id, 'help');
    expect(choice.label, 'Игрок: «Я помогу тебе.»');
    expect(choice.enabled, isTrue);
  });

  test('unmet story_core guard always hides entire spoken reply', () {
    final choice = WorldChoiceView.fromVerifiedRules(
      signedChoice: gated, lockReason: 'condition_not_met:knows_fact',
      verifiedKnowledge: const {'player': <String>{}},
      reviewedSpokenReply: 'Я знаю секретную концовку.',
    );
    expect(choice.enabled, isFalse);
    expect(choice.label, 'Ответ недоступен до выполнения условий');
    expect(choice.label, isNot(contains('секретную')));
  });

  test('a spoken label cannot override a denied engine choice', () {
    final blocked = WorldChoiceView.fromVerifiedRules(
      signedChoice: yes, lockReason: 'condition_not_met:npc_memory',
      verifiedKnowledge: const {}, reviewedSpokenReply: 'Обещаю помочь.',
    );
    expect(blocked.enabled, isFalse);
    expect(blocked.label, 'Ответ недоступен до выполнения условий');
  });

  test('older choices without a spoken review retain legacy labels', () {
    final choice = WorldChoiceView.fromVerifiedRules(
      signedChoice: yes, lockReason: null, verifiedKnowledge: const {},
    );
    expect(choice.label, 'Помочь Марии');
    expect(choice.enabled, isTrue);
  });
}
