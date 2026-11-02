import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'book_import.dart';
import 'book_model.dart';
import 'book_reading_state.dart';
import 'reading_preferences.dart';
import 'reading_settings_sheet.dart';
import 'reader_chrome.dart';

/// Test-only diagnostics: identify which Flutter layout path shifts pixels
/// by the full paragraph extent after the viewport is resized.
class _ReaderProbeController extends ScrollController {
  _ReaderProbeController() : super(keepScrollOffset: false);

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ReaderProbePosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _ReaderProbePosition extends ScrollPositionWithSingleContext {
  _ReaderProbePosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  }) : super(initialPixels: 0.0, keepScrollOffset: false);

  void _trace(String message) {
    assert(() {
      debugPrint('AR-POS $message STACK ${StackTrace.current.toString().split("\\n").take(7).join(" | ")}');
      return true;
    }());
  }

  @override
  void correctBy(double correction) {
    if (correction.abs() > 300) _trace('correctBy $correction from=$pixels');
    super.correctBy(correction);
  }

  @override
  void correctPixels(double value) {
    if (hasPixels && (value - pixels).abs() > 300) {
      _trace('correctPixels $value from=$pixels');
    }
    super.correctPixels(value);
  }

  @override
  void jumpTo(double value) {
    if (hasPixels && pixels < 3500 && value < 3500) {
      _trace('jumpTo $value from=$pixels');
    }
    super.jumpTo(value);
  }
}

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
  // Do not resurrect pixel offsets from PageStorage after a semantic reflow.
  final ScrollController _scroll = _ReaderProbeController();
  int _scrollLayoutEpoch = 0;
  bool _anchorCorrectionPending = false;
  bool _anchorCorrectionScheduled = false;
  int _anchorCorrectionBudget = 0;
  int _anchorCorrectionPasses = 0;
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey _priorBlocksKey = GlobalKey();
  final GlobalKey _followingBlocksKey = GlobalKey();
  final GlobalKey _anchorParagraphKey = GlobalKey();
  final GlobalKey _centerSliverKey = GlobalKey();
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
    BookTextAnchor? trailing;
    bool passedViewport = false;
    BookTextAnchor? consider(RenderBox child, int index) {
      if (index < 0 || index >= _visibleBlockCount) return null;
      final y = child.localToGlobal(Offset.zero).dy;
      final height = child.size.height;
      if (height > 0 && y + height > top && y <= top) {
        return BookTextAnchor(
          blockIndex: index,
          fraction: ((top - y) / height).clamp(0.0, 1.0).toDouble(),
        );
      }
      if (y > top) {
        passedViewport = true;
      } else if (height > 0) {
        trailing = BookTextAnchor(blockIndex: index, fraction: 1);
      }
      return null;
    }

    BookTextAnchor? inLazyList(GlobalKey key, int baseIndex,
        {bool reverse = false}) {
      final sliver = key.currentContext?.findRenderObject();
      if (sliver is! RenderSliverList) return null;
      var child = sliver.firstChild;
      while (child != null) {
        final localIndex = sliver.indexOf(child);
        final realIndex = reverse
            ? baseIndex - localIndex : baseIndex + localIndex;
        final found = consider(child, realIndex);
        if (found != null) return found;
        // Reverse-growth sliver children proceed *upward* from the center:
        // a child below the viewport top does not imply later children are.
        if (passedViewport && !reverse) break;
        child = sliver.childAfter(child);
      }
      return null;
    }

    final before = inLazyList(
      _priorBlocksKey, (_layoutAnchorIndex ?? 0) - 1, reverse: true,
    );
    if (before != null) return before;
    passedViewport = false;
    // Always-mounted source paragraph is in a standalone sliver AFTER
    // the zero-extent center; the rest of the chapter stays lazy.
    final anchorRender = _anchorParagraphKey.currentContext?.findRenderObject();
    if (anchorRender is RenderBox) {
      final found = consider(anchorRender, _layoutAnchorIndex ?? 0);
      if (found != null || passedViewport) return found;
    }
    final after = inLazyList(
      _followingBlocksKey, (_layoutAnchorIndex ?? 0) + 1,
    );
    return after ?? trailing;
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

  /// Restore from a source block, never from the old pixel layout.
  /// A fresh ScrollPosition is created when the center changes. Flutter
  /// can still correct sliver extents after the first layout pass, so verify
  /// the actual paragraph rectangle for a bounded number of frames.
  void _restoreScroll() {
    assert(() { debugPrint('AR-DBG RESTORE start epoch=$_scrollLayoutEpoch anchor=${_reading.anchor?.blockIndex} fraction=${_reading.anchor?.fraction} positions=${_scroll.positions.length} offset=${_scroll.hasClients ? _scroll.offset : "none"}'); return true; }());
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        _restoring = false;
        return;
      }
      final pos = _scroll.position;
      final anchor = _reading.anchor;
      if (_layoutAnchorIndex != null && anchor != null) {
        final target = _anchorParagraphKey.currentContext?.findRenderObject();
        final paragraphOffset = target is RenderBox && target.hasSize
            ? target.size.height * anchor.fraction.clamp(0.0, 0.75)
            : 0.0;
        assert(() { debugPrint('AR-DBG RESTORE layout epoch=$_scrollLayoutEpoch size=${target is RenderBox ? target.size.height : -1} requested=$paragraphOffset current=${pos.pixels} min=${pos.minScrollExtent} max=${pos.maxScrollExtent}'); return true; }());
        _scroll.jumpTo(paragraphOffset.clamp(
          pos.minScrollExtent, pos.maxScrollExtent,
        ).toDouble());
        _beginAnchorCorrection();
      } else {
        _scroll.jumpTo(_reading.scrollOffset.clamp(
          pos.minScrollExtent, pos.maxScrollExtent,
        ).toDouble());
        _restoring = false;
      }
    });
  }

  /// ScrollMetricsNotification fires *after* the viewport has discovered its
  /// new dimensions. A didChangeMetrics-only fix runs too early and Flutter
  /// can then move the old center by the height of one rendered paragraph.
  bool _onScrollMetrics(ScrollMetricsNotification notice) {
    assert(() { debugPrint('AR-DBG METRICS epoch=$_scrollLayoutEpoch depth=${notice.depth} pending=$_anchorCorrectionPending pixel=${notice.metrics.pixels} viewport=${notice.metrics.viewportDimension}'); return true; }());
    if (notice.depth == 0 && _anchorCorrectionPending &&
        _reading.anchor != null && mounted) {
      if (_anchorCorrectionBudget < 2) _anchorCorrectionBudget = 2;
      _scheduleAnchorCorrection();
    }
    return false;
  }

  void _beginAnchorCorrection() {
    _anchorCorrectionPending = true;
    _anchorCorrectionBudget = 6;
    _anchorCorrectionPasses = 0;
    _scheduleAnchorCorrection();
  }

  void _scheduleAnchorCorrection() {
    if (!mounted || !_anchorCorrectionPending ||
        _anchorCorrectionScheduled) return;
    _anchorCorrectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorCorrectionScheduled = false;
      if (!mounted || !_scroll.hasClients || _reading.anchor == null) {
        _anchorCorrectionPending = false;
        _restoring = false;
        return;
      }
      final target = _anchorParagraphKey.currentContext?.findRenderObject();
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (target is RenderBox && target.hasSize &&
          viewport is RenderBox && viewport.hasSize) {
        final anchor = _reading.anchor!;
        final viewTop = viewport.localToGlobal(Offset.zero).dy + 1;
        final paragraphTop = target.localToGlobal(Offset.zero).dy;
        final desiredTop = viewTop -
            target.size.height * anchor.fraction.clamp(0.0, 0.75);
        final correction = paragraphTop - desiredTop;
        final pos = _scroll.position;
        final nextOffset = (pos.pixels + correction).clamp(
          pos.minScrollExtent, pos.maxScrollExtent,
        ).toDouble();
        assert(() { debugPrint('AR-DBG ALIGN epoch=$_scrollLayoutEpoch pass=$_anchorCorrectionPasses pixel=${pos.pixels} target=$paragraphTop expected=$desiredTop delta=$correction next=$nextOffset'); return true; }());
        if (correction.abs() > 1 && (nextOffset - pos.pixels).abs() > 0.5) {
          _scroll.jumpTo(nextOffset);
        }
      }
      _anchorCorrectionPasses++;
      if (_anchorCorrectionBudget > 0 && _anchorCorrectionPasses < 10) {
        _anchorCorrectionBudget--;
        // A callback alone does not create the frame needed for the
        // viewport's subsequent metrics correction. Explicitly request one.
        WidgetsBinding.instance.scheduleFrame();
        _scheduleAnchorCorrection();
      } else {
        assert(() { debugPrint('AR-DBG ALIGN DONE epoch=$_scrollLayoutEpoch pixel=${_scroll.hasClients ? _scroll.offset : "none"}'); return true; }());
        _anchorCorrectionPending = false;
        _restoring = false;
      }
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
    // Window metrics may invalidate the previous RenderBox geometry before
    // the callback runs. The scroll listener already cached the last actual
    // visible paragraph. Preserve that source position across system reflow.
    assert(() { debugPrint('AR-DBG REFLOW start epoch=$_scrollLayoutEpoch current=${_scroll.hasClients ? _scroll.offset : "none"} last=${_reading.anchor?.blockIndex} usingLast=$useLastKnownAnchor'); return true; }());
    final next = useLastKnownAnchor
        ? _reading
        : (_progressReady ? _snapshotPosition() : _reading);
    _restoring = true;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _scrollLayoutEpoch++;
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
    final saved = await _readingStore.load(widget.bookId!);
    if (mounted) setState(() {
      _reading = saved.copyWith(chapter:
          saved.chapter.clamp(0, _count > 0 ? _count - 1 : 0).toInt());
      _layoutAnchorIndex = saved.anchor?.blockIndex;
      _scrollLayoutEpoch++;
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
      _scrollLayoutEpoch++;
    });
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
    assert(() { debugPrint('AR-DBG DIDMETRICS epoch=$_scrollLayoutEpoch restoring=$_restoring'); return true; }());
    // Capture the paragraph location from the previous render tree BEFORE
    // the first frame lays out the new window size/orientation.
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
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: _onScrollMetrics,
              child: CustomScrollView(
              key: ValueKey('reader-scroll-$_scrollLayoutEpoch'),
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
                    // Pre-center slivers use reverse GrowthDirection. Item 0
                    // is next to the center, not the start of the chapter.
                    itemBuilder: (context, index) =>
                        _blockWidget(
                            visibleBlocks[splitIndex - 1 - index], readerText),
                  ),
                ),
                // The center MUST have zero extent: a nonempty center
                // makes RenderViewport add its height to the scroll offset
                // during layout corrections (822px in the regression case).
                SliverToBoxAdapter(
                  key: _centerSliverKey,
                  child: const SizedBox.shrink(),
                ),
                // Source paragraph is mounted even when Flutter temporarily
                // shifts the viewport across a large paragraph during resize.
                // It must NOT be the center sliver (nonzero center produced a
                // repeated one-paragraph-height layout correction).
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: prefs.horizontalPadding),
                  sliver: SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: _anchorParagraphKey,
                      child: visibleBlocks.isEmpty
                          ? const SizedBox.shrink()
                          : _blockWidget(visibleBlocks[splitIndex], readerText),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: prefs.horizontalPadding),
                  sliver: SliverList.builder(
                    key: _followingBlocksKey,
                    // Temporary diagnostic isolation of the forward lazy list.
                    itemCount: anchored ? 0 : (visibleBlocks.isEmpty
                        ? 0 : visibleBlocks.length - splitIndex - 1),
                    itemBuilder: (context, index) =>
                        _blockWidget(visibleBlocks[splitIndex + index + 1],
                            readerText),
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
      ),
    ));
  }
}
