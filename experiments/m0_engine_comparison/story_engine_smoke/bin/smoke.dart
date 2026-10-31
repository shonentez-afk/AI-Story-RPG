import 'package:story_engine/story_engine.dart';

void ensure(bool value, String name) {
  if (!value) throw StateError('FAIL: $name');
}

void main() {
  final startId = StoryEventId('start');
  final finishId = StoryEventId('finish');
  final leaveId = StoryChoiceId('leave');
  final enterId = StoryChoiceId('enter');
  final project = StoryProject(
    id: StoryProjectId('m0_engine_smoke'),
    entryEventId: startId,
    events: [
      StoryEvent(
        id: startId,
        presentation: StoryEventPresentation(
          body: const StoryText('Вы стоите перед особняком.'),
        ),
        choices: [
          StoryChoice(
            id: leaveId,
            presentation: const StoryChoicePresentation(
              text: StoryText('Уехать'),
            ),
            transition: const StoryTerminalTransition(),
          ),
          StoryChoice(
            id: enterId,
            presentation: const StoryChoicePresentation(
              text: StoryText('Войти'),
            ),
            transition: StoryEventTransition(destinationEventId: finishId),
          ),
        ],
      ),
      StoryEvent(
        id: finishId,
        presentation: StoryEventPresentation(
          body: const StoryText('Вы вошли в особняк.'),
        ),
        choices: [
          StoryChoice(
            id: StoryChoiceId('end'),
            presentation: const StoryChoicePresentation(
              text: StoryText('Завершить'),
            ),
            transition: const StoryTerminalTransition(),
          ),
        ],
      ),
    ],
  );
  final report = StoryValidator.validate(project);
  ensure(!report.hasErrors, report.format());
  final engine = StoryEngine(project: project)..start();
  ensure(engine.availableChoices.length == 2, 'start choices');

  final codec = StoryRuntimeSnapshotCodec();
  final saveJson = codec.encodeJson(engine.createSnapshot());
  final restored = StoryEngine.restore(
    project: project,
    snapshot: codec.decodeJson(saveJson, project: project),
  );
  ensure(restored.availableChoices.length == 2, 'restored choices');
  restored.choose(leaveId);
  ensure(restored.status == StoryEngineStatus.terminated, 'terminal choice');

  final second = StoryEngine(project: project)..start();
  second.choose(enterId);
  ensure(second.availableChoices.length == 1, 'direct transition');
  second.choose(StoryChoiceId('end'));
  ensure(second.status == StoryEngineStatus.terminated, 'second ending');
  print('PASS story_engine: validation, choices, transitions, snapshot');
}
