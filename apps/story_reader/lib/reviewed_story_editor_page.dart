import 'package:flutter/material.dart';
import 'preparation_editor_help.dart';

import 'book_source_index.dart';
import 'intermediate_story_blueprint.dart';
import 'native_private_bookworld_compiler.dart';
import 'reviewed_story_composer.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_evidence_graph.dart';
import 'source_semantic_catalog.dart';
import 'source_semantic_editorial_review.dart';
import 'story_evidence_review_session.dart';
import 'world_campaigns_page.dart';
import 'world_library_gateway.dart';

/// Human-authoring step after local text analysis. This deliberately creates
/// a SHORT, PRIVATE, CLASSIC adaptation from two explicitly approved quotes.
/// It is not a model-driven full-novel compiler and never promotes a quote
/// into canon merely because text indexing reached 100%.
class ReviewedStoryEditorPage extends StatefulWidget {
  const ReviewedStoryEditorPage({
    super.key,
    required this.index,
    required this.gateway,
    this.narrativeRepository,
    this.catalogRepository,
    this.editorialRepository,
    this.draftRepository,
  });

  final BookSourceIndex index;
  final WorldLibraryGateway gateway;
  final SourceAnalysisCheckpointRepository? narrativeRepository;
  final SourceAnalysisCheckpointRepository? catalogRepository;
  final SourceAnalysisCheckpointRepository? editorialRepository;
  final SourceAnalysisCheckpointRepository? draftRepository;

  @override
  State<ReviewedStoryEditorPage> createState() =>
      _ReviewedStoryEditorPageState();
}

class _ReviewedStoryEditorPageState extends State<ReviewedStoryEditorPage> {
  final _intro = TextEditingController();
  final _ending = TextEditingController();
  final _alternative = TextEditingController();
  final _canonChoice = TextEditingController(text: 'Следовать книге');
  final _alternateChoice = TextEditingController(text: 'Изменить судьбу');

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
  late final SourceAnalysisCheckpointRepository _draftStore =
      widget.draftRepository ??
      const FileSourceAnalysisCheckpointRepository(
          scope: SourceCheckpointScope.intermediateDraft);

  StoryEvidenceReviewSession? _narrativeSession;
  SourceSemanticCatalog? _catalog;
  SemanticEditorialReviewSession? _editorial;
  List<SourceSemanticAssertion> _available = const [];
  String? _openingId;
  String? _endingId;
  String? _error;
  String? _message;
  bool _loading = true;
  bool _working = false;
  bool _spoilers = false;
  bool _privateConsent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _intro, _ending, _alternative, _canonChoice, _alternateChoice,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _notice(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  Future<void> _load() async {
    if (mounted) setState(() {
      _loading = true;
      _error = null;
      _catalog = null;
      _narrativeSession = null;
      _editorial = null;
      _available = const [];
    });
    final fingerprint = widget.index.sourceFingerprint;
    try {
      final narrativeRaw = await _narrative.read(fingerprint);
      if (narrativeRaw == null) {
        throw const FormatException(
            'Сначала выполните локальную подготовку и проверку цитат.');
      }
      final narrative = StoryEvidenceReviewSession.decode(
          widget.index, narrativeRaw);
      if (narrative.scannedChunks != widget.index.chunks.length) {
        throw const FormatException(
            'Не все фрагменты книги проверены на события.');
      }
      final rawCatalog = await _catalogStore.read(fingerprint);
      if (rawCatalog == null) {
        throw const FormatException(
            'Смысловой каталог ещё не готов. Завершите локальную подготовку.');
      }
      final catalog = SourceSemanticCatalog.decode(
          widget.index, narrative.graph, rawCatalog);
      final rawEditorial = await _editorStore.read(fingerprint);
      final editorial = rawEditorial == null
          ? SemanticEditorialReviewSession.create(widget.index, catalog)
          : SemanticEditorialReviewSession.decode(
              widget.index, narrative.graph, catalog, rawEditorial);
      final records = {
        for (final e in narrative.graph.records) e.id: e,
      };
      final available = catalog.assertions.where((claim) =>
          (claim.kind == SemanticAssertionKind.event ||
              claim.kind == SemanticAssertionKind.fact) &&
          claim.evidenceIds.isNotEmpty &&
          claim.evidenceIds.every((id) {
            final source = records[id];
            return source != null &&
                source.status == EvidenceStatus.confirmed &&
                source.spoilerGate == EvidenceSpoilerGate.chapter &&
                source.visibleAfterChapter == source.chapterIndex;
          })).toList();
      final draftRaw = await _draftStore.read(fingerprint);
      final draft = draftRaw == null ? null
          : IntermediateStoryBlueprint.decode(draftRaw);
      if (draft != null && draft.sourceFingerprint != fingerprint) {
        throw const FormatException('Черновик из другой редакции книги');
      }
      if (!mounted) return;
      setState(() {
        _narrativeSession = narrative;
        _catalog = catalog;
        _editorial = editorial;
        _available = available;
        if (draft != null && draft.scenes.length == 3 &&
            draft.scenes.first.assertionIds.length == 1 &&
            draft.scenes[1].assertionIds.length == 1) {
          final openingId = draft.scenes.first.assertionIds.single;
          final endingId = draft.scenes[1].assertionIds.single;
          _openingId = available.any((a) => a.id == openingId)
              ? openingId : null;
          _endingId = available.any((a) => a.id == endingId)
              ? endingId : null;
          _intro.text = draft.scenes.first.text;
          _ending.text = draft.scenes[1].text;
          _alternative.text = draft.scenes[2].text;
          if (draft.scenes.first.choices.length == 2) {
            _canonChoice.text = draft.scenes.first.choices[0].label;
            _alternateChoice.text = draft.scenes.first.choices[1].label;
          }
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = 'Редактор не готов: $error';
        _loading = false;
      });
    }
  }

  String _label(SourceSemanticAssertion assertion) {
    final parts = [
      assertion.subject, assertion.predicate, assertion.object,
    ].where((value) => value.trim().isNotEmpty).join(' ');
    return parts.length > 95 ? '${parts.substring(0, 95)}…' : parts;
  }

  Future<void> _approve(String? assertionId) async {
    if (_working || assertionId == null || _catalog == null ||
        _editorial == null) return;
    setState(() { _working = true; _error = null; });
    try {
      final next = _editorial!.decide(_catalog!, assertionId,
          SemanticEditorialVerdict.canonCandidate);
      await _editorStore.write(widget.index.sourceFingerprint, next.encode());
      if (mounted) setState(() {
        _editorial = next;
        _message = 'Факт подтверждён редактором для частного сценария.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось сохранить решение: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  IntermediateStoryBlueprint _compose() {
    final narrative = _narrativeSession;
    final catalog = _catalog;
    final editorial = _editorial;
    if (narrative == null || catalog == null || editorial == null ||
        _openingId == null || _endingId == null) {
      throw const FormatException('Выберите два подтверждённых события');
    }
    return ReviewedStoryComposer.compose(
      index: widget.index, evidence: narrative.graph,
      catalog: catalog, editorial: editorial,
      openingAssertionId: _openingId!, endingAssertionId: _endingId!,
      openingText: _intro.text, endingText: _ending.text,
      alternateEndingText: _alternative.text,
      followBookChoice: _canonChoice.text,
      changeFateChoice: _alternateChoice.text,
    );
  }

  Future<IntermediateStoryBlueprint?> _saveDraft() async {
    try {
      final draft = _compose();
      await _draftStore.write(widget.index.sourceFingerprint, draft.encode());
      if (mounted) _notice('Проверенный частный черновик сохранён.');
      return draft;
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Сценарий пока нельзя сохранить: $error');
      return null;
    }
  }

  Future<void> _saveOnly() async {
    if (_working) return;
    setState(() { _working = true; _error = null; });
    try {
      await _saveDraft();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _compileAndOpen() async {
    if (_working || !_privateConsent) return;
    setState(() { _working = true; _error = null; });
    try {
      final draft = await _saveDraft();
      if (draft == null) return;
      final bytes = await compileReviewedPrivateBookworldInWorker(
          widget.index, _narrativeSession!.graph,
          _catalog!, _editorial!, draft);
      final installed = await widget.gateway.install(bytes);
      if (!mounted) return;
      _notice('Приватный .bworld проверен и добавлен в библиотеку.');
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldCampaignsPage(
            world: installed, gateway: widget.gateway),
      ));
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'Сборка или импорт не выполнены: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _claimSelection(
      String title, String? value, ValueChanged<String?> onChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: value,
          items: [
            for (final claim in _available)
              DropdownMenuItem(
                value: claim.id,
                child: Text(_label(claim), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _working ? null : onChange,
          decoration: const InputDecoration(
              border: OutlineInputBorder(), hintText: 'Выберите цитату'),
        ),
        const SizedBox(height: 6),
        if (value != null)
          OutlinedButton.icon(
            onPressed: _working ? null : () => _approve(value),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(_editorial?.verdicts[value] ==
                SemanticEditorialVerdict.canonCandidate
                ? 'Подтверждено редактором'
                : 'Подтвердить утверждение как основу сцены'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _input(String title, TextEditingController controller,
      {int maxLines = 3}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !_working,
      maxLines: maxLines,
      maxLength: maxLines > 1 ? 6000 : 300,
      decoration: InputDecoration(
        labelText: title, border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Редактор частного сценария')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.index.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Этот редактор создаёт короткую ЛИЧНУЮ адаптацию '
                    'из двух подтверждённых событий и одного авторского '
                    'варианта. Это не автоматическая RPG по всей книге. '
                    'Здесь нет ИИ и отправки текста в сеть.',
                  ),
                  const SizedBox(height: 12),
                  const PreparationEditorHelp(
                    purpose: 'Самый короткий путь от проверенных событий к личной игре.',
                    steps: [
                      'Выберите начало и завершение из проверенных событий книги.',
                      'Напишите вариант, при котором решение игрока меняет исход.',
                      'Проверьте два варианта финала, затем соберите и установите игру.',
                    ],
                    result: 'короткая офлайн-RPG с двумя исходами.',
                    next: 'для дополнительных сцен откройте расширенный конструктор.',
                  ),
                  if (_error != null)
                    Text(_error!, style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                  if (_message != null) Text(_message!),
                  if (_catalog == null) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Проверить подготовку заново'),
                    ),
                  ] else ...[
                    Text('Проверенных событий для выбора: '
                        '${_available.length}. Необработанные цитаты '
                        'не могут стать сценами.'),
                    const SizedBox(height: 8),
                    if (!_spoilers)
                      OutlinedButton.icon(
                        key: const Key('editor-show-spoilers'),
                        onPressed: () => setState(() => _spoilers = true),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Показать события (спойлеры)'),
                      )
                    else ...[
                      _claimSelection('Исходная сцена', _openingId,
                          (value) => setState(() => _openingId = value)),
                      _claimSelection('Финальное событие книги', _endingId,
                          (value) => setState(() => _endingId = value)),
                      _input('Текст исходной сцены', _intro),
                      _input('Текст канонического финала', _ending),
                      _input('Текст альтернативного финала (написан вами)',
                          _alternative),
                      _input('Действие: по книге', _canonChoice, maxLines: 1),
                      _input('Действие: изменить судьбу', _alternateChoice,
                          maxLines: 1),
                      CheckboxListTile(
                        key: const Key('editor-private-consent'),
                        value: _privateConsent,
                        onChanged: _working ? null :
                            (next) => setState(
                                () => _privateConsent = next ?? false),
                        title: const Text(
                            'Создать только личную адаптацию'),
                        subtitle: const Text(
                            'Это не даёт права публиковать чужую книгу '
                            'или распространять её текст.'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                          key: const Key('editor-save-draft'),
                          onPressed: _working ? null : _saveOnly,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Сохранить сценарий'),
                        ),
                        FilledButton.icon(
                          key: const Key('editor-compile-private'),
                          onPressed: _working || !_privateConsent
                              ? null : _compileAndOpen,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Собрать и открыть личную RPG'),
                        ),
                      ]),
                      if (_working) const Padding(
                        padding: EdgeInsets.all(12),
                        child: LinearProgressIndicator(),
                      ),
                    ],
                  ],
                ],
              ),
            )),
          ),
  );
}
