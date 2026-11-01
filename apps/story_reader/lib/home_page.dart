import 'package:flutter/material.dart';
import 'save_store.dart';
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
                  'M1.1 • В библиотеке пока доступен демонстрационный пролог. '
                  'Импорт собственных книг будет добавлен следующим этапом.',
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

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Библиотека')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Тайна особняка'),
                subtitle: const Text('Демонстрационная история • офлайн'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StoryReaderPage(),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Добавление TXT, FB2 и EPUB находится в разработке.'),
            ),
          ],
        ),
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: ListView(
          padding: EdgeInsets.all(20),
          children: [
            ListTile(
              leading: Icon(Icons.offline_bolt_outlined),
              title: Text('Режим игры'),
              subtitle: Text('Классический офлайн • без ИИ'),
            ),
            ListTile(
              leading: Icon(Icons.save_outlined),
              title: Text('Сохранения'),
              subtitle: Text('Один локальный слот на устройстве'),
            ),
            ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Версия'),
              subtitle: Text('M1.1 — первый экран и библиотека'),
            ),
          ],
        ),
      );
}
