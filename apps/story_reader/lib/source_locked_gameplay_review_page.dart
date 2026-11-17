import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'reviewed_gameplay_compiler.dart';
import 'reviewed_hero_reading_candidate.dart';
import 'story_plan.dart';
import 'zai_semantic_preview.dart';
import 'zai_source_locked_gameplay_candidates.dart';

/// A selected set of UNATTESTED model suggestions and the human's separate
/// game-FICTION review notes. Only the next exact-digest confirmation permits
/// writing a new private game; this page never installs a BookWorld.
class SelectedGameplayCandidates {
  const SelectedGameplayCandidates({
    required this.context,
    required this.draft,
    required this.selectedUserReviewNotes,
  });

  final SourceLockedGameplayContext context;
  final GameplayCandidateDraft draft;
  final Map<String, String> selectedUserReviewNotes;
}

/// Deliberately optional, cost-controlled proposal/review screen.
/// Opening it sends NOTHING. Only the explicit consent button sends a
/// bounded set of displayed source excerpts with the existing Z.ai key.
/// Later editorial approval NEVER sends another request.
class SourceLockedGameplayReviewPage extends StatefulWidget {
  const SourceLockedGameplayReviewPage({
    super.key,
    required this.index,
    required this.book,
    required this.plan,
    required this.exactEventIds,
    this.service,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final List<String> exactEventIds;
  final ZaiSourceLockedGameplayCandidateService? service;

  @override
  State<SourceLockedGameplayReviewPage> createState() =>
      _SourceLockedGameplayReviewPageState();
}

class _SourceLockedGameplayReviewPageState
    extends State<SourceLockedGameplayReviewPage> {
  final _cancellation = ZaiPreviewCancellation();
  final _notes = <String, TextEditingController>{};
  final _selected = <String>{};
  SourceLockedGameplayContext? _context;
  GameplayCandidateDraft? _draft;
  String? _error;
  bool _explicitCloudConsent = false;
  bool _privateFictionApproved = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    try {
      _context = SourceLockedGameplayContext.forPlan(
        index: widget.index,
        book: widget.book,
        plan: widget.plan,
        exactEventIds: widget.exactEventIds,
      );
    } catch (error) {
      _error = 'Невозможно предложить предметы по этой версии книги: ' +
          error.toString();
    }
  }

  @override
  void dispose() {
    _cancellation.cancel();
    for (final controller in _notes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _request() async {
    final context = _context;
    if (context == null || !_explicitCloudConsent || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final result = await (widget.service ??
          ZaiSourceLockedGameplayCandidateService()).propose(
        context: context,
        explicitExcerptConsent: _explicitCloudConsent,
        approvedDigest: context.approvalDigest,
        cancellation: _cancellation,
      );
      if (!mounted) return;
      for (final note in _notes.values) {
        note.dispose();
      }
      _notes.clear();
      _selected.clear();
      for (final item in result.candidates) {
        final id = ReviewedGameplayCompiler.signature(item);
        _notes[id] = TextEditingController();
      }
      setState(() {
        _draft = result;
        _privateFictionApproved = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось проверить предложения ИИ: ' +
              error.toString() +
              '. Существующие книги и игры не изменены.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // This path is fully OFFLINE. It proposes only the verified literal
  // quote the chosen character can observe through a typed role-gated
  // gameplay decision. It still needs a human review note + second consent.
  void _proposeLocalHeroReading() {
    final context = _context;
    if (context == null || _working) return;
    try {
      final draft = ReviewedHeroReadingCandidate.fromContext(
        index: widget.index, context: context,
      );
      if (draft == null || draft.candidates.length != 1) {
        throw const FormatException(
            'Сначала выберите героя и ролевое изучение цитаты.');
      }
      for (final controller in _notes.values) {
        controller.dispose();
      }
      _notes.clear();
      _selected.clear();
      for (final item in draft.candidates) {
        _notes[ReviewedGameplayCompiler.signature(item)] =
            TextEditingController();
      }
      setState(() {
        _draft = draft;
        _explicitCloudConsent = false;
        _privateFictionApproved = false;
        _error = null;
      });
    } catch (error) {
      setState(() => _error =
          'Нельзя предложить локальное знание: ' + error.toString());
    }
  }

  void _accept() {
    final ctx = _context;
    final draft = _draft;
    if (ctx == null || draft == null ||
        _working || !_privateFictionApproved ||
        _selected.isEmpty) return;
    final notes = <String, String>{};
    for (final id in _selected) {
      final value = _notes[id]?.text.trim() ?? '';
      if (value.length < 18 || value.length > 350) return;
      notes[id] = value;
    }
    Navigator.of(context).pop(SelectedGameplayCandidates(
      context: ctx, draft: draft,
      selectedUserReviewNotes: Map.unmodifiable(notes),
    ));
  }

  bool get _notesReady => _selected.isNotEmpty &&
      _selected.every((id) {
        final note = _notes[id]?.text.trim() ?? '';
        return note.length >= 18 && note.length <= 350;
      });

  @override
  Widget build(BuildContext context) {
    final source = _context;
    final draft = _draft;
    final candidates = draft?.candidates ?? const <GameplayCandidate>[];
    final showError = _error != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Предметы и знания из книги')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Text(widget.index.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Дополнительно: ИИ может предложить предметы или знания '
              'для частной игры. Само упоминание вещи ещё не доказывает, '
              'что герой её получил. Можно ничего не добавлять и '
              'играть без предметов.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Запрос к Z.ai выполняется только после отдельного согласия. '
              'Может расходовать лимит API. При временных ошибках он '
              'повторяется с тем же содержимым не более трёх раз.',
            ),
            if (source != null && draft == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Это ТОЧНО те цитаты и игровые решения, '
                'которые будут отправлены:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final e in source.excerpts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Глава ' +
                            (e.source.chapterIndex + 1).toString()),
                        const SizedBox(height: 6),
                        SelectableText('«' + e.source.quote + '»'),
                      ],
                    ),
                  ),
                ),
              for (final choice in source.choices)
                ListTile(
                  dense: true,
                  title: Text(choice.intent),
                  subtitle: Text('Сцена: ' + choice.sceneId +
                      ' · действие: ' + choice.choiceId),
                ),
              if (ReviewedHeroReadingCandidate.hasEligibleChoice(source)) ...[
                const Text('Без ИИ: можно предложить запись о дословном '
                    'отрывке, который игрок изучит за выбранного героя. '
                    'Знания литературного персонажа этим не доказываются.'),
                OutlinedButton.icon(
                  key: const Key('gameplay-local-hero-reading'),
                  onPressed: _working ? null : _proposeLocalHeroReading,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Предложить знание из цитаты без ИИ'),
                ),
              ],
              CheckboxListTile(
                key: const Key('gameplay-source-cloud-consent'),
                contentPadding: EdgeInsets.zero,
                value: _explicitCloudConsent,
                onChanged: _working ? null : (v) => setState(() =>
                    _explicitCloudConsent = v == true),
                title: const Text('Разрешаю отправить только показанные '
                    'цитаты и решения в Z.ai'),
              ),
              FilledButton.icon(
                key: const Key('gameplay-source-request'),
                onPressed: _explicitCloudConsent && !_working
                    ? _request : null,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Предложить предметы и знания'),
              ),
            ],
            if (_working) ...[
              const LinearProgressIndicator(),
              const Text('Запрос отправлен только с вашего разрешения. '
                  'Игра не изменяется.'),
            ],
            if (draft != null) ...[
              const SizedBox(height: 8),
              Text('Проверяемых предложений: ' +
                  candidates.length.toString()),
              if (candidates.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Подтверждённых находок нет'),
                    subtitle: Text('Не нужно придумывать предметы. '
                        'Вернитесь и создайте обычную RPG.'),
                  ),
                ),
              for (final (position, candidate) in candidates.indexed) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          key: Key('gameplay-source-candidate-' +
                              position.toString()),
                          value: _selected.contains(
                              ReviewedGameplayCompiler.signature(candidate)),
                          contentPadding: EdgeInsets.zero,
                          onChanged: _working ? null : (v) => setState(() {
                            final key = ReviewedGameplayCompiler
                                .signature(candidate);
                            if (v == true) {
                              _selected.add(key);
                            } else {
                              _selected.remove(key);
                            }
                          }),
                          title: Text(candidate.label),
                          subtitle: Text(candidate.op + ' · ' +
                              candidate.choiceId),
                        ),
                        Text(candidate.uncertainty),
                        if (_selected.contains(
                            ReviewedGameplayCompiler.signature(candidate)))
                          TextField(
                            key: Key('gameplay-source-review-note-' +
                                position.toString()),
                            controller: _notes[
                                ReviewedGameplayCompiler.signature(candidate)],
                            maxLength: 350,
                            maxLines: 3,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Почему допустимо для игры',
                              helperText: 'Не менее 18 символов. '
                                  'Не выдавайте за канон книги.',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (candidates.isNotEmpty) ...[
                CheckboxListTile(
                  key: const Key('gameplay-source-private-fiction'),
                  contentPadding: EdgeInsets.zero,
                  value: _privateFictionApproved,
                  onChanged: _working ? null : (v) => setState(() =>
                      _privateFictionApproved = v == true),
                  title: const Text('Разрешаю лишь частную ИГРОВУЮ '
                      'интерпретацию выбранных действий, не канон'),
                ),
                FilledButton.icon(
                  key: const Key('gameplay-source-accept-selection'),
                  onPressed: _privateFictionApproved && _notesReady &&
                      !_working ? _accept : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Вернуть выбранные эффекты в подготовку'),
                ),
              ],
            ],
            if (showError)
              Text(_error!, key: const Key('gameplay-source-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  )),
            const SizedBox(height: 10),
            const Text('Этот экран не создаёт игру и не расходует '
                'дополнительные запросы при выборе пунктов. '
                'После возврата понадобится отдельная проверка '
                'маршрутов и подтверждение сборки нового мира.'),
          ],
        ),
      ),
    );
  }
}
