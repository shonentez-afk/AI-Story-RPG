import 'dart:async';
import 'package:flutter/material.dart';
import 'package:story_engine/story_engine.dart';
import 'save_store.dart';
import 'home_page.dart';
import 'app_theme.dart';
import 'reading_preferences.dart';
import 'game_panels.dart';
import 'game_progress.dart';
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
  StoryEvent node(String id, String title, String body, List<StoryChoice> choices) =>
      StoryEvent(
        id: StoryEventId(id),
        presentation: StoryEventPresentation(
          title: StoryText(title), body: StoryText(body)),
        choices: choices,
      );
  StoryChoice go(String id, String label, String destination) => StoryChoice(
    id: StoryChoiceId(id),
    presentation: StoryChoicePresentation(text: StoryText(label)),
    transition: StoryEventTransition(destinationEventId: StoryEventId(destination)),
  );
  StoryChoice end(String id, String label) => StoryChoice(
    id: StoryChoiceId(id),
    presentation: StoryChoicePresentation(text: StoryText(label)),
    transition: const StoryTerminalTransition(),
  );

  return StoryProject(
    id: StoryProjectId('ai_story_m1_intro'),
    entryEventId: StoryEventId('gate'),
    events: [
      node('gate', 'Тайна особняка',
        'На закате вы подходите к старому особняку. За воротами слышатся шаги.', [
          go('enter', 'Войти и исследовать дом', 'library'),
          end('leave', 'Вернуться домой'),
        ]),
      node('library', 'Библиотека',
        'В библиотеке вы находите старое письмо. В нижнем ящике что-то звенит.', [
          go('inspect_letter', 'Прочитать старое письмо', 'study'),
          go('search_drawer', 'Осмотреть ящик стола', 'study'),
          end('finish', 'Завершить пролог'),
        ]),
      node('study', 'Кабинет хранителя',
        'За книжной полкой скрыта лестница. На стене висит план особняка.', [
          go('take_map', 'Забрать план особняка', 'corridor'),
          go('follow_steps', 'Пойти на звук шагов', 'corridor'),
        ]),
      node('corridor', 'Тёмный коридор',
        'В конце коридора — дверь с латунным замком и потемневшая лестница.', [
          go('unlock_cellar', 'Открыть дверь в подвал', 'cellar'),
          go('climb_tower', 'Подняться по лестнице', 'tower'),
        ]),
      node('cellar', 'Подвал',
        'В подвале мерцает свет. За каменной кладкой слышится голос.', [
          go('open_secret', 'Раскрыть тайный проход', 'secret'),
          end('retreat', 'Запереть подвал и уйти'),
        ]),
      node('tower', 'Башня',
        'В башне колышется тень. На столе лежат следы чужого исследования.', [
          go('face_shadow', 'Подойти к таинственной тени', 'secret'),
          end('escape_tower', 'Покинуть особняк через балкон'),
        ]),
      node('secret', 'Тайна раскрыта',
        'Вы находите запись хранителя: особняк собирал истории путешественников.', [
          end('preserve_story', 'Сохранить тайну особняка'),
          end('reveal_story', 'Рассказать миру правду'),
        ]),
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
  bool _saveBusy = false;
  bool _restoreBusy = false;
  bool _loadedFromSlot = false;
  final List<String> _sessionDecisions = [];
  GameProgress _progress = const GameProgress();
  int _rulesVersion = 1; // New pilot games use inventory-gated choices.
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
    if (_saveBusy || _restoreBusy) return;
    // Validate at the action boundary, not only in the disabled-button UI.
    if (_rulesVersion >= 1 && _progress.choiceLockReason(id.value) != null) {
      return;
    }
    final event = _engine.currentEvent;
    final label = _engine.availableChoices
        .where((choice) => choice.id == id)
        .map((choice) => choice.presentation?.text.value ?? choice.id.value)
        .first;
    setState(() {
      _engine.choose(id);
      final before = _progress;
      _progress = _progress.apply(id.value);
      _sessionDecisions.add('${event?.presentation?.title?.value ?? 'Сцена'}: $label');
      final effects = <String>[];
      if (_progress.courage > before.courage) effects.add('Смелость +${_progress.courage - before.courage}');
      if (_progress.insight > before.insight) effects.add('Наблюдательность +${_progress.insight - before.insight}');
      for (final item in _progress.items) {
        if (!before.items.contains(item)) effects.add('Найдено: ${GameProgress.itemNames[item] ?? item}');
      }
      if (effects.isNotEmpty) {
        _sessionDecisions.add('Результат: ${effects.join(', ')}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(effects.join(' • ')), duration: const Duration(seconds: 3)));
        });
      }
    });
  }

  Future<void> _save() async {
    if (_saveBusy || _restoreBusy) return;
    setState(() => _saveBusy = true);
    try {
      // A new session must not silently replace a previously saved game.
      if (!_loadedFromSlot && await _saves.read() != null) {
        if (!mounted) return;
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Заменить сохранение?'),
            content: const Text(
              'Сейчас сохранена другая игровая сессия. '
              'Её прогресс будет перезаписан. Продолжить?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Заменить')),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      final encoded = StoryRuntimeSnapshotCodec()
          .encodeJson(_engine.createSnapshot());
      await _saves.writeGame(encoded, _sessionDecisions, _progress, _rulesVersion);
      if (!mounted) return;
      setState(() {
        _hasSave = true;
        _loadedFromSlot = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Прогресс сохранён на устройстве')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $error')),
      );
    } finally {
      if (mounted) setState(() => _saveBusy = false);
    }
  }

  Future<void> _restore() async {
    if (_saveBusy || _restoreBusy) return;
    setState(() => _restoreBusy = true);
    try {
      final saved = await _saves.readGame();
      if (saved == null) return;
      final restored = StoryEngine.restore(
        project: _project,
        snapshot: StoryRuntimeSnapshotCodec().decodeJson(
          saved.snapshot, project: _project,
        ),
      );
      if (!mounted) return;
      setState(() {
        _engine = restored;
        _progress = saved.progress;
        _rulesVersion = saved.rulesVersion;
        _loadedFromSlot = true;
        _sessionDecisions
          ..clear()
          ..addAll(saved.journal);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранение несовместимо или повреждено: $error')),
      );
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
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
        journalEntries: List.unmodifiable(_sessionDecisions),
        progress: _progress,
      ),
    );
  }

  void _restart() {
    setState(() {
      _sessionDecisions.clear();
      _progress = const GameProgress();
      _rulesVersion = 1;
      _loadedFromSlot = false;
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
              padding: EdgeInsets.fromLTRB(_reading.horizontalPadding,
                _reading.horizontalPadding, _reading.horizontalPadding, 100),
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
                  _PilotChoiceButton(
                    label: choice.presentation?.text.value ?? choice.id.value,
                    disabledReason: _rulesVersion == 0
                        ? null
                        : _progress.choiceLockReason(choice.id.value),
                    foreground: _reading.foreground,
                    onPressed: () => _choose(choice.id),
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
                      onPressed: _saveBusy || _restoreBusy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _hasSave && !_saveBusy && !_restoreBusy ? _restore : null,
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

/// A visible, explanatory lock is preferable to silently hiding a choice.
/// Keeps the same list layout and accessibility on phone and desktop.
class _PilotChoiceButton extends StatelessWidget {
  const _PilotChoiceButton({
    required this.label,
    required this.disabledReason,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final String? disabledReason;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: disabledReason == null ? onPressed : null,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(label),
                ),
              ),
            ),
            if (disabledReason != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                child: Text(
                  'Недоступно: $disabledReason',
                  style: TextStyle(color: foreground, fontSize: 12),
                ),
              ),
          ],
        ),
      );
}
