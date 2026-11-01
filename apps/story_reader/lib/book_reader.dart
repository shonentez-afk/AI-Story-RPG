import 'package:flutter/material.dart';
import 'book_import.dart';
import 'reading_preferences.dart';

class BookReaderPage extends StatefulWidget {
  const BookReaderPage({super.key, required this.book});
  final ImportedBook book;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  final ReadingSettingsStore _store = ReadingSettingsStore();
  ReadingPreferences _settings = const ReadingPreferences();

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
                  SegmentedButton<ReadingPalette>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ReadingPalette.light, label: Text('Свет')),
                      ButtonSegment(value: ReadingPalette.sepia, label: Text('Сепия')),
                      ButtonSegment(value: ReadingPalette.dark, label: Text('Тёмная')),
                      ButtonSegment(value: ReadingPalette.oled, label: Text('OLED')),
                    ],
                    selected: {_settings.palette},
                    onSelectionChanged: (value) =>
                        apply(_settings.copyWith(palette: value.first)),
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
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            tooltip: 'Настройки чтения',
            onPressed: _showReaderSettings,
            icon: const Icon(Icons.text_fields),
          ),
        ],
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
                if (widget.book.cover != null)
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
                for (var i = 0; i < widget.book.chapters.length; i++) ...[
                  Text('Глава ${i + 1}',
                      style: readerText.copyWith(
                        fontSize: prefs.fontSize + 4,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 12),
                  SelectableText(widget.book.chapters[i], style: readerText),
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
