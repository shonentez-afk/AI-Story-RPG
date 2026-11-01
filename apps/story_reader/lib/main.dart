import 'dart:async';
import 'package:flutter/material.dart';
import 'package:story_engine/story_engine.dart';
import 'save_store.dart';
import 'home_page.dart';
import 'app_theme.dart';
import 'reading_preferences.dart';
import 'game_panels.dart';
import 'reading_settings_sheet.dart';
import 'reader_chrome.dart';

void main() {
  runApp(const AIStoryApp());
}

class AIStoryApp extends StatefulWidget {
  const AIStoryApp({super.key});

  @override
  State<AIStoryApp> createState() => _AIStoryAppState();
}

class _AIStoryAppState extends State<AIStoryApp> {
  @override
  void initState() {
    super.initState();
    AppAppearanceController.instance.addListener(_refresh);
    AppAppearanceController.instance.load();
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    AppAppearanceController.instance.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Живая книга',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: AppAppearanceController.instance.value == AppAppearance.dark
            ? ThemeMode.dark : ThemeMode.light,
        home: const HomePage(),
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
  const StoryReaderPage({super.key, this.resume = false});

  final bool resume;

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  late final StoryProject _project;
  late StoryEngine _engine;
  final SaveStore _saves = SaveStore();
  bool _hasSave = false;
  ReadingPreferences _reading = const ReadingPreferences();
  ReaderChromeMode _chrome = ReaderChromeMode.normal;
  bool _peekControls = false;
  Timer? _peekTimer;
  final ReadingSettingsStore _readingSettingsStore = ReadingSettingsStore();

  @override
  void initState() {
    super.initState();
    _project = makePilotStory();
    final validation = StoryValidator.validate(_project);
    if (validation.hasErrors) {
      throw StateError(validation.format());
    }
    _engine = StoryEngine(project: _project)..start();
    _checkSave();
    _readingSettingsStore.load().then((value) {
      if (mounted) setState(() => _reading = value);
    });
    if (widget.resume) _restore();
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    super.dispose();
  }

  void _changeChrome(ReaderChromeMode next) {
    _peekTimer?.cancel();
    setState(() {
      _chrome = next;
      _peekControls = false;
    });
  }

  void _tapReadingCanvas() {
    if (_chrome != ReaderChromeMode.fullscreen) return;
    _peekTimer?.cancel();
    setState(() => _peekControls = !_peekControls);
    if (_peekControls) {
      _peekTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _peekControls = false);
      });
    }
  }

  Future<void> _checkSave() async {
    final snapshot = await _saves.read();
    if (mounted) setState(() => _hasSave = snapshot != null);
  }

  void _choose(StoryChoiceId id) {
    setState(() => _engine.choose(id));
  }

  Future<void> _save() async {
    try {
      final encoded = StoryRuntimeSnapshotCodec()
          .encodeJson(_engine.createSnapshot());
      await _saves.write(encoded);
      if (!mounted) return;
      setState(() => _hasSave = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Прогресс сохранён на устройстве')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $error')),
      );
    }
  }

  Future<void> _restore() async {
    try {
      final saved = await _saves.read();
      if (saved == null) return;
      final restored = StoryEngine.restore(
        project: _project,
        snapshot: StoryRuntimeSnapshotCodec().decodeJson(
          saved,
          project: _project,
        ),
      );
      if (!mounted) return;
      setState(() => _engine = restored);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранение несовместимо или повреждено: $error')),
      );
    }
  }

  void _updateReading(ReadingPreferences next) {
    setState(() => _reading = next);
    _readingSettingsStore.save(next);
  }

  void _showReadingSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReadingSettingsSheet(
        preferences: _reading,
        onChanged: _updateReading,
      ),
    );
  }

  void _openPanel(GamePanel panel) {
    final event = _engine.currentEvent;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => GameInfoSheet(
        panel: panel,
        currentScene: event?.presentation?.title?.value ?? 'Конец пролога',
      ),
    );
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
      backgroundColor: _reading.background,
      appBar: !_chrome.showTopBar ? null : AppBar(
        backgroundColor: _reading.background,
        foregroundColor: _reading.foreground,
        title: const Text('Живая книга'),
        actions: [
          IconButton(
            tooltip: 'Настройки чтения',
            onPressed: _showReadingSettings,
            icon: const Icon(Icons.text_fields),
          ),
        ],
      ),
      floatingActionButton: ReaderChromeButton(
        mode: _chrome,
        background: _reading.foreground,
        foreground: _reading.background,
        onChange: _changeChrome,
      ),
      bottomNavigationBar: !(_chrome.showGameBar || _peekControls) ? null : ColoredBox(
        color: _reading.background,
        child: Theme(
          data: Theme.of(context).copyWith(
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: _reading.foreground),
            ),
          ),
          child: GameQuickBar(onOpen: _openPanel, color: _reading.foreground),
        ),
      ),
      body: ColoredBox(
        color: _reading.background,
        child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _tapReadingCanvas,
        child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: EdgeInsets.all(_reading.horizontalPadding),
              children: [
                Text(
                  done ? 'Конец пролога' :
                      (event?.presentation?.title?.value ?? 'История'),
                  style: TextStyle(color: _reading.foreground,
                    fontSize: _reading.fontSize + 7, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Text(
                  done ? 'Попробуйте другое решение.' :
                      (event?.presentation?.body?.value ?? ''),
                  style: TextStyle(color: _reading.foreground,
                    fontSize: _reading.fontSize, height: _reading.lineHeight),
                ),
                const SizedBox(height: 30),
                if (!done && _engine.availableChoices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('ВАШЕ ДЕЙСТВИЕ',
                      style: TextStyle(color: _reading.foreground,
                        fontSize: 12, fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
                  ),
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
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _hasSave ? _restore : null,
                      icon: const Icon(Icons.restore),
                      label: const Text('Загрузить'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Демо RPG • Один локальный слот сохранения',
                  style: TextStyle(color: _reading.foreground, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}
