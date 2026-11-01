import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'book_import.dart';
import 'book_storage.dart';
import 'book_reader.dart';
import 'save_store.dart';
import 'app_theme.dart';
import 'reading_preferences.dart';
import 'reading_settings_sheet.dart';
import 'main.dart' show StoryReaderPage;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasSave = false;
  List<StoredBook> _books = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    // The book filesystem may be unavailable in widget tests or temporarily
    // unreadable on device. It must not hide an existing RPG save.
    try {
      final save = await SaveStore().read();
      if (mounted) setState(() => _hasSave = save != null);
    } catch (_) {
      // Keep the last known save indicator; do not hide it because a read failed.
    }
    try {
      final books = await BookStorage().all();
      if (mounted) setState(() => _books = books);
    } catch (_) {
      // Home remains usable without the library; saved RPG still appears.
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Живая книга'),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(const SettingsPage()),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text('Читай. Выбирай. Меняй.',
                    style: text.titleMedium?.copyWith(color: scheme.primary)),
                const SizedBox(height: 20),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_hasSave ? 'СЕЙЧАС В ИСТОРИИ' : 'НАЧНИ СВОЮ ИСТОРИЮ',
                            style: text.labelLarge?.copyWith(color: scheme.primary)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              width: 76, height: 94,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.auto_stories_outlined,
                                  size: 42, color: scheme.primary),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Тайна особняка', style: text.titleLarge),
                                  const SizedBox(height: 6),
                                  Text(_hasSave
                                      ? 'Продолжить сохранённую игровую историю'
                                      : 'Демонстрационная история • офлайн',
                                      style: text.bodyMedium),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _open(StoryReaderPage(resume: _hasSave)),
                            icon: Icon(_hasSave ? Icons.play_arrow : Icons.auto_stories),
                            label: Text(_hasSave ? 'Продолжить' : 'Начать историю'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 360;
                  final library = _HomeAction(
                    icon: Icons.library_books_outlined,
                    title: 'Библиотека',
                    subtitle: 'Книги и миры',
                    onTap: () => _open(const LibraryPage()),
                  );
                  final story = _HomeAction(
                    icon: Icons.add_circle_outline,
                    title: 'Новая история',
                    subtitle: 'Начать заново',
                    onTap: () => _open(const StoryReaderPage()),
                  );
                  return narrow
                      ? Column(children: [library, const SizedBox(height: 10), story])
                      : Row(children: [
                          Expanded(child: library),
                          const SizedBox(width: 10),
                          Expanded(child: story),
                        ]);
                }),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Text('Моя библиотека', style: text.titleLarge)),
                    TextButton(
                      onPressed: () => _open(const LibraryPage()),
                      child: const Text('Все книги'),
                    ),
                  ],
                ),
                if (_books.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.book_outlined),
                      title: const Text('Добавьте свою первую книгу'),
                      subtitle: const Text('Поддерживаются TXT и FB2'),
                      onTap: () => _open(const LibraryPage()),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  )
                else
                  SizedBox(
                    height: 166,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _books.length > 8 ? 8 : _books.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final entry = _books[i];
                        return SizedBox(
                          width: 116,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _open(BookReaderPage(
                              book: entry.book, bookId: entry.id)),
                            child: Column(children: [
                              Container(
                                width: 104, height: 118,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10)),
                                clipBehavior: Clip.antiAlias,
                                child: entry.book.cover == null
                                    ? Icon(Icons.menu_book_outlined,
                                        size: 40, color: scheme.primary)
                                    : Image.memory(entry.book.cover!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            Icon(Icons.book, color: scheme.primary)),
                              ),
                              const SizedBox(height: 5),
                              Text(entry.book.title, maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: text.labelSmall),
                            ]),
                          ),
                        );
                      },
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

class _HomeAction extends StatelessWidget {
  const _HomeAction({
    required this.icon, required this.title,
    required this.subtitle, required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
        ]),
      ),
    ),
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final BookStorage _storage = BookStorage();
  final TextEditingController _searchController = TextEditingController();
  List<StoredBook> _books = [];
  bool _working = false;
  String _query = '';
  bool _sortDescending = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final books = await _storage.all();
      if (mounted) setState(() => _books = books);
    } catch (error) {
      _error('Ошибка библиотеки: $error');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _import() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'fb2'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('Не удалось прочитать файл');
      final book = BookImporter.parse(file.name, bytes);
      await _storage.add(book);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлена книга: ${book.title}')),
        );
      }
    } catch (error) {
      _error('Импорт не выполнен: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _books.where((entry) {
      final term = _query.trim().toLowerCase();
      return term.isEmpty ||
          entry.book.title.toLowerCase().contains(term) ||
          entry.book.author.toLowerCase().contains(term);
    }).toList()
      ..sort((a, b) {
        final order = a.book.title.toLowerCase()
            .compareTo(b.book.title.toLowerCase());
        return _sortDescending ? -order : order;
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        actions: [
          IconButton(
            tooltip: 'Добавить книгу (TXT или FB2)',
            onPressed: _working ? null : _import,
            icon: const Icon(Icons.library_add_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverList.list(children: [
                Text('Ваши книги и игровые истории',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Card(child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Тайна особняка'),
                  subtitle: const Text('Демонстрационная RPG • офлайн'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const StoryReaderPage())),
                )),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Поиск книг',
                    hintText: 'Название или автор',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty ? null : IconButton(
                      tooltip: 'Очистить поиск',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(
                    'Импортированные книги: ${filtered.length} из ${_books.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  TextButton.icon(
                    onPressed: () => setState(() => _sortDescending = !_sortDescending),
                    icon: Icon(_sortDescending
                        ? Icons.arrow_downward : Icons.arrow_upward),
                    label: Text(_sortDescending ? 'Я—А' : 'А—Я'),
                  ),
                ]),
                if (_working) const LinearProgressIndicator(),
                if (_books.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Здесь появятся ваши книги. Нажмите значок книги с плюсом вверху, чтобы добавить TXT или FB2.'),
                  )
                else if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('По вашему запросу книги не найдены.'),
                  ),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  return Card(child: ListTile(
                    leading: entry.book.cover == null
                        ? const Icon(Icons.book_outlined)
                        : Image.memory(entry.book.cover!,
                            width: 48, height: 64, fit: BoxFit.cover,
                            errorBuilder: (_, error, stack) =>
                                const Icon(Icons.book_outlined)),
                    title: Text(entry.book.title),
                    subtitle: Text(entry.book.author.isEmpty
                        ? 'Импортированная книга' : entry.book.author),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BookReaderPage(
                          book: entry.book, bookId: entry.id))),
                  ));
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final controller = AppAppearanceController.instance;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    super.dispose();
  }

  final ReadingSettingsStore _readerStore = ReadingSettingsStore();

  Future<void> _openReadingSettings() async {
    try {
      final current = await _readerStore.load();
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ReadingSettingsSheet(
          preferences: current,
          onChanged: (next) => _readerStore.save(next),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть настройки чтения: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Внешний вид',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Светлая'),
                      selected: controller.value == AppAppearance.light,
                      onSelected: (_) => controller.change(AppAppearance.light),
                    ),
                    ChoiceChip(
                      label: const Text('Тёмная'),
                      selected: controller.value == AppAppearance.dark,
                      onSelected: (_) => controller.change(AppAppearance.dark),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('Оформление страниц'),
                  subtitle: const Text('Палитра, размер текста, интервалы и поля'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openReadingSettings,
                ),
                const ListTile(
                  leading: Icon(Icons.offline_bolt_outlined),
                  title: Text('Режим игры'),
                  subtitle: Text('Классический офлайн • без ИИ'),
                ),
                const ListTile(
                  leading: Icon(Icons.save_outlined),
                  title: Text('Сохранения'),
                  subtitle: Text('Игра и позиции книг хранятся отдельно'),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Версия'),
                  subtitle: Text('M1.5 UI — Моя история'),
                ),
              ],
            ),
          ),
        ),
      );
}
