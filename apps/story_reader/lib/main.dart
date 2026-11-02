import 'dart:async';
import 'package:flutter/material.dart';
import 'package:story_engine/story_engine.dart';
import 'save_store.dart';
import 'campaign_store.dart';
import 'home_page.dart';
import 'app_theme.dart';
import 'reading_preferences.dart';
import 'game_panels.dart';
import 'game_progress.dart';
import 'reading_settings_sheet.dart';
import 'reader_chrome.dart';
import 'world_library_gateway.dart';

void main() {
  // Production explicitly opts in to native BookWorld/SQLite. Lightweight
  // hosts and legacy widget tests can instantiate AIStoryApp without plugins.
  runApp(const AIStoryApp(
    worldGateway: DeviceWorldLibraryGateway(),
  ));
}

class AIStoryApp extends StatefulWidget {
  const AIStoryApp({super.key, this.worldGateway});

  final WorldLibraryGateway? worldGateway;

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
        home: HomePage(worldGateway: widget.worldGateway),
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
  const StoryReaderPage({super.key, this.resume = false, this.campaignId});

  final bool resume;
  final String? campaignId;

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  late final StoryProject _project;
  late StoryEngine _engine;
  final CampaignStore _campaigns = CampaignStore();
  String? _campaignId;
  Future<bool> _pendingWrite = Future<bool>.value(true);
  bool _hasSave = false;
  bool _saveBusy = false;
  bool _restoreBusy = false;
  bool _restoreFailed = false;
  String? _restoreFailureText;
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
    _campaignId = widget.campaignId;
    if (widget.resume || widget.campaignId != null) {
      _restore();
    } else {
      _campaignId = CampaignStore.newId();
      // Start each new story with a separate initial checkpoint.
      _queueSave();
    }
    _readingSettingsStore.load().then((value) {
      if (mounted) setState(() => _reading = value);
    });
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

  /// Every confirmed transition captures all state synchronously.
  /// Writes are serialized so a slow earlier turn cannot overwrite a newer
  /// choice, even when the user taps actions quickly or leaves the page.
  Future<bool> _queueSave() {
    final id = _campaignId;
    if (id == null) return Future<bool>.value(false);
    late final GameSaveRecord game;
    try {
      game = GameSaveRecord(
        StoryRuntimeSnapshotCodec().encodeJson(_engine.createSnapshot()),
        List<String>.unmodifiable(_sessionDecisions),
        _progress,
        _rulesVersion,
      );
    } catch (error) {
      _saveError(error);
      return Future<bool>.value(false);
    }
    final scene = _engine.currentEvent?.presentation?.title?.value
        ?? 'История завершена';
    // Enqueue in CampaignStore synchronously, before navigation can request
    // all(). The store's shared _writeFence guarantees write order across
    // pages. Delaying this call in _pendingWrite.then would leave a gap:
    // HomePage could list saves before the last choice was even queued.
    _pendingWrite = _campaigns.write(id, game, sceneTitle: scene).then<bool>(
      (_) {
        if (mounted && id == _campaignId) {
          setState(() => _hasSave = true);
        }
        return true;
      },
      onError: (Object error) {
        _saveError(error);
        return false;
      },
    );
    return _pendingWrite;
  }

  void _saveError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Автосохранение не удалось: $error')),
      );
    }
  }

  void _choose(StoryChoiceId id) {
    if (_saveBusy || _restoreBusy || _restoreFailed) return;
    // Validate at the action boundary, not only in the disabled-button UI.
    if (_rulesVersion >= 1 && _progress.choiceLockReason(id.value) != null) {
      return;
    }
    final event = _engine.currentEvent;
    final available = _engine.availableChoices
        .where((choice) => choice.id == id);
    if (available.isEmpty) return; // Ignore a stale/double tap.
    final label = available.first.presentation?.text.value ?? id.value;
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
    _queueSave();
  }

  Future<void> _save() async {
    if (_saveBusy || _restoreBusy || _restoreFailed) return;
    setState(() => _saveBusy = true);
    final ok = await _queueSave();
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Прогресс сохранён на устройстве')),
        );
      }
      setState(() => _saveBusy = false);
    }
  }

  Future<void> _restore() async {
    if (_saveBusy || _restoreBusy) return;
    setState(() => _restoreBusy = true);
    try {
      await _pendingWrite;
      String? id = _campaignId;
      if (id == null) {
        final available = await _campaigns.all();
        if (available.isEmpty) throw StateError('Нет сохранённых прохождений');
        id = available.first.id;
      }
      final saved = await _campaigns.read(id);
      if (saved == null) throw StateError('Сохранение не найдено');
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
        _campaignId = id;
        _hasSave = true;
        _restoreFailed = false;
        _restoreFailureText = null;
        _sessionDecisions
          ..clear()
          ..addAll(saved.journal);
      });
      await _campaigns.markActive(id);
    } catch (error) {
      if (!mounted) return;
      // Never fall back to an empty writable new game for a broken save.
      // The original bytes stay in storage for recovery or explicit deletion.
      setState(() {
        _restoreFailed = true;
        _restoreFailureText = error.toString();
      });
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
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GameInfoSheet(
        panel: panel,
        currentScene: event?.presentation?.title?.value ?? _progress.endingTitle,
        journalEntries: List.unmodifiable(_sessionDecisions),
        progress: _progress,
      ),
    );
  }

  void _restart() {
    if (_saveBusy || _restoreBusy || _restoreFailed) return;
    setState(() {
      // A fresh campaign never destroys the completed one.
      _campaignId = CampaignStore.newId();
      _hasSave = false;
      _sessionDecisions.clear();
      _progress = const GameProgress();
      _rulesVersion = 1;
      _engine = StoryEngine(project: _project)..start();
    });
    _queueSave();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoreFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Сохранение не удалось открыть')),
        body: SafeArea(child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_amber_outlined, size: 48),
              const SizedBox(height: 16),
              const Text('Прохождение не изменено. Загрузка остановлена, '
                  'чтобы не перезаписать ваши данные.'),
              if (_restoreFailureText != null) ...[
                const SizedBox(height: 12),
                SelectableText(_restoreFailureText!),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _restoreBusy ? null : () {
                  setState(() => _restoreFailed = false);
                  _restore();
                },
                child: const Text('Повторить загрузку'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Вернуться к прохождениям'),
              ),
            ]),
          ),
        ))),
      );
    }
    if (_restoreBusy) {
      return Scaffold(
        appBar: AppBar(title: const Text('Загрузка прохождения')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final event = _engine.currentEvent;
    final done = _engine.status == StoryEngineStatus.terminated;
    return ReaderChromeKeyboard(
      mode: _chrome,
      onChange: _changeChrome,
      child: Scaffold(
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
                  done ? _progress.endingTitle :
                      (event?.presentation?.title?.value ?? 'История'),
                  style: TextStyle(color: _reading.foreground,
                    fontSize: _reading.fontSize + 7, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Text(
                  done ? _progress.endingDescription :
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
                if (done) ...[
                  Text('Ваш результат сохранён. '
                      'Другие прохождения доступны из главного меню.',
                    style: TextStyle(color: _reading.foreground,
                      fontSize: _reading.fontSize * 0.85)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _restart,
                        child: const Text('Новая история'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _reading.foreground),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('В главное меню'),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 36),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _reading.foreground),
                      onPressed: _saveBusy || _restoreBusy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Сохранить'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _reading.foreground),
                      onPressed: _hasSave && !_saveBusy && !_restoreBusy
                          ? _restore : null,
                      icon: const Icon(Icons.restore),
                      label: const Text('Восстановить'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Демо RPG • Автосохранение • Независимые прохождения',
                  style: TextStyle(color: _reading.foreground, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    ));
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
                style: FilledButton.styleFrom(
                  foregroundColor: foreground,
                  backgroundColor: foreground.withValues(alpha: 0.10),
                  disabledForegroundColor: foreground.withValues(alpha: 0.72),
                  disabledBackgroundColor: foreground.withValues(alpha: 0.06),
                  side: BorderSide(
                    color: foreground.withValues(alpha: 0.30),
                  ),
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
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
