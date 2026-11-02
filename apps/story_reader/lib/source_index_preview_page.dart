import 'dart:isolate';

import 'package:flutter/material.dart';

import 'book_import.dart';
import 'book_source_index.dart';

/// M2a inspection from the existing book library. No duplicate import
/// controls and no claim that an index equals a playable AI-generated RPG.
class SourceIndexPreviewPage extends StatefulWidget {
  const SourceIndexPreviewPage({super.key, required this.book});
  final ImportedBook book;

  @override
  State<SourceIndexPreviewPage> createState() => _SourceIndexPreviewPageState();
}

class _SourceIndexPreviewPageState extends State<SourceIndexPreviewPage> {
  late Future<BookSourceIndex> _result;

  @override
  void initState() {
    super.initState();
    _buildIndex();
  }

  void _buildIndex() {
    // Native Dart runs offline on Windows and Android. Large TXT/FB2 books
    // are processed outside the UI isolate.
    _result = Isolate.run(() => BookSourceIndexer.index(widget.book));
  }

  void _retry() => setState(_buildIndex);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Подготовка книги'),
    ),
    body: FutureBuilder<BookSourceIndex>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Разбиваем исходный текст на проверяемые фрагменты…'),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_outlined, size: 40),
                    const SizedBox(height: 12),
                    Text('Не удалось проиндексировать книгу: '
                        '${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final index = snapshot.requireData;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.book.title,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        const Text('Этап M2a — индекс исходного текста'),
                        const SizedBox(height: 14),
                        Text('Главы с текстом: '
                            '${index.indexedChapterCount} из ${index.chapterCount}'),
                        Text('Индексировано символов: '
                            '${index.indexedTextUtf16} из ${index.totalTextUtf16}'),
                        Text('Текстовое покрытие индекса: '
                            '${(index.textIndexCoverage * 100).toStringAsFixed(1)}%'),
                        Text('Иллюстраций на отдельную проверку: '
                            '${index.unindexedMediaBlocks}'),
                        const SizedBox(height: 12),
                        const Text(
                          'Это только подготовка исходных фрагментов. '
                          'Персонажи, сюжет и игровые сцены ещё не созданы. '
                          'Готового игрового мира нет; текст никуда не отправлялся.',
                        ),
                        const SizedBox(height: 12),
                        Text('Фрагментов на последующий анализ: '
                            '${index.chunks.length}'),
                        const Divider(height: 28),
                        Text('Разделы произведения',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: index.chapters.length,
                  itemBuilder: (context, i) {
                    final chapter = index.chapters[i];
                    return ListTile(
                      title: Text('Глава ${chapter.chapterIndex + 1}'),
                      subtitle: Text(
                        'Фрагментов: ${chapter.sourceChunks} · '
                        'Статус анализа: ожидает'
                        ${chapter.hasUnindexedMedia
                            ? ' · Иллюстрации требуют проверки'
                            : ''}',
                      ),
                      leading: Icon(
                        chapter.fullyIndexed
                            ? Icons.check_circle_outline
                            : Icons.report_gmailerrorred_outlined,
                      ),
                    );
                  },
                ),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: 24),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
