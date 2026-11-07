import 'dart:async';

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'npc_campaign_writing_session.dart';
import 'reviewed_hero_role.dart';
import 'story_plan_trial_compiler.dart';
import 'whole_book_npc_campaign.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';
import 'zai_npc_campaign_writing.dart';
import 'zai_semantic_preview.dart';

/// One source/authoring/AI/review/install workflow. All installed gameplay
/// remains in the existing rich-v3 runtime; opening the editor never posts.
class WholeBookNpcCampaignPage extends StatefulWidget {
  const WholeBookNpcCampaignPage({
    super.key, required this.index, required this.book, required this.bookMap,
    required this.draft, required this.gateway, this.roleCatalog,
    this.draftStore, this.aiWriter,
  });
  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final MultiActStoryPlanDraft draft;
  final WorldLibraryGateway gateway;
  final ReviewedHeroRoleCatalog? roleCatalog;
  final NpcWritingStore? draftStore;
  final ZaiNpcCampaignWriting? aiWriter;
  @override
  State<WholeBookNpcCampaignPage> createState() => _WholeBookNpcCampaignPageState();
}

class _ConversationEdit {
  _ConversationEdit(NpcWritingEdit saved)
      : player = TextEditingController(text: saved.playerLine),
        npc = TextEditingController(text: saved.npcLine),
        dependencies = [...saved.dependencies], uncertainty = saved.uncertainty,
        origin = saved.origin, noSuggestion = saved.noSuggestion;
  final TextEditingController player, npc;
  final List<String> dependencies;
  String uncertainty, origin;
  bool noSuggestion;
  void changed() { uncertainty = ''; origin = 'manual'; noSuggestion = false; }
  void dispose() { player.dispose(); npc.dispose(); }
}

class _WholeBookNpcCampaignPageState extends State<WholeBookNpcCampaignPage>
    with WidgetsBindingObserver {
  WholeBookNpcSourcePlan? _source;
  StoryPlanTrialCompilation? _base;
  List<ReviewedHeroRole> _roles = const [];
  List<BookwideNpcConversationCandidate> _candidates = const [];
  final _edits = <String, _ConversationEdit>{};
  late final NpcWritingStore _store = widget.draftStore ?? NpcWritingStore();
  late final ZaiNpcCampaignWriting _writer = widget.aiWriter ?? ZaiNpcCampaignWriting();
  NpcWritingCatalog? _catalog;
  NpcWritingSession? _session;
  ReviewedBookwideNpcCampaign? _approval;
  ZaiPreviewCancellation? _cancellation;
  Timer? _saveTimer;
  Future<void> _saveTail = Future<void>.value();
  int _editGeneration = 0;
  bool _quotesReviewed = false, _privateFiction = false, _campaignConfirmed = false;
  bool _working = false, _dirty = false, _storageBlocked = false, _allowLeave = false;
  String? _error;
  ReviewedHeroRoleCatalog get _roleCatalog => widget.roleCatalog ?? const ReviewedHeroRoleCatalog();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _source = WholeBookNpcSourcePlan.fromBook(
        index: widget.index, book: widget.book,
        bookMap: widget.bookMap, draft: widget.draft,
      );
    } catch (error) { _error = error.toString(); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _dirty && !_working) {
      unawaited(_flush().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancellation?.cancel();
    _saveTimer?.cancel();
    if (_dirty && !_storageBlocked) {
      // Capture field values before disposing controllers; repository writes
      // do not retain Widget/Context or implicitly authorize cloud calls.
      unawaited(_flush().catchError((Object _) {}));
    }
    for (final edit in _edits.values) { edit.dispose(); }
    super.dispose();
  }

  void _invalidate() { _approval = null; _campaignConfirmed = false; }
  List<NpcWritingEdit> _snapshot() => [
    for (final entry in _edits.entries) NpcWritingEdit(
      id: entry.key, playerLine: entry.value.player.text,
      npcLine: entry.value.npc.text, dependencies: entry.value.dependencies,
      uncertainty: entry.value.uncertainty, origin: entry.value.origin,
      noSuggestion: entry.value.noSuggestion,
    ),
  ];

  void _touch() {
    _invalidate(); _dirty = true; _editGeneration++; _error = null;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450),
        () => unawaited(_flush().catchError((Object _) {})));
  }

  Future<void> _flush() {
    _saveTimer?.cancel();
    final catalog = _catalog;
    if (!_dirty || catalog == null || _session == null) return _saveTail;
    if (_storageBlocked) return Future<void>.error(
        const FormatException('Сохранение заблокировано до проверки старого файла.'));
    final snapshot = _snapshot();
    final generation = _editGeneration;
    final operation = _saveTail.then((_) async {
      final saved = await _store.save(catalog,
          edits: snapshot, expectedRevision: _session!.revision);
      _session = saved;
      if (mounted) setState(() {
        if (_editGeneration == generation) _dirty = false;
      });
    });
    _saveTail = operation.catchError((Object error) {
      if (mounted) setState(() => _error =
          'Черновик ещё не сохранён: $error. Текст в редакторе не удалён.');
    });
    return operation;
  }

  void _restore(NpcWritingSession session) {
    for (final edit in _edits.values) { edit.dispose(); }
    _edits.clear();
    for (final e in session.edits.values) { _edits[e.id] = _ConversationEdit(e); }
    _session = session; _dirty = false; _invalidate();
  }

  Future<void> _leave() async {
    if (_working) { _cancellation?.cancel(); return; }
    try {
      await _flush();
      if (!mounted) return;
      setState(() => _allowLeave = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (_) { /* Error is displayed; never discard an unsaved editor. */ }
  }

  Future<void> _prepare() async {
    final source = _source;
    if (source == null || !_quotesReviewed || !_privateFiction || _working) return;
    setState(() { _working = true; _error = null; _invalidate(); });
    try {
      await _flush();
      final roles = await _roleCatalog.load(widget.index);
      final candidates = BookwideNpcCampaignAuthoring.discover(
          source: source, currentReviewedRoles: roles);
      if (candidates.isEmpty) throw const FormatException(
          'Нужны подтверждённые карточки NPC с упоминаниями в двух включённых событиях.');
      final catalog = NpcWritingCatalog(source: source, candidates: candidates);
      _catalog = catalog;
      NpcWritingSession saved;
      try { saved = await _store.load(catalog); }
      catch (_) { _storageBlocked = true; rethrow; }
      final base = await source.compileBase(
        approvedPlanDigest: source.planDigest,
        allShownQuotesReviewed: _quotesReviewed, privateFictionConfirmed: _privateFiction,
      );
      if (!mounted) return;
      setState(() {
        _base = base; _roles = roles; _candidates = candidates;
        _storageBlocked = false; _restore(saved);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally { if (mounted) setState(() => _working = false); }
  }

  void _toggle(BookwideNpcConversationCandidate c, bool selected) {
    if (_working || _storageBlocked) return;
    setState(() {
      if (selected) {
        if (_edits.length >= 32) { _error = 'В одном пакете допустимо до 32 разговоров.'; return; }
        _edits.putIfAbsent(c.id, () => _ConversationEdit(NpcWritingEdit(id: c.id)));
      } else {
        _edits.remove(c.id)?.dispose();
        for (final edit in _edits.values) { edit.dependencies.remove(c.id); }
      }
      _touch();
    });
  }

  Future<void> _reset() async {
    final catalog = _catalog;
    if (catalog == null || _working) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить только этот авторский черновик?'),
      content: const Text('Будут удалены выбранные встречи и написанные реплики этой '
          'редакции. Книга, карточки NPC и сохранённые игры останутся.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить черновик'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      _saveTimer?.cancel(); await _saveTail;
      await _store.reset(catalog, confirmed: true);
      final empty = await _store.load(catalog);
      if (mounted) setState(() { _restore(empty); _storageBlocked = false; _error = null; });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _generate() async {
    if (_working || _storageBlocked || _catalog == null || _session == null) return;
    try {
      await _flush();
      if (!mounted) return;
      final request = NpcWritingRequest.prepare(_catalog!, _session!);
      var checked = false;
      final consent = await showDialog<bool>(context: context, builder: (ctx) =>
        StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
          title: const Text('Передать показанные фрагменты в Z.ai?'),
          content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Новых разговоров: ${request.candidateCount}. Запросов: '
                  '${request.requestCount}, с повторами — не более ${request.maximumAttempts}. '
                  'Готовые и вручную изменённые реплики не отправляются повторно. '
                  'Применяются условия вашего аккаунта Z.ai.'),
              const Text('Ни ключ, ни сохранения игры не включены в контекст. '
                  'ИИ предложит текст, но не изменит правила игры и не одобрит его за вас.'),
              ExpansionTile(title: const Text('Точные данные для отправки'),
                children: [SelectableText(request.shownText)]),
              CheckboxListTile(key: const Key('npc-writing-cloud-consent'), value: checked,
                title: const Text('Разрешаю отправить именно эти цитаты и личности'),
                onChanged: (value) => refresh(() => checked = value == true)),
            ],
          ))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(key: const Key('npc-writing-cloud-send'),
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Подготовить черновики')),
          ],
        )),
      );
      if (consent != true || !mounted) return;
      setState(() { _working = true; _error = null; _invalidate(); });
      final freshRoles = await _roleCatalog.load(widget.index);
      final fresh = NpcWritingCatalog(source: _source!, candidates:
          BookwideNpcCampaignAuthoring.discover(source: _source!, currentReviewedRoles: freshRoles));
      if (fresh.digest != _catalog!.digest) throw const FormatException(
          'После просмотра изменились карточки NPC. Отправка отменена.');
      _cancellation = ZaiPreviewCancellation();
      await _writer.generate(
        catalog: fresh, store: _store, request: request,
        approvedDigest: request.approvalDigest, explicitCloudConsent: true,
        cancellation: _cancellation,
        onSaved: (saved) async { if (mounted) setState(() => _restore(saved)); },
      );
    } catch (error) {
      // Completed batches remain durable even if a later network operation
      // failed. Do not erase manual text or resurrect a persisted approval.
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _cancellation = null;
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _review() async {
    if (_working || _base == null || _source == null || _storageBlocked) return;
    try {
      await _flush();
      final edits = _snapshot();
      if (edits.any((e) => !e.complete)) throw const FormatException(
          'Заполните обе реплики каждого выбранного разговора или снимите его выбор.');
      final review = BookwideNpcCampaignAuthoring.review(
        source: _source!, verifiedBaseArchive: _base!.archive,
        currentReviewedRoles: _roles, selectedDrafts: edits.map((e) => e.toDraft()).toList(),
      );
      if (mounted) setState(() { _approval = review; _campaignConfirmed = false; _error = null; });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
  }

  Future<void> _start() async {
    final approval = _approval;
    final source = _source;
    if (_working || approval == null || source == null || !_campaignConfirmed ||
        !_quotesReviewed || !_privateFiction || _storageBlocked) return;
    setState(() { _working = true; _error = null; });
    try {
      await _flush();
      final built = await BookwideNpcCampaignAuthoring.compile(
        source: source, approval: approval,
        freshReviewedRoles: await _roleCatalog.load(widget.index),
        approvedDigest: approval.approvalDigest,
        explicitlyConfirmedPrivateFiction: _campaignConfirmed,
      );
      if (!mounted) return;
      final installed = await widget.gateway.install(built.archive);
      if (installed.archiveHash != built.archiveSha256) throw const FormatException(
          'Установленный мир отличается от проверенного.');
      final campaignId = await widget.gateway.start(installed.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldPlayPage(gateway: widget.gateway, campaignId: campaignId)));
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось начать кампанию: $error. '
          'Исходная книга, черновик и прежние игры сохранены.');
    } finally { if (mounted) setState(() => _working = false); }
  }

  Widget _conversation(BookwideNpcConversationCandidate c) {
    final edit = _edits[c.id];
    final earlier = _candidates.where((other) => other.id != c.id &&
        _edits.containsKey(other.id) &&
        other.firstEvent.narrativePosition < c.firstEvent.narrativePosition).toList();
    final enabled = !_working && !_storageBlocked;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CheckboxListTile(key: ValueKey('whole-npc-select-${c.id}'), value: edit != null,
          onChanged: enabled ? (value) => _toggle(c, value == true) : null,
          title: Text(c.role.displayName),
          subtitle: Text('Главы ${c.firstEvent.source.chapterIndex + 1} → '
              '${c.responseEvent.source.chapterIndex + 1}')),
        ExpansionTile(title: const Text('Точные цитаты для встречи и ответа'), children: [
          SelectableText(c.firstEvent.source.quote), const SizedBox(height: 8),
          SelectableText(c.responseEvent.source.quote),
        ]),
        if (edit != null) ...[
          if (edit.origin == 'ai_draft') Text(edit.noSuggestion
              ? 'ИИ не предложил разговор. ${edit.uncertainty}'
              : 'Черновик ИИ — проверьте смысл. ${edit.uncertainty}'),
          TextField(key: ValueKey('whole-npc-player-${c.id}'), controller: edit.player,
            enabled: enabled, maxLength: 400,
            decoration: const InputDecoration(labelText: 'Игровая реплика героя'),
            onChanged: (_) => setState(() { edit.changed(); _touch(); })),
          TextField(key: ValueKey('whole-npc-line-${c.id}'), controller: edit.npc,
            enabled: enabled, maxLength: 400,
            decoration: const InputDecoration(labelText: 'Ответ NPC после знакомства'),
            onChanged: (_) => setState(() { edit.changed(); _touch(); })),
          Wrap(spacing: 6, children: [for (final id in edit.dependencies)
            InputChip(label: Text('После ${_catalog!.candidates[id]!.role.displayName}'),
              onDeleted: enabled ? () => setState(() { edit.dependencies.remove(id); _touch(); }) : null)]),
          DropdownButtonFormField<String>(
            key: ValueKey('whole-npc-dependency-${c.id}-${edit.dependencies.join()}'),
            initialValue: '', isExpanded: true,
            decoration: const InputDecoration(labelText: 'Добавить условие начала встречи'),
            items: [const DropdownMenuItem(value: '', child: Text('Без нового условия')),
              for (final other in earlier)
                if (!edit.dependencies.contains(other.id)) DropdownMenuItem(value: other.id,
                  child: Text('${other.role.displayName}, глава ${other.firstEvent.source.chapterIndex + 1}'))],
            onChanged: enabled ? (id) { if (id != null && id.isNotEmpty) setState(() {
              edit.dependencies.add(id); _touch();
            }); } : null,
          ),
          const Text('Знакомство добавляет знание и память только этому NPC. '
              'Зависимость от другой встречи — игровое условие, не передача чужих знаний.'),
        ],
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return PopScope(
      canPop: _allowLeave || (!_working && !_dirty),
      onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_leave()); },
      child: Scaffold(
        appBar: AppBar(title: const Text('События книги и несколько NPC'),
            leading: BackButton(onPressed: _leave)),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(widget.index.title, style: Theme.of(context).textTheme.titleLarge),
          const Text('Одна автономная кампания. Совпадение цитаты не доказывает канон. '
              'Редактор сохраняет работу на устройстве; запросы ИИ требуют отдельного согласия.'),
          if (source != null) ...[
            Text('Охвачено событий: ${source.coverage.referencedEvents} из ${source.coverage.allEvents}. '
                'Актов: ${source.draft.parts.length}. Сцен: ${source.plan.situations.length}.'),
            if (!source.coverage.allDetectedEventsReferenced || !source.coverage.allChaptersCovered)
              const Text('Охват неполный: исходный сценарий не включает некоторые события или главы.'),
            ExpansionTile(key: const Key('whole-npc-source-quotes'),
              title: const Text('Проверить все включённые цитаты'), children: [
                for (final event in widget.book.events)
                  if (source.reviewedEventIds.contains(event.id)) ListTile(
                    title: Text('Глава ${event.source.chapterIndex + 1}'),
                    subtitle: SelectableText(event.source.quote)),
              ]),
            CheckboxListTile(key: const Key('whole-npc-quotes-reviewed'), value: _quotesReviewed,
              title: const Text('Проверены все показанные цитаты этой редакции'),
              onChanged: _working ? null : (value) => setState(() { _quotesReviewed = value == true; _invalidate(); })),
            CheckboxListTile(key: const Key('whole-npc-private-fiction'), value: _privateFiction,
              title: const Text('Подтверждаю частную игровую адаптацию, не канон'),
              onChanged: _working ? null : (value) => setState(() { _privateFiction = value == true; _invalidate(); })),
            OutlinedButton.icon(key: const Key('whole-npc-prepare'),
              onPressed: !_working && _quotesReviewed && _privateFiction && !_storageBlocked ? _prepare : null,
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Открыть или восстановить редактор разговоров')),
          ],
          if (_base != null) ...[
            Text('Возможных разговоров: ${_candidates.length}; выбрано: ${_edits.length}.'),
            Text(_dirty ? 'Изменения ещё сохраняются…' : 'Черновик сохранён локально. '
                'Согласия на облако и сборку не восстанавливаются.', key: const Key('npc-writing-save-state')),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton(key: const Key('npc-writing-save'),
                onPressed: !_working && !_storageBlocked ? () => unawaited(_flush().catchError((Object _) {})) : null,
                child: const Text('Сохранить черновик')),
              OutlinedButton(key: const Key('npc-writing-generate'),
                onPressed: !_working && !_storageBlocked && _edits.isNotEmpty ? _generate : null,
                child: const Text('Подготовить пустые диалоги через ИИ')),
            ]),
            for (final candidate in _candidates) _conversation(candidate),
            OutlinedButton(key: const Key('whole-npc-review-package'),
              onPressed: !_working && !_storageBlocked && _edits.isNotEmpty ? _review : null,
              child: const Text('Проверить весь пакет разговоров')),
          ],
          if (_approval != null) ...[
            Text('Пакет: ${_approval!.actorCount} NPC, ${_approval!.episodeCount} разговоров. '
                'Все игровые пути и зависимости ещё будут проверены при сборке.'),
            CheckboxListTile(key: const Key('whole-npc-final-approval'), value: _campaignConfirmed,
              title: const Text('Одобряю именно эти реплики, личности и условия'),
              onChanged: _working ? null : (value) => setState(() => _campaignConfirmed = value == true)),
            FilledButton.icon(key: const Key('whole-npc-start'),
              onPressed: !_working && _campaignConfirmed && _quotesReviewed && _privateFiction ? _start : null,
              icon: const Icon(Icons.play_arrow), child: const Text('Собрать и начать новую кампанию')),
          ],
          if (_working) ...[
            const LinearProgressIndicator(),
            Text(_cancellation == null ? 'Проверяется сценарий и локальное сохранение.'
                : 'ИИ готовит реплики. Каждый законченный пакет сохраняется отдельно.'),
            if (_cancellation != null) TextButton(key: const Key('npc-writing-cancel'),
              onPressed: () => _cancellation?.cancel(), child: const Text('Остановить новые запросы')),
          ],
          if (_error != null) SelectableText(_error!, key: const Key('whole-npc-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_catalog != null) TextButton(key: const Key('npc-writing-reset'),
            onPressed: _working ? null : _reset, child: const Text('Удалить этот авторский черновик…')),
        ])),
      ),
    );
  }
}
