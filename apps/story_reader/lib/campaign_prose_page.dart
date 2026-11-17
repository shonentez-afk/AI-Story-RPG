import 'dart:async';
import 'dart:typed_data';

import 'package:bookworld_format/reviewed_campaign_prose_writer.dart';
import 'package:flutter/material.dart';

import 'campaign_prose_authoring.dart';
import 'zai_semantic_preview.dart';

/// Final authoring step, not another library or runtime. Returns reviewed
/// bytes to the SAME installation flow; opening this page never makes a POST.
class CampaignProsePage extends StatefulWidget {
  const CampaignProsePage({
    super.key, required this.manifest, this.store, this.service,
    this.acceptExisting, this.applyReviewed,
  });
  final CampaignProseManifest manifest;
  final CampaignProseStore? store;
  final ZaiCampaignProse? service;
  /// Client-supplied callbacks let the same stage-gated RPG API complete
  /// both the original-text and approved full-narration paths.
  final Future<Uint8List> Function()? acceptExisting;
  final Future<Uint8List> Function(
    CampaignProseSession session,
    CampaignProseStore store,
    String approvedDigest,
    bool fullTextReviewed,
    bool privateFictionConfirmed,
  )? applyReviewed;
  @override State<CampaignProsePage> createState() => _CampaignProsePageState();
}

class _CampaignProsePageState extends State<CampaignProsePage> {
  late final _store = widget.store ?? CampaignProseStore();
  late final _service = widget.service ?? ZaiCampaignProse();
  CampaignProseSession? _session;
  ZaiPreviewCancellation? _token;
  bool _busy = false, _reviewed = false, _fiction = false;
  String? _error;
  bool get _complete => _session != null &&
      _session!.entries.length == widget.manifest.sceneIds.length;

  @override void initState() { super.initState(); unawaited(_load()); }
  @override void dispose() { _token?.cancel(); super.dispose(); }
  void _invalidate() { _reviewed = false; _fiction = false; }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      await widget.manifest.verifyCurrent();
      final session = await _store.load(widget.manifest);
      if (mounted) setState(() { _session = session; _error = null; _invalidate(); });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _generate() async {
    if (_busy || _session == null || _complete) return;
    setState(() { _busy = true; _error = null; _invalidate(); });
    final token = ZaiPreviewCancellation(); _token = token;
    try {
      await widget.manifest.verifyCurrent();
      final current = await _store.load(widget.manifest);
      if (current.recordHash != _session!.recordHash) throw const FormatException('Текст изменён в другом окне. Перечитайте сохранённую версию.');
      final request = CampaignProseRequest.prepare(widget.manifest, current);
      if (!mounted) return;
      var agreed = false;
      final yes = await showDialog<bool>(context: context, builder: (ctx) =>
        StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
          title: const Text('Подготовить текст оставшихся сцен?'), scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Новых запросов: ${request.requestCount}, с временными повторами — '
                'не более ${request.maximumAttempts}. Готовые и ручные тексты повторно не передаются.'),
            const Text('Передаются показанные цели сцен, разрешённые исходные '
                'цитаты, замысел истории и инвентарь по реальным путям игры. '
                'Скрытые реплики NPC, их тайны и игровые сохранения не отправляются. '
                'Каждый ответ сохраняется локально. Применяются условия аккаунта Z.ai.'),
            ExpansionTile(key: const Key('campaign-prose-payload'),
              title: const Text('Все точные данные для отправки'),
              children: [SelectableText(request.shownText)]),
            CheckboxListTile(key: const Key('campaign-prose-cloud-consent'), value: agreed,
              title: const Text('Разрешаю отправить именно показанные данные'),
              onChanged: (v) => refresh(() => agreed = v == true)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(key: const Key('campaign-prose-cloud-send'),
              onPressed: agreed ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Подготовить текст'))],
        )));
      if (yes != true || !mounted) return;
      await _service.generate(manifest: widget.manifest, store: _store, request: request,
        approvedDigest: request.approvalDigest, explicitCloudConsent: true,
        cancellation: token, onSaved: (session) {
          if (mounted) setState(() { _session = session; _invalidate(); });
        });
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { _token = null; if (mounted) setState(() => _busy = false); }
  }

  Future<void> _edit(String sceneId) async {
    if (_busy || _session == null) return;
    setState(() { _busy = true; _invalidate(); _error = null; });
    try {
      final text = await showDialog<String>(context: context, builder: (_) =>
          _ProseEditDialog(initial: _session!.entries[sceneId]?.text ?? ''));
      if (text == null) return;
      final next = CampaignProseEntry(sceneId: sceneId, text: text,
        uncertainty: 'Текст отредактирован автором как частная игровая адаптация.');
      final session = await _store.save(manifest: widget.manifest, expected: _session!,
        entries: [..._session!.entries.values.where((e) => e.sceneId != sceneId), next]);
      if (mounted) setState(() => _session = session);
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _keepOriginal() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.manifest.verifyCurrent();
      final archive = widget.acceptExisting == null
          ? widget.manifest.originalArchive
          : await widget.acceptExisting!();
      if (mounted) Navigator.pop<Uint8List>(context, archive);
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _accept() async {
    if (_busy || !_complete || !_reviewed || !_fiction) return;
    final session = _session!;
    setState(() { _busy = true; _error = null; });
    try {
      final review = CampaignProseAcceptance.review(widget.manifest, session);
      final digest = ReviewedCampaignProseWriter.digest(review);
      final archive = widget.applyReviewed == null
          ? await CampaignProseAcceptance.build(
              manifest: widget.manifest, store: _store, session: session,
              approvedDigest: digest, fullTextReviewed: _reviewed,
              privateFictionConfirmed: _fiction)
          : await widget.applyReviewed!(
              session, _store, digest, _reviewed, _fiction);
      if (mounted) Navigator.pop<Uint8List>(context, archive);
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _invalidate(); });
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override Widget build(BuildContext context) {
    final manifest = widget.manifest, contexts = manifest.contexts;
    return PopScope(canPop: !_busy,
      onPopInvokedWithResult: (popped, _) { if (!popped) _token?.cancel(); },
      child: Scaffold(appBar: AppBar(title: const Text('Текст всего прохождения')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Игра уже собрана. Можно сохранить прежний текст или подготовить '
              'повествование для всех сцен и обеих развязок. Правила, исходные '
              'цитаты и отдельно согласованные диалоги NPC не переписываются.'),
          const SizedBox(height: 8),
          Text('Сохранено сцен: ${_session?.entries.length ?? 0} из ${manifest.sceneIds.length}.',
              key: const Key('campaign-prose-progress')),
          const Text('После возврата текст восстановится локально, но согласия '
              'на отправку и применение не сохраняются. Наличие текста не '
              'доказывает соответствие литературному канону — прочтите его перед применением.'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(key: const Key('campaign-prose-keep-original'),
              onPressed: _busy ? null : _keepOriginal, child: const Text('Оставить прежний текст и продолжить')),
            OutlinedButton(key: const Key('campaign-prose-reload'),
              onPressed: _busy ? null : _load, child: const Text('Перечитать сохранённый текст')),
            FilledButton(key: const Key('campaign-prose-generate'),
              onPressed: !_busy && _session != null && !_complete ? _generate : null,
              child: const Text('Подготовить оставшиеся сцены через ИИ')),
          ]),
          for (var i = 0; i < manifest.sceneIds.length; i++)
            ExpansionTile(key: ValueKey('campaign-prose-scene-${manifest.sceneIds[i]}'),
              title: Text('${i + 1}. ${contexts[manifest.sceneIds[i]]['goal']}'),
              subtitle: Text(contexts[manifest.sceneIds[i]]['terminal'] == true
                  ? 'Развязка — ${_session?.entries.containsKey(manifest.sceneIds[i]) == true ? 'текст сохранён' : 'нет текста'}'
                  : (_session?.entries.containsKey(manifest.sceneIds[i]) == true ? 'Текст сохранён' : 'Ожидает подготовки')),
              children: [
                if (_session?.entries[manifest.sceneIds[i]] != null) ...[
                  SelectableText(_session!.entries[manifest.sceneIds[i]]!.text),
                  Text(_session!.entries[manifest.sceneIds[i]]!.uncertainty),
                ],
                TextButton(key: ValueKey('campaign-prose-edit-${manifest.sceneIds[i]}'),
                  onPressed: !_busy && _session != null ? () => _edit(manifest.sceneIds[i]) : null,
                  child: const Text('Написать или исправить вручную')),
              ]),
          CheckboxListTile(key: const Key('campaign-prose-full-review'), value: _reviewed,
            title: const Text('Прочитал текст всех сцен, включая обе развязки'),
            onChanged: !_busy && _complete ? (v) => setState(() => _reviewed = v == true) : null),
          CheckboxListTile(key: const Key('campaign-prose-fiction'), value: _fiction,
            title: const Text('Одобряю этот текст как частную игровую адаптацию'),
            onChanged: !_busy && _complete ? (v) => setState(() => _fiction = v == true) : null),
          FilledButton(key: const Key('campaign-prose-accept'),
            onPressed: !_busy && _complete && _reviewed && _fiction ? _accept : null,
            child: const Text('Проверить полное прохождение и применить текст')),
          if (_busy) ...[
            const LinearProgressIndicator(),
            if (_token != null) TextButton(key: const Key('campaign-prose-cancel'),
              onPressed: () => _token?.cancel(), child: const Text('Остановить дальнейшие запросы')),
          ],
          if (_error != null) SelectableText(_error!, key: const Key('campaign-prose-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]))));
  }
}

class _ProseEditDialog extends StatefulWidget {
  const _ProseEditDialog({required this.initial});
  final String initial;
  @override State<_ProseEditDialog> createState() => _ProseEditDialogState();
}
class _ProseEditDialogState extends State<_ProseEditDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Повествование сцены'), scrollable: true,
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Один русский абзац без прямой речи. Диалоги NPC сохраняются отдельно. '
          'Не описывайте невыполненный выбор как уже совершённое действие.'),
      TextField(key: const Key('campaign-prose-manual-text'), controller: _controller,
        minLines: 4, maxLines: 10, maxLength: 1800),
      if (_error != null) Text(_error!),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
      FilledButton(key: const Key('campaign-prose-manual-save'), onPressed: () {
        try {
          final text = _controller.text.trim();
          ReviewedCampaignProseWriter.validateNarration(text);
          Navigator.pop(context, text);
        } catch (error) { setState(() => _error = error.toString()); }
      }, child: const Text('Сохранить текст'))]);
}
