import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'book_import.dart';
import 'book_storage.dart';
import 'book_reader.dart';
import 'save_store.dart';
import 'app_theme.dart';
import 'main.dart' show StoryReaderPage;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasSave = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final value = await SaveStore().read();
      if (mounted) setState(() => _hasSave = value != null);
    } catch (_) {
      if (mounted) setState(() => _hasSave = false);
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Живая книга')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.auto_stories_outlined, size: 64),
                const SizedBox(height: 16),
                Text('Добро пожаловать в историю',
                    style: text.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'Исследуйте сюжеты, принимайте решения и меняйте судьбы героев.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _hasSave
                      ? () => _open(const StoryReaderPage(resume: true))
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Продолжить'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _open(const StoryReaderPage()),
                  icon: const Icon(Icons.add),
                  label: const Text('Новая история'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _open(const LibraryPage()),
                  icon: const Icon(Icons.library_books_outlined),
                  label: const Text('Библиотека'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _open(const SettingsPage()),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Настройки'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Библиотека поддерживает TXT и FB2. Откройте библиотеку, чтобы импортировать книгу.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final BookStorage _storage = BookStorage();
  List<StoredBook> _books = [];
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _refresh();
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Библиотека'),
          actions: [
            TextButton.icon(
              onPressed: _working ? null : _import,
              icon: const Icon(Icons.library_add_outlined),
              label: const Text('Добавить книгу'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Тайна особняка'),
                subtitle: const Text('Демонстрационная RPG • офлайн'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StoryReaderPage(),
                  ),
                ),
              ),
            ),
            for (final entry in _books)
              Card(
                child: ListTile(
                  leading: entry.book.cover == null
                      ? const Icon(Icons.book_outlined)
                      : Image.memory(
                          entry.book.cover!,
                          width: 48,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stack) =>
                              const Icon(Icons.book_outlined),
                        ),
                  title: Text(entry.book.title),
                  subtitle: Text(entry.book.author.isEmpty
                      ? 'Импортированная книга'
                      : entry.book.author),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BookReaderPage(book: entry.book, bookId: entry.id),
                    ),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Нажмите «Добавить книгу» вверху, чтобы выбрать TXT или FB2. '
                  'Это пока режим чтения, а не автоматическое создание RPG.'),
            ),
          ],
        ),
      );
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Оформление приложения',
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
                const ListTile(
                  leading: Icon(Icons.auto_stories_outlined),
                  title: Text('Оформление страниц'),
                  subtitle: Text('Четыре темы и настройки текста доступны внутри книги'),
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
                  subtitle: Text('M1.3 UI — единое оформление'),
                ),
              ],
            ),
          ),
        ),
      );
}
