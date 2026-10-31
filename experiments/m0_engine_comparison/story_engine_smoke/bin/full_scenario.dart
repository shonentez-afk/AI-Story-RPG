import 'dart:convert';
import 'dart:io';
import 'package:story_engine/story_engine.dart';

StoryValue scalar(dynamic value) {
  if (value is bool) return StoryBooleanValue(value);
  if (value is int) return StoryIntegerValue(value);
  if (value is double) return StoryNumberValue(value);
  if (value is String) return StoryStringValue(value);
  throw FormatException('Unsupported state value: $value');
}

StoryValueType valueType(dynamic value) {
  if (value is bool) return StoryValueType.boolean;
  if (value is int) return StoryValueType.integer;
  if (value is double) return StoryValueType.number;
  if (value is String) return StoryValueType.string;
  throw FormatException('Unsupported state type: $value');
}

StoryProject buildProject(Map<String, dynamic> source) {
  final initial = Map<String, dynamic>.from(source['initial'] as Map);
  return StoryProject(
    id: StoryProjectId(source['id'] as String),
    entryEventId: StoryEventId(source['entry'] as String),
    stateSchema: StoryStateSchema(
      variables: [
        for (final entry in initial.entries)
          StoryVariableDefinition(
            id: StoryVariableId(entry.key),
            type: valueType(entry.value),
            initialValue: scalar(entry.value),
          ),
      ],
    ),
    events: [
      for (final scene in source['scenes'] as List)
        buildScene(scene as Map<String, dynamic>),
    ],
  );
}

StoryEvent buildScene(Map<String, dynamic> scene) {
  final id = StoryEventId(scene['id'] as String);
  final choices = scene['choices'] as List;
  final ending = scene['ending'] == true;
  return StoryEvent(
    id: id,
    presentation: StoryEventPresentation(
      body: StoryText(scene['text'] as String),
    ),
    choices: [
      for (final raw in choices)
        buildChoice(raw as Map<String, dynamic>),
    ],
    // Empty ending scenes must explicitly terminate on Continue.
    continuationTransition: ending ? const StoryTerminalTransition() : null,
  );
}

StoryChoice buildChoice(Map<String, dynamic> choice) {
  final conditions = Map<String, dynamic>.from(choice['when'] as Map? ?? {});
  final predicates = <StoryCondition>[];
  for (final entry in conditions.entries) {
    final wanted = entry.value;
    if (wanted is Map) {
      predicates.add(StoryVariableComparisonCondition(
        variableId: StoryVariableId(entry.key),
        operator: StoryComparisonOperator.greaterThanOrEqual,
        value: scalar(wanted['gte']),
      ));
    } else {
      predicates.add(StoryVariableComparisonCondition(
        variableId: StoryVariableId(entry.key),
        operator: StoryComparisonOperator.equal,
        value: scalar(wanted),
      ));
    }
  }
  return StoryChoice(
    id: StoryChoiceId(choice['id'] as String),
    presentation: StoryChoicePresentation(
      text: StoryText(choice['text'] as String),
    ),
    availabilityCondition: predicates.isEmpty
        ? null
        : predicates.length == 1
            ? predicates.single
            : StoryAllCondition(conditions: predicates),
    effects: [
      for (final entry in (choice['set'] as Map? ?? {}).entries)
        StorySetVariableEffect(
          variableId: StoryVariableId(entry.key as String),
          value: scalar(entry.value),
        ),
      for (final entry in (choice['inc'] as Map? ?? {}).entries)
        StoryIncrementVariableEffect(
          variableId: StoryVariableId(entry.key as String),
          amount: scalar(entry.value),
        ),
    ],
    transition: StoryEventTransition(
      destinationEventId: StoryEventId(choice['next'] as String),
    ),
  );
}

void check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('scenario.json expected_contract.json required');
  }
  final source = jsonDecode(File(args[0]).readAsStringSync())
      as Map<String, dynamic>;
  final contract = jsonDecode(File(args[1]).readAsStringSync())
      as Map<String, dynamic>;
  final project = buildProject(source);
  final validation = StoryValidator.validate(project);
  check(!validation.hasErrors, validation.format());
  final initial = Map<String, dynamic>.from(source['initial'] as Map);
  var passed = 0;
  for (final raw in contract['cases'] as List) {
    final sample = raw as Map<String, dynamic>;
    var engine = StoryEngine(project: project)..start();
    final actions = (sample['choices'] as List).cast<String>();
    for (var i = 0; i < actions.length; i++) {
      if (i == actions.length ~/ 2) {
        final codec = StoryRuntimeSnapshotCodec();
        final snapshot = codec.encodeJson(engine.createSnapshot());
        engine = StoryEngine.restore(
          project: project,
          snapshot: codec.decodeJson(snapshot, project: project),
        );
      }
      final id = actions[i];
      check(engine.availableChoices.any((choice) => choice.id.value == id),
          'Unavailable choice: $id');
      engine.choose(StoryChoiceId(id));
    }
    check(engine.currentEvent?.id.value == sample['final_scene'],
        'Wrong scene: ${sample['case']}');
    final wanted = Map<String, dynamic>.from(sample['final_state'] as Map);
    for (final entry in initial.entries) {
      check(engine.state?.rawValueOf(StoryVariableId(entry.key)) ==
          wanted[entry.key], 'State mismatch: ${sample['case']} / ${entry.key}');
    }
    final visible = engine.availableChoices.map((c) => c.id.value).toList();
    check(jsonEncode(visible) == jsonEncode(sample['visible_choice_ids']),
        'Choice mismatch: ${sample['case']}');
    check(engine.status == StoryEngineStatus.awaitingContinue,
        'Ending should await explicit Continue: ${sample['case']}');
    engine.continueStory();
    check(engine.status == StoryEngineStatus.terminated,
        'Ending did not terminate: ${sample['case']}');
    passed++;
    stdout.writeln('PASS story_engine scenario: ${sample['case']}');
  }
  check(passed >= 5, 'Insufficient fixtures');
  stdout.writeln('PASS all $passed story_engine contract paths');
}
