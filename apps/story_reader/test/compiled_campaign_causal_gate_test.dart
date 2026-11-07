import 'dart:convert';
import 'dart:io';

import 'package:ai_story_reader/compiled_campaign_causal_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:story_core/story_core.dart';

StoryBlueprint _scenario({
  bool unreachableEnding = false,
  bool hasSoftlock = false,
  bool hasClosedCycle = false,
  bool cycleHasExit = false,
}) {
  final data = jsonDecode(File(
      '../../shared_schemas/fixtures/private_classic_sample.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final raw = data['blueprint'] as Map<String, dynamic>;
  final entry = (raw['scenes'] as List).first as Map<String, dynamic>;
  final choices = entry['choices'] as List;
  if (unreachableEnding) {
    // Helped is initially false and can only change on a terminal path.
    ((choices[1] as Map)['conditions'] as List).add({
      'op': 'flag_is', 'id': 'helped', 'value': true,
    });
  }
  if (hasSoftlock) {
    (choices[0] as Map)['next_scene_id'] = 'sealed';
    (raw['scenes'] as List).add({
      'id': 'sealed',
      'text': 'Непроходимый игровой участок.',
      'terminal': false,
      'choices': [
        {
          'id': 'unlock', 'label': 'Попробовать продолжить',
          'next_scene_id': 'canon_end',
          'conditions': [
            {'op': 'flag_is', 'id': 'helped', 'value': true},
          ],
          'effects': <dynamic>[],
        },
      ],
    });
  }
  if (hasClosedCycle) {
    (choices[0] as Map)['next_scene_id'] = 'closed_loop';
    (raw['scenes'] as List).add({
      'id': 'closed_loop', 'text': 'Повторяющийся путь.',
      'terminal': false, 'choices': [
        {
          'id': 'repeat', 'label': 'Ходить по кругу',
          'next_scene_id': 'closed_loop',
          'conditions': <dynamic>[], 'effects': <dynamic>[],
        },
        if (cycleHasExit)
          {
            'id': 'leave_loop', 'label': 'Выйти к развязке',
            'next_scene_id': 'canon_end',
            'conditions': <dynamic>[], 'effects': <dynamic>[],
          },
      ],
    });
  }
  return StoryBlueprint.fromJson(raw);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verified private game has two independently playable endings', () {
    final report = CompiledCampaignCausalGate.verify(
      blueprint: _scenario(),
      requiredChoiceIds: const ['wait', 'help', 'leave'],
    );
    expect(report.status, CampaignCausalStatus.playable);
    expect(report.terminalWitnesses.keys,
        containsAll(['canon_end', 'alternate_end']));
    expect(report.choiceWitnesses.keys,
        containsAll(['wait', 'help', 'leave']));
    expect(report.exhaustive, isTrue);
  });

  test('compiler refuses unreachable endings instead of graph-only PASS',
      () {
    expect(() => CompiledCampaignCausalGate.verify(
      blueprint: _scenario(unreachableEnding: true),
    ), throwsA(isA<FormatException>().having(
      (e) => e.message, 'message',
      contains('недостижимые'),
    )));
  });

  test('compiler rejects a playable path into a nonterminal softlock', () {
    expect(() => CompiledCampaignCausalGate.verify(
      blueprint: _scenario(hasSoftlock: true),
    ), throwsA(isA<FormatException>().having(
      (e) => e.message, 'message',
      contains('sealed'),
    )));
  });

  test('compiler refuses a runnable but nonterminating story loop', () {
    expect(() => CompiledCampaignCausalGate.verify(
      blueprint: _scenario(hasClosedCycle: true),
    ), throwsA(isA<FormatException>().having(
      (e) => e.message, 'message', contains('цикл'),
    )));
  });

  test('compiler permits voluntary loops when escape to a finale exists', () {
    final report = CompiledCampaignCausalGate.verify(
      blueprint: _scenario(hasClosedCycle: true, cycleHasExit: true),
    );
    expect(report.playable, isTrue);
    expect(report.cycles, isEmpty);
  });

  test('incomplete bounded audit never installs an unverified campaign',
      () {
    expect(() => CompiledCampaignCausalGate.verify(
      blueprint: _scenario(), maxStates: 1,
    ), throwsA(isA<FormatException>().having(
      (e) => e.message, 'message',
      contains('лимите'),
    )));
  });
}
