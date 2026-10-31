import 'dart:convert';
import 'dart:io';
import 'probe.dart' as runtime;

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Usage: dart run bin/verify_contract.dart <scenario.json> <expected_contract.json>');
  }
  final scenario = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final contract = jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  if (contract['format'] != 'ai-story-rpg/m0-contract-v1' ||
      contract['scenario'] != scenario['id']) {
    throw StateError('Invalid contract identity');
  }

  var passed = 0;
  for (final raw in contract['cases'] as List) {
    final item = raw as Map<String, dynamic>;
    final game = runtime.Probe(scenario);
    for (final choice in item['choices'] as List) {
      game.choose(choice as String);
    }
    final expectedState = Map<String, dynamic>.from(item['final_state'] as Map);
    final expectedChoices = (item['visible_choice_ids'] as List).cast<String>();
    final actualChoices = game.available.map((choice) => choice['id'] as String).toList();
    if (game.current != item['final_scene'] ||
        jsonEncode(game.state) != jsonEncode(expectedState) ||
        jsonEncode(actualChoices) != jsonEncode(expectedChoices) ||
        game.history.length != item['history_length']) {
      throw StateError('Contract mismatch: ${item['case']}');
    }
    passed++;
    stdout.writeln('PASS contract: ${item['case']}');
  }
  if (passed < 5) throw StateError('Insufficient contract coverage: $passed');
  stdout.writeln('PASS all $passed reference vs Dart contract cases');
}
