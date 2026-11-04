import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'preparation_editor_help.dart';

import 'intermediate_story_blueprint.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';
import 'zai_causal_choice_notebook.dart';
import 'zai_manual_source_alignment.dart';
import 'zai_manual_source_alignment_page.dart';
import 'zai_cross_window_evidence_graph.dart';
import 'zai_editorial_consistency.dart';
import 'zai_m2c_source_bridge.dart';
import 'zai_private_bookworld_compilation.dart';
import 'zai_private_compilation_draft.dart';
import 'zai_semantic_review_queue.dart';
import 'zai_source_scene_board.dart';

/// M2f3f2: manual, source-locked private compiler UI.
/// The original book is never uploaded or bundled into a generated package.
/// Only a second, explicit tap can install a verified world in SQLite.
class ZaiPrivateCompilationPage extends StatefulWidget {
  const ZaiPrivateCompilationPage({
    super.key,
    required this.queue,
    required this.notebook,
    required this.consistency,
    this.causalRepository,
    this.draftRepository,
    this.narrativeRepository,
    this.catalogRepository,
    this.editorialRepository,
    this.alignmentRepository,
    this.gateway,
  });

  final ZaiWindowReviewQueue queue;
  final ZaiCausalChoiceNotebook notebook;
  final ZaiEditorialConsistencyNotebook consistency;
  final SourceAnalysisCheckpointRepository? causalRepository;
  final SourceAnalysisCheckpointRepository? draftRepository;
  final SourceAnalysisCheckpointRepository? narrativeRepository;
  final SourceAnalysisCheckpointRepository? catalogRepository;
  final SourceAnalysisCheckpointRepository? editorialRepository;
  final SourceAnalysisCheckpointRepository? alignmentRepository;
  final WorldLibraryGateway? gateway;

  @override
  State<ZaiPrivateCompilationPage> createState() =>
      _ZaiPrivateCompilationPageState();
}

class _EditorialSources {
  const _EditorialSources(this.evidence, this.catalog, this.editorial);
  final SourceEvidenceGraph evidence;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
}

class _ZaiPrivateCompilationPageState
    extends State<ZaiPrivateCompilationPage> {
  late final SourceAnalysisCheckpointRepository _draftRepo =
      widget.draftRepository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.zaiPrivateCompilation);
  late final SourceAnalysisCheckpointRepository _causalRepo =
      widget.causalRepository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.zaiCausalChoices);
  late final SourceAnalysisCheckpointRepository _narrativeRepo =
      widget.narrativeRepository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.narrativeEvidence);
  late final SourceAnalysisCheckpointRepository _catalogRepo =
      widget.catalogRepository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.semanticCatalog);
  late final SourceAnalysisCheckpointRepository _editorialRepo =
      widget.editorialRepository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.semanticEditorial);
  late final SourceAnalysisCheckpointRepository _alignmentRepo =
      widget.alignmentRepository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.zaiSourceAlignment);
  late final WorldLibraryGateway _gateway =
      widget.gateway ?? const DeviceWorldLibraryGateway();

  final _sceneText = TextEditingController();
  ZaiPrivateCompilationDraft? _draft;
  _EditorialSources? _sources;
  ZaiCompiledPrivateWorld? _compiled;
  WorldLibraryItem? _installed;
  String? _compiledEditorSha;
  String? _compiledM2cSha;
  bool _busy = false;
  bool _loading = true;
  bool _corrupt = false;
  bool _showFuture = false;
  int _scenePosition = 0;
  String? _error;
  String? _notice;

  String get _fingerprint => widget.queue.index.sourceFingerprint;
  List<ZaiSourceScene> get _scenes => widget.notebook.board.scenes;
  ZaiSourceScene get _scene => _scenes[_scenePosition];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sceneText.dispose();
    super.dispose();
  }

  Future<_EditorialSources> _readSources() async {
    final baseline = await ZaiSourceAlignmentBaseline.load(
      index: widget.queue.index,
      narrativeRepository: _narrativeRepo,
      catalogRepository: _catalogRepo,
      editorialRepository: _editorialRepo,
    );
    final overlayRaw = await _alignmentRepo.read(_fingerprint);
    if (overlayRaw == null) {
      return _EditorialSources(
          baseline.narrative.graph, baseline.catalog, baseline.editorial);
    }
    final ledger = ZaiManualSourceAlignment.decode(
      queue: widget.queue, baseline: baseline, raw: overlayRaw);
    final applied = ledger.apply(queue: widget.queue, baseline: baseline);
    return _EditorialSources(
        applied.evidence, applied.catalog, applied.editorial);
  }

  Future<void> _openSourceAlignment() async {
    if (_busy || _loading || _corrupt || _draft == null ||
        _scenes.isEmpty || !mounted) return;
    if (_sceneText.text !=
        (_draft!.authoredSceneTexts[_scene.id] ?? '')) {
      setState(() => _error = 'Сначала сохраните введённый текст сцены.');
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ZaiManualSourceAlignmentPage(
        queue: widget.queue,
        board: widget.notebook.board,
        narrativeRepository: _narrativeRepo,
        catalogRepository: _catalogRepo,
        editorialRepository: _editorialRepo,
        alignmentRepository: _alignmentRepo,
      ),
    ));
    if (!mounted) return;
    setState(() {
      _compiled = null;
      _compiledEditorSha = null;
      _compiledM2cSha = null;
      _error = null;
    });
    try {
      final updated = await _readSources();
      if (mounted) setState(() {
        _sources = updated;
        _notice = 'Соответствия перезагружены. '
            'Укажите подтверждённые факты для исходных сцен.';
      });
    } catch (error) {
      if (mounted) setState(() {
        _sources = null;
        _error = 'Проверка M2f3g: ' + error.toString();
      });
    }
  }

  Future<void> _load() async {
    try {
      final raw = await _draftRepo.read(_fingerprint);
      final draft = raw == null
          ? ZaiPrivateCompilationDraft.empty(widget.notebook)
          : ZaiPrivateCompilationDraft.decode(widget.notebook, raw);
      _sceneText.text = _scenes.isEmpty ? '' :
          draft.authoredSceneTexts[_scenes.first.id] ?? '';
      if (mounted) setState(() {
        _draft = draft;
        _corrupt = false;
        _error = null;
      });
      try {
        final sources = await _readSources();
        if (mounted) setState(() { _sources = sources; _notice = null; });
      } on FormatException catch (error) {
        if (mounted) setState(() {
          _notice = error.message;
          _sources = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _corrupt = true;
        _error = 'Сохранённый черновик изменился или повреждён. '
            'Книга не изменена. Можно отдельно сбросить черновик сборки.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(ZaiPrivateCompilationDraft updated) async {
    if (_busy || _corrupt || _draft == null) return;
    setState(() => _busy = true);
    try {
      await _draftRepo.write(_fingerprint, updated.encode(widget.notebook));
      if (mounted) setState(() {
        _draft = updated;
        _compiled = null;
        _installed = null;
        _compiledEditorSha = null;
        _compiledM2cSha = null;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() =>
          _error = 'Не удалось сохранить изменения. Прежний черновик сохранён.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy || _loading) return;
    final yes = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить только этот черновик сборки?'),
        content: const Text('Удалятся только редакторские тексты и ручные '
            'соответствия событий M2f3f2. Книга, результаты анализа, '
            'готовые миры и игровые сохранения останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
            key: const Key('zai-private-reset-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить M2f3f2')),
        ],
      ));
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _draftRepo.delete(_fingerprint);
      if (mounted) setState(() {
        _draft = ZaiPrivateCompilationDraft.empty(widget.notebook);
        _sceneText.clear();
        _scenePosition = 0;
        _compiled = null;
        _installed = null;
        _compiledEditorSha = null;
        _compiledM2cSha = null;
        _corrupt = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error =
          'Не удалось удалить только M2f3f2; остальные данные сохранены.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _permission(String title, String explanation) async {
    var allow = false;
    return await showDialog<bool>(context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(explanation),
              CheckboxListTile(
                key: const Key('zai-private-consent'),
                value: allow,
                onChanged: (v) => refresh(() => allow = v == true),
                title: const Text('Подтверждаю частное использование. '
                    'Не разрешаю публичное распространение текста или игры.'),
              ),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            FilledButton(
              key: const Key('zai-private-confirm'),
              onPressed: allow ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Подтвердить'),
            ),
          ],
        ))) ?? false;
  }

  List<SourceSemanticAssertion> _possibleClaims(String eventId) {
    final sources = _sources;
    if (sources == null) return const [];
    final found = ZaiCrossWindowEvidenceGraph
        .fromQueue(widget.queue).reviewed
        .where((f) => f.id == eventId).firstOrNull;
    if (found == null) return const [];
    final refs = {for (final e in sources.evidence.records) e.id: e};
    return [
      for (final claim in sources.catalog.assertions)
        if (claim.kind == SemanticAssertionKind.event &&
            claim.voice == AssertionVoice.narratorCandidate &&
            claim.polarity == AssertionPolarity.affirmative &&
            claim.time == AssertionTime.textOrderOnly &&
            sources.editorial.verdicts[claim.id] ==
                SemanticEditorialVerdict.canonCandidate &&
            claim.evidenceIds.any((id) {
              final e = refs[id];
              return e != null && e.kind == EvidenceKind.event &&
                  e.status == EvidenceStatus.confirmed &&
                  e.chunkId == found.candidate.chunkId &&
                  e.startUtf16 == found.candidate.startUtf16 &&
                  e.endUtf16 == found.candidate.endUtf16 &&
                  e.evidenceSha256 == sha256.convert(
                      utf8.encode(found.quote)).toString();
            })) claim,
    ];
  }

  Future<void> _checkCurrentNotebook() async {
    final latest = await _causalRepo.read(_fingerprint);
    if (latest == null ||
        latest != widget.notebook.encode()) {
      throw const FormatException(
          'Игровые решения изменились или ещё не сохранены. '
          'Откройте заново редактор сборки.');
    }
    final draft = _draft;
    if (draft == null ||
        await _draftRepo.read(_fingerprint) !=
            draft.encode(widget.notebook)) {
      throw const FormatException(
          'Редакторские тексты изменились на диске. '
          'Перезагрузите редактор без потери прежних решений.');
    }
  }

  Future<void> _compile() async {
    final draft = _draft;
    if (_loading || _busy || draft == null || _corrupt) return;
    if (_scenes.isEmpty) {
      setState(() => _error = 'Сначала создайте сцены в редакторе событий.');
      return;
    }
    if (_sceneText.text !=
        (draft.authoredSceneTexts[_scene.id] ?? '')) {
      setState(() => _error = 'Сначала сохраните текст выбранной сцены.');
      return;
    }
    final approved = await _permission(
      'Собрать частный игровой мир?',
      'Текст сцены создан или отдельно утверждён вами. '
      'Исходные утверждения требуют точных совпадений с M2c. '
      'Компиляция работает без сети. Пакет пока НЕ устанавливается.',
    );
    if (!approved || !mounted) return;
    setState(() { _busy = true; _error = null; _compiled = null; });
    try {
      await _checkCurrentNotebook();
      final sources = await _readSources();
      final built = await ZaiPrivateBookworldCompilation.compile(
        queue: widget.queue,
        notebook: widget.notebook,
        consistency: widget.consistency,
        evidence: sources.evidence,
        catalog: sources.catalog,
        editorial: sources.editorial,
        sourceSceneIds: draft.sourceSceneIds,
        eventAssertionIds: draft.eventAssertionIds,
        authoredSceneTexts: draft.authoredSceneTexts,
        consentForPrivateCompilation: true,
      );
      if (mounted) setState(() {
        _compiled = built;
        _sources = sources;
        _compiledEditorSha = draft.encode(widget.notebook);
        _compiledM2cSha = sources.editorial.encode();
        _notice = 'Пакет проверен. Он остаётся только в памяти '
            'до отдельного подтверждения установки.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Компиляция остановлена: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install() async {
    final built = _compiled;
    if (built == null || _busy || _corrupt) return;
    final allowed = await _permission(
      'Установить проверенный игровой мир?',
      'Будет добавлен новый частный мир в локальную библиотеку. '
      'Текущие кампании и сохранения не изменятся. '
      'Игра появится после установки, запуск — отдельной кнопкой.');
    if (!allowed || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _checkCurrentNotebook();
      final fresh = await _readSources();
      final result = ZaiM2cSourceBridge.review(
        queue: widget.queue,
        notebook: widget.notebook,
        consistency: widget.consistency,
        evidence: fresh.evidence,
        catalog: fresh.catalog,
        editorial: fresh.editorial,
        sourceSceneIds: _draft!.sourceSceneIds,
        eventAssertionIds: _draft!.eventAssertionIds,
        authoredSceneTexts: _draft!.authoredSceneTexts,
        rights: PreparationRights.privateUse,
        consentForPrivateCompilation: true,
      );
      if (!result.canStageForPrivateCompiler ||
          _compiledEditorSha != _draft!.encode(widget.notebook) ||
          _compiledM2cSha != fresh.editorial.encode()) {
        throw const FormatException(
            'Источники изменились со времени компиляции. '
            'Повторите проверку, прежде чем устанавливать.');
      }
      final world = await ZaiPrivateBookworldCompilation.installConfirmed(
        compiled: built, gateway: _gateway, userConfirmedInstall: true);
      if (mounted) setState(() {
        _installed = world;
        _notice = 'Личный игровой мир установлен. '
            'Для начала создайте новую кампанию.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Установка отменена: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final world = _installed;
    if (_busy || world == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final campaignId = await _gateway.start(world.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) =>
            WorldPlayPage(gateway: _gateway, campaignId: campaignId)));
    } catch (error) {
      if (mounted) setState(() => _error =
          'Не удалось начать кампанию, установленный мир сохранён: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reveal() async {
    final yes = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Показать будущие главы?'),
        content: const Text('Редактор содержит названия сцен и '
            'источниковые события, включая возможные спойлеры.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Не показывать')),
          FilledButton(
            key: const Key('zai-private-spoiler-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Показать')),
        ],
      ));
    if (yes == true && mounted) setState(() => _showFuture = true);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final enabled = !_loading && !_busy && !_corrupt && draft != null;
    final palette = Theme.of(context).colorScheme;
    final visible = _scenes.indexed.where((entry) =>
        _showFuture || entry.$2.chapterIndex == 0).toList();
    final shown = _scenes.isNotEmpty && (_showFuture || _scene.chapterIndex == 0);
    return Scaffold(
      appBar: AppBar(title: const Text('Собрать частную RPG')),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
          children: [
            Text('Из проверенного сценария в игру',
                key: const Key('zai-private-title'),
                style: Theme.of(context).textTheme.titleLarge),
            const Text('Это ручная проверка перед сборкой. Ответы ИИ '
                'с пометкой «проверить» ещё не подтверждены. '
                'Публикация и отправка исходного текста запрещены.'),
            const PreparationEditorHelp(
              purpose: 'Последняя проверка перед созданием личного игрового мира.',
              steps: [
                'Сопоставьте каждое исходное событие с проверенной цитатой.',
                'Сохраните текст сцен и отделите придуманные альтернативы.',
                'Нажмите «Проверить и собрать», затем отдельно подтвердите установку и начните игру.',
              ],
              result: 'проверенный локальный игровой мир и новая кампания только после подтверждения.',
              next: 'перейдите в библиотеку или продолжите сохранённую игру.',
            ),
            if (_loading || _busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, key: const Key('zai-private-error'),
                  style: TextStyle(color: palette.error)),
            if (_notice != null)
              Text(_notice!, key: const Key('zai-private-notice')),
            if (_corrupt)
              OutlinedButton.icon(
                key: const Key('zai-private-reset'),
                onPressed: !_busy ? _reset : null,
                icon: const Icon(Icons.restore),
                label: const Text('Сбросить только подготовку сборки'),
              ),
            if (!_corrupt && draft != null) ...[
              const SizedBox(height: 12),
              Text('Сцен: ${_scenes.length} · исходных: '
                  '${draft.sourceSceneIds.length} · '
                  'ручных соответствий: ${draft.eventAssertionIds.length}',
                  key: const Key('zai-private-stats')),
              OutlinedButton.icon(
                key: const Key('zai-private-open-source-alignment'),
                onPressed: enabled && _scenes.isNotEmpty
                    ? _openSourceAlignment : null,
                icon: const Icon(Icons.library_books_outlined),
                label: const Text('Сопоставить игровые события с книгой'),
              ),
              if (_sources == null)
                const Text('Для сборки подготовьте и утвердите '
                    'исходные цитаты через «Персонажи, события '
                    'и хронология».'),
              if (!_showFuture && _scenes.any((s) => s.chapterIndex > 0))
                OutlinedButton.icon(
                  key: const Key('zai-private-reveal'),
                  onPressed: _reveal,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Редактировать будущие главы'),
                ),
              if (_scenes.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('zai-private-select-scene-$_scenePosition-$_showFuture'),
                  initialValue: shown ? _scenePosition : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Редактируемая сцена',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final pair in visible)
                      DropdownMenuItem(
                        value: pair.$1,
                        child: Text('Гл. ${pair.$2.chapterIndex + 1} · '
                            '${pair.$2.title}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: enabled ? (i) {
                    if (i == null) return;
                    if (_sceneText.text !=
                        (draft.authoredSceneTexts[_scene.id] ?? '')) {
                      setState(() => _error =
                          'Сначала сохраните введённый текст.');
                      return;
                    }
                    setState(() {
                      _scenePosition = i;
                      _sceneText.text =
                          draft.authoredSceneTexts[_scene.id] ?? '';
                      _error = null;
                    });
                  } : null,
                ),
                if (shown) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('zai-private-source-toggle'),
                    title: const Text('Исходная сцена книги'),
                    subtitle: const Text('Выключить только для '
                        'написанной вами альтернативы.'),
                    value: draft.sourceSceneIds.contains(_scene.id),
                    onChanged: enabled ? (yes) async {
                      try {
                        await _save(draft.setSource(
                            widget.notebook, _scene.id, yes));
                      } on FormatException catch (error) {
                        if (mounted) setState(() => _error = error.message);
                      }
                    } : null,
                  ),
                  for (final eventId in _scene.eventIds)
                    if (draft.sourceSceneIds.contains(_scene.id))
                      Builder(builder: (_) {
                        final possible = _possibleClaims(eventId);
                        final selected = draft.eventAssertionIds[eventId];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Исходное событие: '
                                '${widget.notebook.board.graph.reviewed.firstWhere(
                                  (finding) => finding.id == eventId).label}',
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            DropdownButtonFormField<String>(
                              key: Key('zai-private-claim-$eventId'),
                              initialValue: possible.any((a) => a.id == selected)
                                  ? selected : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Подтверждённый факт из книги',
                              ),
                              hint: const Text('Выбрать проверенную цитату'),
                              items: [
                                for (final claim in possible)
                                  DropdownMenuItem(
                                    value: claim.id,
                                    child: Text('${claim.subject} '
                                        '${claim.predicate} ${claim.object}',
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: enabled && possible.isNotEmpty
                                  ? (id) async {
                                    try {
                                      await _save(draft.setAssertion(
                                          widget.notebook, eventId, id));
                                    } on FormatException catch (error) {
                                      if (mounted) setState(
                                          () => _error = error.message);
                                    }
                                  } : null,
                            ),
                            if (possible.isEmpty)
                              const Text('Для события нет проверенного факта книги. '
                                  'Откройте независимый редактор событий.'),
                            const SizedBox(height: 12),
                          ],
                        );
                      }),
                  TextField(
                    key: const Key('zai-private-scene-prose'),
                    controller: _sceneText,
                    maxLines: 5,
                    minLines: 3,
                    maxLength: 6000,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Редакторский текст для игры',
                      helperText: 'Это собственное описание, '
                          'а не автоматический пересказ ИИ.',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('zai-private-save-text'),
                    onPressed: enabled ? () async {
                      try {
                        await _save(draft.setText(widget.notebook,
                            _scene.id, _sceneText.text));
                      } on FormatException catch (error) {
                        if (mounted) setState(() => _error = error.message);
                      }
                    } : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Сохранить текст сцены'),
                  ),
                ],
              ],
              const Divider(height: 24),
              Text('Проверка и частная компиляция',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text('Только исходные цитаты с точными диапазонами '
                  'и подтверждениями редактора попадут в историю как источник. '
                  'Требуются две достижимые концовки и последствия выбора.'),
              FilledButton.icon(
                key: const Key('zai-private-compile'),
                onPressed: enabled ? _compile : null,
                icon: const Icon(Icons.build_outlined),
                label: const Text('Проверить и собрать .bworld'),
              ),
              if (_compiled != null) ...[
                Text('Собрано: ${_compiled!.title} · '
                    '${_compiled!.archive.length} байт',
                    key: const Key('zai-private-compiled')),
                OutlinedButton.icon(
                  key: const Key('zai-private-install'),
                  onPressed: !_busy && _installed == null ? _install : null,
                  icon: const Icon(Icons.add_to_home_screen),
                  label: const Text('Установить в мою библиотеку'),
                ),
              ],
              if (_installed != null) ...[
                Text('Установлен: ${_installed!.title}',
                    key: const Key('zai-private-installed')),
                FilledButton.icon(
                  key: const Key('zai-private-start'),
                  onPressed: !_busy ? _start : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Начать новую игру'),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('zai-private-reset'),
                onPressed: !_busy ? _reset : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Сбросить только черновик сборки'),
              ),
              const Text('Оригинальная книга, настройки подключения '
                  'ИИ и старые игровые сохранения остаются неизменными.'),
            ],
          ],
        ),
      ))),
    );
  }
}
