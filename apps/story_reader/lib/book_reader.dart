import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

class _BookReaderPageState extends State<BookReaderPage>
    with WidgetsBindingObserver {
  final ReadingSettingsStore _store = ReadingSettingsStore();
  ReadingPreferences _settings = const ReadingPreferences();
  final BookReadingStore _readingStore = BookReadingStore();
  BookReadingState _reading = const BookReadingState();
  bool _progressReady = false;
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  int _scrollEpoch = 0;
  final GlobalKey _viewportKey = GlobalKey();
  GlobalKey _priorBlocksKey = GlobalKey();
  GlobalKey _currentBlocksKey = GlobalKey();
  GlobalKey _centerSliverKey = GlobalKey();
  Timer? _progressTimer;
  bool _restoring = false;
  int? _layoutAnchorIndex;
  int _visibleBlockCount = 0;

  /// Locate the first paragraph intersecting the viewport top using only
  /// Flutter's currently rendered lazy sliver children (O(visible items)).
  /// No GlobalKey per paragraph, eager measuring or full-book layout.
  BookTextAnchor? _visibleTextAnchor() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy + 1;
    BookTextAnchor? lastVisible;
    for (final pair in [
      (_priorBlocksKey, _layoutAnchorIndex == null ? 0 : _layoutAnchorIndex! - 1),
      (_currentBlocksKey, _layoutAnchorIndex ?? 0),
    ]) {
      final sliver = pair.$1.currentContext?.findRenderObject();
      if (sliver is! RenderSliverList) continue;
      var child = sliver.firstChild;
      while (child != null) {
        final y = child.localToGlobal(Offset.zero).dy;
        final height = child.size.height;
        final index = pair.$1 == _priorBlocksKey && _layoutAnchorIndex != null
            ? pair.$2 - sliver.indexOf(child)
            : pair.$2 + sliver.indexOf(child);
        if (index >= _visibleBlockCount) break;
        if (height > 0 && y + height > top && y <= top) {
          final fraction = ((top - y) / height).clamp(0.0, 1.0).toDouble();
          return BookTextAnchor(blockIndex: index, fraction: fraction);
        }
        if (y > top) {
          // A title, header or cover is at the top, not this paragraph.
          return null;
        }
        if (height > 0 && y <= top) {
          lastVisible = BookTextAnchor(blockIndex: index, fraction: 1);
        }
        child = sliver.childAfter(child);
      }
    }
    // At the navigation footer, retain the final source block.
    return lastVisible;
  }

  BookReadingState _snapshotPosition() {
    if (!_scroll.hasClients) return _reading;
    final anchor = _visibleTextAnchor();
    return _reading.copyWith(
      scrollOffset: _scroll.offset.clamp(0.0, 100000000.0).toDouble(),
      anchor: anchor,
      clearAnchor: anchor == null,
    );
  }

  void _saveScroll() {
    if (!_progressReady || _restoring || widget.bookId == null ||
        !_scroll.hasClients) return;
    final snapshot = _snapshotPosition();
    _reading = snapshot;
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 350), () {
      if (widget.bookId != null) {
        unawaited(_readingStore.save(widget.bookId!, snapshot));
      }
    });
  }

  /// Reconstruct an anchored layout with the target paragraph as the sliver
  /// center. Earlier blocks remain scrollable backwards, even in long books.
  void _restoreScroll() {
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        final anchor = _reading.anchor;
        double offset = _reading.scrollOffset;
        if (_layoutAnchorIndex != null && anchor != null) {
          final sliver = _currentBlocksKey.currentContext?.findRenderObject();
          if (sliver is RenderSliverList && sliver.firstChild != null) {
            offset = sliver.firstChild!.size.height *
                anchor.fraction.clamp(0.0, 1.0);
          } else {
            offset = 0;
          }
        }
        final pos = _scroll.position;
        _scroll.jumpTo(offset.clamp(
          pos.minScrollExtent, pos.maxScrollExtent,
        ).toDouble());
      }
      _restoring = false;
    });
  }

  /// A font, width, line-height or reader-chrome change preserves a semantic
  /// paragraph location rather than reusing pixel offsets after reflow.
  void _reflow({
    ReadingPreferences? settings,
    ReaderChromeMode? chrome,
    bool useLastKnownAnchor = false,
  }) {
    _progressTimer?.cancel();
    final next = useLastKnownAnchor
        ? _reading : (_progressReady ? _snapshotPosition() : _reading);
    _restoring = true;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      // IMPORTANT: sliver GlobalKeys must be regenerated when a center is
      // introduced or moved. Reparenting the old RenderSliverList preserves
      // dead-reckoned child offsets from the previous chapter layout,
      // causing RenderViewport.correctBy(paragraphHeight) on every frame.
      _scrollEpoch++;
      _priorBlocksKey = GlobalKey();
      _currentBlocksKey = GlobalKey();
      _centerSliverKey = GlobalKey();
      _reading = next;
      _layoutAnchorIndex = next.anchor?.blockIndex;
      if (settings != null) _settings = settings;
      if (chrome != null) _chrome = chrome;
    });
    _restoreScroll();
    if (widget.bookId != null && _progressReady) {
      unawaited(_readingStore.save(widget.bookId!, next));
    }
  }
  ReaderChromeMode _chrome = ReaderChromeMode.normal;


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    if (widget.bookId != null && _scroll.hasClients && _progressReady) {
      final snapshot = _restoring ? _reading : _snapshotPosition();
      unawaited(_readingStore.save(widget.bookId!, snapshot));
    }
    _scroll.dispose();
    super.dispose();
  }

  void _changeChrome(ReaderChromeMode next) => _reflow(chrome: next);

  int get _count => widget.book.structuredChapters.isNotEmpty
      ? widget.book.structuredChapters.length : widget.book.chapters.length;

  Future<void> _loadPosition() async {
    if (widget.bookId == null) {
      setState(() => _progressReady = true);
      return;
    }
    // A damaged or inaccessible preference record must not prevent
    // opening the imported book. Fall back to its first chapter.
    BookReadingState saved;
    try {
      saved = await _readingStore.load(widget.bookId!);
    } catch (_) {
      saved = const BookReadingState();
    }
    if (!mounted) return;
    setState(() {
      _reading = saved.copyWith(chapter:
          saved.chapter.clamp(0, _count > 0 ? _count - 1 : 0).toInt());
      _layoutAnchorIndex = saved.anchor?.blockIndex;
      _scrollEpoch++;
      _priorBlocksKey = GlobalKey();
      _currentBlocksKey = GlobalKey();
      _centerSliverKey = GlobalKey();
      _progressReady = true;
    });
    _restoreScroll();
  }

  void _chapter(int index) {
    if (index < 0 || index >= _count) return;
    _progressTimer?.cancel();
    _restoring = true;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _reading = _reading.copyWith(
        chapter: index, scrollOffset: 0, clearAnchor: true,
      );
      _layoutAnchorIndex = null;
      _scrollEpoch++;
      _priorBlocksKey = GlobalKey();
      _currentBlocksKey = GlobalKey();
      _centerSliverKey = GlobalKey();
    });
    _restoreScroll();
    if (widget.bookId != null) {
      unawaited(_readingStore.save(widget.bookId!, _reading));
    }
  }

  void _bookmark() {
    final marks = _reading.bookmarks.toSet();
    if (!marks.add(_reading.chapter)) marks.remove(_reading.chapter);
    setState(() => _reading = _reading.copyWith(bookmarks: marks.toList()..sort()));
    if (widget.bookId != null) {
      unawaited(_readingStore.save(widget.bookId!, _reading));
    }
  }

  String _chapterLabel(int i) {
    if (widget.book.structuredChapters.isNotEmpty) {
      final blocks = widget.book.structuredChapters[i].blocks;
      for (final block in blocks) {
        if (block.kind == BookBlockKind.heading && block.text.trim().isNotEmpty) {
          return block.text.trim().replaceAll(RegExp(r'\s+'), ' ');
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
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _loadPosition();
    _scroll.addListener(_saveScroll);
  }

  @override
  void didChangeMetrics() {
    if (mounted && _progressReady && !_restoring) {
      _reflow(useLastKnownAnchor: true);
    }
  }

  @override
  void didChangeTextScaleFactor() {
    if (mounted && _progressReady && !_restoring) {
      _reflow(useLastKnownAnchor: true);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final value = await _store.load();
      if (mounted) {
        // Position and style load independently at startup. Do not
        // replace a restored legacy pixel offset with scroll=0 while its
        // first layout is still pending.
        if (_progressReady && !_restoring) {
          _reflow(settings: value);
        } else {
          setState(() => _settings = value);
        }
      }
    } catch (_) {
      // Defaults remain usable when preferences cannot be read.
    }
  }

  void _change(ReadingPreferences next) {
    _reflow(settings: next);
    unawaited(_store.save(next));
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
                .split(RegExp(r'\n\s*\n'))
                .where((text) => text.trim().isNotEmpty)
                .map((text) => BookBlock(kind: BookBlockKind.paragraph, text: text))
                .toList();
    // First FB2 heading is already rendered above the chapter content.
    // Preserve all nested/remaining headings in original order.
    final visibleBlocks = blocks.isNotEmpty &&
            blocks.first.kind == BookBlockKind.heading &&
            blocks.first.text.trim() == _chapterLabel(_reading.chapter)
        ? blocks.skip(1).toList()
        : blocks;
    _visibleBlockCount = visibleBlocks.length;
    final splitIndex = _layoutAnchorIndex != null &&
            _layoutAnchorIndex! >= 0 &&
            _layoutAnchorIndex! < visibleBlocks.length
        ? _layoutAnchorIndex! : 0;
    final anchored = _layoutAnchorIndex != null &&
        _layoutAnchorIndex! < visibleBlocks.length;


    return ReaderChromeKeyboard(
      mode: _chrome,
      onChange: _changeChrome,
      child: Scaffold(
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
            key: _viewportKey,
            constraints: const BoxConstraints(maxWidth: 800),
            child: CustomScrollView(
              key: ValueKey('book-scroll-$_scrollEpoch'),
              controller: _scroll,
              center: anchored ? _centerSliverKey : null,
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
                    key: _priorBlocksKey,
                    itemCount: splitIndex,
                    // Reverse-growth sliver: index zero must be the paragraph
                    // immediately BEFORE the selected source paragraph.
                    itemBuilder: (context, index) =>
                        _blockWidget(
                            visibleBlocks[splitIndex - 1 - index], readerText),
                  ),
                ),
                SliverPadding(
                  key: _centerSliverKey,
                  padding: EdgeInsets.symmetric(horizontal: prefs.horizontalPadding),
                  sliver: SliverList.builder(
                    key: _currentBlocksKey,
                    itemCount: visibleBlocks.length - splitIndex,
                    itemBuilder: (context, index) =>
                        _blockWidget(visibleBlocks[splitIndex + index], readerText),
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
                            Text(_count == 0 ? 'Нет глав' :
                                  '${_reading.chapter + 1} / $_count',
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
    ));
  }
}
