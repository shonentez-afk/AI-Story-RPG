import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The FIRST dialogue UI contract is intentionally presentation-only.
///
/// A line is dialogue only when the authored scene explicitly names the
/// speaker and quotes their words. Bare em dashes, unattributed quotations
/// and prose must NEVER be assigned to an invented character.
class SceneDialogueTurn {
  const SceneDialogueTurn({required this.text, this.speaker});
  final String text;
  final String? speaker;
  bool get isNarration => speaker == null;
}

class SceneDialogueScript {
  SceneDialogueScript._(List<SceneDialogueTurn> turns)
      : turns = List.unmodifiable(turns);

  final List<SceneDialogueTurn> turns;

  // Script is a UI projection of the actual signed scene text, not a new
  // world-state, NPC identity, proof of CANON or executable mini-language.
  static final RegExp _named = RegExp(
    r'^([А-ЯЁA-Z][А-Яа-яЁёA-Za-z0-9 .-]{0,49}):[ \t]*(«[^»\n]{1,1200}»|"[^"\n]{1,1200}"|—[ \t]*[^\n]{1,1200})$',
    unicode: true,
  );
  static const maxTurns = 64;

  static SceneDialogueScript? fromSceneText(String text) {
    if (text.trim().isEmpty || text.length > 50000) return null;
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final beats = <SceneDialogueTurn>[];
    final speakers = <String>{};
    var spoken = 0;
    for (final source in lines) {
      final line = source.trim();
      if (line.isEmpty) continue;
      final match = _named.firstMatch(line);
      if (match == null) {
        // Do not silently drop narrator prose between two dialogue turns.
        if (line.length > 5000) return null;
        beats.add(SceneDialogueTurn(text: line));
      } else {
        final speaker = match.group(1)!.trim();
        var speech = match.group(2)!.trim();
        if (speaker.isEmpty) return null;
        if (speech.startsWith('«') && speech.endsWith('»') ||
            speech.startsWith('"') && speech.endsWith('"')) {
          speech = speech.substring(1, speech.length - 1).trim();
        } else if (speech.startsWith('—')) {
          speech = speech.substring(1).trim();
        }
        if (speech.isEmpty) return null;
        speakers.add(speaker);
        spoken++;
        beats.add(SceneDialogueTurn(speaker: speaker, text: speech));
      }
      if (beats.length > maxTurns) return null;
    }
    // One speaker, a quote or a paragraph heading is not a conversation.
    if (spoken < 2 || speakers.length < 2) return null;
    return SceneDialogueScript._(beats);
  }
}

/// Device-local reading position; not part of story_core, BookWorld, SQLite
/// journal or the portable game save. Key includes scene AND committed turn
/// revision, so no old progress leaks into another choice branch.
class DialoguePositionStore {
  const DialoguePositionStore();
  static const _prefix = 'asr_dialogue_position_v1_';
  static Future<void> _queue = Future<void>.value();

  String key({
    required String campaign,
    required String scene,
    required int revision,
    required List<SceneDialogueTurn> turns,
  }) {
    final fingerprint = jsonEncode({
      'campaign': campaign, 'scene': scene, 'revision': revision,
      'turns': [
        for (final turn in turns)
          [turn.speaker, turn.text],
      ],
    });
    return _prefix +
        sha256.convert(utf8.encode(fingerprint)).toString().substring(0, 32);
  }

  Future<int> read(String key, int length) async {
    try {
      // Wait for an earlier in-session write before restoring the position.
      await _queue.catchError((Object _) {});
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(key) ?? 0;
      return value >= 0 && value <= length ? value : 0;
    } catch (_) {
      return 0; // UI persistence must not block the game.
    }
  }

  Future<void> save(String key, int value) {
    final previous = _queue;
    final task = previous.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    });
    _queue = task;
    return task;
  }
}

/// Reader-style dialogue stage. Rendering, animations and local position do
/// NOT invoke the gameplay engine; choices remain in WorldPlayPage.
class DialogueStage extends StatefulWidget {
  const DialogueStage({
    super.key,
    required this.script,
    required this.campaignId,
    required this.sceneId,
    required this.revision,
    required this.textColor,
    required this.pageColor,
    required this.fontSize,
    required this.lineHeight,
    required this.onFinished,
    this.portraitFor,
    this.store = const DialoguePositionStore(),
  });

  final SceneDialogueScript script;
  final String campaignId, sceneId;
  final int revision;
  final Color textColor, pageColor;
  final double fontSize, lineHeight;
  final ValueChanged<bool> onFinished;
  final ImageProvider? Function(String speaker)? portraitFor;
  final DialoguePositionStore store;

  @override
  State<DialogueStage> createState() => _DialogueStageState();
}

class _DialogueStageState extends State<DialogueStage> {
  int _position = 0;
  bool _loading = true;
  bool _showHistory = false;
  late final String _positionKey;

  @override
  void initState() {
    super.initState();
    _positionKey = widget.store.key(
      campaign: widget.campaignId, scene: widget.sceneId,
      revision: widget.revision, turns: widget.script.turns,
    );
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final position = await widget.store.read(
        _positionKey, widget.script.turns.length);
    if (!mounted) return;
    setState(() {
      _position = position;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinished(_position >= widget.script.turns.length);
    });
  }

  void _advance() {
    if (_loading || _position >= widget.script.turns.length) return;
    setState(() => _position++);
    unawaited(widget.store.save(_positionKey, _position).catchError((Object _) {}));
    widget.onFinished(_position >= widget.script.turns.length);
  }

  void _skip() {
    if (_loading || _position >= widget.script.turns.length) return;
    setState(() => _position = widget.script.turns.length);
    unawaited(widget.store.save(_positionKey, _position).catchError((Object _) {}));
    widget.onFinished(true);
  }

  Widget _avatar(SceneDialogueTurn turn, Color accent) {
    final portrait = turn.speaker == null
        ? null : widget.portraitFor?.call(turn.speaker!);
    final placeholder = Center(
      child: Icon(turn.isNarration ? Icons.menu_book_outlined
          : Icons.person_outline_rounded, size: 42, color: accent),
    );
    return Semantics(
      label: turn.isNarration
          ? 'Повествование'
          : (portrait == null
              ? 'Портрет не предоставлен: ' + turn.speaker!
              : 'Портрет: ' + turn.speaker!),
      child: Container(
        key: const ValueKey('dialogue-speaker-portrait'),
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: 0.65), width: 2),
          color: accent.withValues(alpha: 0.09),
        ),
        child: ClipOval(child: portrait == null ? placeholder :
          Image(image: portrait, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: LinearProgressIndicator(
        key: ValueKey('dialogue-restoring')));
    }
    final turns = widget.script.turns;
    final finished = _position >= turns.length;
    final index = finished ? turns.length - 1 : _position;
    final current = turns[index];
    final accent = widget.textColor;
    final contrast = Color.alphaBlend(
      widget.textColor.withValues(alpha: 0.055),
      widget.pageColor,
    );
    final name = current.speaker ?? 'Повествование';
    return Semantics(
      container: true,
      label: 'Диалог, реплика ' + (index + 1).toString() +
          ' из ' + turns.length.toString(),
      child: Column(
        key: const ValueKey('dialogue-stage'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero : const Duration(milliseconds: 180),
            child: Container(
              key: ValueKey('dialogue-beat-' + index.toString()),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: contrast,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: accent.withValues(alpha: 0.16)),
              ),
              child: Column(
                children: [
                  _avatar(current, accent),
                  const SizedBox(height: 12),
                  Text(name, key: const ValueKey('dialogue-speaker-name'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: accent, fontSize: widget.fontSize,
                        fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(current.text, key: const ValueKey('dialogue-line'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: widget.textColor,
                        fontSize: widget.fontSize, height: widget.lineHeight)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(
              'Реплика ' + (index + 1).toString() + ' / ' +
                  turns.length.toString(),
              style: TextStyle(color: accent, fontSize: widget.fontSize * 0.75),
            )),
            TextButton.icon(
              key: const ValueKey('dialogue-history-toggle'),
              onPressed: () => setState(() => _showHistory = !_showHistory),
              icon: const Icon(Icons.history_rounded),
              label: Text(_showHistory ? 'Скрыть историю' : 'История'),
            ),
          ]),
          if (_showHistory)
            Container(
              key: const ValueKey('dialogue-history'),
              constraints: const BoxConstraints(maxHeight: 240),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i <= index; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                        (turns[i].speaker ?? 'Повествование') +
                          ': ' + turns[i].text,
                        style: TextStyle(color: accent,
                            fontSize: widget.fontSize * 0.84),
                      ),
                    ),
                ],
              ),
            ),
          if (!finished) ...[
            const SizedBox(height: 6),
            FilledButton.icon(
              key: const ValueKey('dialogue-next'),
              onPressed: _advance,
              icon: const Icon(Icons.chevron_right_rounded),
              label: Text(index == turns.length - 1
                  ? 'К выбору' : 'Следующая реплика'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('dialogue-skip'),
                onPressed: _skip,
                child: const Text('Пропустить разговор'),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Разговор завершён. Можно выбрать действие.',
                key: const ValueKey('dialogue-complete'),
                textAlign: TextAlign.center,
                style: TextStyle(color: accent)),
            ),
        ],
      ),
    );
  }
}
