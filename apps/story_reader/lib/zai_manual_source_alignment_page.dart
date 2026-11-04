import 'package:flutter/material.dart';
import 'preparation_editor_help.dart';

import 'source_analysis_checkpoint_repository.dart';
import 'source_semantic_provider.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_manual_source_alignment.dart';
import 'zai_semantic_review_queue.dart';
import 'zai_source_scene_board.dart';

/// Source quotes stay hidden until explicit spoiler consent, even when the
/// entire fairy tale is in ONE chapter. No automatic canon or cloud requests.
class ZaiManualSourceAlignmentPage extends StatefulWidget {
  const ZaiManualSourceAlignmentPage({
    super.key,
    required this.queue,
    required this.board,
    required this.narrativeRepository,
    required this.catalogRepository,
    required this.editorialRepository,
    required this.alignmentRepository,
  });

  final ZaiWindowReviewQueue queue;
  final ZaiSourceSceneBoard board;
  final SourceAnalysisCheckpointRepository narrativeRepository;
  final SourceAnalysisCheckpointRepository catalogRepository;
  final SourceAnalysisCheckpointRepository editorialRepository;
  final SourceAnalysisCheckpointRepository alignmentRepository;

  @override
  State<ZaiManualSourceAlignmentPage> createState() =>
      _ZaiManualSourceAlignmentPageState();
}

class _ZaiManualSourceAlignmentPageState
    extends State<ZaiManualSourceAlignmentPage> {
  final _subject = TextEditingController();
  final _predicate = TextEditingController();
  final _object = TextEditingController();
  ZaiSourceAlignmentBaseline? _baseline;
  ZaiManualSourceAlignment? _ledger;
  String? _selectedId;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _broken = false;
  bool _revealed = false;
  bool _quoteConsent = false;
  bool _meaningConsent = false;

  String get _fingerprint => widget.queue.index.sourceFingerprint;

  late final List<ZaiAnchoredFinding> _events = () {
    final ids = {for (final scene in widget.board.scenes) ...scene.eventIds};
    return ZaiCrossWindowEvidenceGraph.fromQueue(widget.queue).reviewed
        .where((f) => ids.contains(f.id) &&
            f.category == SemanticCategory.event).toList();
  }();

  ZaiAnchoredFinding? get _selected =>
      _events.where((e) => e.id == _selectedId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _predicate.dispose();
    _object.dispose();
    super.dispose();
  }

  Future<ZaiSourceAlignmentBaseline> _readBaseline() =>
      ZaiSourceAlignmentBaseline.load(
        index: widget.queue.index,
        narrativeRepository: widget.narrativeRepository,
        catalogRepository: widget.catalogRepository,
        editorialRepository: widget.editorialRepository,
      );

  void _select(String? id) {
    if (id == null) return;
    final saved = _ledger?.entries.where((e) => e.findingId == id).firstOrNull;
    setState(() {
      _selectedId = id;
      _subject.text = saved?.subject ?? '';
      _predicate.text = saved?.predicate ?? '';
      _object.text = saved?.object ?? '';
      _quoteConsent = false;
      _meaningConsent = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    try {
      final baseline = await _readBaseline();
      final raw = await widget.alignmentRepository.read(_fingerprint);
      final ledger = raw == null
          ? ZaiManualSourceAlignment.empty(widget.queue.index, baseline)
          : ZaiManualSourceAlignment.decode(
              queue: widget.queue, baseline: baseline, raw: raw);
      ledger.apply(queue: widget.queue, baseline: baseline);
      if (!mounted) return;
      setState(() {
        _baseline = baseline;
        _ledger = ledger;
        _broken = false;
        _error = null;
        _selectedId = _events.isEmpty ? null : _events.first.id;
      });
      if (_selectedId != null) _select(_selectedId);
    } catch (error) {
      if (mounted) setState(() {
        _broken = true;
        _error = 'Подтверждения относятся к другой версии книги или сцен: ' +
            error.toString() +
            '. Старый checkpoint сохранён, доступен только отдельный сброс.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reveal() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Показать цитаты и спойлеры?'),
        content: const Text('Даже в одной главе могут быть '
            'события концовки. Текст останется на устройстве.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('zai-align-reveal-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Показать цитаты'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) setState(() => _revealed = true);
  }

  Future<void> _write(ZaiManualSourceAlignment next) async {
    if (_busy || _broken) return;
    setState(() => _busy = true);
    try {
      final fresh = await _readBaseline();
      final raw = next.encode(queue: widget.queue, baseline: fresh);
      next.apply(queue: widget.queue, baseline: fresh);
      await widget.alignmentRepository.write(_fingerprint, raw);
      final readBack = await widget.alignmentRepository.read(_fingerprint);
      if (readBack != raw) {
        throw const FormatException('Запись контрольной точки не завершена.');
      }
      ZaiManualSourceAlignment.decode(
          queue: widget.queue, baseline: fresh, raw: raw);
      if (mounted) setState(() {
        _ledger = next;
        _baseline = fresh;
        _quoteConsent = false;
        _meaningConsent = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error =
          'Не удалось сохранить привязку: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    final source = _selected;
    final baseline = _baseline;
    final ledger = _ledger;
    if (source == null || baseline == null || ledger == null || _busy) return;
    try {
      await _write(ledger.accept(
        queue: widget.queue,
        baseline: baseline,
        findingId: source.id,
        subject: _subject.text,
        predicate: _predicate.text,
        object: _object.text,
        quoteConfirmedByReader: _quoteConsent,
        narratorAssertionConfirmedByReader: _meaningConsent,
      ));
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _revoke() async {
    final source = _selected;
    final ledger = _ledger;
    final baseline = _baseline;
    if (source == null || ledger == null || baseline == null) return;
    final yes = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать подтверждение?'),
        content: const Text('Удалится только выбранная связь с цитатой. '
            'Исходная книга, проверенные факты и сохранения не изменятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('zai-align-revoke-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отозвать'),
          ),
        ],
      ));
    if (yes == true && mounted) {
      await _write(ledger.remove(queue: widget.queue,
          baseline: baseline, findingId: source.id));
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final yes = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить только подтверждения цитат?'),
        content: const Text('Исходная книга, проверенные факты, '
            'все игровые миры и сохранения останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('zai-align-reset-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить M2f3g')),
        ],
      ));
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.alignmentRepository.delete(_fingerprint);
      final baseline = await _readBaseline();
      if (mounted) setState(() {
        _baseline = baseline;
        _ledger = ZaiManualSourceAlignment.empty(
            widget.queue.index, baseline);
        _broken = false;
        _error = null;
        _quoteConsent = false;
        _meaningConsent = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error =
          'Сброс подтверждений не выполнен: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && !_loading && !_broken && _ledger != null;
    final source = _selected;
    final accepted = _ledger?.entries.any(
        (e) => e.findingId == source?.id) ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка цитат из книги')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('Подтверждение событий из книги',
                key: const Key('zai-align-title'),
                style: Theme.of(context).textTheme.titleLarge),
            const Text('Две независимые проверки: точный фрагмент '
                'и ручное утверждение. Автоматической канонизации нет.'),
            const PreparationEditorHelp(
              purpose: 'Подтверждает, что игровое событие действительно описано в книге.',
              steps: [
                'Разрешите показ цитат, включая возможные спойлеры.',
                'Сравните точную цитату с книгой и своими словами укажите, кто и что сделал.',
                'Отдельно подтвердите цитату и смысл события, затем сохраните связку.',
              ],
              result: 'частное подтверждение источника; оно не меняет оригинальную книгу.',
              next: 'вернитесь к сборке RPG и выберите подтверждённый факт.',
            ),
            if (_loading || _busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, key: const Key('zai-align-error'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            Text('Принято: ' + (_ledger?.entries.length ?? 0).toString() +
                ' / ' + _events.length.toString(),
                key: const Key('zai-align-count')),
            if (_broken)
              OutlinedButton.icon(
                key: const Key('zai-align-reset'),
                onPressed: _busy ? null : _reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Сбросить только подтверждения цитат'),
              ),
            if (enabled && !_revealed)
              OutlinedButton(
                key: const Key('zai-align-reveal'),
                onPressed: _reveal,
                child: const Text('Показать цитаты (включая спойлеры)'),
              ),
            if (enabled && _revealed && _events.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('zai-align-select-' + (_selectedId ?? 'none')),
                initialValue: _selectedId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Событие'),
                items: [
                  for (final (i, e) in _events.indexed)
                    DropdownMenuItem(
                      value: e.id,
                      child: Text((i + 1).toString() +
                          '. Гл. ' + (e.chapterIndex + 1).toString() +
                          ': ' + e.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _select,
              ),
              if (source != null) ...[
                const SizedBox(height: 12),
                Text('Цитата из книги',
                    style: Theme.of(context).textTheme.titleMedium),
                SelectableText(source.quote,
                    key: const Key('zai-align-exact-quote')),
                Text('UTF-16: ' + source.candidate.startUtf16.toString() +
                    '–' + source.candidate.endUtf16.toString()),
                if (accepted) const Text('Ранее подтверждено редактором.'),
                TextField(
                  key: const Key('zai-align-subject'),
                  controller: _subject, maxLength: 160,
                  decoration: const InputDecoration(
                      labelText: 'Субъект события (проверяется вручную)'),
                ),
                TextField(
                  key: const Key('zai-align-predicate'),
                  controller: _predicate, maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Действие'),
                ),
                TextField(
                  key: const Key('zai-align-object'),
                  controller: _object, maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Объект'),
                ),
                CheckboxListTile(
                  key: const Key('zai-align-confirm-quote'),
                  title: const Text('Лично проверил точную цитату книги.'),
                  value: _quoteConsent,
                  onChanged: (v) => setState(
                      () => _quoteConsent = v == true),
                ),
                CheckboxListTile(
                  key: const Key('zai-align-confirm-narrator'),
                  title: const Text('Лично проверил, что утверждение '
                      'описывает событие повествователя, не чью-то '
                      'догадку или событие из будущего.'),
                  value: _meaningConsent,
                  onChanged: (v) => setState(
                      () => _meaningConsent = v == true),
                ),
                FilledButton.icon(
                  key: const Key('zai-align-save'),
                  onPressed: _quoteConsent && _meaningConsent ? _accept : null,
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Сохранить частный кандидат канона'),
                ),
                if (accepted)
                  TextButton(
                    key: const Key('zai-align-revoke'),
                    onPressed: _revoke,
                    child: const Text('Отозвать подтверждение'),
                  ),
              ],
              const SizedBox(height: 12),
              const Text('Результат не публикует игру, не меняет '
                  'исходную книгу или проверенные факты и не обращается к сети.'),
            ],
          ],
        ),
      ))),
    );
  }
}
