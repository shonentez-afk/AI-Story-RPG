import 'dart:convert';
import 'dart:io';
import 'package:story_engine/story_engine.dart';
import 'full_scenario.dart' as full;

void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Usage: dart run bin/stress.dart <stress.json>');
  }
  final scenario = jsonDecode(File(args.single).readAsStringSync())
      as Map<String, dynamic>;
  final project = full.buildProject(scenario);
  final report = StoryValidator.validate(project);
  if (report.hasErrors) throw StateError(report.format());

  final count = (scenario['scenes'] as List).length;
  final engine = StoryEngine(project: project)..start();
  final watch = Stopwatch()..start();

  for (var i = 0; i < count - 1; i++) {
    final id = StoryChoiceId('next_${i.toString().padLeft(4, '0')}');
    if (!engine.availableChoices.any((choice) => choice.id == id)) {
      throw StateError('Missing choice at $i');
    }
    engine.choose(id);
  }
  watch.stop();

  final finalId = 'scene_${(count - 1).toString().padLeft(4, '0')}';
  if (engine.currentEvent?.id.value != finalId ||
      engine.state?.rawValueOf(StoryVariableId('visited')) != count - 1) {
    throw StateError('Wrong ending or visit count');
  }

  final codec = StoryRuntimeSnapshotCodec();
  final encoded = codec.encodeJson(engine.createSnapshot());
  final restored = StoryEngine.restore(
    project: project,
    snapshot: codec.decodeJson(encoded, project: project),
  );
  if (restored.currentEvent?.id.value != finalId ||
      restored.state?.rawValueOf(StoryVariableId('visited')) != count - 1) {
    throw StateError('Snapshot restore failed');
  }
  restored.continueStory();
  if (restored.status != StoryEngineStatus.terminated) {
    throw StateError('Final continuation failed');
  }
  print(jsonEncode({
    'status': 'PASS',
    'engine': 'story_engine',
    'scene_count': count,
    'choice_count': count - 1,
    'elapsed_ms': watch.elapsedMilliseconds,
    'snapshot_bytes': utf8.encode(encoded).length,
    'snapshot_restore': 'PASS',
  }));
}
