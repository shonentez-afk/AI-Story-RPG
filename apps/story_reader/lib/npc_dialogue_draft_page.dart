import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'zai_npc_dialogue_draft.dart';
import 'zai_semantic_preview.dart';

/// Authoring-only screen. It is never mounted by a playing campaign and
/// never installs a BookWorld or sends a request without explicit consent.
class NpcDialogueDraftPage extends StatefulWidget {
  const NpcDialogueDraftPage({
    super.key, required this.preview, this.service,
  });

  final NpcDialogueDraftContext preview;
  final ZaiNpcDialogueDraftService? service;

  @override
  State<NpcDialogueDraftPage> createState() => _NpcDialogueDraftPageState();
}

class _NpcDialogueDraftPageState extends State<NpcDialogueDraftPage> {
  late final ZaiNpcDialogueDraftService _service =
      widget.service ?? ZaiNpcDialogueDraftService();
  ZaiPreviewCancellation? _token;
  NpcDialogueCloudDraft? _draft;
  bool _consent = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!_consent || _working || _draft != null) return;
    setState(() { _error = null; _working = true; });
    final token = ZaiPreviewCancellation();
    _token = token;
    try {
      final draft = await _service.preview(
        context: widget.preview,
        approvedDigest: widget.preview.approvalDigest,
        explicitCloudConsent: _consent,
        cancellation: token,
      );
      if (!mounted) return;
      setState(() { _draft = draft; _consent = false; });
    } catch (_) {
      if (mounted) setState(() {
        _consent = false;
        _error = 'Невозможно получить проверяемый черновик NPC. '
            'Проверьте подключение Z.ai или ограничения формата. '
            'Собранная игра и сохранения не изменены.';
      });
    } finally {
      if (mounted) setState(() => _working = false);
      _token = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = const JsonEncoder.withIndent('  ')
        .convert(widget.preview.consentPreview);
    return Scaffold(
      appBar: AppBar(title: const Text('Черновик разговора NPC')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text('Подготовка игры, не её прохождение. '
              'Готовая RPG остаётся автономной и работает без ИИ. '
              'Облачный ответ не изменяет игровое состояние или канон.'),
          const SizedBox(height: 12),
          Text('Сцена ' + widget.preview.sceneId,
              style: Theme.of(context).textTheme.titleMedium),
          const Text('Ниже весь контекст, который может быть отправлен '
              'в Z.ai. Имя книги, полный файл, сохранения, ключ и '
              'неодобренные заметки NPC не прикладываются. '
              'Запрос может быть платным; при временных сбоях допускается '
              'до трёх отправок одних и тех же данных.'),
          const SizedBox(height: 8),
          SelectableText(payload,
              key: const Key('npc-dialogue-cloud-payload')),
          CheckboxListTile(
            key: const Key('npc-dialogue-cloud-consent'),
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: _working || _draft != null
                ? null : (v) => setState(() {
                    _consent = v == true;
                    _error = null;
                  }),
            title: const Text('Разрешаю передать именно показанные '
                'реплики и игровые условия в Z.ai один раз'),
          ),
          FilledButton.icon(
            key: const Key('npc-dialogue-cloud-generate'),
            onPressed: _consent && !_working && _draft == null
                ? _generate : null,
            icon: const Icon(Icons.auto_stories),
            label: const Text('Предложить художественные реплики'),
          ),
          if (_working) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, key: const Key('npc-dialogue-cloud-error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          if (_draft != null) ...[
            const Divider(height: 30),
            Text('Черновик — НЕ установлен в игру',
                style: Theme.of(context).textTheme.titleMedium),
            const Text('Это частная художественная интерпретация. '
                'Проверьте мотивы, знания, хронологию и смысл каждого '
                'высказывания. Для включения в RPG надо изменить '
                'исходную авторскую сцену и заново проверить/собрать '
                'обычный .bworld. ИИ не может сделать это автоматически.'),
            const SizedBox(height: 8),
            SelectableText(_draft!.sceneText,
                key: const Key('npc-dialogue-cloud-draft')),
            Text('Неопределённость: ' + _draft!.uncertainty),
            OutlinedButton.icon(
              key: const Key('npc-dialogue-cloud-copy'),
              onPressed: () => Clipboard.setData(
                  ClipboardData(text: _draft!.sceneText)),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Копировать текст для редактора сцен'),
            ),
          ],
        ],
      )),
    );
  }
}
