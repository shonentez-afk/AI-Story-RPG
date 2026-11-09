import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:rpg_api/rpg_api.dart'
    show RpgWorldIntakePreview, WorldLibraryGateway, WorldLibraryItem,
    RpgBookGameplayAudit, BookGameplayAuditStatus;

import 'world_import_review_worker.dart';

typedef WorldImportInspector = Future<RpgWorldIntakePreview> Function(
    Uint8List archive, String? readiness);

/// A generator's .bworld is a compiled game, not a reader book.
/// This review never mutates the library or reimplements game rules.
abstract final class WorldImportReviewFlow {
  static Future<String?> pickReadinessJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'], withData: true,
    );
    if (result == null) return null;
    if (result.files.length != 1 ||
        !result.files.single.name.toLowerCase().endsWith('.readiness.json') ||
        result.files.single.size > 256 * 1024 ||
        result.files.single.bytes == null) {
      throw const FormatException(
          'Выберите отдельный .readiness.json (до 256 КБ).');
    }
    return utf8.decode(result.files.single.bytes!, allowMalformed: false);
  }

  static Future<WorldLibraryItem?> confirmAndInstall({
    required BuildContext context,
    required Uint8List archive,
    required WorldLibraryGateway gateway,
    Future<String?> Function()? pickReadiness,
    WorldImportInspector? inspector,
  }) async {
    final safeArchive = Uint8List.fromList(archive);
    final review = inspector ?? reviewImportedWorldInWorker;
    final initial = await review(safeArchive, null);
    if (!context.mounted) return null;
    final approved = await showDialog<_ReviewedImport>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WorldImportReviewDialog(
        archive: safeArchive, initial: initial, review: review,
        pickReadiness: pickReadiness ?? pickReadinessJson,
      ),
    );
    if (approved == null || !context.mounted) return null;
    // Second read-only verification immediately before real install.
    final current = await review(safeArchive, approved.readinessJson);
    if (current.archiveHash != approved.preview.archiveHash ||
        current.bookworldId != approved.preview.bookworldId ||
        current.sourceFingerprint != approved.preview.sourceFingerprint ||
        current.generatorReportAttached !=
            approved.preview.generatorReportAttached) {
      throw const FormatException('Мир или отчёт изменились после согласия.');
    }
    final installed = await gateway.install(safeArchive);
    if (installed.archiveHash != current.archiveHash ||
        installed.bookworldId != current.bookworldId ||
        installed.title != current.title) {
      throw const FormatException(
          'Установленная игра отличается от проверенного пакета.');
    }
    return installed;
  }
}

final class _ReviewedImport {
  const _ReviewedImport(this.preview, this.readinessJson);
  final RpgWorldIntakePreview preview;
  final String? readinessJson;
}

class _WorldImportReviewDialog extends StatefulWidget {
  const _WorldImportReviewDialog({
    required this.archive, required this.initial,
    required this.review, required this.pickReadiness,
  });
  final Uint8List archive;
  final RpgWorldIntakePreview initial;
  final WorldImportInspector review;
  final Future<String?> Function() pickReadiness;

  @override
  State<_WorldImportReviewDialog> createState() =>
      _WorldImportReviewDialogState();
}

class _WorldImportReviewDialogState extends State<_WorldImportReviewDialog> {
  late RpgWorldIntakePreview _preview = widget.initial;
  String? _readiness, _error;
  RpgBookGameplayAudit? _gameplayAudit;
  bool _loading = false;

  Future<void> _auditGameplay() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await auditImportedWorldInWorker(widget.archive);
      if (!mounted) return;
      if (result.archiveHash != _preview.archiveHash) {
        throw const FormatException('Игровой архив изменён до проверки.');
      }
      setState(() => _gameplayAudit = result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Проверка игрового маршрута: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _attach() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final text = await widget.pickReadiness();
      if (text == null) return;
      final inspected = await widget.review(widget.archive, text);
      if (!mounted) return;
      setState(() { _readiness = text; _preview = inspected; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Отчёт отклонён: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _discard() {
    setState(() {
      _readiness = null;
      _preview = widget.initial;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Проверить готовую RPG'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_preview.title, key: const Key('world-intake-title'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Проверен движком BookWorld v${_preview.formatVersion}: '
              '${_preview.sceneCount} сцен, '
              '${_preview.endingCount} финалов, '
              '${_preview.npcActorCount} NPC, '
              '${_preview.itemCount} предметов.'),
          if (_preview.sourceChaptersTotal > 0)
            Text('По оригиналу подтверждены главы: '
                '${_preview.sourceChaptersWithGameplay}/'
                '${_preview.sourceChaptersTotal}. '
                'Проверено источником BookWorld, не текстом отчёта.'),
          const SizedBox(height: 8),
          Text(_preview.isPrivate
              ? 'Частная игровая адаптация; публикация не разрешена.'
              : 'Демонстрационный мир, а не частная адаптация.'),
          const SizedBox(height: 8),
          if (_preview.sourceCausalReviewVerified) ...[
            const SizedBox(height: 8),
            const Text('Подтверждён исходный причинный граф v5: '
                'условия событий и NPC проверены штатным движком. '
                'Литературные мотивы требуют отдельной оценки.',
                key: Key('world-intake-verified-causality')),
          ] else if (_preview.sourceLiteralCanonVerified) ...[
            const SizedBox(height: 8),
            const Text('Буквальный CANON подтверждён, но полный '
                'причинный обзор книги не приложен.',
                key: Key('world-intake-literal-only')),
          ],
          const Text('Точный ZIP и игровые правила проверяются '
              'независимым движком. Литературный канон и качество '
              'автоматически не подтверждаются.'),
          const SizedBox(height: 8),
          Text(_preview.generatorReportAttached
            ? 'Отчёт генератора соответствует SHA-256 этой игры и '
              'заявляет две разные завершённые партии. Отчёт — '
              'заявление автора, а не повторный прогон на этом устройстве.'
            : 'Отчёт .readiness.json не приложен. '
              'Это не препятствует проверенному офлайн-импорту.',
            key: const Key('world-intake-report-status')),
          if (_gameplayAudit != null) ...[
            const SizedBox(height: 8),
            Text(switch (_gameplayAudit!.status) {
              BookGameplayAuditStatus.playable =>
                  'Сам движок проверил все финалы и отсутствие '
                  'безвыходных состояний за '
                  '${_gameplayAudit!.exploredStates} состояний.',
              BookGameplayAuditStatus.blocked =>
                  'Движок нашёл недоступные финалы или сюжетную ловушку. '
                  'Установка заблокирована.',
              BookGameplayAuditStatus.inconclusive =>
                  'Проверка игрового графа достигла лимита. '
                  'Это не доказательство ошибки или полной готовности.',
            }, key: const Key('world-intake-gameplay-audit')),
          ],
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, key: const Key('world-intake-report-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          Wrap(spacing: 6, runSpacing: 4, children: [
            OutlinedButton(
              key: const Key('world-intake-audit-gameplay'),
              onPressed: _loading || _preview.formatVersion < 3
                  ? null : _auditGameplay,
              child: const Text('Проверить игровые маршруты'),
            ),
            OutlinedButton(
              key: const Key('world-intake-attach-report'),
              onPressed: _loading || _preview.formatVersion != 4
                  ? null : _attach,
              child: const Text('Приложить отчёт генератора'),
            ),
            if (_readiness != null || _error != null)
              TextButton(key: const Key('world-intake-remove-report'),
                onPressed: _loading ? null : _discard,
                child: const Text('Продолжить без отчёта')),
          ]),
        ],
      )),
    ),
    actions: [
      TextButton(key: const Key('world-intake-cancel'),
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: const Text('Отмена')),
      FilledButton(key: const Key('world-intake-confirm'),
        onPressed: _loading || _error != null ||
            _gameplayAudit?.status == BookGameplayAuditStatus.blocked ? null
            : () => Navigator.pop(context,
                _ReviewedImport(_preview, _readiness)),
        child: const Text('Добавить RPG')),
    ],
  );
}
