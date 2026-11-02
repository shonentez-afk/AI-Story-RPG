import 'dart:async';

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_evidence_graph.dart';
import 'source_narrative_chronology.dart';
import 'source_relation_review.dart';
import 'book_isolate_workers.dart';

/// Nested inside the existing spoiler-gated evidence panel.
/// The user opens it explicitly. Decisions live in a separate private file.
class SourceRelationsReviewPanel extends StatefulWidget {
  const SourceRelationsReviewPanel({
    super.key,
    required this.index,
    required this.graph,
    this.checkpointRepository,
    this.sessionBuilder,
    this.sessionDecoder,
    this.checkpointEncoder,
    this.chronologyBuilder,
    this.relationDecider,
  });

  final BookSourceIndex index;
  final SourceEvidenceGraph graph;
  final SourceAnalysisCheckpointRepository? checkpointRepository;
  final Future<SourceRelationReviewSession> Function(
      BookSourceIndex, SourceEvidenceGraph)? sessionBuilder;
  final Future<SourceRelationReviewSession> Function(
      BookSourceIndex, SourceEvidenceGraph, String)? sessionDecoder;
  final Future<String> Function(SourceRelationReviewSession)? checkpointEncoder;
  final Future<SourceNarrativeChronology> Function(
      BookSourceIndex, SourceEvidenceGraph)? chronologyBuilder;
  final Future<SourceRelationReviewSession> Function(
      BookSourceIndex, SourceEvidenceGraph,
      SourceRelationReviewSession, String, IdentityDecision)? relationDecider;

  @override
  State<SourceRelationsReviewPanel> createState() =>
      _SourceRelationsReviewPanelState();
}

class _SourceRelationsReviewPanelState
    extends State<SourceRelationsReviewPanel> {
  late final SourceAnalysisCheckpointRepository _store =
      widget.checkpointRepository ??
      const FileSourceAnalysisCheckpointRepository(
        scope: SourceCheckpointScope.identityRelations,
      );

  SourceRelationReviewSession? _session;
  SourceNarrativeChronology? _chronology;
  bool _opened = false;
  bool _busy = false;
  bool _stale = false;
  String? _error;

  @override
  void didUpdateWidget(covariant SourceRelationsReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index.sourceFingerprint != widget.index.sourceFingerprint ||
        !identical(oldWidget.graph, widget.graph)) {
      // A new or rejected citation invalidates the current review snapshot.
      // Require an explicit reload, never issue decisions against old data.
      _stale = true;
    }
  }

  Future<SourceRelationReviewSession> _newSession() async {
    final worker = widget.sessionBuilder;
    if (worker != null) return worker(widget.index, widget.graph);
    return createRelationReviewInWorker(widget.index, widget.graph);
  }

  Future<SourceNarrativeChronology> _newChronology() async {
    final worker = widget.chronologyBuilder;
    if (worker != null) return worker(widget.index, widget.graph);
    return buildSourceChronologyInWorker(widget.index, widget.graph);
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _opened = true;
      _busy = true;
      _error = null;
      _session = null;
      _chronology = null;
    });
    try {
      final raw = await _store.read(widget.index.sourceFingerprint);
      final decoder = widget.sessionDecoder;
      final restored = raw == null ? await _newSession()
          : decoder == null
              ? await decodeRelationReviewInWorker(widget.index, widget.graph, raw)
              : await decoder(widget.index, widget.graph, raw);
      final chronology = await _newChronology();
      if (mounted) {
        setState(() {
          _session = restored;
          _chronology = chronology;
          _stale = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() {
        _stale = true;
        _error = 'Связи не загружены: $error. '
            'Исходная книга и сохранения не изменены.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persist(SourceRelationReviewSession updated) async {
    final encoder = widget.checkpointEncoder;
    final raw = encoder == null
        ? await encodeRelationReviewInWorker(updated)
        : await encoder(updated);
    await _store.write(widget.index.sourceFingerprint, raw);
    if (mounted) setState(() => _session = updated);
  }

  Future<void> _decideRelation(
      IdentityRelationReview relation, IdentityDecision choice) async {
    final current = _session;
    if (_busy || _stale || current == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final worker = widget.relationDecider;
      final updated = worker == null
          ? await decideRelationInWorker(widget.index, widget.graph, current, relation.hint.id, choice)
          : await worker(widget.index, widget.graph,
              current, relation.hint.id, choice);
      await _persist(updated);
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Решение не сохранено: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decideTime(int before, ChapterTimeDecision choice) async {
    final current = _session;
    if (_busy || _stale || current == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = current.decideChapter(widget.index, before, choice);
      await _persist(updated);
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Порядок глав не сохранён: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Сбросить связи и хронологию?'),
        content: const Text('Будут удалены только решения SAME/DIFFERENT '
            'и ручные отметки порядка глав. Книга, доказательства, '
            'решения о цитатах и игровые сохранения останутся.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить связи'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // A corrupted/stale relation checkpoint can be deleted independently.
      await _store.delete(widget.index.sourceFingerprint);
      final initial = await _newSession();
      final chronology = await _newChronology();
      if (mounted) setState(() {
        _session = initial;
        _chronology = chronology;
        _stale = false;
      });
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Не удалось сбросить связи: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _decision(IdentityDecision choice) => switch (choice) {
    IdentityDecision.unresolved => 'Не определено',
    IdentityDecision.same => 'Один персонаж / объект',
    IdentityDecision.different => 'Разные персонажи / объекты',
  };
  String _time(ChapterTimeDecision choice) => switch (choice) {
    ChapterTimeDecision.unknown => 'Неизвестно',
    ChapterTimeDecision.forward => 'Далее по времени',
    ChapterTimeDecision.flashback => 'Флешбэк',
    ChapterTimeDecision.parallel => 'Параллельные события',
  };

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final session = _session;
    final chronology = _chronology;
    if (!_opened) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 28),
          Text('Имена и порядок событий', style: style.titleMedium),
          const SizedBox(height: 6),
          const Text('Найденные совпадения имён могут относиться '
              'к разным людям. Откройте редактор для ручных решений.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.route_outlined),
            label: const Text('Открыть связи и хронологию'),
          ),
        ],
      );
    }
    final evidence = {for (final e in widget.graph.records) e.id: e};
    final relations = session?.proposedRelations.take(4).toList()
        ?? <IdentityRelationReview>[];
    final chapterOrder = session?.chapterOrder.take(3).toList()
        ?? <ChapterTemporalReview>[];
    final observations = chronology?.observations.take(6).toList()
        ?? <NarrativeObservation>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Text('Имена и порядок событий', style: style.titleMedium),
        const SizedBox(height: 6),
        const Text('Решения редактора об упоминаниях, а не слияние '
            'игровых NPC. Порядок чтения глав не доказывает хронологию.'),
        if (_busy && session == null) const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Загружаем проверяемые связи…'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: colors.error)),
        ],
        if (_stale) const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Исходные сведения изменились: обновите '
              'проверку связей перед новым решением.'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Обновить связи'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Сбросить связи'),
          ),
        ]),
        if (session != null && !_stale) ...[
          const SizedBox(height: 10),
          Text('Возможных пар: ${session.hints.length} · '
              'не определено: ${session.unresolvedCount}'),
          if (relations.isEmpty)
            const Text('Пока нет предложенных связей. '
                'Возможны другие варианты имён, не распознанные '
                'ограниченным локальным анализом.'),
          for (final relation in relations)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${relation.hint.firstName} — '
                        '${relation.hint.secondName}',
                        style: style.titleSmall),
                    Text(relation.hint.kind == IdentityHintKind.explicitAlias
                        ? 'Явное прозвище в источнике'
                        : 'Повтор похожего имени в разных главах'),
                    const SizedBox(height: 4),
                    Text('Решение: ${_decision(relation.decision)}'),
                    if (evidence[relation.hint.firstId]?.status !=
                            EvidenceStatus.confirmed ||
                        evidence[relation.hint.secondId]?.status !=
                            EvidenceStatus.confirmed)
                      const Text('Сначала подтвердите обе цитаты '
                          'в разделе утверждений.'),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      OutlinedButton(
                        onPressed: _busy ||
                            (evidence[relation.hint.firstId]?.status !=
                                  EvidenceStatus.confirmed ||
                             evidence[relation.hint.secondId]?.status !=
                                  EvidenceStatus.confirmed)
                            ? null : () => _decideRelation(
                                relation, IdentityDecision.same),
                        child: const Text('Один'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ||
                            (evidence[relation.hint.firstId]?.status !=
                                  EvidenceStatus.confirmed ||
                             evidence[relation.hint.secondId]?.status !=
                                  EvidenceStatus.confirmed)
                            ? null : () => _decideRelation(
                                relation, IdentityDecision.different),
                        child: const Text('Разные'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _decideRelation(
                            relation, IdentityDecision.unresolved),
                        child: const Text('Не определено'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Порядок событий между главами', style: style.titleSmall),
          const Text('Это отдельные решения человека. '
              'Автоматически порядок внутри мира не определяется.'),
          for (final order in chapterOrder)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Глава ${order.beforeChapter + 1} → '
                      'глава ${order.afterChapter + 1}'),
                  DropdownButton<ChapterTimeDecision>(
                    value: order.decision,
                    isExpanded: true,
                    onChanged: _busy ? null :
                        (value) {
                          if (value != null) {
                            unawaited(_decideTime(order.beforeChapter, value));
                          }
                        },
                    items: [
                      for (final choice in ChapterTimeDecision.values)
                        DropdownMenuItem(
                          value: choice,
                          child: Text(_time(choice)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text('Последовательность текстовых свидетельств',
              style: style.titleSmall),
          const Text('Не утверждает действительную хронологию '
              'или достоверность заявлений.'),
          if (observations.isEmpty)
            const Text('Пока не найдены поддерживаемые конструкции.'),
          for (final item in observations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Глава ${item.evidence.chapterIndex + 1}: '
                '«${item.evidence.label}» · '
                '${item.polarity == ClaimPolarity.negated
                    ? "отрицание" : "утверждение"} · '
                '${switch (item.voice) {
                    ClaimVoice.narratorCandidate => "текст повествования",
                    ClaimVoice.reportedSpeech => "чьи-то слова",
                    ClaimVoice.uncertain => "неуверенное высказывание",
                  }}',
              ),
            ),
        ],
      ],
    );
  }
}
