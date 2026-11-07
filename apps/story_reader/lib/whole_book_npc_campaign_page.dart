import 'dart:async';

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'npc_campaign_hero_selection.dart';
import 'npc_campaign_writing_session.dart';
import 'reviewed_hero_role.dart';
import 'story_plan_trial_compiler.dart';
import 'whole_book_npc_campaign.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';
import 'zai_npc_campaign_writing.dart';
import 'zai_semantic_preview.dart';

/// One source/hero/NPC/AI/review/install workflow; no request on opening.
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
  late final NpcCampaignHeroStore _heroStore = NpcCampaignHeroStore(repository: _store.repository);
  late final ZaiNpcCampaignWriting _writer = widget.aiWriter ?? ZaiNpcCampaignWriting();
  NpcCampaignHeroSelection _hero = const NpcCampaignHeroSelection(null, false, 0);
  NpcWritingCatalog? _catalog;
  NpcWritingSession? _session;
  ReviewedBookwideNpcCampaign? _approval;
  ZaiPreviewCancellation? _cancellation;
  Timer? _saveTimer;
  Future<void> _saveTail = Future<void>.value();
  int _editGeneration = 0;
  bool _quotesReviewed = false, _privateFiction = false, _campaignConfirmed = false;
  bool _working = false, _dirty = false, _storageBlocked = false, _allowLeave = false;
  bool _rolesLoaded = false, _heroBlocked = false;
  String? _error;
  ReviewedHeroRoleCatalog get _roleCatalog => widget.roleCatalog ?? const ReviewedHeroRoleCatalog();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _source = WholeBookNpcSourcePlan.fromBook(index: widget.index, book: widget.book,
          bookMap: widget.bookMap, draft: widget.draft);
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
    _cancellation?.cancel(); _saveTimer?.cancel();
    if (_dirty && !_storageBlocked) unawaited(_flush().catchError((Object _) {}));
    for (final edit in _edits.values) { edit.dispose(); }
    super.dispose();
  }

  void _invalidate() { _approval = null; _campaignConfirmed = false; }
  List<NpcWritingEdit> _snapshot() => [for (final entry in _edits.entries) NpcWritingEdit(
    id: entry.key, playerLine: entry.value.player.text, npcLine: entry.value.npc.text,
    dependencies: entry.value.dependencies, uncertainty: entry.value.uncertainty,
    origin: entry.value.origin, noSuggestion: entry.value.noSuggestion,
  )];

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
      final saved = await _store.save(catalog, edits: snapshot, expectedRevision: _session!.revision);
      _session = saved;
      if (mounted) setState(() { if (_editGeneration == generation) _dirty = false; });
    });
    _saveTail = operation.catchError((Object error) {
      if (mounted) setState(() => _error = 'Черновик ещё не сохранён: $error. Текст не удалён.');
    });
    return operation;
  }

  void _restore(NpcWritingSession session) {
    for (final edit in _edits.values) { edit.dispose(); }
    _edits.clear();
    for (final e in session.edits.values) { _edits[e.id] = _ConversationEdit(e); }
    _session = session; _dirty = false; _invalidate();
  }

  /// Called only after all pending writes complete. A role change selects
  /// another draft address; it never relabels or deletes existing writings.
  void _switchSource(WholeBookNpcSourcePlan source) {
    _saveTimer?.cancel();
    for (final edit in _edits.values) { edit.dispose(); }
    _edits.clear(); _source = source; _base = null; _catalog = null; _session = null;
    _candidates = const []; _dirty = false; _storageBlocked = false;
    _editGeneration++; _quotesReviewed = false; _privateFiction = false; _invalidate();
  }

  Future<void> _leave() async {
    if (_working) { _cancellation?.cancel(); return; }
    try {
      await _flush();
      if (!mounted) return;
      setState(() => _allowLeave = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (_) { /* Preserve unsaved work. */ }
  }

  Future<void> _loadHeroes() async {
    if (_working || _source == null) return;
    setState(() { _working = true; _error = null; _invalidate(); });
    try {
      await _flush();
      final roles = await _roleCatalog.load(widget.index);
      final saved = await _heroStore.load(_source!, roles);
      final next = saved.bind(_source!);
      if (!mounted) return;
      setState(() {
        if (next.planDigest != _source!.planDigest || next.heroReviewDigest != _source!.heroReviewDigest) {
          _switchSource(next);
        }
        _hero = saved; _roles = roles; _rolesLoaded = true; _heroBlocked = false;
      });
    } catch (error) {
      if (mounted) setState(() { _heroBlocked = true; _rolesLoaded = false; _error = error.toString(); });
    } finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _chooseHero(String? id, {bool sourceAction = false}) async {
    if (_working || _source == null || !_rolesLoaded || _heroBlocked) return;
    final found = _roles.where((r) => r.characterId == id).toList();
    if (id != null && id.isNotEmpty && found.length != 1) return;
    final role = found.isEmpty ? null : found.single;
    setState(() { _working = true; _error = null; _invalidate(); });
    try {
      await _flush();
      final fresh = await _roleCatalog.load(widget.index);
      final saved = await _heroStore.save(_source!, currentRoles: fresh,
        role: role, sourceAction: sourceAction, expectedRevision: _hero.revision);
      final next = saved.bind(_source!);
      if (!mounted) return;
      setState(() {
        _switchSource(next); _hero = saved; _roles = fresh;
        _rolesLoaded = true; _heroBlocked = false;
      });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _resetHero() async {
    if (_working || _source == null) return;
    setState(() => _working = true);
    try {
      final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Сбросить только сохранённый выбор героя?'),
        content: const Text('Черновики всех героев, карточки и игры останутся. '
            'Будет выбран свободный игрок; роль можно выбрать заново.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сбросить выбор'))],
      ));
      if (yes != true || !mounted) return;
      await _flush();
      await _heroStore.reset(_source!, confirmed: true);
      final roles = await _roleCatalog.load(widget.index);
      final empty = await _heroStore.load(_source!, roles);
      final next = empty.bind(_source!);
      if (mounted) setState(() {
        _switchSource(next); _hero = empty; _roles = roles;
        _heroBlocked = false; _rolesLoaded = true; _error = null;
      });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _prepare() async {
    final source = _source;
    if (source == null || !_quotesReviewed || !_privateFiction || _working || _heroBlocked) return;
    setState(() { _working = true; _error = null; _invalidate(); });
    try {
      await _flush();
      final roles = await _roleCatalog.load(widget.index);
      NpcCampaignHeroSelection savedHero;
      try { savedHero = await _heroStore.load(source, roles); }
      catch (_) { _heroBlocked = true; _rolesLoaded = false; rethrow; }
      final selected = savedHero.bind(source);
      if (selected.planDigest != source.planDigest || selected.heroReviewDigest != source.heroReviewDigest) {
        if (mounted) setState(() {
          _switchSource(selected); _hero = savedHero; _roles = roles; _rolesLoaded = true;
          _error = 'Восстановлен герой ${selected.heroName}. Подтвердите цитаты и роль перед подготовкой.';
        });
        return;
      }
      source.verifyCurrentHero(roles);
      final candidates = BookwideNpcCampaignAuthoring.discover(source: source, currentReviewedRoles: roles);
      if (candidates.isEmpty) throw const FormatException(
          'Нужны другие подтверждённые NPC с упоминаниями в двух включённых событиях. '
          'Выбранный герой не может разговаривать с собой.');
      final catalog = NpcWritingCatalog(source: source, candidates: candidates);
      _catalog = catalog;
      NpcWritingSession saved;
      try { saved = await _store.load(catalog); }
      catch (_) { _storageBlocked = true; rethrow; }
      final base = await source.compileBase(approvedPlanDigest: source.planDigest,
        approvedHeroDigest: source.heroReviewDigest,
        allShownQuotesReviewed: _quotesReviewed, privateFictionConfirmed: _privateFiction);
      if (!mounted) return;
      setState(() {
        _base = base; _roles = roles; _hero = savedHero; _rolesLoaded = true;
        _candidates = candidates; _storageBlocked = false; _restore(saved);
      });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  void _toggle(BookwideNpcConversationCandidate c, bool selected) {
    if (_working || _storageBlocked || _heroBlocked) return;
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
    setState(() => _working = true);
    try {
      final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Удалить только этот авторский черновик?'),
        content: const Text('Будут удалены встречи и реплики только текущей роли и редакции. '
            'Другие герои, книга, карточки NPC и игры останутся.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить черновик'))],
      ));
      if (confirmed != true || !mounted) return;
      _saveTimer?.cancel(); await _saveTail;
      await _store.reset(catalog, confirmed: true);
      final empty = await _store.load(catalog);
      if (mounted) setState(() { _restore(empty); _storageBlocked = false; _error = null; });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _generate() async {
    if (_working || _storageBlocked || _heroBlocked || _catalog == null || _session == null) return;
    setState(() { _working = true; _error = null; _invalidate(); });
    try {
      await _flush();
      if (!mounted) return;
      final request = NpcWritingRequest.prepare(_catalog!, _session!);
      var checked = false;
      final consent = await showDialog<bool>(context: context, builder: (ctx) =>
        StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
          title: const Text('Передать показанные фрагменты в Z.ai?'),
          content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Герой: ${_source!.heroName}. Новых разговоров: ${request.candidateCount}. '
                  'Запросов: ${request.requestCount}, с повторами — не более ${request.maximumAttempts}. '
                  'Готовые и ручные реплики не пересылаются. Применяются условия вашего аккаунта Z.ai.'),
              const Text('Показанная роль героя не даёт ему знаний других NPC. '
                  'ИИ пишет черновик, но не меняет личности, правила и согласия.'),
              ExpansionTile(title: const Text('Точные данные для отправки'),
                children: [SelectableText(request.shownText)]),
              CheckboxListTile(key: const Key('npc-writing-cloud-consent'), value: checked,
                title: const Text('Разрешаю отправить эти цитаты, роль героя и личности'),
                onChanged: (value) => refresh(() => checked = value == true)),
            ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(key: const Key('npc-writing-cloud-send'),
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Подготовить черновики'))],
        )),
      );
      if (consent != true || !mounted) return;
      final freshRoles = await _roleCatalog.load(widget.index);
      final fresh = NpcWritingCatalog(source: _source!, candidates:
          BookwideNpcCampaignAuthoring.discover(source: _source!, currentReviewedRoles: freshRoles));
      if (fresh.digest != _catalog!.digest) throw const FormatException(
          'После просмотра изменились герой или NPC. Отправка отменена.');
      _cancellation = ZaiPreviewCancellation();
      if (mounted) setState(() {});
      await _writer.generate(catalog: fresh, store: _store, request: request,
        approvedDigest: request.approvalDigest, explicitCloudConsent: true,
        cancellation: _cancellation,
        onSaved: (saved) async { if (mounted) setState(() => _restore(saved)); });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { _cancellation = null; if (mounted) setState(() => _working = false); }
  }

  Future<void> _review() async {
    if (_working || _base == null || _source == null || _storageBlocked || _heroBlocked) return;
    setState(() { _working = true; _error = null; });
    try {
      await _flush();
      final edits = _snapshot();
      if (edits.any((e) => !e.complete)) throw const FormatException(
          'Заполните обе реплики каждого выбранного разговора или снимите выбор.');
      final fresh = await _roleCatalog.load(widget.index);
      final review = BookwideNpcCampaignAuthoring.review(source: _source!,
        verifiedBaseArchive: _base!.archive, currentReviewedRoles: fresh,
        selectedDrafts: edits.map((e) => e.toDraft()).toList());
      if (mounted) setState(() { _roles = fresh; _approval = review; _campaignConfirmed = false; });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _start() async {
    final approval = _approval, source = _source;
    if (_working || approval == null || source == null || !_campaignConfirmed ||
        !_quotesReviewed || !_privateFiction || _storageBlocked || _heroBlocked) return;
    setState(() { _working = true; _error = null; });
    try {
      await _flush();
      final built = await BookwideNpcCampaignAuthoring.compile(source: source, approval: approval,
        freshReviewedRoles: await _roleCatalog.load(widget.index),
        approvedDigest: approval.approvalDigest, explicitlyConfirmedPrivateFiction: _campaignConfirmed);
      if (!mounted) return;
      final installed = await widget.gateway.install(built.archive);
      if (installed.archiveHash != built.archiveSha256) throw const FormatException('Установленный мир отличается от проверенного.');
      final campaignId = await widget.gateway.start(installed.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldPlayPage(gateway: widget.gateway, campaignId: campaignId)));
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось начать кампанию: $error. '
          'Книга, черновики и прежние игры сохранены.');
    } finally { if (mounted) setState(() => _working = false); }
  }

  Widget _conversation(BookwideNpcConversationCandidate c) {
    final edit = _edits[c.id];
    final earlier = _candidates.where((other) => other.id != c.id && _edits.containsKey(other.id) &&
        other.firstEvent.narrativePosition < c.firstEvent.narrativePosition).toList();
    final enabled = !_working && !_storageBlocked && !_heroBlocked;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CheckboxListTile(key: ValueKey('whole-npc-select-${c.id}'), value: edit != null,
          onChanged: enabled ? (value) => _toggle(c, value == true) : null,
          title: Text(c.role.displayName), subtitle: Text('Главы ${c.firstEvent.source.chapterIndex + 1} → '
              '${c.responseEvent.source.chapterIndex + 1}')),
        ExpansionTile(title: const Text('Точные цитаты для встречи и ответа'), children: [
          SelectableText(c.firstEvent.source.quote), const SizedBox(height: 8), SelectableText(c.responseEvent.source.quote)]),
        if (edit != null) ...[
          if (edit.origin == 'ai_draft') Text(edit.noSuggestion ? 'ИИ не предложил разговор. ${edit.uncertainty}'
              : 'Черновик ИИ — проверьте смысл. ${edit.uncertainty}'),
          TextField(key: ValueKey('whole-npc-player-${c.id}'), controller: edit.player,
            enabled: enabled, maxLength: 400, decoration: InputDecoration(labelText: 'Реплика героя: ${_source!.heroName}'),
            onChanged: (_) => setState(() { edit.changed(); _touch(); })),
          TextField(key: ValueKey('whole-npc-line-${c.id}'), controller: edit.npc,
            enabled: enabled, maxLength: 400, decoration: const InputDecoration(labelText: 'Ответ NPC после знакомства'),
            onChanged: (_) => setState(() { edit.changed(); _touch(); })),
          Wrap(spacing: 6, children: [for (final id in edit.dependencies)
            InputChip(label: Text('После ${_catalog!.candidates[id]!.role.displayName}'),
              onDeleted: enabled ? () => setState(() { edit.dependencies.remove(id); _touch(); }) : null)]),
          DropdownButtonFormField<String>(key: ValueKey('whole-npc-dependency-${c.id}-${edit.dependencies.join()}'),
            initialValue: '', isExpanded: true,
            decoration: const InputDecoration(labelText: 'Добавить условие начала встречи'),
            items: [const DropdownMenuItem(value: '', child: Text('Без нового условия')),
              for (final other in earlier) if (!edit.dependencies.contains(other.id))
                DropdownMenuItem(value: other.id, child: Text('${other.role.displayName}, '
                    'глава ${other.firstEvent.source.chapterIndex + 1}'))],
            onChanged: enabled ? (id) { if (id != null && id.isNotEmpty) setState(() { edit.dependencies.add(id); _touch(); }); } : null),
          const Text('Знакомство добавляет знание и память только этому NPC. '
              'Зависимость от другой встречи не передаёт чужие знания.'),
        ],
      ])));
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return PopScope(canPop: _allowLeave || (!_working && !_dirty),
      onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_leave()); },
      child: Scaffold(appBar: AppBar(title: const Text('Герой и разговоры NPC'), leading: BackButton(onPressed: _leave)),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(widget.index.title, style: Theme.of(context).textTheme.titleLarge),
          const Text('Одна автономная кампания. Цитаты не доказывают канон. '
              'Работа сохраняется на устройстве; ИИ требует отдельного согласия.'),
          if (source != null) ...[
            Text('Герой: ${source.heroName}', key: const Key('whole-npc-current-hero')),
            OutlinedButton.icon(key: const Key('whole-npc-load-heroes'),
              onPressed: _working ? null : _loadHeroes, icon: const Icon(Icons.person_outline),
              label: const Text('Выбрать или восстановить героя')),
            if (_rolesLoaded && !_heroBlocked) ...[
              DropdownButtonFormField<String>(key: ValueKey('whole-npc-hero-${_hero.role?.characterId ?? 'free'}'),
                initialValue: _hero.role?.characterId ?? '', isExpanded: true,
                decoration: const InputDecoration(labelText: 'Кем играть'),
                items: [const DropdownMenuItem(value: '', child: Text('Свободный игрок')),
                  for (final role in _roles) DropdownMenuItem(value: role.characterId, child: Text(role.displayName))],
                onChanged: _working ? null : (id) => unawaited(_chooseHero(id))),
              const Text('Выбор связан с постоянной карточкой персонажа. Его знания и секреты '
                  'не переносятся игроку. Для каждой роли сохраняется отдельный черновик.'),
              if (_hero.role != null) CheckboxListTile(key: const Key('whole-npc-hero-source-action'),
                value: _hero.sourceAction, title: const Text('Добавить ролевое наблюдение и последующее воспоминание'),
                subtitle: const Text('Нужны две подходящие цитаты. Без первого действия второе недоступно.'),
                onChanged: _working ? null : (value) => unawaited(_chooseHero(
                    _hero.role!.characterId, sourceAction: value == true))),
            ],
            if (_heroBlocked) TextButton(key: const Key('whole-npc-reset-hero'),
              onPressed: _working ? null : _resetHero, child: const Text('Сбросить устаревший выбор героя…')),
            Text('Охвачено событий: ${source.coverage.referencedEvents} из ${source.coverage.allEvents}. '
                'Актов: ${source.draft.parts.length}. Сцен: ${source.plan.situations.length}.'),
            if (!source.coverage.allDetectedEventsReferenced || !source.coverage.allChaptersCovered)
              const Text('Исходный сценарий не включает некоторые события или главы.'),
            ExpansionTile(key: const Key('whole-npc-source-quotes'), title: const Text('Проверить все включённые цитаты'),
              children: [for (final event in widget.book.events) if (source.reviewedEventIds.contains(event.id))
                ListTile(title: Text('Глава ${event.source.chapterIndex + 1}'), subtitle: SelectableText(event.source.quote))]),
            CheckboxListTile(key: const Key('whole-npc-quotes-reviewed'), value: _quotesReviewed,
              title: Text('Проверены цитаты и выбранная роль: ${source.heroName}'),
              onChanged: _working || _heroBlocked ? null : (v) => setState(() { _quotesReviewed = v == true; _invalidate(); })),
            CheckboxListTile(key: const Key('whole-npc-private-fiction'), value: _privateFiction,
              title: const Text('Подтверждаю частную игровую адаптацию, не канон'),
              onChanged: _working || _heroBlocked ? null : (v) => setState(() { _privateFiction = v == true; _invalidate(); })),
            OutlinedButton.icon(key: const Key('whole-npc-prepare'),
              onPressed: !_working && _quotesReviewed && _privateFiction && !_storageBlocked && !_heroBlocked ? _prepare : null,
              icon: const Icon(Icons.groups_outlined), label: const Text('Открыть или восстановить редактор разговоров')),
          ],
          if (_base != null) ...[
            Text('Возможных разговоров: ${_candidates.length}; выбрано: ${_edits.length}.'),
            Text(_dirty ? 'Изменения ещё сохраняются…' : 'Черновик сохранён локально. Согласия не восстанавливаются.',
                key: const Key('npc-writing-save-state')),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton(key: const Key('npc-writing-save'),
                onPressed: !_working && !_storageBlocked ? () => unawaited(_flush().catchError((Object _) {})) : null,
                child: const Text('Сохранить черновик')),
              OutlinedButton(key: const Key('npc-writing-generate'),
                onPressed: !_working && !_storageBlocked && !_heroBlocked && _edits.isNotEmpty ? _generate : null,
                child: const Text('Подготовить пустые диалоги через ИИ'))]),
            for (final candidate in _candidates) _conversation(candidate),
            OutlinedButton(key: const Key('whole-npc-review-package'),
              onPressed: !_working && !_storageBlocked && !_heroBlocked && _edits.isNotEmpty ? _review : null,
              child: const Text('Проверить героя и весь пакет разговоров')),
          ],
          if (_approval != null) ...[
            Text('Герой: ${source!.heroName}. ${_approval!.actorCount} NPC, ${_approval!.episodeCount} разговоров. '
                'Все игровые пути будут проверены при сборке.'),
            CheckboxListTile(key: const Key('whole-npc-final-approval'), value: _campaignConfirmed,
              title: const Text('Одобряю именно эту роль, реплики, личности и условия'),
              onChanged: _working ? null : (v) => setState(() => _campaignConfirmed = v == true)),
            FilledButton.icon(key: const Key('whole-npc-start'),
              onPressed: !_working && _campaignConfirmed && _quotesReviewed && _privateFiction && !_heroBlocked ? _start : null,
              icon: const Icon(Icons.play_arrow), label: const Text('Собрать и начать новую кампанию')),
          ],
          if (_working) ...[
            const LinearProgressIndicator(),
            Text(_cancellation == null ? 'Проверяются герой, сценарий и сохранение.'
                : 'ИИ готовит реплики. Каждый готовый пакет сохраняется.'),
            if (_cancellation != null) TextButton(key: const Key('npc-writing-cancel'),
              onPressed: () => _cancellation?.cancel(), child: const Text('Остановить новые запросы'))],
          if (_error != null) SelectableText(_error!, key: const Key('whole-npc-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_catalog != null) TextButton(key: const Key('npc-writing-reset'),
            onPressed: _working ? null : _reset, child: const Text('Удалить этот авторский черновик…')),
        ]))),
    );
  }
}
