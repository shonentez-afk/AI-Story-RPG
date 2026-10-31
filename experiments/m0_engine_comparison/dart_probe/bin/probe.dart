import 'dart:convert';
import 'dart:io';

class Probe {
  Probe(Map<String, dynamic> data)
      : scenes = {
          for (final raw in data['scenes'] as List)
            (raw as Map<String, dynamic>)['id'] as String: raw
        },
        state = Map<String, dynamic>.from(data['initial'] as Map),
        current = data['entry'] as String;

  final Map<String, Map<String, dynamic>> scenes;
  final Map<String, dynamic> state;
  String current;
  final List<String> history = [];

  List<Map<String, dynamic>> get available {
    final raw = scenes[current]!['choices'] as List;
    return raw.cast<Map<String, dynamic>>().where((choice) {
      final conditions = (choice['when'] as Map?) ?? {};
      for (final entry in conditions.entries) {
        final actual = state[entry.key];
        final wanted = entry.value;
        if (wanted is Map) {
          if (!wanted.containsKey('gte') || actual is! num ||
              actual < (wanted['gte'] as num)) return false;
        } else if (wanted != actual) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void choose(String id) {
    final matches = available.where((choice) => choice['id'] == id).toList();
    if (matches.length != 1) throw StateError('Unavailable choice: $id');
    final choice = matches.single;
    for (final entry in ((choice['set'] as Map?) ?? {}).entries) {
      if (state[entry.key].runtimeType != entry.value.runtimeType) {
        throw StateError('Mismatched state type');
      }
      state[entry.key] = entry.value;
    }
    for (final entry in ((choice['inc'] as Map?) ?? {}).entries) {
      if (state[entry.key] is! int || entry.value is! int) {
        throw StateError('Increment type error');
      }
      state[entry.key] = (state[entry.key] as int) + (entry.value as int);
    }
    current = choice['next'] as String;
    history.add(id);
  }
}

Never _fail(String message) => throw StateError(message);

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/probe.dart <path to scenario.json>');
    exitCode = 64;
    return;
  }
  final data = jsonDecode(File(args.single).readAsStringSync()) as Map<String, dynamic>;

  Probe run(List<String> choices) {
    final game = Probe(data);
    for (final choice in choices) {
      game.choose(choice);
    }
    return game;
  }

  final escape = run(['leave']);
  if (escape.current != 'end_leave') _fail('Leave ending');
  final fail = run(['talk', 'enter_yard', 'ignore_witness', 'tower_empty', 'accuse']);
  if (fail.current != 'end_failure') _fail('Failure ending');
  final truth = run(['talk', 'enter_yard', 'save_witness', 'find_letter', 'show_evidence']);
  if (truth.current != 'end_truth') _fail('Truth ending');
  if (fail.state['witness_alive'] != false) _fail('Witness consequence');

  final locked = run(['talk']);
  if (locked.available.any((choice) => choice['id'] == 'open_gate')) _fail('Key gate');
  final unlocked = run(['market', 'take_key']);
  if (!unlocked.available.any((choice) => choice['id'] == 'open_gate')) _fail('Key grant');
  final trust = run(['talk', 'befriend', 'save_witness', 'ask_witness']);
  if (!trust.available.any((choice) => choice['id'] == 'trust_talk')) _fail('Trust gate');
  final dead = run(['talk', 'enter_yard', 'ignore_witness']);
  if (dead.available.any((choice) => choice['id'] == 'ask_witness')) _fail('Dead witness gate');

  final steps = <String>['talk'];
  for (var i = 0; i < 9; i++) {
    steps.addAll(['befriend', 'return_gate']);
  }
  steps.addAll(['befriend', 'save_witness', 'find_letter', 'show_evidence']);
  final uninterrupted = run(steps);
  final replay = run(steps.take(11).toList());
  for (final choice in steps.skip(11)) {
    replay.choose(choice);
  }
  if (uninterrupted.current != replay.current ||
      jsonEncode(uninterrupted.state) != jsonEncode(replay.state) ||
      uninterrupted.history.length < 20) {
    _fail('Replay mismatch');
  }

  stdout.writeln(jsonEncode({
    'status': 'PASS',
    'engine': 'independent_dart_probe',
    'scenes': data['scenes'].length,
    'choices': (data['scenes'] as List).fold<int>(
        0, (sum, s) => sum + (s['choices'] as List).length),
    'replayed_turns': uninterrupted.history.length,
    'endings_tested': ['end_leave', 'end_failure', 'end_truth'],
    'notice': 'Not story_engine or ink_dart integration'
  }));
}
