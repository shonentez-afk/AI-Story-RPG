import 'package:flutter/material.dart';

import 'book_source_index.dart';
import 'book_import.dart';
import 'book_isolate_workers.dart';
import 'quick_rpg_builder.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';

/// Opens the short private RPG wizard directly from the library.
class QuickRpgFromBookPage extends StatefulWidget {
  const QuickRpgFromBookPage({super.key, required this.book,
    required this.gateway, this.indexer});
  final ImportedBook book;
  final WorldLibraryGateway gateway;
  final Future<BookSourceIndex> Function(ImportedBook)? indexer;
  @override
  State<QuickRpgFromBookPage> createState() => _QuickRpgFromBookPageState();
}

class _QuickRpgFromBookPageState extends State<QuickRpgFromBookPage> {
  late Future<BookSourceIndex> _index;
  @override
  void initState() { super.initState(); _load(); }
  void _load() {
    _index = (widget.indexer ?? indexImportedBookInWorker)(widget.book);
  }
  void _retry() { setState(_load); }
  @override
  Widget build(BuildContext context) => FutureBuilder<BookSourceIndex>(
    future: _index,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return QuickRpgPage(index: snapshot.data!, gateway: widget.gateway);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Создать RPG по книге')),
        body: SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (snapshot.hasError) ...[
              const Icon(Icons.warning_amber_outlined, size: 36),
              const SizedBox(height: 12),
              const Text('Не удалось подготовить текст книги. '
                  'Исходная книга и сохранения не изменились.'),
              Text(snapshot.error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('quick-rpg-index-retry'),
                onPressed: _retry,
                child: const Text('Повторить'),
              ),
            ] else ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('Подготавливаем «${widget.book.title}»…',
                  textAlign: TextAlign.center),
            ],
          ]),
        ))),
      );
    },
  );
}

/// A short path from a source book to an independently verified private
/// BookWorld. The user never needs to open a technical editor or copy files.
class QuickRpgPage extends StatefulWidget {
  const QuickRpgPage({
    super.key,
    required this.index,
    required this.gateway,
  });

  final BookSourceIndex index;
  final WorldLibraryGateway gateway;

  @override
  State<QuickRpgPage> createState() => _QuickRpgPageState();
}

class _QuickRpgPageState extends State<QuickRpgPage> {
  QuickRpgMode _mode = QuickRpgMode.changeFate;
  QuickRpgPlan? _plan;
  bool _reviewedQuotes = false;
  bool _privateUse = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    try {
      final plan = QuickRpgBuilder.propose(widget.index, mode: _mode);
      _plan = plan;
      _error = null;
    } on FormatException catch (error) {
      _plan = null;
      _error = error.message;
    } catch (_) {
      _plan = null;
      _error = 'Не удалось составить маршрут из фрагментов книги.';
    }
  }

  void _selectMode(QuickRpgMode value) {
    if (_working || _mode == value) return;
    setState(() {
      _mode = value;
      _reviewedQuotes = false;
      _prepare();
    });
  }

  Future<void> _start() async {
    final plan = _plan;
    if (_working || plan == null || !_reviewedQuotes || !_privateUse) return;
    setState(() { _working = true; _error = null; });
    try {
      final compiled = await QuickRpgBuilder.compile(
        plan: plan,
        allQuotesReviewedByUser: _reviewedQuotes,
        privateUseConfirmed: _privateUse,
      );
      if (!mounted || compiled.sourceFingerprint !=
          widget.index.sourceFingerprint) return;
      // install() does not modify any existing save or reading position.
      final installed = await widget.gateway.install(compiled.archive);
      if (installed.archiveHash != compiled.archiveSha256 ||
          installed.bookworldId != compiled.bookworldId) {
        throw const FormatException(
            'Установленный пакет не совпадает с проверенным.');
      }
      final campaignId = await widget.gateway.start(installed.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldPlayPage(
          gateway: widget.gateway,
          campaignId: campaignId,
        ),
      ));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Создание игры не завершено: $error. '
              'Книга и прежние прохождения не удалены.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final enabled = plan != null && !_working;
    return Scaffold(
      appBar: AppBar(title: const Text('Создать RPG из книги')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(widget.index.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text('Выберите режим. Приложение автоматически составит '
                'короткую личную игру по настоящим отрывкам книги. '
                'Позже её можно будет расширить в редакторе. '
                'Это пока НЕ полноценная автоматическая адаптация всей книги.'),
            const SizedBox(height: 18),
            Text('Как играть', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                key: const Key('quick-rpg-follow-book'),
                label: const Text('Сохранить сюжет'),
                selected: _mode == QuickRpgMode.followBook,
                onSelected: enabled
                    ? (_) => _selectMode(QuickRpgMode.followBook) : null,
              ),
              ChoiceChip(
                key: const Key('quick-rpg-change-fate'),
                label: const Text('Менять сюжет'),
                selected: _mode == QuickRpgMode.changeFate,
                onSelected: enabled
                    ? (_) => _selectMode(QuickRpgMode.changeFate) : null,
              ),
            ]),
            const SizedBox(height: 8),
            Text(_mode == QuickRpgMode.followBook
                ? 'Следуйте выбранным фрагментам в порядке книги. '
                    'Можно завершить маршрут раньше финала.'
                : 'Выбирайте: следовать книге или получить альтернативную '
                    'развязку после каждого эпизода. Альтернативы '
                    'написаны приложением, а не автором книги.'),
            const SizedBox(height: 18),
            if (plan != null) ...[
              Text('Проверка источника',
                  style: Theme.of(context).textTheme.titleMedium),
              Text('${plan.sourceScenes} отрывков · '
                  '${plan.endings} вариантов завершения. '
                  'Они выбраны автоматически из текста именно этой книги.'),
              const SizedBox(height: 6),
              const Text('Пожалуйста, убедитесь, что приведённые ниже '
                  'цитаты есть в книге и подходят как игровые эпизоды. '
                  'Возможны спойлеры из последних глав.'),
              for (var i = 0; i < plan.anchors.length; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Эпизод ${i + 1}, глава '
                            '${plan.anchors[i].chapterIndex + 1}',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        SelectableText('«${plan.anchors[i].quote}»'),
                      ],
                    ),
                  ),
                ),
              CheckboxListTile(
                key: const Key('quick-rpg-review-confirm'),
                value: _reviewedQuotes,
                onChanged: enabled ? (value) =>
                    setState(() => _reviewedQuotes = value == true) : null,
                title: const Text('Я проверил(а) отрывки и разрешаю '
                    'использовать их как эпизоды личной игры.'),
                subtitle: const Text('Это подтверждает цитаты, '
                    'а не достоверность всех событий и отношений героев.'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                key: const Key('quick-rpg-private-confirm'),
                value: _privateUse,
                onChanged: enabled ? (value) =>
                    setState(() => _privateUse = value == true) : null,
                title: const Text('Создать только личную игру на устройстве'),
                subtitle: const Text('Без отправки текста в ИИ, '
                    'публикации книги и удаления предыдущих сохранений.'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('quick-rpg-create-and-play'),
                onPressed: enabled && _reviewedQuotes && _privateUse
                    ? _start : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Создать и начать играть'),
              ),
            ],
            if (_working) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const Text('Проверяем ссылки на книгу и собираем '
                  'игровой мир на устройстве…'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, key: const Key('quick-rpg-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
