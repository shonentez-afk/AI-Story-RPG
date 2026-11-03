import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'book_isolate_workers.dart';
import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_character_dossiers.dart';
import 'source_evidence_graph.dart';
import 'source_relation_review.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';

SourceCharacterDossierIndex _deriveCharacterDossiers((
  BookSourceIndex,
  SourceEvidenceGraph,
  SourceRelationReviewSession,
  SourceSemanticCatalog,
  SemanticEditorialReviewSession,
) request) => SourceCharacterDossierIndex.build(
    request.$1, request.$2, request.$3, request.$4, request.$5);

/// Read-only character dossier over existing source and review decisions.
/// SourceRelationsReviewPanel is the ONLY place that writes identity decisions.
class SourceCharacterDossierPanel extends StatefulWidget {
  const SourceCharacterDossierPanel({
    super.key, required this.index, required this.graph,
    required this.catalog, required this.editorial,
    this.checkpointRepository, this.refreshRevision = 0,
    this.sessionBuilder, this.sessionDecoder, this.dossierBuilder,
  });

  final BookSourceIndex index;
  final SourceEvidenceGraph graph;
  final SourceSemanticCatalog catalog;
  final SemanticEditorialReviewSession editorial;
  final SourceAnalysisCheckpointRepository? checkpointRepository;
  final int refreshRevision;
  final Future<SourceRelationReviewSession> Function(
      BookSourceIndex, SourceEvidenceGraph)? sessionBuilder;
  final Future<SourceRelationReviewSession> Function(
      BookSourceIndex, SourceEvidenceGraph, String)? sessionDecoder;
  final Future<SourceCharacterDossierIndex> Function(
      BookSourceIndex, SourceEvidenceGraph, SourceRelationReviewSession,
      SourceSemanticCatalog, SemanticEditorialReviewSession)? dossierBuilder;

  @override
  State<SourceCharacterDossierPanel> createState() =>
      _SourceCharacterDossierPanelState();
}

class _SourceCharacterDossierPanelState
    extends State<SourceCharacterDossierPanel> {
  late final SourceAnalysisCheckpointRepository _repository =
      widget.checkpointRepository ??
          const FileSourceAnalysisCheckpointRepository(
            scope: SourceCheckpointScope.identityRelations,
          );
  SourceCharacterDossierIndex? _dossiers;
  bool _opened = false;
  bool _busy = false;
  String? _error;
  String _search = '';
  int _page = 0;
  int _generation = 0;
  final Set<String> _details = {};
  static const _pageSize = 8;

  @override
  void didUpdateWidget(covariant SourceCharacterDossierPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index.sourceFingerprint != widget.index.sourceFingerprint ||
        !identical(oldWidget.graph, widget.graph)) {
      _generation++;
      _opened = false;
      _dossiers = null;
      _details.clear();
      _search = '';
      _page = 0;
      _error = null;
      return;
    }
    if (_opened &&
        (oldWidget.refreshRevision != widget.refreshRevision ||
            !identical(oldWidget.catalog, widget.catalog) ||
            !identical(oldWidget.editorial, widget.editorial))) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _opened = true;
      _busy = true;
      _error = null;
    });
    try {
      final raw = await _repository.read(widget.index.sourceFingerprint);
      final session = raw == null
          ? widget.sessionBuilder == null
              ? await createRelationReviewInWorker(widget.index, widget.graph)
              : await widget.sessionBuilder!(widget.index, widget.graph)
          : widget.sessionDecoder == null
              ? await decodeRelationReviewInWorker(widget.index, widget.graph, raw)
              : await widget.sessionDecoder!(widget.index, widget.graph, raw);
      final dossiers = widget.dossierBuilder == null
          ? await compute(_deriveCharacterDossiers,
              (widget.index, widget.graph, session,
                  widget.catalog, widget.editorial),
              debugLabel: 'story-character-dossiers')
          : await widget.dossierBuilder!(widget.index, widget.graph, session,
              widget.catalog, widget.editorial);
      if (!mounted || generation != _generation) return;
      setState(() {
        _dossiers = dossiers;
        _page = 0;
        _details.clear();
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _dossiers = null;
          _error = 'Карточки не открыты: $error. '
              'Книга, отношения, игры и сохранения не изменены.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  String _identityStatus(IdentityDecision decision) => switch (decision) {
    IdentityDecision.unresolved => 'Не проверено',
    IdentityDecision.same => 'Один персонаж (решение редактора)',
    IdentityDecision.different => 'Разные персонажи (решение редактора)',
  };

  String _verdictLabel(SemanticEditorialVerdict? decision) => switch (decision) {
    null => 'Гипотеза',
    SemanticEditorialVerdict.passageOnly => 'Только цитата',
    SemanticEditorialVerdict.canonCandidate => 'Кандидат канона',
    SemanticEditorialVerdict.disputed => 'Спорно',
    SemanticEditorialVerdict.rejected => 'Отклонено',
  };

  Widget _card(SourceCharacterDossier dossier) {
    final expanded = _details.contains(dossier.id);
    final mentions = expanded
        ? dossier.mentions : dossier.mentions.take(3).toList();
    final links = expanded
        ? dossier.identityHints : dossier.identityHints.take(3).toList();
    final aliases = expanded
        ? dossier.aliasHints : dossier.aliasHints.take(2).toList();
    final relationships = expanded
        ? dossier.relationshipHints
        : dossier.relationshipHints.take(2).toList();

    return Card(
      key: Key('dossier-card-${dossier.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dossier.labels.join(' / '),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Упоминаний: ${dossier.mentions.length} · '
                'проверенных цитат: ${dossier.confirmedQuotes} · '
                'главы ${dossier.firstChapter + 1}–${dossier.lastChapter + 1}'),
            const Text('Карточка — группа упоминаний, а не созданный NPC. '
                'Одинаковые имена не объединяются без решения редактора.'),
            const SizedBox(height: 8),
            Text('Цитаты', style: Theme.of(context).textTheme.titleSmall),
            for (final quote in mentions)
              Text('Глава ${quote.chapterIndex + 1} · '
                  '«${quote.label}» · ${quote.status.name}'),
            if (dossier.identityHints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Проверка личности и имён',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final edge in links)
                Text('${edge.hint.firstName} — ${edge.hint.secondName}: '
                    '${_identityStatus(edge.decision)}'),
            ],
            if (dossier.aliasHints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Подсказки псевдонимов',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final item in aliases)
                Text('${item.subject} / ${item.object} · '
                    'цитата, не подтверждённая личность'),
            ],
            if (dossier.relationshipHints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Возможные отношения по совпадению написания',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final relation in relationships)
                Text('Глава ${relation.chapterIndex + 1}: '
                    '${relation.assertion.subject} '
                    '${relation.assertion.predicate} '
                    '${relation.assertion.object} · '
                    '${_verdictLabel(relation.verdict)} · '
                    '«${relation.citation}»'),
              const Text('Совпадение имени не доказывает личность '
                  'или устойчивые отношения персонажей.'),
            ],
            if (dossier.mentions.length > 3 ||
                dossier.identityHints.length > 3 ||
                dossier.aliasHints.length > 2 ||
                dossier.relationshipHints.length > 2)
              TextButton.icon(
                key: Key('dossier-toggle-${dossier.id}'),
                onPressed: () => setState(() {
                  if (!_details.remove(dossier.id)) {
                    _details.add(dossier.id);
                  }
                }),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(expanded
                    ? 'Свернуть подробности'
                    : 'Показать все цитаты и связи'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _dossiers?.dossiers ?? const <SourceCharacterDossier>[];
    final search = _search.trim().toLowerCase();
    final filtered = items.where((d) => search.isEmpty ||
        d.labels.any((label) => label.toLowerCase().contains(search))).toList();
    final pages = filtered.isEmpty ? 1
        : (filtered.length + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(0, pages - 1).toInt();
    final visible = filtered.skip(page * _pageSize).take(_pageSize).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Карточки персонажей и псевдонимов',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        const Text('Карточки собираются из проверяемых цитат и уже '
            'сохранённых решений «один / разные». У них нет отдельных '
            'игровых данных и они не меняют историю. Возможны спойлеры.'),
        const SizedBox(height: 8),
        if (!_opened)
          OutlinedButton.icon(
            key: const Key('dossier-open'),
            onPressed: _load,
            icon: const Icon(Icons.people_outline),
            label: const Text('Показать карточки персонажей (спойлеры)'),
          )
        else ...[
          OutlinedButton.icon(
            key: const Key('dossier-refresh'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Перепроверить карточки и связи'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Проверяем упоминания и решения…'),
            ),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_dossiers != null && !_busy) ...[
            const SizedBox(height: 8),
            Text('Найдено ${_dossiers!.totalCharacterMentions} упоминаний · '
                '${_dossiers!.possibleCharacterGroups} отдельных групп · '
                '${_dossiers!.pendingIdentityHints} связей без решения. '
                'Группы не равны числу персонажей в книге.'),
            const SizedBox(height: 6),
            TextField(
              key: const Key('dossier-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Поиск имён и псевдонимов',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _search = value;
                _page = 0;
              }),
            ),
            const SizedBox(height: 6),
            Text('Карточек: ${filtered.length}'),
            if (filtered.isEmpty)
              const Text('По выбранному имени карточек нет.'),
            for (final item in visible) _card(item),
            if (pages > 1)
              Wrap(spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    key: const Key('dossier-prev'),
                    onPressed: page == 0
                        ? null : () => setState(() => _page--),
                    child: const Text('Назад'),
                  ),
                  Text('Страница ${page + 1} из $pages'),
                  OutlinedButton(
                    key: const Key('dossier-next'),
                    onPressed: page + 1 >= pages
                        ? null : () => setState(() => _page++),
                    child: const Text('Дальше'),
                  ),
                ],
              ),
          ],
        ],
      ],
    );
  }
}
