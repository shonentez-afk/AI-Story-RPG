import 'dart:async';

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'bookwide_unified_story.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'zai_semantic_preview.dart';
import 'zai_unified_book_story.dart';

/// The same authoring flow: this sheet returns an ordinary multi-act draft
/// to the existing hero/items/NPC editor. It never installs or starts a game.
class UnifiedBookStoryPanel extends StatefulWidget {
  const UnifiedBookStoryPanel({super.key, required this.index, required this.book,
    required this.bookMap, required this.onAccepted,
    this.roleCatalog, this.store, this.gateway});
  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final ValueChanged<MultiActStoryPlanDraft> onAccepted;
  final ReviewedHeroRoleCatalog? roleCatalog;
  final UnifiedBookStoryStore? store;
  final ZaiUnifiedBookStory? gateway;
  @override State<UnifiedBookStoryPanel> createState() => _UnifiedBookStoryPanelState();
}

class _UnifiedBookStoryPanelState extends State<UnifiedBookStoryPanel> {
  late final _roles = widget.roleCatalog ?? const ReviewedHeroRoleCatalog();
  late final _store = widget.store ?? UnifiedBookStoryStore();
  late final _gateway = widget.gateway ?? ZaiUnifiedBookStory();
  final _cancellation = ZaiPreviewCancellation();
  UnifiedBookStoryContext? _context;
  UnifiedBookStoryDraft? _draft;
  bool _loading = true, _working = false, _quotesReviewed = false, _fictionReviewed = false;
  String? _error;

  @override void initState() { super.initState(); unawaited(_load()); }
  @override void dispose() { _cancellation.cancel(); super.dispose(); }

  Future<void> _load() async {
    try {
      final roles = await _roles.load(widget.index);
      final context = UnifiedBookStoryContext.create(index: widget.index,
        book: widget.book, bookMap: widget.bookMap, roles: roles);
      final checkpoint = await _store.load(context);
      if (mounted) setState(() {
        _context = context; _draft = checkpoint.draft;
        _loading = false; _error = null;
        _quotesReviewed = false; _fictionReviewed = false;
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Future<void> _generate() async {
    final source = _context;
    if (_working || source == null || _draft != null) return;
    var agreed = false;
    final yes = await showDialog<bool>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        title: const Text('Передать карту книги для общего сценария?'),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Будут отправлены ${source.eventCount} показанных цитат из '
                '${source.actCount} частей и перечисленные карточки персонажей. '
                'Это не полный файл книги. Название книги, тайны из карточек, '
                'сохранения игры и ключ в содержимое запроса не включаются.'),
            const Text('Один запрос, до трёх одинаковых попыток при временном сбое. '
                'Модель предлагает общий конфликт, мотивы и зависимости; '
                'игровые последствия потребуют отдельного одобрения.'),
            ExpansionTile(title: const Text('Все точные данные для отправки'),
              children: [SelectableText(source.shownText,
                key: const Key('unified-story-cloud-payload'))]),
            CheckboxListTile(key: const Key('unified-story-cloud-consent'), value: agreed,
              title: const Text('Разрешаю отправить именно эту карту и показанные имена'),
              onChanged: (value) => refresh(() => agreed = value == true)),
          ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(key: const Key('unified-story-cloud-send'),
            onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Подготовить общий сюжет'))],
      )));
    if (yes != true || !mounted) return;
    setState(() { _working = true; _error = null; _quotesReviewed = false; _fictionReviewed = false; });
    try {
      final saved = await _gateway.generate(context: source, store: _store,
        approvedDigest: source.approvalDigest, explicitCloudConsent: true,
        loadCurrentRoles: () => _roles.load(widget.index), cancellation: _cancellation);
      if (mounted) setState(() => _draft = saved.draft);
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _accept() async {
    if (_working || _context == null || _draft == null ||
        !_quotesReviewed || !_fictionReviewed) return;
    setState(() { _working = true; _error = null; });
    try {
      final current = await _store.load(_context!);
      if (current.draft?.reviewDigest != _draft!.reviewDigest) {
        throw const FormatException('Сохранённый сюжет изменён после просмотра.');
      }
      final accepted = _draft!.accept(context: _context!,
        freshRoles: await _roles.load(widget.index),
        approvedReviewDigest: _draft!.reviewDigest,
        allShownQuotesAndStoryReviewed: _quotesReviewed,
        fictionalConsequencesConfirmed: _fictionReviewed);
      if (!mounted) return;
      widget.onAccepted(accepted);
    } catch (error) {
      if (mounted) setState(() {
        _quotesReviewed = false; _fictionReviewed = false; _error = error.toString();
      });
    } finally { if (mounted) setState(() => _working = false); }
  }

  @override Widget build(BuildContext context) {
    final draft = _draft, source = _context;
    final names = {for (final r in source?.roles ?? <ReviewedHeroRole>[]) r.characterId: r.displayName};
    return SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Связный сюжет всей карты книги', style: Theme.of(context).textTheme.titleLarge),
      const Text('Это частная адаптация с изменением судьбы. Полноценный CANON '
          'ещё не подтверждён. Карта всех найденных событий не гарантирует, '
          'что анализ обнаружил всё существенное в оригинале.'),
      const SizedBox(height: 8),
      if (_loading) const LinearProgressIndicator(),
      if (source != null) ...[
        Text('В контексте: ${source.actCount} актов, ${source.eventCount} событий.'),
        ExpansionTile(key: const Key('unified-story-source-map'),
          title: const Text('Проверить исходную карту и цитаты'),
          children: [SelectableText(source.shownText)]),
        if (draft == null) OutlinedButton.icon(
          key: const Key('unified-story-generate'), onPressed: _working ? null : _generate,
          icon: const Icon(Icons.auto_stories_outlined),
          label: const Text('Подготовить один общий сюжет через ИИ')),
      ],
      if (draft != null && !draft.applicable)
        Text('Предложение не создано: ${draft.reason}. Результат сохранён; '
            'повторной отправки при открытии не будет.'),
      if (draft != null && draft.applicable) ...[
        const Text('Черновик восстановлен локально. Согласия не сохраняются.'),
        const SizedBox(height: 8),
        Text('Общая цель: ${draft.goal}', key: const Key('unified-story-goal')),
        Text('Основной конфликт: ${draft.conflict}'),
        for (final motive in draft.motivations) ListTile(
          title: Text('${names[motive.characterId]}: ${motive.goal}'),
          subtitle: Text('${motive.reason}\nОснование: ${motive.sourceEventIds.join(', ')}. '
              'Мотив — гипотеза, не автоматическое знание персонажа.')),
        for (var i = 0; i < draft.acts.length; i++) ExpansionTile(
          title: Text('Часть ${i + 1}: ${draft.acts[i].purpose}'), children: [
            ListTile(title: Text(draft.acts[i].proposal.dilemma)),
            ListTile(title: const Text('Принять'), subtitle: Text(
              '${draft.acts[i].proposal.acceptIntent}\n${draft.acts[i].proposal.followupGoal}\n'
              '${draft.acts[i].proposal.finishOriginalIntent}\n${draft.acts[i].proposal.originalEnding}')),
            ListTile(title: const Text('Изменить путь'), subtitle: Text(
              '${draft.acts[i].proposal.refuseIntent}\n${draft.acts[i].proposal.alternativeSearchGoal}\n'
              '${draft.acts[i].proposal.searchIntent}\n${draft.acts[i].proposal.alternativeDiscovery}\n'
              '${draft.acts[i].proposal.useDiscoveryIntent}\n${draft.acts[i].proposal.alternativeEnding}')),
          ]),
        for (final link in draft.links) ListTile(
          title: Text('Последствие: ${link.fromActId} → ${link.toActId}'),
          subtitle: Text('${link.reason}\nПозднее согласие требует раннего '
              '${link.outcome.name == 'original' ? 'первоначального' : 'альтернативного'} '
              'исхода. Поздний отказ остаётся доступным.')),
        CheckboxListTile(key: const Key('unified-story-review'), value: _quotesReviewed,
          title: const Text('Проверены цитаты, общий конфликт, мотивы и все части сценария'),
          onChanged: _working ? null : (v) => setState(() => _quotesReviewed = v == true)),
        CheckboxListTile(key: const Key('unified-story-fiction'), value: _fictionReviewed,
          title: const Text('Одобряю показанные игровые зависимости как частную адаптацию'),
          onChanged: _working ? null : (v) => setState(() => _fictionReviewed = v == true)),
        FilledButton(key: const Key('unified-story-accept'),
          onPressed: !_working && _quotesReviewed && _fictionReviewed ? _accept : null,
          child: const Text('Проверить связи и продолжить в общем редакторе')),
        const Text('Герой, предметы и разговоры настраиваются в существующем редакторе. '
            'Сама проверка этого предложения ещё не устанавливает игру.'),
      ],
      if (_working) ...[
        const LinearProgressIndicator(),
        const Text('Выполняется только подтверждённая подготовка или локальная проверка.'),
      ],
      if (_error != null) SelectableText(_error!, key: const Key('unified-story-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]));
  }
}
