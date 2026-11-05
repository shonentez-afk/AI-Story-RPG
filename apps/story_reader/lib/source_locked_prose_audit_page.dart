import 'dart:convert';

import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'narrative_book_model.dart';
import 'source_locked_prose_audit_checkpoint_store.dart';
import 'story_plan.dart';
import 'zai_semantic_preview.dart';
import 'zai_source_locked_prose_audit.dart';
import 'zai_source_locked_prose_preview.dart';

/// Optional, independently consented AI critique of one already generated
/// private prose draft. Read/checkpoint on init: NEVER post to Z.ai on open.
class SourceLockedProseAuditPage extends StatefulWidget {
  const SourceLockedProseAuditPage({
    super.key,
    required this.index,
    required this.book,
    required this.plan,
    required this.draft,
    this.store,
    this.auditService,
  });

  final BookSourceIndex index;
  final NarrativeBookModel book;
  final StoryPlan plan;
  final SourceLockedProseDraft draft;
  final SourceLockedProseAuditCheckpointStore? store;
  final ZaiSourceLockedProseAuditService? auditService;

  @override
  State<SourceLockedProseAuditPage> createState() =>
      _SourceLockedProseAuditPageState();
}

class _SourceLockedProseAuditPageState
    extends State<SourceLockedProseAuditPage> {
  late final SourceLockedProseAuditCheckpointStore _store;
  late final ZaiSourceLockedProseAuditService _service;
  SourceLockedProseAuditContext? _auditContext;
  AiProseAuditReport? _report;
  ZaiPreviewCancellation? _token;
  bool _loading = true;
  bool _working = false;
  bool _storageBlocked = false;
  bool _consented = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SourceLockedProseAuditCheckpointStore();
    _service = widget.auditService ?? ZaiSourceLockedProseAuditService();
    _loadSaved();
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    setState(() {
      _loading = true;
      _storageBlocked = false;
      _report = null;
      _consented = false;
      _error = null;
    });
    try {
      final context = SourceLockedProseAuditContext.forDraft(
        index: widget.index,
        book: widget.book,
        plan: widget.plan,
        draft: widget.draft,
      );
      final saved = await _store.read(context);
      if (!mounted) return;
      setState(() {
        _auditContext = context;
        _report = saved;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storageBlocked = true;
        _error = 'Сцену или её локальную проверку невозможно '
            'сверить с исходной редакцией. Отправка в ИИ заблокирована.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review() async {
    final context = _auditContext;
    if (context == null || _loading || _working || _storageBlocked ||
        !_consented || _report != null) return;
    final token = ZaiPreviewCancellation();
    setState(() {
      _working = true;
      _token = token;
      _status = 'Проверяем локальные сохранения';
      _error = null;
    });
    try {
      AiProseAuditReport? result;
      try {
        result = await _store.read(context);
      } catch (_) {
        _storageBlocked = true;
        rethrow;
      }
      if (result == null) {
        result = await _service.review(
          context: context,
          approvedDigest: context.approvalDigest,
          explicitReviewConsent: _consented,
          cancellation: token,
          onProgress: (attempt, count, detail) {
            if (mounted) {
              setState(() => _status = detail +
                  ' (' + attempt.toString() + '/' + count.toString() + ')');
            }
          },
        );
        if (!mounted) return;
        // Retain an already received critique when persistence fails.
        setState(() => _report = result);
        await _store.save(context: context, report: result);
      }
      if (!mounted) return;
      setState(() {
        _report = result;
        _status = 'Рекомендации ИИ сохранены на устройстве. '
            'Это НЕ подтверждение литературного канона.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _consented = false;
        _error = _report == null
            ? 'Не удалось завершить проверку. '
              'Игра и текст сцены не изменены. '
              'Для повторной отправки потребуется новое согласие.'
            : 'Проверка получена, но локальное сохранение не удалось. '
              'Текст рекомендаций остаётся на экране.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _token = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audit = _auditContext;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('ИИ-проверка литературной логики')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Text('GLM 4.7 Flash может искать возможные ошибки '
                'в причинности, знаниях персонажей, предметах, обещаниях '
                'и выбранной ветке сюжета. Но ему предоставляется лишь '
                'ограниченный исходный отрывок, а не вся книга. '
                'Даже положительный ответ ИИ НЕ доказывает канон.'),
            const SizedBox(height: 12),
            if (audit == null)
              const Text('Исходная сцена не прошла проверку.')
            else ...[
              Text('Сцена: ' + audit.scene.situation.id,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ExpansionTile(
                key: const Key('literary-audit-context-preview'),
                title: const Text('Точно передаваемые данные'),
                subtitle: const Text('Отдельный платный запрос '
                    'после подтверждения, с текстом черновика и цитатой'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ')
                          .convert(audit.sentContext),
                    ),
                  ),
                ],
              ),
              const Text('Отправка будет выполнена только после '
                  'установленного ниже согласия и нажатия кнопки. '
                  'Временные ошибки могут вызвать до трёх '
                  'повторов одного и того же запроса. '
                  'Стоимость зависит от тарифа Z.ai.'),
              CheckboxListTile(
                key: const Key('literary-audit-consent'),
                contentPadding: EdgeInsets.zero,
                value: _consented,
                onChanged: _loading || _working || _storageBlocked ||
                        report != null
                    ? null
                    : (value) => setState(() {
                        _consented = value == true;
                        _error = null;
                        _status = null;
                      }),
                title: const Text('Разрешаю отдельно отправить '
                    'показанный черновик и контекст сцены для '
                    'литературной ИИ-проверки'),
              ),
              FilledButton.icon(
                key: const Key('literary-audit-submit'),
                onPressed: _consented && !_loading && !_working &&
                        !_storageBlocked && report == null
                    ? _review : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Проверить логику сцены через ИИ'),
              ),
              if (_working)
                TextButton.icon(
                  key: const Key('literary-audit-cancel'),
                  onPressed: () => _token?.cancel(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Остановить проверку'),
                ),
              if (_loading || _working)
                const LinearProgressIndicator(),
              if (_status != null) Text(_status!),
              if (_error != null)
                Text(_error!, key: const Key('literary-audit-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              if (report != null) ...[
                const Divider(height: 30),
                Text('Заключение ИИ: ' + report.verdict.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    key: const Key('literary-audit-verdict')),
                Text('Найдено замечаний: ' +
                    report.findings.length.toString()),
                for (final finding in report.findings)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(finding.kind.name + ' — ' +
                              finding.severity.name),
                          const SizedBox(height: 4),
                          SelectableText(finding.problem),
                          if (finding.evidenceQuote != null) ...[
                            const SizedBox(height: 6),
                            const Text('Дословно проверенная цитата:'),
                            SelectableText('«' +
                                finding.evidenceQuote! + '»'),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('Что осталось неизвестным: ' + report.uncertainty),
                const SizedBox(height: 8),
                const Text('ИИ-проверка — только рекомендации. '
                    'Она не устанавливает достоверность сюжета, '
                    'не даёт персонажам новых знаний или предметов '
                    'и не меняет игру.'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
