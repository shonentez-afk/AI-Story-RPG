import 'dart:async';
import 'package:flutter/material.dart';
import 'book_import.dart';
import 'book_model.dart';
import 'book_reading_state.dart';
import 'reading_preferences.dart';
import 'reading_settings_sheet.dart';
import 'reader_chrome.dart';

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
  final ScrollController _scroll = ScrollController();
  Timer? _progressTimer;
  bool _restoring = false;

  void _saveScroll() {
    if (!_progressReady || _restoring || widget.bookId == null || !_scroll.hasClients) return;
    _progressTimer?.cancel();
    final offset = _scroll.offset;
    _progressTimer = Timer(const Duration(milliseconds: 350), () {
      _readingStore.save(widget.bookId!, _reading.copyWith(scrollOffset: offset));
    });
  }

  void _restoreScroll() {
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.jumpTo(_reading.scrollOffset.clamp(0.0, _scroll.position.maxScrollExtent));
      }
      _restoring = false;
    });
  }
  ReaderChromeMode _chrome = ReaderChromeMode.normal;


  @override
  void dispose() {
    _progressTimer?.cancel();
    if (widget.bookId != null && _scroll.hasClients) {
      _readingStore.save(widget.bookId!, _reading.copyWith(scrollOffset: _scroll.offset));
    }
    _scroll.dispose();
    super.dispose();
  }

  void _changeChrome(ReaderChromeMode next) {
    setState(() {
      _chrome = next;
    });
  }

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
    _restoreScroll();
  }

  void _chapter(int index) {
    if (index < 0 || index >= _count) return;
    _progressTimer?.cancel();
    setState(() => _reading = _reading.copyWith(chapter: index, scrollOffset: 0));
    _restoreScroll();
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

  String _chapterLabel(int i) {
    if (widget.book.structuredChapters.isNotEmpty) {
      final blocks = widget.book.structuredChapters[i].blocks;
      for (final block in blocks) {
        if (block.kind == BookBlockKind.heading && block.text.trim().isNotEmpty) {
          return block.text.trim().replaceAll(RegExp(r'\\s+'), ' ');
        }
      }
    }
    return 'Глава ${i + 1}';
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
              title: Text(_chapterLabel(i)),
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
    _scroll.addListener(_saveScroll);
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
      builder: (_) => ReadingSettingsSheet(
        preferences: _settings,
        onChanged: _change,
      ),
    );
  }

  Widget _blockWidget(BookBlock block, TextStyle readerText) {
    if (block.kind != BookBlockKind.image) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SelectableText(
          block.text,
          style: block.kind == BookBlockKind.heading
              ? readerText.copyWith(fontWeight: FontWeight.bold)
              : readerText,
        ),
      );
    }
    final image = widget.book.images[block.resourceId];
    if (image == null) {
      return Text('Иллюстрация недоступна', style: readerText.copyWith(fontSize: 13));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Semantics(
        label: 'Иллюстрация книги. Нажмите для увеличения',
        button: true,
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: InteractiveViewer(
                minScale: 0.5, maxScale: 5,
                child: Image.memory(image.bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          child: Image.memory(
            image.bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) =>
                Text('Ошибка изображения', style: readerText),
          ),
        ),
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
    final blocks = _count == 0 ? <BookBlock>[] :
        widget.book.structuredChapters.isNotEmpty
            ? widget.book.structuredChapters[_reading.chapter].blocks
            : widget.book.chapters[_reading.chapter]
                .split(RegExp(r'\\n\\s*\\n'))
                .where((text) => text.trim().isNotEmpty)
                .map((text) => BookBlock(kind: BookBlockKind.paragraph, text: text))
                .toList();

    return Scaffold(
      backgroundColor: prefs.background,
      appBar: !_chrome.showTopBar ? null : AppBar(
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
      floatingActionButton: ReaderChromeButton(
        mode: _chrome,
        background: prefs.foreground,
        foreground: prefs.background,
        onChange: _changeChrome,
      ),
      body: ColoredBox(
        color: prefs.background,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    prefs.horizontalPadding, 24, prefs.horizontalPadding, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_reading.chapter == 0 && widget.book.cover != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Image.memory(
                              widget.book.cover!, height: 280,
                              fit: BoxFit.contain,
                              errorBuilder: (_, error, stack) =>
                                  Icon(Icons.menu_book, color: prefs.foreground),
                            ),
                          ),
                        if (_reading.chapter == 0)
                          Text(widget.book.title,
                            style: readerText.copyWith(
                              fontSize: prefs.fontSize + 8,
                              fontWeight: FontWeight.bold)),
                        if (_reading.chapter == 0 && widget.book.author.isNotEmpty)
                          Text(widget.book.author, style: readerText),
                        const SizedBox(height: 18),
                        if (_count > 0)
                          Text(_chapterLabel(_reading.chapter),
                            style: readerText.copyWith(
                              fontSize: prefs.fontSize + 4,
                              fontWeight: FontWeight.w600)),
                        if (_count > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text('Глава ${_reading.chapter + 1} из $_count',
                              style: readerText.copyWith(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: prefs.horizontalPadding),
                  sliver: SliverList.builder(
                    itemCount: blocks.length,
                    itemBuilder: (context, index) => _blockWidget(
                      blocks[index], readerText),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(prefs.horizontalPadding, 8,
                    prefs.horizontalPadding, 110),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: prefs.foreground.withValues(alpha: 0.20)),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12, runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: prefs.foreground),
                              onPressed: _reading.chapter > 0
                                  ? () => _chapter(_reading.chapter - 1) : null,
                              icon: const Icon(Icons.chevron_left),
                              label: const Text('Назад'),
                            ),
                            Text('${_reading.chapter + 1} / $_count',
                              style: TextStyle(color: prefs.foreground)),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: prefs.foreground),
                              onPressed: _reading.chapter + 1 < _count
                                  ? () => _chapter(_reading.chapter + 1) : null,
                              icon: const Icon(Icons.chevron_right),
                              label: const Text('Далее'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('Режим чтения • RPG по этой книге появится позже',
                          style: readerText.copyWith(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
