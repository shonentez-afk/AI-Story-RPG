import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_evidence_graph.dart';
import 'source_character_dossier_panel.dart';
import 'source_relations_review_panel.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_evidence_review_session.dart';

/// A human-review workspace for ALL source-backed semantic proposals.
/// It never changes BookWorld, a published game, a book or its save files.
/// The source quote and catalog are independently decoded before any edits.
class SourceEditorialReviewPage extends StatefulWidget {
  const SourceEditorialReviewPage({
    super.key,
    required this.index,
    this.narrativeRepository,
    this.catalogRepository,
    this.editorialRepository,
    this.relationsRepository,
  });

  final BookSourceIndex index;
  final SourceAnalysisCheckpointRepository? narrativeRepository;
  final SourceAnalysisCheckpointRepository? catalogRepository;
  final SourceAnalysisCheckpointRepository? editorialRepository;
  final SourceAnalysisCheckpointRepository? relationsRepository;

  @override
  State<SourceEditorialReviewPage> createState() =>
      _SourceEditorialReviewPageState();
}

class _SourceEditorialReviewPageState extends State<SourceEditorialReviewPage> {
  late final SourceAnalysisCheckpointRepository _narrative =
      widget.narrativeRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.narrativeEvidence);
  late final SourceAnalysisCheckpointRepository _catalogStore =
      widget.catalogRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.semanticCatalog);
  late final SourceAnalysisCheckpointRepository _editorStore =
      widget.editorialRepository ??
          const FileSourceAnalysisCheckpointRepository(
              scope: SourceCheckpointScope.semanticEditorial);

  SourceSemanticCatalog? _catalog;
  SourceEvidenceGraph? _graph;
  SemanticEditorialReviewSession? _editorial;
  bool _loading = true;
  bool _busy = false;
  bool _revealed = false;
  int _relationRevision = 0;
  String? _error;
  String? _notice;
  String _search = '';
  SemanticAssertionKind? _kind;
  int _page = 0;
  static const pageSize = 12;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _catalog = null;
      _graph = null;
      _editorial = null;
      _page = 0;
      _revealed = false;
    });
    try {
      final fingerprint = widget.index.sourceFingerprint;
      final narrativeRaw = await _narrative.read(fingerprint);
      if (narrativeRaw == null) {
        throw const FormatException(
            'Сначала подготовьте книгу и проверьте цитаты событий.');
      }
      final session = StoryEvidenceReviewSession.decode(
          widget.index, narrativeRaw);
      if (session.scannedChunks != widget.index.chunks.length) {
        throw const FormatException(
            'Анализ событий не закончен для всех фрагментов книги.');
      }
      final catalogRaw = await _catalogStore.read(fingerprint);
      if (catalogRaw == null) {
        throw const FormatException(
            'Смысловой каталог отсутствует. Запустите локальную подготовку.');
      }
      final catalog = SourceSemanticCatalog.decode(
          widget.index, session.graph, catalogRaw);
      final editorialRaw = await _editorStore.read(fingerprint);
      final editorial = editorialRaw == null
          ? SemanticEditorialReviewSession.create(widget.index, catalog)
          : SemanticEditorialReviewSession.decode(
              widget.index, session.graph, catalog, editorialRaw);
      if (!mounted) return;
      setState(() {
        _graph = session.graph;
        _catalog = catalog;
        _editorial = editorial;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Данные редактора не открыты: $error. '
              'Сохранённые книги и прохождения не изменены.';
          _loading = false;
        });
      }
    }
  }

  String _kindName(SemanticAssertionKind kind) => switch (kind) {
    SemanticAssertionKind.character => 'Персонаж',
    SemanticAssertionKind.location => 'Место',
    SemanticAssertionKind.event => 'Событие',
    SemanticAssertionKind.fact => 'Факт',
    SemanticAssertionKind.relation => 'Отношение',
    SemanticAssertionKind.alias => 'Псевдоним',
  };

  String _verdictLabel(SemanticEditorialVerdict? verdict) => switch (verdict) {
    null => 'Не проверено',
    SemanticEditorialVerdict.passageOnly => 'Только цитата',
    SemanticEditorialVerdict.canonCandidate => 'Кандидат канона',
    SemanticEditorialVerdict.disputed => 'Спорное',
    SemanticEditorialVerdict.rejected => 'Отклонено',
  };

  bool _canProposeCanon(SourceSemanticAssertion claim) {
    final byEvidence = {for (final e in _graph!.records) e.id: e};
    return claim.evidenceIds.isNotEmpty &&
        claim.evidenceIds.every((id) {
          final source = byEvidence[id];
          return source != null &&
              source.status == EvidenceStatus.confirmed &&
              source.spoilerGate == EvidenceSpoilerGate.chapter &&
              source.visibleAfterChapter == source.chapterIndex;
        });
  }

  Future<void> _decide(
      SourceSemanticAssertion claim, SemanticEditorialVerdict? verdict) async {
    if (_busy || _editorial == null || _catalog == null) return;
    if (verdict == SemanticEditorialVerdict.canonCandidate &&
        !_canProposeCanon(claim)) {
      setState(() => _error =
          'Сначала подтвердите каждую исходную цитату и правило спойлеров.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final next = _editorial!.decide(_catalog!, claim.id, verdict);
      // Publish the decision only after the local checkpoint was committed.
      await _editorStore.write(widget.index.sourceFingerprint, next.encode());
      if (mounted) {
        setState(() {
          _editorial = next;
          _notice = 'Решение по утверждению сохранено локально.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Решение не сохранено: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _verdictButton(SourceSemanticAssertion claim,
      SemanticEditorialVerdict verdict, String label, IconData icon) {
    final current = _editorial!.verdicts[claim.id];
    final blocked = verdict == SemanticEditorialVerdict.canonCandidate &&
        !_canProposeCanon(claim);
    return OutlinedButton.icon(
      key: Key('source-verdict-${claim.id}-${verdict.name}'),
      onPressed: _busy || blocked || current == verdict
          ? null
          : () => _decide(claim, verdict),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }

  Widget _assertionCard(SourceSemanticAssertion claim,
      Map<String, SourceEvidence> evidence) {
    final verdict = _editorial!.verdicts[claim.id];
    final heading = [
      claim.subject,
      claim.predicate,
      claim.object,
    ].where((v) => v.trim().isNotEmpty).join(' ');
    final sources = [
      for (final id in claim.evidenceIds)
        if (evidence[id] != null) evidence[id]!,
    ];
    return Card(
      key: Key('source-assertion-${claim.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('${_kindName(claim.kind)} · ${_verdictLabel(verdict)} · '
                'Голос: ${claim.voice.name}, время: ${claim.time.name}'),
            Text('Пометка анализа: ${claim.uncertainty}'),
            const SizedBox(height: 6),
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('Глава ${source.chapterIndex + 1}: '
                    '«${source.label}» · ${source.status.name}'),
              ),
            if (!_canProposeCanon(claim))
              const Text('Для кандидата канона необходимы все '
                  'проверенные цитаты без скрытых спойлеров.'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _verdictButton(claim,
                    SemanticEditorialVerdict.passageOnly,
                    'Только цитата', Icons.format_quote_outlined),
                _verdictButton(claim,
                    SemanticEditorialVerdict.canonCandidate,
                    'Кандидат канона', Icons.fact_check_outlined),
                _verdictButton(claim,
                    SemanticEditorialVerdict.disputed,
                    'Спорное', Icons.help_outline),
                _verdictButton(claim,
                    SemanticEditorialVerdict.rejected,
                    'Отклонить', Icons.close),
                if (verdict != null)
                  TextButton(
                    onPressed: _busy ? null : () => _decide(claim, null),
                    child: const Text('Снять решение'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final graph = _graph;
    final editorial = _editorial;
    final all = catalog?.assertions ?? <SourceSemanticAssertion>[];
    final search = _search.trim().toLowerCase();
    final filtered = all.where((claim) =>
        (_kind == null || claim.kind == _kind) &&
        (search.isEmpty || [
          claim.subject, claim.predicate, claim.object,
        ].any((value) => value.toLowerCase().contains(search)))).toList();
    final pages = filtered.isEmpty
        ? 1 : (filtered.length + pageSize - 1) ~/ pageSize;
    final page = _page.clamp(0, pages - 1).toInt();
    final visible = filtered.skip(page * pageSize).take(pageSize).toList();
    final evidence = graph == null
        ? <String, SourceEvidence>{}
        : {for (final item in graph.records) item.id: item};

    return Scaffold(
      appBar: AppBar(title: const Text('Персонажи, события и хронология')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.index.title,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('Это рабочие гипотезы по книге, а не '
                          'игровой канон. Редакторские решения не '
                          'изменяют оригинал, созданные миры или '
                          'сохранения. ИИ не используется.'),
                      if (_error != null)
                        Text(_error!, style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                      if (_notice != null) Text(_notice!),
                      const SizedBox(height: 12),
                      if (catalog == null || graph == null ||
                          editorial == null)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Перепроверить подготовку'),
                        )
                      else ...[
                        Text('Готовность проверки: '
                            '${editorial.reviewedCount} из '
                            '${catalog.assertions.length} утверждений '
                            'получили решение редактора. '
                            'Это не процент готовой RPG.'),
                        Text('Подтверждённых фрагментов: '
                            '${graph.records.where((e) =>
                                e.status == EvidenceStatus.confirmed).length}. '
                            'Кандидатов канона: ${editorial.canonCandidates}.'),
                        const SizedBox(height: 8),
                        if (!_revealed)
                          OutlinedButton.icon(
                            key: const Key('source-editor-show-spoilers'),
                            onPressed: () => setState(() => _revealed = true),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Показать утверждения (спойлеры)'),
                          )
                        else ...[
                          TextField(
                            key: const Key('source-editor-search'),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Поиск по персонажу, событию или факту',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => setState(() {
                              _search = value;
                              _page = 0;
                            }),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<SemanticAssertionKind?>(
                            key: const Key('source-editor-kind'),
                            initialValue: _kind,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Раздел',
                                border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem<SemanticAssertionKind?>(
                                value: null,
                                child: Text('Все типы утверждений'),
                              ),
                              for (final kind in SemanticAssertionKind.values)
                                DropdownMenuItem<SemanticAssertionKind?>(
                                  value: kind,
                                  child: Text(_kindName(kind)),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              _kind = value;
                              _page = 0;
                            }),
                          ),
                          const SizedBox(height: 10),
                          Text('Показано ${visible.length} из '
                              '${filtered.length} найденных утверждений.'),
                          if (visible.isEmpty)
                            const Text('Для выбранного фильтра записей нет.'),
                          for (final claim in visible)
                            _assertionCard(claim, evidence),
                          if (pages > 1)
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton(
                                  key: const Key('source-editor-prev'),
                                  onPressed: page == 0
                                      ? null : () => setState(() => _page--),
                                  child: const Text('Назад'),
                                ),
                                Text('Страница ${page + 1} из $pages'),
                                OutlinedButton(
                                  key: const Key('source-editor-next'),
                                  onPressed: page + 1 >= pages
                                      ? null : () => setState(() => _page++),
                                  child: const Text('Дальше'),
                                ),
                              ],
                            ),
                          const SizedBox(height: 14),
                          SourceCharacterDossierPanel(
                            key: ValueKey('character-dossiers-${widget.index.sourceFingerprint}'),
                            index: widget.index,
                            graph: graph,
                            catalog: catalog,
                            editorial: editorial,
                            checkpointRepository: widget.relationsRepository,
                            refreshRevision: _relationRevision,
                          ),
                          const SizedBox(height: 14),
                          SourceRelationsReviewPanel(
                            key: ValueKey('relations-${widget.index.sourceFingerprint}'),
                            index: widget.index,
                            graph: graph,
                            checkpointRepository: widget.relationsRepository,
                            onReviewSaved: () => setState(
                                () => _relationRevision++),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
