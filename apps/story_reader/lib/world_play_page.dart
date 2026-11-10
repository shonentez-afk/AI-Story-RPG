import 'dart:async';
import 'dart:math';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'free_text_action_panel.dart';
import 'game_panels.dart';
import 'local_dialogue_portraits.dart';
import 'reader_chrome.dart';
import 'scene_dialogue_stage.dart';
import 'reading_preferences.dart';
import 'reading_settings_sheet.dart';
import 'world_library_gateway.dart';
import 'world_ui_presenter.dart';

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
  bool _dialogueFinished = false;
  final LocalDialoguePortraitStore _portraitStore =
      const LocalDialoguePortraitStore();
  final Map<String, Uint8List> _portraitBytes = {};
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

  // The view carries the importer-verified, replay-gated actor mapping.
  // Never infer a portrait owner from the name in a reviewed NPC scene.
  String? _portraitAddress(WorldGameView view, String speaker) =>
      view.portraitStorageKeyFor(speaker);

  Future<void> _loadPortraits(WorldGameView view) async {
    final script = view.sceneDialogueTurns == null
        ? SceneDialogueScript.fromSceneText(view.sceneText)
        : SceneDialogueScript.fromSignedTurns(view.sceneDialogueTurns!);
    final speakers = script?.turns.map((turn) => turn.speaker)
        .whereType<String>().toSet() ?? <String>{};
    final loaded = <String, Uint8List>{};
    for (final speaker in speakers) {
      final address = _portraitAddress(view, speaker);
      if (address == null) continue;
      var bytes = await _portraitStore.read(
          campaignId: widget.campaignId, speaker: address);
      if (bytes == null && address != speaker &&
          !view.sceneSpeakerIdentityReviewed) {
        // Only old v1/v2 scenes may read portrait PNGs by a display name.
        // Rich reviewed NPC IDs must never fall back to another actor's PNG.
        bytes = await _portraitStore.read(
            campaignId: widget.campaignId, speaker: speaker);
      }
      if (bytes != null) loaded[speaker] = bytes;
    }
    if (!mounted || _view?.sceneId != view.sceneId ||
        _view?.revision != view.revision) return;
    setState(() { _portraitBytes..clear()..addAll(loaded); });
  }

  Future<void> _pickPortrait(String speaker) async {
    final current = _view;
    if (current == null || speaker.trim().isEmpty) return;
    final address = _portraitAddress(current, speaker);
    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Портрет недоступен: реплика ещё не открыта, '
            'личность не подтверждена или имена совпадают.')));
      return;
    }
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: false, withData: true,
      );
      if (!mounted || selected == null) return;
      final bytes = selected.files.single.bytes;
      if (bytes == null) {
        throw const FormatException(
            'Не удалось прочитать изображение. Выберите локальный PNG.');
      }
      await _portraitStore.save(
        campaignId: widget.campaignId, speaker: address, png: bytes);
      if (!mounted) return;
      setState(() => _portraitBytes[speaker] = bytes);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Портрет для «' + speaker +
            '» сохранён только на этом устройстве.'),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Не удалось загрузить портрет: $error'),
      ));
    }
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
        final previous = _view;
        _view = view;
        if (previous == null || previous.sceneId != view.sceneId ||
            previous.revision != view.revision) {
          _dialogueFinished = false;
        }
        _errorText = null;
      });
      if (mounted) unawaited(_loadPortraits(view));
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
        'npc_unavailable' => 'Собеседник сейчас недоступен',
        'npc_memory' => 'Сначала требуется подтверждённая встреча',
        'npc_trust' => 'Пока недостаточно доверия для этого разговора',
        'npc_item_owner' => 'Предмет должен быть у нужного персонажа',
        'npc_item_custody' => 'Сначала требуется подтверждённая передача предмета',
        'npc_life_transition' => 'Состояние персонажа не позволяет этот выбор',
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
      setState(() {
        _view = result.view;
        if (result.applied && (result.view.revision != previous.revision ||
            result.view.sceneId != previous.sceneId)) {
          _dialogueFinished = false;
        }
      });
      if (result.applied) unawaited(_loadPortraits(result.view));
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
    // Prefer v3 importer-verified structured turns. Older v1/v2 worlds
    // retain their original signed-scene-text parsing without migration.
    final dialogue = view == null ? null :
        (view.sceneDialogueTurns == null
            ? SceneDialogueScript.fromSceneText(view.sceneText)
            : SceneDialogueScript.fromSignedTurns(
                view.sceneDialogueTurns!));
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
                child: GameQuickBar(
                  onOpen: _openPanel, color: ink,
                  showNpc: view.npcRelations.isNotEmpty,
                ),
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
                                // Show only the currently reached,
                                // source-reviewed scene name. The rest of
                                // sceneNames may describe future chapters.
                                if (view.sceneNames[view.sceneId] != null &&
                                    view.sceneNames[view.sceneId]!
                                        .trim().isNotEmpty) ...[
                                  Text(view.sceneNames[view.sceneId]!,
                                      key: const ValueKey(
                                          'world-current-scene-title'),
                                      style: readerText.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: prefs.fontSize + 3,
                                      )),
                                  const SizedBox(height: 10),
                                ],
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  Chip(
                                    label: Text(view.activePlotMode == 'ALTER_FATE' &&
                                            view.sourceLiteralCanon
                                        ? 'ALTER_FATE · альтернативная история'
                                        : view.sourceLiteralCanon
                                            ? 'CANON · текст книги + свободный ИИ'
                                        : dialogue == null ? 'Классический режим' : 'Диалог',
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
                                  if (view.sceneSource != null)
                                    Chip(
                                      key: const ValueKey('world-book-origin'),
                                      label: Text(
                                        (view.sourceLiteralCanon &&
                                                view.activePlotMode == 'ALTER_FATE'
                                            ? 'Альтернативный сюжет · от главы '
                                            : view.sourceLiteralCanon
                                                ? 'CANON · глава '
                                            : view.sceneSource!.isSourcePassage
                                                ? 'По книге · глава '
                                                : 'Альтернативный сюжет · глава ') +
                                            '${view.sceneSource!.chapterNumber}/'
                                            '${view.sceneSource!.chapterCount}',
                                        style: TextStyle(color: ink),
                                      ),
                                      backgroundColor: prefs.background,
                                      side: BorderSide(
                                          color: ink.withValues(alpha: 0.25)),
                                    ),
                                ]),
                                const SizedBox(height: 18),
                                if (view.sourceLiteralCanon &&
                                    view.activePlotMode == 'ALTER_FATE') ...[
                                  Card(
                                    key: const ValueKey('world-alternate-continuity'),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Альтернативная история',
                                              style: Theme.of(context)
                                                  .textTheme.titleMedium),
                                          const SizedBox(height: 4),
                                          for (final line in
                                              WorldUiPresenter.alternatePlot(view))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 3),
                                              child: Text(line),
                                            ),
                                          TextButton(
                                            onPressed: () =>
                                                _openPanel(GamePanel.journal),
                                            child: const Text('Открыть журнал'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                if (dialogue == null)
                                  Text(view.sceneText, style: readerText)
                                else
                                  DialogueStage(
                                    key: ValueKey('world-dialogue-' +
                                        view.campaignId + '-' + view.sceneId +
                                        '-' + view.revision.toString()),
                                    script: dialogue,
                                    campaignId: view.campaignId,
                                    sceneId: view.sceneId,
                                    revision: view.revision,
                                    textColor: ink,
                                    pageColor: prefs.background,
                                    fontSize: prefs.fontSize,
                                    lineHeight: prefs.lineHeight,
                                    portraitFor: (speaker) {
                                      final bytes = _portraitBytes[speaker];
                                      return bytes == null ? null :
                                          MemoryImage(bytes);
                                    },
                                    onAddPortrait: (speaker) =>
                                        unawaited(_pickPortrait(speaker)),
                                    canAddPortrait: (speaker) =>
                                        _portraitAddress(view, speaker) != null,
                                    onFinished: (finished) {
                                      if (!mounted || _view?.sceneId != view.sceneId ||
                                          _view?.revision != view.revision ||
                                          _dialogueFinished == finished) return;
                                      setState(() => _dialogueFinished = finished);
                                    },
                                  ),
                                // Only a COMMITTED and replay-verified latest
                                // free action is displayed beside the book.
                                // It is explicitly separated from the
                                // immutable literal CANON scene text.
                                if (view.sourceLiteralCanon &&
                                    view.activePlotMode == 'CANON' &&
                                    view.journal.isNotEmpty &&
                                    view.journal.last.sequence == view.revision &&
                                    view.journal.last.choiceLabel.startsWith(
                                        'Свободное действие (не текст книги): ')) ...[
                                  const SizedBox(height: 14),
                                  Card(
                                    key: const ValueKey('world-last-dynamic-event'),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Игровая вставка ИИ · не канон книги',
                                              style: Theme.of(context).textTheme.titleSmall),
                                          const SizedBox(height: 6),
                                          Text(view.journal.last.choiceLabel,
                                              style: Theme.of(context).textTheme.bodyMedium),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                if (dialogue != null && !_dialogueFinished) ...[
                                  Text('Прочитайте диалог или выберите «Пропустить разговор», '
                                      'чтобы открыть решения героя.',
                                      key: const ValueKey('world-dialogue-choice-gate'),
                                      style: readerText.copyWith(
                                        fontSize: prefs.fontSize * 0.84,
                                      )),
                                ] else if (view.isTerminal) ...[
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
                                      subtitle: Text(view.freeformAvailable
                                          ? 'Новые действия ИИ с настоящими последствиями'
                                          : 'Офлайн или ИИ: только доступные ходы'),
                                      initiallyExpanded: false,
                                      children: [
                                        FreeTextActionPanel(
                                          campaignId: widget.campaignId,
                                          dynamicAvailable: view.freeformAvailable,
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
                                              _dialogueFinished = false;
                                              _choosing = false;
                                              _errorText = null;
                                            });
                                            unawaited(_loadPortraits(result.view));
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

  // The v3 runtime still uses the actor key 'player'. Only a user-reviewed
  // source-linked NPC role may set a permanent player_is_npc_<id> flag.
  // Never invent one from the display name, dialogue or knownFacts.
  static String _memoryKindName(String kind) => switch (kind) {
    'witnessed' => 'Наблюдал',
    'promiseReceived' => 'Принял обещание',
    'promiseBroken' => 'Нарушенное обещание',
    'promiseFulfilled' => 'Исполненное обещание',
    'autonomousDecision' => 'Самостоятельное решение',
    'warned' => 'Получил предупреждение',
    'helped' => 'Получил помощь',
    'betrayed' => 'Пережил предательство',
    'rumorHeard' => 'Услышал сведения',
    _ => 'Подтверждённые события',
  };


  @override
  Widget build(BuildContext context) {
    // The ledger may contain source-reviewed custodians not yet met in
    // this branch. Only replay-proven NPC encounters may disclose names
    // or their owned items to the player.
    final encounteredNames = <String, String>{
      for (final npc in view.npcRelations) npc.actorId: npc.displayName,
    };
    final visibleNpcItems = view.npcItemOwners.entries
        .where((item) => encounteredNames.containsKey(item.value)).toList();
    final heading = switch (panel) {
      GamePanel.character => 'Герой',
      GamePanel.inventory => 'Предметы',
      GamePanel.journal => 'Журнал',
      GamePanel.npc => 'Персонажи',
    };
    final entries = switch (panel) {
      GamePanel.character => [
        if (view.heroName != null) 'Герой: ' + view.heroName!,
        if (view.heroDescription != null) view.heroDescription!,
        if (view.heroSourceCharacterId != null)
          'Роль: проверенный книжный персонаж',
        if (view.sourceReviewedHeroStart)
          'Стартовые предметы и сведения подтверждены цитатами первой главы.',
        if (view.heroSourceCharacterId != null &&
            !view.sourceReviewedHeroStart)
          'Знания и секреты NPC не присваиваются автоматически.',
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
        if (view.journal.isNotEmpty) 'Последние изменения героя и мира:',
        ...WorldUiPresenter.heroRecentChanges(view),
        if (view.npcRelations.isNotEmpty)
          'Только встреченные персонажи:',
        for (final npc in view.npcRelations)
          npc.displayName + ': ' +
              switch (npc.lifeState) {
                'present' => 'доступен',
                'absent' => 'отсутствует',
                'dead' => 'погиб',
                _ => 'состояние не подтверждено',
              },
      ],
      GamePanel.inventory => [
        if (view.inventory.isEmpty)
          visibleNpcItems.isEmpty
              ? 'Предметов пока нет' : 'У героя сейчас нет предметов',
        if (view.inventory.isNotEmpty) 'У героя:',
        for (final id in view.inventory)
          (view.itemNames[id] ?? id) +
              (view.itemDescriptions[id] == null
                  ? '' : ' — ' + view.itemDescriptions[id]!),
        if (visibleNpcItems.isNotEmpty)
          'У встреченных персонажей (подтверждено событиями):',
        for (final entry in visibleNpcItems)
          (view.itemNames[entry.key] ?? entry.key) + ' — у ' +
              encounteredNames[entry.value]!,
        if (WorldUiPresenter.availableItemActions(view).isNotEmpty)
          'Сейчас доступны действия с имеющимися предметами:',
        ...WorldUiPresenter.availableItemActions(view),
        'Предметы и владельцы — только из подтверждённых ходов. '
            'Передача или применение выполняются через разрешённый '
            'выбор либо проверенное свободное действие.',
      ],
      GamePanel.journal => [
        if (view.journal.isEmpty) 'Решений пока нет',
        if (view.activePlotMode == 'ALTER_FATE') ...[
          'Альтернативная ветка (вымысел, не текст книги):',
          ...WorldUiPresenter.alternatePlot(view),
        ],
        for (final entry in view.journal)
          entry.sequence.toString() + '. ' +
              (entry.sceneTitle == null ? '' : entry.sceneTitle! + ': ') +
              entry.choiceLabel +
              (entry.changes.isEmpty ? '' :
                  '\n' + entry.changes.map((change) => '• ' + change).join('\n')),
        'Журнал содержит только подтверждённые решения и последствия '
            'из SQLite. Свободная фраза не заменяет сохранённый выбор.',
      ],
      GamePanel.npc => const <String>[],
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
              // Everything below the title scrolls. An expanded role ID
              // or 200% text may never push the last journal row off-screen.
              Flexible(child: panel == GamePanel.npc
                  ? ListView(
                      key: const Key('world-npc-relation-list'),
                      shrinkWrap: true,
                      children: [
                        const Text('Только встреченные персонажи. '
                            'Память и отношение вычислены из сохранённых '
                            'решений, а не из реплик ИИ или текста книги.'),
                        const SizedBox(height: 8),
                        for (final npc in view.npcRelations)
                          Card(
                            key: Key('world-npc-' + npc.actorId),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(npc.displayName,
                                      style: Theme.of(context)
                                          .textTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text('Отношение NPC к герою: ' +
                                      (npc.directedScore > 0 ? '+' : '') +
                                      npc.directedScore.toString()),
                                  Text('Запомненных событий: ' +
                                      npc.memoryCount.toString()),
                                  if (npc.lifeState != null)
                                    Text('Состояние: ' +
                                        switch (npc.lifeState) {
                                          'present' => 'доступен',
                                          'absent' => 'отсутствует',
                                          'dead' => 'погиб',
                                          _ => 'неизвестно',
                                        }),
                                  if (npc.currentGoal != null)
                                    Text('Текущая цель: ' +
                                        WorldUiPresenter.record(npc.currentGoal!)),
                                  if (npc.openPromiseIds.isNotEmpty) ...[
                                    const Text('Открытые обещания:'),
                                    for (final id in npc.openPromiseIds)
                                      Text('• ' + WorldUiPresenter.record(id)),
                                  ],
                                  if (npc.autonomousDecisionIds.isNotEmpty) ...[
                                    const Text('Самостоятельные решения:'),
                                    for (final id in npc.autonomousDecisionIds)
                                      Text('• ' + WorldUiPresenter.record(id)),
                                  ],
                                  for (final kind in npc.memoryKinds.entries)
                                    Text(_memoryKindName(kind.key) + ': ' +
                                        kind.value.toString()),
                                  for (final item in visibleNpcItems.where(
                                      (entry) => entry.value == npc.actorId))
                                    Text('Предмет у персонажа: ' +
                                        (view.itemNames[item.key] ?? item.key)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : ListView.builder(
                      key: Key(panel == GamePanel.journal
                          ? 'world-journal-scroll' : 'world-info-scroll'),
                      shrinkWrap: true,
                      itemCount: entries.length +
                          (panel == GamePanel.character &&
                                  view.heroSourceCharacterId != null ? 1 : 0),
                      itemBuilder: (_, index) {
                        final diagnosis = panel == GamePanel.character &&
                            view.heroSourceCharacterId != null;
                        if (diagnosis && index == 1) {
                          return ExpansionTile(
                            key: const Key('world-hero-diagnostics'),
                            title: const Text('Техническая диагностика роли'),
                            children: [
                              SelectableText('Постоянный ID: '
                                  '${view.heroSourceCharacterId!}'),
                            ],
                          );
                        }
                        final row = diagnosis && index > 1 ? index - 1 : index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Text(entries[row]),
                        );
                      },
                    )),
            ],
          ),
        ),
      ),
    );
  }
}
