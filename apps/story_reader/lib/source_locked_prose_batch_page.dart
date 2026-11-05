import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'story_plan.dart';
import 'zai_semantic_preview.dart';
import 'zai_source_locked_prose_batch.dart';

/// Explicit opt-in for a BOUNDED group of exact source-locked scenes.
/// No HTTP call on opening; generated scenes remain LOCAL DRAFTS.
class SourceLockedProseBatchPage extends StatefulWidget {
  const SourceLockedProseBatchPage({
    super.key,
    required this.index,
    required this.book,
    required this.plan,
    this.batchService,
    this.initialMaxNewScenes = 4,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final SourceLockedProseBatchService? batchService;
  final int initialMaxNewScenes;

  @override
  State<SourceLockedProseBatchPage> createState() =>
      _SourceLockedProseBatchPageState();
}

class _SourceLockedProseBatchPageState
    extends State<SourceLockedProseBatchPage> {
  late final SourceLockedProseBatchService _batchService;
  int _batchNumber = 0;
  late int _maxNewScenes;
  bool _approved = false;
  bool _working = false;
  bool _loading = true;
  bool _blocked = false;
  SourceLockedProseBatchProgress? _progress;
  ZaiPreviewCancellation? _token;
  String? _status, _error;

  @override
  void initState() {
    super.initState();
    _batchService = widget.batchService ?? SourceLockedProseBatchService();
    _maxNewScenes = math.max(1,
        math.min(widget.initialMaxNewScenes, _selection.length));
    _inspect();
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  int get _batchCount =>
      (widget.plan.situations.length +
          SourceLockedProseBatchManifest.maxScenesInBatch - 1) ~/
      SourceLockedProseBatchManifest.maxScenesInBatch;

  List<String> get _selection {
    final size = SourceLockedProseBatchManifest.maxScenesInBatch;
    return [
      for (final scene in widget.plan.situations
          .skip(_batchNumber * size).take(size)) scene.id,
    ];
  }

  SourceLockedProseBatchManifest _manifest() =>
      SourceLockedProseBatchManifest.fromSelection(
        index: widget.index,
        book: widget.book,
        plan: widget.plan,
        sceneIds: _selection,
        maxNewScenesPerRun: _maxNewScenes,
      );

  Future<void> _inspect() async {
    final selectedGroup = _batchNumber;
    setState(() {
      _approved = false;
      _loading = true;
      _blocked = false;
      _error = null;
      _status = null;
      _progress = null;
    });
    try {
      final result = await _batchService.inspect(_manifest());
      if (!mounted || _batchNumber != selectedGroup) return;
      setState(() => _progress = result);
    } catch (_) {
      if (!mounted || _batchNumber != selectedGroup) return;
      setState(() {
        _blocked = true;
        _error = 'Нельзя проверить сохранённые сцены или '
            'их привязку к книге. Облачный запрос заблокирован.';
      });
    } finally {
      if (mounted && _batchNumber == selectedGroup) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _generate() async {
    if (_working || _loading || _blocked || !_approved) return;
    final selectedGroup = _batchNumber;
    final manifest = _manifest();
    final token = ZaiPreviewCancellation();
    setState(() {
      _working = true;
      _token = token;
      _status = 'Проверяем согласие и локальные черновики';
      _error = null;
    });
    try {
      final progress = await _batchService.generate(
        manifest: manifest,
        approvedManifestDigest: manifest.approvalDigest,
        explicitBatchConsent: _approved,
        cancellation: token,
        onProgress: (value) {
          if (mounted && _batchNumber == selectedGroup) {
            setState(() {
              _progress = value;
              _status = 'Готово ' + value.completed.toString() +
                  ' из ' + value.total.toString() +
                  '; создано сейчас ' + value.newlyGenerated.toString();
            });
          }
        },
      );
      if (!mounted || _batchNumber != selectedGroup) return;
      setState(() {
        _progress = progress;
        _status = progress.allReadyAsDrafts
            ? 'Все черновики группы сохранены на устройстве. '
              'Они НЕ одобрены для игры.'
            : 'Достигнут предел запросов этого запуска. '
              'Для продолжения снова подтвердите весь контекст.';
      });
    } catch (_) {
      if (!mounted || _batchNumber != selectedGroup) return;
      setState(() {
        _error = 'Подготовка остановлена. Готовые сцены сохранены. '
            'Они будут восстановлены без повторного платного запроса. '
            'Проверьте подключение, доступ к Z.ai и сохранения.';
      });
    } finally {
      if (mounted && _batchNumber == selectedGroup) {
        setState(() {
          _working = false;
          _approved = false;
          _token = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SourceLockedProseBatchManifest? snapshot;
    try {
      snapshot = _manifest();
    } catch (_) {
      // A foreign book or malformed plan never enables the submit button.
    }
    final manifest = snapshot;
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Художественные сцены по частям')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Text('Дополнительная подготовка черновиков '
                'через Z.ai (GLM 4.7 Flash). '
                'Один запуск может охватить не более восьми сцен. '
                'Отправка только после отдельного разрешения; '
                'черновики не включаются в игру автоматически.'),
            const SizedBox(height: 12),
            if (_batchCount > 1)
              DropdownButtonFormField<int>(
                key: ValueKey('prose-batch-select-' +
                    _batchNumber.toString()),
                initialValue: _batchNumber,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Группа сцен',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var i = 0; i < _batchCount; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('Группа ' + (i + 1).toString() +
                          ' из ' + _batchCount.toString()),
                    ),
                ],
                onChanged: _loading || _working ? null : (value) {
                  if (value == null || value == _batchNumber) return;
                  setState(() {
                    _batchNumber = value;
                    _maxNewScenes = math.min(4, _selection.length);
                  });
                  _inspect();
                },
              ),
            if (_selection.length > 1) ...[
              const SizedBox(height: 10),
              Text('Предел новых сцен в запуске: ' +
                  _maxNewScenes.toString()),
              Slider(
                key: const Key('prose-batch-limit'),
                min: 1,
                max: _selection.length.toDouble(),
                divisions: _selection.length - 1,
                value: _maxNewScenes.toDouble(),
                onChanged: _loading || _working ? null : (value) {
                  setState(() {
                    _maxNewScenes = value.round();
                    _approved = false;
                    _status = null;
                  });
                },
              ),
            ],
            const SizedBox(height: 10),
            if (manifest == null)
              const Text('Пакет не прошёл проверку редакции и сценария.')
            else ...[
              Text('Показано сцен: ' +
                  manifest.sceneIds.length.toString() +
                  '. В этом запуске не более ' +
                  manifest.maxNewScenesPerRun.toString() +
                  ' новых сцен и ' +
                  manifest.maxModelAttempts.toString() +
                  ' попыток обращения при временных сбоях. '
                  'Точная стоимость зависит от тарифов Z.ai.'),
              Text('Объём пользовательского контекста примерно ' +
                  manifest.sentContextUtf8Bytes.toString() +
                  ' байт без системного запроса. '
                  'Полный FB2, отдельные поля названия и автора, '
                  'API-ключ и сохранения не добавляются. '
                  'Названия и имена могут встретиться в показанных '
                  'цитатах или описаниях сцен.'),
              const SizedBox(height: 8),
              Text('Пользовательский контекст (служебный запрос '
                  'добавляется отдельно):',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final sceneContext in manifest.contexts)
                ExpansionTile(
                  key: ValueKey('prose-batch-context-' +
                      sceneContext.situation.id),
                  title: Text(sceneContext.situation.goal),
                  subtitle: Text('Сцена ' + sceneContext.situation.id),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ')
                            .convert(sceneContext.consentPreview),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              const Text('Просмотрите каждую сцену: цитаты, '
                  'варианты выбора и условия. Это частная '
                  'вымышленная адаптация, а не доказанный канон.'),
              CheckboxListTile(
                key: const Key('prose-batch-consent'),
                value: _approved,
                contentPadding: EdgeInsets.zero,
                onChanged: _working || _loading || _blocked ||
                        progress?.allReadyAsDrafts == true
                    ? null
                    : (value) => setState(() => _approved = value == true),
                title: const Text('Я проверил(а) ВСЕ показанные сцены '
                    'и разрешаю ограниченный пакет запросов к Z.ai'),
              ),
              FilledButton.icon(
                key: const Key('prose-batch-start'),
                onPressed: _approved && !_working && !_loading &&
                        !_blocked && progress?.allReadyAsDrafts != true
                    ? _generate : null,
                icon: const Icon(Icons.auto_stories),
                label: const Text('Подготовить черновики этих сцен'),
              ),
              if (_working)
                TextButton.icon(
                  key: const Key('prose-batch-cancel'),
                  onPressed: () => _token?.cancel(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Остановить последующие запросы'),
                ),
              if (_loading || _working)
                const LinearProgressIndicator(),
              if (progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  key: const Key('prose-batch-progress'),
                  value: progress.total == 0 ? 0 :
                      progress.completed / progress.total,
                ),
                Text('Сохранено ' + progress.completed.toString() +
                    ' из ' + progress.total.toString() +
                    ', ранее создано ' +
                    progress.recovered.toString() + '.'),
              ],
              if (_status != null) Text(_status!),
              if (_error != null)
                Text(_error!,
                    key: const Key('prose-batch-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              const Text('Для включения черновика в частную RPG '
                  'позже откройте каждую нужную сцену '
                  'и отдельно подтвердите художественный текст. '
                  'Книги и ранее созданные кампании не меняются.'),
            ],
          ],
        ),
      ),
    );
  }
}
