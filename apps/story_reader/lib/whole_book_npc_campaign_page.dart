import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'bookwide_act_planner.dart';
import 'bookwide_storyplan_composer.dart';
import 'narrative_book_model.dart';
import 'reviewed_hero_role.dart';
import 'story_plan_trial_compiler.dart';
import 'whole_book_npc_campaign.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';

/// One campaign review, not one screen/PR per NPC or field. Source coverage,
/// all selected conversations, their dependencies and final offline install
/// are approved as a single package. Opening this page never calls an API.
class WholeBookNpcCampaignPage extends StatefulWidget {
  const WholeBookNpcCampaignPage({
    super.key, required this.index, required this.book, required this.bookMap,
    required this.draft, required this.gateway, this.roleCatalog,
  });
  final BookSourceIndex index;
  final NarrativeBookModel book;
  final BookwideActPlan bookMap;
  final MultiActStoryPlanDraft draft;
  final WorldLibraryGateway gateway;
  final ReviewedHeroRoleCatalog? roleCatalog;

  @override
  State<WholeBookNpcCampaignPage> createState() => _WholeBookNpcCampaignPageState();
}

class _ConversationEdit {
  final player = TextEditingController();
  final npc = TextEditingController();
  String? dependency;
  void dispose() { player.dispose(); npc.dispose(); }
}

class _WholeBookNpcCampaignPageState extends State<WholeBookNpcCampaignPage> {
  WholeBookNpcSourcePlan? _source;
  StoryPlanTrialCompilation? _base;
  List<ReviewedHeroRole> _roles = const [];
  List<BookwideNpcConversationCandidate> _candidates = const [];
  final _edits = <String, _ConversationEdit>{};
  ReviewedBookwideNpcCampaign? _approval;
  bool _quotesReviewed = false;
  bool _privateFiction = false;
  bool _campaignConfirmed = false;
  bool _working = false;
  String? _error;

  ReviewedHeroRoleCatalog get _catalog =>
      widget.roleCatalog ?? const ReviewedHeroRoleCatalog();

  @override
  void initState() {
    super.initState();
    try {
      _source = WholeBookNpcSourcePlan.fromBook(
        index: widget.index, book: widget.book,
        bookMap: widget.bookMap, draft: widget.draft,
      );
    } catch (error) { _error = error.toString(); }
  }

  @override
  void dispose() {
    for (final edit in _edits.values) { edit.dispose(); }
    super.dispose();
  }

  void _invalidate() {
    _approval = null;
    _campaignConfirmed = false;
    _error = null;
  }

  Future<void> _prepare() async {
    final source = _source;
    if (source == null || !_quotesReviewed || !_privateFiction || _working) return;
    setState(() { _working = true; _invalidate(); });
    try {
      final roles = await _catalog.load(widget.index);
      final candidates = BookwideNpcCampaignAuthoring.discover(
          source: source, currentReviewedRoles: roles);
      if (candidates.isEmpty) {
        throw const FormatException(
            'Нужны проверенные карточки NPC с упоминаниями хотя бы в двух '
            'включённых событиях. Личности не угадываются по именам.');
      }
      final base = await source.compileBase(
        approvedPlanDigest: source.planDigest,
        allShownQuotesReviewed: _quotesReviewed,
        privateFictionConfirmed: _privateFiction,
      );
      if (!mounted) return;
      setState(() {
        for (final edit in _edits.values) { edit.dispose(); }
        _edits.clear();
        _base = base; _roles = roles; _candidates = candidates;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _toggle(BookwideNpcConversationCandidate candidate, bool value) {
    if (_working) return;
    setState(() {
      if (value) {
        _edits.putIfAbsent(candidate.id, () => _ConversationEdit());
      } else {
        _edits.remove(candidate.id)?.dispose();
        for (final edit in _edits.values) {
          if (edit.dependency == candidate.id) edit.dependency = null;
        }
      }
      _invalidate();
    });
  }

  void _review() {
    if (_working || _base == null || _source == null) return;
    try {
      final approval = BookwideNpcCampaignAuthoring.review(
        source: _source!, verifiedBaseArchive: _base!.archive,
        currentReviewedRoles: _roles,
        selectedDrafts: [
          for (final entry in _edits.entries)
            NpcCampaignDialogueDraft(
              candidateId: entry.key,
              playerLine: entry.value.player.text.trim(),
              npcLine: entry.value.npc.text.trim(),
              requiresCandidateIds: [
                if (entry.value.dependency != null) entry.value.dependency!,
              ],
            ),
        ],
      );
      setState(() {
        _approval = approval; _campaignConfirmed = false; _error = null;
      });
    } catch (error) { setState(() => _error = error.toString()); }
  }

  Future<void> _start() async {
    final approval = _approval;
    final source = _source;
    if (_working || approval == null || source == null ||
        !_campaignConfirmed || !_quotesReviewed || !_privateFiction) return;
    setState(() { _working = true; _error = null; });
    try {
      // Revoke stale consent when source groups or permanent cards changed
      // while the editor was open. No old actor identity can slip through.
      final freshRoles = await _catalog.load(widget.index);
      final built = await BookwideNpcCampaignAuthoring.compile(
        source: source, approval: approval, freshReviewedRoles: freshRoles,
        approvedDigest: approval.approvalDigest,
        explicitlyConfirmedPrivateFiction: _campaignConfirmed,
      );
      if (!mounted) return;
      final installed = await widget.gateway.install(built.archive);
      if (installed.archiveHash != built.archiveSha256) {
        throw const FormatException('Установленный мир отличается от проверенного.');
      }
      final campaignId = await widget.gateway.start(installed.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldPlayPage(gateway: widget.gateway, campaignId: campaignId),
      ));
    } catch (error) {
      if (mounted) setState(() => _error =
          'Кампания не создана: $error. Исходная книга и прежние игры сохранены.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _conversation(BookwideNpcConversationCandidate candidate) {
    final edit = _edits[candidate.id];
    final dependencies = _candidates.where((other) =>
        other.id != candidate.id && _edits.containsKey(other.id) &&
        other.firstEvent.narrativePosition < candidate.firstEvent.narrativePosition)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CheckboxListTile(
            key: ValueKey('whole-npc-select-${candidate.id}'),
            value: edit != null,
            onChanged: _working ? null : (value) => _toggle(candidate, value == true),
            title: Text(candidate.role.displayName),
            subtitle: Text('Главы ${candidate.firstEvent.source.chapterIndex + 1}'
                ' → ${candidate.responseEvent.source.chapterIndex + 1}. '
                'Постоянная личность: ${candidate.role.characterId.substring(0, 12)}'),
          ),
          ExpansionTile(
            title: const Text('Две точные цитаты для встречи и ответа'),
            children: [
              SelectableText(candidate.firstEvent.source.quote),
              const SizedBox(height: 8),
              SelectableText(candidate.responseEvent.source.quote),
            ],
          ),
          if (edit != null) ...[
            TextField(
              key: ValueKey('whole-npc-player-${candidate.id}'),
              controller: edit.player, enabled: !_working, maxLength: 400,
              decoration: const InputDecoration(labelText: 'Игровая реплика героя'),
              onChanged: (_) => setState(_invalidate),
            ),
            TextField(
              key: ValueKey('whole-npc-line-${candidate.id}'),
              controller: edit.npc, enabled: !_working, maxLength: 400,
              decoration: const InputDecoration(
                  labelText: 'Ответ NPC после знакомства — частная адаптация'),
              onChanged: (_) => setState(_invalidate),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('whole-npc-dependency-${candidate.id}-${edit.dependency}'),
              initialValue: edit.dependency ?? '',
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Условие начала этой встречи'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Без другой встречи')),
                for (final other in dependencies)
                  DropdownMenuItem(value: other.id,
                      child: Text('${other.role.displayName}, '
                          'глава ${other.firstEvent.source.chapterIndex + 1}')),
              ],
              onChanged: _working ? null : (id) => setState(() {
                edit.dependency = id == null || id.isEmpty ? null : id;
                _invalidate();
              }),
            ),
            const SizedBox(height: 8),
            const Text('Первый разговор создаёт память и знание только у этого '
                'NPC. Пропуск знакомства закрывает его последующий ответ. '
                'Зависимость от другой встречи — отдельно одобряемое игровое правило.'),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      appBar: AppBar(title: const Text('События книги и несколько NPC')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.index.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Одна автономная кампания. Ни цитаты, ни игровые диалоги '
              'не подтверждают литературный канон. Облачных запросов на этом '
              'экране нет; реплики проверяются перед сборкой.'),
          if (source != null) ...[
            const SizedBox(height: 12),
            Text('Охвачено событий: ${source.coverage.referencedEvents} '
                'из ${source.coverage.allEvents}. '
                'Актов: ${source.draft.parts.length}. '
                'Сцен: ${source.plan.situations.length}.'),
            if (!source.coverage.allDetectedEventsReferenced ||
                !source.coverage.allChaptersCovered)
              const Text('Охват неполный: в исходном сценарии отсутствуют '
                  'некоторые события или главы. Ничего не отброшено молча.'),
            ExpansionTile(
              key: const Key('whole-npc-source-quotes'),
              title: const Text('Проверить все включённые цитаты'),
              children: [
                for (final event in widget.book.events)
                  if (source.reviewedEventIds.contains(event.id))
                    ListTile(
                      title: Text('Глава ${event.source.chapterIndex + 1}'),
                      subtitle: SelectableText(event.source.quote),
                    ),
              ],
            ),
            CheckboxListTile(
              key: const Key('whole-npc-quotes-reviewed'),
              value: _quotesReviewed,
              title: const Text('Проверены все показанные цитаты этой редакции'),
              onChanged: _working ? null : (value) => setState(() {
                _quotesReviewed = value == true; _invalidate();
              }),
            ),
            CheckboxListTile(
              key: const Key('whole-npc-private-fiction'),
              value: _privateFiction,
              title: const Text('Подтверждаю частную игровую адаптацию, не канон'),
              onChanged: _working ? null : (value) => setState(() {
                _privateFiction = value == true; _invalidate();
              }),
            ),
            OutlinedButton.icon(
              key: const Key('whole-npc-prepare'),
              onPressed: !_working && _quotesReviewed && _privateFiction
                  ? _prepare : null,
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Проверить сценарий и найти встречи NPC'),
            ),
          ],
          if (_base != null) ...[
            Text('Найдено возможных разговоров: ${_candidates.length}. '
                'Выбрано: ${_edits.length}. '
                'Личности взяты из проверенных карточек, не угаданы из текста.'),
            for (final candidate in _candidates) _conversation(candidate),
            OutlinedButton(
              key: const Key('whole-npc-review-package'),
              onPressed: !_working && _edits.isNotEmpty ? _review : null,
              child: const Text('Проверить весь пакет разговоров'),
            ),
          ],
          if (_approval != null) ...[
            Text('Пакет: ${_approval!.actorCount} NPC, '
                '${_approval!.episodeCount} разговоров. '
                'При сборке проверяются все игровые пути и зависимости.'),
            CheckboxListTile(
              key: const Key('whole-npc-final-approval'),
              value: _campaignConfirmed,
              title: const Text('Одобряю именно эти реплики, личности и условия'),
              onChanged: _working ? null : (value) => setState(
                  () => _campaignConfirmed = value == true),
            ),
            FilledButton.icon(
              key: const Key('whole-npc-start'),
              onPressed: !_working && _campaignConfirmed &&
                      _quotesReviewed && _privateFiction ? _start : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Собрать и начать новую кампанию'),
            ),
          ],
          if (_working) ...[
            const LinearProgressIndicator(),
            const Text('Проверяются правила, реплики и автономное сохранение.'),
          ],
          if (_error != null)
            SelectableText(_error!, key: const Key('whole-npc-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      )),
    );
  }
}
