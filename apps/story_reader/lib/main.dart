import 'package:flutter/material.dart';
import 'package:story_engine/story_engine.dart';

void main() {
  runApp(const AIStoryApp());
}

class AIStoryApp extends StatelessWidget {
  const AIStoryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Живая книга',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF6750A4),
        ),
        home: const StoryReaderPage(),
      );
}

StoryProject makePilotStory() {
  const gate = 'gate';
  const library = 'library';
  return StoryProject(
    id: StoryProjectId('ai_story_m1_intro'),
    entryEventId: StoryEventId(gate),
    events: [
      StoryEvent(
        id: StoryEventId(gate),
        presentation: StoryEventPresentation(
          title: const StoryText('Тайна особняка'),
          body: const StoryText(
            'На закате вы подходите к старому особняку. За воротами слышатся шаги.',
          ),
        ),
        choices: [
          StoryChoice(
            id: StoryChoiceId('enter'),
            presentation: const StoryChoicePresentation(
              text: StoryText('Войти и исследовать дом'),
            ),
            transition: StoryEventTransition(
              destinationEventId: StoryEventId(library),
            ),
          ),
          StoryChoice(
            id: StoryChoiceId('leave'),
            presentation: const StoryChoicePresentation(
              text: StoryText('Вернуться домой'),
            ),
            transition: const StoryTerminalTransition(),
          ),
        ],
      ),
      StoryEvent(
        id: StoryEventId(library),
        presentation: StoryEventPresentation(
          title: const StoryText('Библиотека'),
          body: const StoryText(
            'В библиотеке вы находите старое письмо. История только начинается.',
          ),
        ),
        choices: [
          StoryChoice(
            id: StoryChoiceId('finish'),
            presentation: const StoryChoicePresentation(
              text: StoryText('Завершить пролог'),
            ),
            transition: const StoryTerminalTransition(),
          ),
        ],
      ),
    ],
  );
}

class StoryReaderPage extends StatefulWidget {
  const StoryReaderPage({super.key});

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  late final StoryProject _project;
  late StoryEngine _engine;
  String? _savedSnapshot;

  @override
  void initState() {
    super.initState();
    _project = makePilotStory();
    final validation = StoryValidator.validate(_project);
    if (validation.hasErrors) {
      throw StateError(validation.format());
    }
    _engine = StoryEngine(project: _project)..start();
  }

  void _choose(StoryChoiceId id) {
    setState(() => _engine.choose(id));
  }

  void _save() {
    setState(() {
      _savedSnapshot = StoryRuntimeSnapshotCodec()
          .encodeJson(_engine.createSnapshot());
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Снимок прохождения сохранён в памяти')),
    );
  }

  void _restore() {
    final saved = _savedSnapshot;
    if (saved == null) return;
    setState(() {
      _engine = StoryEngine.restore(
        project: _project,
        snapshot: StoryRuntimeSnapshotCodec().decodeJson(
          saved,
          project: _project,
        ),
      );
    });
  }

  void _restart() {
    setState(() {
      _engine = StoryEngine(project: _project)..start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = _engine.currentEvent;
    final done = _engine.status == StoryEngineStatus.terminated;
    return Scaffold(
      appBar: AppBar(title: const Text('Живая книга')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  done ? 'Конец пролога' :
                      (event?.presentation?.title?.value ?? 'История'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                Text(
                  done ? 'Попробуйте другое решение.' :
                      (event?.presentation?.body?.value ?? ''),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 30),
                for (final choice in _engine.availableChoices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton.tonal(
                      onPressed: () => _choose(choice.id),
                      child: Text(choice.presentation?.text.value ?? choice.id.value),
                    ),
                  ),
                if (done)
                  FilledButton(
                    onPressed: _restart,
                    child: const Text('Начать заново'),
                  ),
                const Divider(height: 36),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: done ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _savedSnapshot == null ? null : _restore,
                      icon: const Icon(Icons.restore),
                      label: const Text('Загрузить'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'M1 прототип: сохранение пока только в оперативной памяти. '
                  'Импорт книг, постоянные слоты и ИИ будут добавлены отдельно.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
