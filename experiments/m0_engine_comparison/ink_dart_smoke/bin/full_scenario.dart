import 'dart:convert';
import 'dart:io';
import 'package:ink_dart/ink_dart.dart';

void verify(bool ok, String message) {
  if (!ok) throw StateError(message);
}

String advance(Story story) {
  final output = StringBuffer();
  while (story.canContinue) {
    output.write(story.continueStory());
  }
  return output.toString();
}

void main(List<String> args) {
  if (args.length != 3) {
    throw ArgumentError('Usage: full_scenario.dart compiled.json scenario.json expected_contract.json');
  }
  final compiled = File(args[0]).readAsStringSync();
  final scenario = jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final contract = jsonDecode(File(args[2]).readAsStringSync()) as Map<String, dynamic>;
  verify(contract['scenario'] == scenario['id'], 'Scenario identity mismatch');

  final sceneById = <String, Map<String, dynamic>>{
    for (final raw in scenario['scenes'] as List)
      (raw as Map<String, dynamic>)['id'] as String: raw,
  };

  var passed = 0;
  for (final raw in contract['cases'] as List) {
    final test = raw as Map<String, dynamic>;
    final actions = (test['choices'] as List).cast<String>();
    var story = Story.fromJson(compiled);
    final errors = <String>[];
    story.onError = (message, type) => errors.add('$type: $message');
    var sceneId = scenario['entry'] as String;
    var visibleText = advance(story);

    for (var i = 0; i < actions.length; i++) {
      final actionId = actions[i];
      final scene = sceneById[sceneId]!;
      final matching = (scene['choices'] as List)
          .cast<Map<String, dynamic>>()
          .where((c) => c['id'] == actionId)
          .toList();
      verify(matching.length == 1, 'Unknown choice $actionId at $sceneId');
      final action = matching.single;
      final matchingIndices = <int>[];
      for (var index = 0; index < story.currentChoices.length; index++) {
        if (story.currentChoices[index].text.trim() ==
            (action['text'] as String).trim()) {
          matchingIndices.add(index);
        }
      }
      verify(matchingIndices.length == 1,
          'Choice $actionId unavailable or ambiguous at $sceneId');
      story.chooseChoiceIndex(matchingIndices.single);
      sceneId = action['next'] as String;
      visibleText = advance(story);

      if (i == actions.length ~/ 2) {
        // Cross-instance restoration is stronger than reloading the same instance.
        final saved = story.state.toJson();
        final restored = Story.fromJson(compiled);
        restored.state.loadJson(saved);
        final restoredText = advance(restored);
        verify(restoredText == '', 'Restore unexpectedly replayed narrative');
        verify(restored.currentChoices.length == story.currentChoices.length,
            'Restore changed number of choices');
        for (var k = 0; k < story.currentChoices.length; k++) {
          verify(restored.currentChoices[k].text == story.currentChoices[k].text,
              'Restore changed choice text');
        }
        restored.onError = (message, type) => errors.add('$type: $message');
        story = restored; // Continue all remaining actions on restored instance.
      }
    }

    final expectedScene = test['final_scene'] as String;
    verify(sceneId == expectedScene, 'Wrong destination for ${test['case']}');
    verify(visibleText.contains(sceneById[expectedScene]!['text'] as String),
        'Final scene text mismatch for ${test['case']}');
    for (final entry in (test['final_state'] as Map).entries) {
      verify(story.variablesState[entry.key as String] == entry.value,
          'State mismatch for ${test['case']} / ${entry.key}');
    }
    verify(story.currentChoices.isEmpty && !story.canContinue,
        'Ending should terminate for ${test['case']}');
    verify(errors.isEmpty, 'Ink runtime errors: $errors');
    passed++;
    stdout.writeln('PASS ink_dart contract: ${test['case']}');
  }
  verify(passed >= 5, 'Insufficient contract cases');
  stdout.writeln('PASS all $passed ink_dart paths with state and save checks');
}
