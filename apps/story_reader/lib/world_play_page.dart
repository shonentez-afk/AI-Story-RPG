import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'free_text_action_panel.dart';
import 'game_panels.dart';
import 'reader_chrome.dart';
import 'reading_preferences.dart';
import 'reading_settings_sheet.dart';
import 'world_library_gateway.dart';

/// Real RPG screen for a verified BookWorld; never mutates local game state
/// before the SQLite transaction has committed on a worker isolate.
class WorldPlayPage extends StatefulWidget {
  const WorldPlayPage({
    super.key, required this.gateway, required this.campaignId,
  });

  final WorldLibraryGateway gateway;
  final String campaignId;

  @override
  State<WorldPlayPage> createState() => _WorldPlayPageState();
}

class _WorldPlayPageState extends State<WorldPlayPage> {
  WorldGameView? _view;
  bool _loading = true;
  bool _refreshing = false;
  bool _choosing = false;
  String? _errorText;
  final ReadingSettingsStore _settingsStore = ReadingSettingsStore();
  ReadingPreferences _reading = const ReadingPreferences();
  ReaderChromeMode _chrome = ReaderChromeMode.normal;
  bool _peekControls = false;
  final ScrollController _sceneScroll = ScrollController();

  // Reader settings are UI-only. They never change the event log or SQLite.
  Future<void> _loadReading() async {
    try {
      final settings = await _settingsStore.load();
      if (mounted) setState(() => _reading = settings);
    } catch (_) {
      // Offline play remains usable when preferences are unavailable.
    }
  }

  Future<void> _saveReading(ReadingPreferences settings) async {
    try {
      await _settingsStore.save(settings);
    } catch (_) {
      // A missing platform preferences service must not stop gameplay.
    }
  }

  void _changeReading(ReadingPreferences settings) {
    setState(() => _reading = settings);
    unawaited(_saveReading(settings));
  }

  void _showReadingSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReadingSettingsSheet(
        preferences: _reading,
        onChanged: _changeReading,
      ),
    );
  }

  void _changeChrome(ReaderChromeMode next) {
    if (_chrome == next && !_peekControls) return;
    setState(() {
      _chrome = next;
      _peekControls = false;
    });
  }

  void _tapCanvas() {
    if (_chrome != ReaderChromeMode.fullscreen || _view == null) return;
    setState(() => _peekControls = !_peekControls);
  }

  KeyEventResult _handleReaderKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || _view == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    // F11 switches reader chrome, not the native OS window state.
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      _changeChrome(_chrome == ReaderChromeMode.fullscreen
          ? ReaderChromeMode.normal : ReaderChromeMode.fullscreen);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _chrome != ReaderChromeMode.normal) {
      _changeChrome(ReaderChromeMode.normal);
      return KeyEventResult.handled;
    }
    // Tab/Shift+Tab/Enter retain Flutter's built-in focus and activation.
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _reload();
    unawaited(_loadReading());
  }

  @override
  void dispose() {
    _sceneScroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_choosing || _refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    try {
      final view = await widget.gateway.load(widget.campaignId);
      if (mounted) setState(() {
        _view = view;
        _errorText = null;
      });
    } catch (error) {
      if (mounted) setState(() {
        _view = null;
        _errorText = 'Сохранение не удалось открыть: $error';
      });
    } finally {
      if (mounted) setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  static String _newActionId() {
    final random = Random.secure();
    return 'ui_' + List.generate(12, (_) => random.nextInt(256))
        .map((part) => part.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _reason(String? code) {
    if (code == null) return 'Действие недоступно';
    if (code.startsWith('condition_not_met:')) {
      return switch (code.split(':').last) {
        'has_item' => 'Для выбора необходим предмет',
        'knows_fact' => 'Сначала требуется узнать новые сведения',
        'stat_at_least' => 'Не хватает характеристики персонажа',
        'tick_at_least' => 'Ещё не наступило время события',
        _ => 'Пока не выполнены сюжетные условия',
      };
    }
    return switch (code) {
      'stale_revision' => 'История обновилась, повторите действие',
      'terminal_scene' => 'История уже завершена',
      _ => 'Выбор пока недоступен',
    };
  }

  Future<void> _choose(WorldChoiceView choice) async {
    final previous = _view;
    if (previous == null || _choosing ||
        !choice.enabled || previous.isTerminal) return;
    setState(() => _choosing = true);
    try {
      final result = await widget.gateway.choose(
        widget.campaignId,
        actionId: _newActionId(),
        choiceId: choice.id,
        expectedRevision: previous.revision,
      );
      if (!mounted) return;
      setState(() => _view = result.view);
      if (!result.applied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_reason(result.reason))),
        );
      }
    } catch (error) {
      if (mounted) {
        // Never update the UI optimistically after a failed write.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ход не сохранён. Повторите попытку: $error'),
        ));
      }
    } finally {
      if (mounted) {
        // A confirmed or rejected action must leave the beginning of the
        // current scene, including turn count, visible. Chrome toggles do
        // not reset scrolling; only actual choice attempts do.
        if (_sceneScroll.hasClients) _sceneScroll.jumpTo(0);
        setState(() => _choosing = false);
      }
    }
  }

  void _openPanel(GamePanel panel) {
    final view = _view;
    if (view == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WorldInfoSheet(panel: panel, view: view),
    );
  }


  @override
  Widget build(BuildContext context) {
    final view = _view;
    final prefs = _reading;
    final chrome = view == null ? ReaderChromeMode.normal : _chrome;
    final ink = prefs.foreground;
    final readerText = TextStyle(
      color: ink, fontSize: prefs.fontSize, height: prefs.lineHeight,
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _handleReaderKey,
      child: Scaffold(
        backgroundColor: prefs.background,
        appBar: !chrome.showTopBar ? null : AppBar(
          backgroundColor: prefs.background,
          foregroundColor: ink,
          title: Text(view?.worldTitle ?? 'Игровой мир',
              overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Настройки чтения',
              onPressed: _showReadingSettings,
              icon: const Icon(Icons.text_fields),
            ),
            IconButton(
              tooltip: 'Обновить сохранённое состояние',
              onPressed: _choosing || _loading || _refreshing ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<ReaderChromeMode>(
              tooltip: 'Режим экрана',
              icon: const Icon(Icons.tune_outlined),
              onSelected: _changeChrome,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: ReaderChromeMode.normal,
                  child: Text('Обычный режим'),
                ),
                PopupMenuItem(
                  value: ReaderChromeMode.reading,
                  child: Text('Режим чтения'),
                ),
                PopupMenuItem(
                  value: ReaderChromeMode.fullscreen,
                  child: Text('Полный экран'),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: view == null ? null : ReaderChromeButton(
          mode: chrome,
          background: ink,
          foreground: prefs.background,
          onChange: _changeChrome,
        ),
        bottomNavigationBar: view == null ||
                !(chrome.showGameBar || _peekControls)
            ? null
            : ColoredBox(
                color: prefs.background,
                child: GameQuickBar(onOpen: _openPanel, color: ink),
              ),
        body: ColoredBox(
          color: prefs.background,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: chrome == ReaderChromeMode.fullscreen
                ? _tapCanvas : null,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _loading || _refreshing
                      ? const Center(child: CircularProgressIndicator())
                      : view == null
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.warning_amber_outlined,
                                      size: 36),
                                  const SizedBox(height: 12),
                                  Text(_errorText ??
                                      'Не удалось открыть прохождение',
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: _reload,
                                    child: const Text('Повторить загрузку'),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              key: const ValueKey('world-scene-scroll'),
                              controller: _sceneScroll,
                              padding: EdgeInsets.fromLTRB(
                                  prefs.horizontalPadding, 14,
                                  prefs.horizontalPadding, 112),
                              children: [
                                if (!chrome.showTopBar) ...[
                                  Text(view.worldTitle,
                                      style: readerText.copyWith(
                                        fontSize: prefs.fontSize + 6,
                                        fontWeight: FontWeight.bold,
                                      )),
                                  const SizedBox(height: 12),
                                ],
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  Chip(
                                    label: Text('Классический режим',
                                        style: TextStyle(color: ink)),
                                    backgroundColor: prefs.background,
                                    side: BorderSide(
                                        color: ink.withValues(alpha: 0.25)),
                                  ),
                                  Chip(
                                    label: Text('Ходов: ${view.revision}',
                                        style: TextStyle(color: ink)),
                                    backgroundColor: prefs.background,
                                    side: BorderSide(
                                        color: ink.withValues(alpha: 0.25)),
                                  ),
                                ]),
                                const SizedBox(height: 18),
                                Text(view.sceneText, style: readerText),
                                const SizedBox(height: 24),
                                if (view.isTerminal) ...[
                                  Text('История завершена',
                                      style: readerText.copyWith(
                                        fontSize: prefs.fontSize + 4,
                                        fontWeight: FontWeight.bold,
                                      )),
                                  const SizedBox(height: 8),
                                  Text('Решения и состояние сохранены '
                                      'в этой кампании.', style: readerText),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('К прохождениям'),
                                  ),
                                ] else ...[
                                  Text('Ваш выбор',
                                      style: readerText.copyWith(
                                        fontWeight: FontWeight.w600,
                                      )),
                                  const SizedBox(height: 12),
                                  for (final choice in view.choices) ...[
                                    Semantics(
                                      label: choice.enabled
                                          ? choice.label
                                          : '${choice.label}. '
                                              '${_reason(choice.lockReason)}',
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: FilledButton(
                                          key: ValueKey(
                                              'world-choice-${choice.id}'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: ink,
                                            foregroundColor: prefs.background,
                                            disabledBackgroundColor:
                                                ink.withValues(alpha: 0.14),
                                            disabledForegroundColor:
                                                ink.withValues(alpha: 0.72),
                                          ),
                                          onPressed: _choosing ||
                                                  !choice.enabled
                                              ? null
                                              : () => _choose(choice),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 11),
                                            child: Text(choice.label,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: prefs.fontSize * 0.9,
                                                )),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!choice.enabled)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 8),
                                        child: Text(
                                          _reason(choice.lockReason),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: ink,
                                            fontSize: prefs.fontSize * 0.82,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                  ],
                                  // Uses the existing gateway/SQLite campaign;
                                  // does not replace the classic choice buttons.
                                  // ExpansionTile builds a ListTile internally; it
                                  // also needs its own Material painting surface
                                  // above the opaque reading palette ColoredBox.
                                  Material(
                                    color: Colors.transparent,
                                    child: ExpansionTile(
                                      key: ValueKey('world-free-text-' +
                                          view.campaignId + '-' +
                                          view.revision.toString()),
                                      title: const Text(
                                          'Свободное действие'),
                                      subtitle: const Text(
                                          'Офлайн или с помощью ИИ — с подтверждением'),
                                      initiallyExpanded: false,
                                      children: [
                                        FreeTextActionPanel(
                                          campaignId: widget.campaignId,
                                          gateway: widget.gateway,
                                          onBusyChanged: (busy) {
                                            if (mounted) {
                                              setState(() => _choosing = busy);
                                            }
                                          },
                                          onCommitted: (result) {
                                            if (!mounted) return;
                                            setState(() {
                                              _view = result.view;
                                              _choosing = false;
                                              _errorText = null;
                                            });
                                            if (_sceneScroll.hasClients) {
                                              _sceneScroll.jumpTo(0);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_choosing) const LinearProgressIndicator(
                                    key: ValueKey('world-saving'),
                                  ),
                                ],
                              ],
                            ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorldInfoSheet extends StatelessWidget {
  const _WorldInfoSheet({required this.panel, required this.view});

  // Only translate known stat identifiers; authored unknown ones stay intact.
  static String _statLabel(String id) => switch (id) {
    'insight' => 'Наблюдательность',
    'courage' => 'Смелость',
    'strength' => 'Сила',
    'intelligence' => 'Интеллект',
    'charisma' => 'Харизма',
    _ => id,
  };
  final GamePanel panel;
  final WorldGameView view;

  @override
  Widget build(BuildContext context) {
    final heading = switch (panel) {
      GamePanel.character => 'Герой',
      GamePanel.inventory => 'Предметы',
      GamePanel.journal => 'Журнал',
    };
    final entries = switch (panel) {
      GamePanel.character => [
        if (view.heroName != null) 'Герой: ' + view.heroName!,
        if (view.heroDescription != null) view.heroDescription!,
        if (view.stats.isEmpty) 'Характеристики не заданы',
        for (final stat in view.stats.entries)
          (view.statNames[stat.key] ?? _statLabel(stat.key)) +
              ': ' + stat.value.toString(),
        'Игровое время: ' + view.tick.toString(),
        if (view.knownFacts.isNotEmpty)
          'Открытые сведения: ' +
              view.knownFacts
                  .map((id) => view.factNames[id] ?? id).join(', '),
        if (view.knownFacts.isEmpty) 'Открыто сведений: 0',
      ],
      GamePanel.inventory => view.inventory.isEmpty
          ? <String>['Предметов пока нет']
          : [
              for (final id in view.inventory)
                (view.itemNames[id] ?? id) +
                    (view.itemDescriptions[id] == null
                        ? ''
                        : ' — ' + view.itemDescriptions[id]!),
            ],
      GamePanel.journal => view.journal.isEmpty
          ? <String>['Решений пока нет']
          : [
              for (final entry in view.journal)
                entry.sequence.toString() + '. ' +
                    (entry.sceneTitle == null
                        ? ''
                        : entry.sceneTitle! + ': ') +
                    entry.choiceLabel +
                    (entry.changes.isEmpty
                        ? ''
                        : '\n' + entry.changes
                            .map((change) => '• ' + change).join('\n')),
            ],
    };
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(heading,
                    style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 8),
              Flexible(child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (_, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Text(entries[index]),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
