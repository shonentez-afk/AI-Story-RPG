import 'package:flutter/material.dart';

import 'book_import.dart';
import 'book_isolate_workers.dart';
import 'book_source_index.dart';
import 'quick_rpg_page.dart';
import 'world_library_gateway.dart';
import 'zai_auto_whole_book_analysis.dart';
import 'zai_whole_book_analysis_page.dart';

/// A single honest entry point for a library book. Neither opening this page
/// nor choosing the AI path sends any text to Z.ai: the downstream analysis
/// page requests an exact, explicit consent before its first POST.
///
/// The long path is still an experimental preparation pipeline, not CANON or
/// a promise that every source event has been understood.
class BookRpgStartPage extends StatefulWidget {
  const BookRpgStartPage({
    super.key,
    required this.book,
    required this.gateway,
    this.indexer,
    this.analysis,
  });

  final ImportedBook book;
  final WorldLibraryGateway gateway;

  /// Test seam; production indexes in a worker isolate.
  final Future<BookSourceIndex> Function(ImportedBook)? indexer;

  /// Test seam; real analysis is created only after the user selects AI.
  final ZaiAutoWholeBookAnalysis? analysis;

  @override
  State<BookRpgStartPage> createState() => _BookRpgStartPageState();
}

class _BookRpgStartPageState extends State<BookRpgStartPage> {
  bool _opening = false;
  String? _error;

  Future<void> _openOffline() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => QuickRpgFromBookPage(
          book: widget.book,
          gateway: widget.gateway,
          indexer: widget.indexer,
        ),
      ));
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Не удалось открыть офлайн-пробу: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openWholeBook() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      // No cloud call here. A new book revision must be indexed and verified
      // before any source-locked consent can be offered.
      final indexer = widget.indexer;
      final index = indexer == null
          ? await indexImportedBookInWorker(widget.book)
          : await indexer(widget.book);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ZaiWholeBookAnalysisPage(
          index: index,
          analysis: widget.analysis,
          gateway: widget.gateway,
        ),
      ));
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Не удалось открыть анализ книги: ' + error.toString() +
            '. Книга и ранее созданные игры не изменены.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Создать RPG по книге')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(widget.book.title,
              key: const Key('rpg-start-book-title'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Выберите доступный способ подготовки. '
              'Книга остаётся в вашей библиотеке; существующие '
              'прохождения не заменяются.'),
          const SizedBox(height: 8),
          const Text('Герой: сейчас используется игровой персонаж по '
              'умолчанию. Выбор любого героя книги ещё не реализован.'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Быстрая офлайн-проба',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Короткая игра по проверяемым фрагментам '
                      'без обращения к ИИ. Внутри можно выбрать '
                      '«Сохранить сюжет» или «Менять сюжет», '
                      'но это не полный CANON / ALTER_FATE.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('rpg-start-offline'),
                    onPressed: _opening ? null : _openOffline,
                    icon: const Icon(Icons.offline_bolt_outlined),
                    label: const Text('Начать офлайн-пробу'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Анализ всей книги через ИИ',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Сначала локально индексируем текст, затем '
                      'показываем объём и просим согласие на передачу '
                      'частей книги в Z.ai. Можно прервать и возобновить. '
                      'Следующие этапы пока создают пробную адаптацию, '
                      'а не литературно подтверждённую полную RPG.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('rpg-start-ai'),
                    onPressed: _opening ? null : _openWholeBook,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Подготовить книгу через ИИ'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Полный CANON, свободный выбор книжного героя '
              'и автоматическая завершённая RPG ещё разрабатываются. '
              'Эти возможности не выдаются за готовые режимы.'),
          if (_opening) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(
                key: Key('rpg-start-opening-progress')),
            const Text('Открываем выбранный способ подготовки…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                key: const Key('rpg-start-error'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    ),
  );
}
