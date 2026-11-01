import 'package:flutter/material.dart';
import 'book_import.dart';
import 'book_model.dart';
import 'book_reading_state.dart';
import 'reading_preferences.dart';

class BookReaderPage extends StatefulWidget {
  const BookReaderPage({super.key, required this.book, this.bookId});
  final ImportedBook book;
  final String? bookId;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  final ReadingSettingsStore _store = ReadingSettingsStore();
  ReadingPreferences _settings = const ReadingPreferences();
  final BookReadingStore _readingStore = BookReadingStore();
  BookReadingState _reading = const BookReadingState();
  bool _progressReady = false;
  bool _immersive = false;

  int get _count => widget.book.structuredChapters.isNotEmpty
      ? widget.book.structuredChapters.length : widget.book.chapters.length;

  Future<void> _loadPosition() async {
    if (widget.bookId == null) {
      setState(() => _progressReady = true);
      return;
    }
    final saved = await _readingStore.load(widget.bookId!);
    if (mounted) setState(() {
      _reading = saved.copyWith(chapter: saved.chapter.clamp(0, _count > 0 ? _count - 1 : 0).toInt());
      _progressReady = true;
    });
  }

  void _chapter(int index) {
    if (index < 0 || index >= _count) return;
    setState(() => _reading = _reading.copyWith(chapter: index));
    if (widget.bookId != null) {
      _readingStore.save(widget.bookId!, _reading);
    }
  }

  void _bookmark() {
    final marks = _reading.bookmarks.toSet();
    if (!marks.add(_reading.chapter)) marks.remove(_reading.chapter);
    setState(() => _reading = _reading.copyWith(bookmarks: marks.toList()..sort()));
    if (widget.bookId != null) _readingStore.save(widget.bookId!, _reading);
  }

  void _chapters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: ListView.builder(
            itemCount: _count,
            itemBuilder: (context, i) => ListTile(
              leading: Icon(_reading.bookmarks.contains(i)
                  ? Icons.bookmark : Icons.menu_book_outlined),
              title: Text('Глава ${i + 1}'),
              subtitle: i == _reading.chapter ? const Text('Текущая') : null,
              onTap: () {
                Navigator.pop(context);
                _chapter(i);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPosition();
  }

  Future<void> _loadSettings() async {
    try {
      final value = await _store.load();
      if (mounted) setState(() => _settings = value);
    } catch (_) {
      // Defaults remain usable when preferences cannot be read.
    }
  }

  void _change(ReadingPreferences next) {
    setState(() => _settings = next);
    _store.save(next);
  }

  void _showReaderSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) {
          void apply(ReadingPreferences value) {
            _change(value);
            updateSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Настройки чтения',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final entry in <(ReadingPalette, String)>[
                        (ReadingPalette.light, 'Свет'),
                        (ReadingPalette.sepia, 'Сепия'),
                        (ReadingPalette.dark, 'Тёмная'),
                        (ReadingPalette.oled, 'OLED'),
                      ])
                        ChoiceChip(
                          label: Text(entry.$2),
                          selected: _settings.palette == entry.$1,
                          onSelected: (_) =>
                              apply(_settings.copyWith(palette: entry.$1)),
                        ),
                    ],
                  ),
                  Text('Размер текста: ${_settings.fontSize.toStringAsFixed(0)}'),
                  Slider(
                    value: _settings.fontSize, min: 12, max: 32, divisions: 20,
                    onChanged: (value) =>
                        apply(_settings.copyWith(fontSize: value)),
                  ),
                  Text('Интервал: ${_settings.lineHeight.toStringAsFixed(2)}'),
                  Slider(
                    value: _settings.lineHeight, min: 1.2, max: 2.2,
                    divisions: 20,
                    onChanged: (value) =>
                        apply(_settings.copyWith(lineHeight: value)),
                  ),
                  Text('Поля: ${_settings.horizontalPadding.toStringAsFixed(0)}'),
                  Slider(
                    value: _settings.horizontalPadding, min: 12, max: 48,
                    divisions: 18,
                    onChanged: (value) =>
                        apply(_settings.copyWith(horizontalPadding: value)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _settings;
    final readerText = TextStyle(
      fontSize: prefs.fontSize,
      height: prefs.lineHeight,
      color: prefs.foreground,
    );

    return Scaffold(
      appBar: _immersive ? null : AppBar(
        backgroundColor: prefs.background,
        foregroundColor: prefs.foreground,
        title: Text(widget.book.title),
        actions: [
          IconButton(
            tooltip: 'Оглавление',
            onPressed: _chapters,
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: _reading.bookmarks.contains(_reading.chapter)
                ? 'Убрать закладку' : 'Добавить закладку',
            onPressed: _progressReady && widget.bookId != null ? _bookmark : null,
            icon: Icon(_reading.bookmarks.contains(_reading.chapter)
                ? Icons.bookmark : Icons.bookmark_border),
          ),
          IconButton(
            tooltip: 'Настройки чтения',
            onPressed: _showReaderSettings,
            icon: const Icon(Icons.text_fields),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: _immersive ? 'Показать управление' : 'Скрыть управление',
        onPressed: () => setState(() => _immersive = !_immersive),
        child: Icon(_immersive ? Icons.visibility : Icons.visibility_off),
      ),
      body: ColoredBox(
        color: prefs.background,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: prefs.horizontalPadding,
                vertical: 24,
              ),
              children: [
                if (_reading.chapter == 0 && widget.book.cover != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Image.memory(
                      widget.book.cover!,
                      height: 280,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) =>
                          Icon(Icons.menu_book, color: prefs.foreground),
                    ),
                  ),
                Text(widget.book.title,
                    style: readerText.copyWith(
                      fontSize: prefs.fontSize + 8,
                      fontWeight: FontWeight.bold,
                    )),
                if (widget.book.author.isNotEmpty)
                  Text(widget.book.author, style: readerText),
                const SizedBox(height: 24),
                if (_count > 0) ...[
                  Text('Глава ${_reading.chapter + 1} из $_count',
                      style: readerText.copyWith(
                        fontSize: prefs.fontSize + 4,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 12),
                  if (widget.book.structuredChapters.isNotEmpty)
                    for (final block in widget.book.structuredChapters[_reading.chapter].blocks) ...[
                      if (block.kind == BookBlockKind.image)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Builder(builder: (context) {
                            final image = widget.book.images[block.resourceId];
                            if (image == null) {
                              return Text('Иллюстрация недоступна',
                                  style: readerText.copyWith(fontSize: 13));
                            }
                            return InkWell(
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) => Dialog(
                                  child: InteractiveViewer(
                                    minScale: 0.5, maxScale: 5,
                                    child: Image.memory(image.bytes, fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                              child: Image.memory(image.bytes, fit: BoxFit.contain,
                                  errorBuilder: (_, error, stack) =>
                                      Text('Ошибка изображения', style: readerText)),
                            );
                          }),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SelectableText(block.text,
                            style: block.kind == BookBlockKind.heading
                                ? readerText.copyWith(fontWeight: FontWeight.bold)
                                : readerText),
                        ),
                    ]
                  else
                    SelectableText(widget.book.chapters[_reading.chapter], style: readerText),
                  const Divider(height: 36),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _reading.chapter > 0
                            ? () => _chapter(_reading.chapter - 1) : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Назад'),
                      ),
                      Text('${_reading.chapter + 1} / $_count',
                          style: TextStyle(color: prefs.foreground)),
                      FilledButton.tonalIcon(
                        onPressed: _reading.chapter + 1 < _count
                            ? () => _chapter(_reading.chapter + 1) : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Далее'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],
                Text('Режим чтения • RPG по этой книге появится позже',
                    style: readerText.copyWith(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
