import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'book_import.dart';
import 'book_storage.dart';
import 'book_reader.dart';
import 'world_library_gateway.dart';
import 'world_campaigns_page.dart';
import 'world_play_page.dart';
import 'campaign_store.dart';
import 'campaigns_page.dart';
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
  bool _saveLoading = true;
  bool _opening = false;
  String? _recentCampaignId;
  int _campaignCount = 0;
  int _pilotCount = 0;
  int _worldCount = 0;
  String? _recentWorldId;
  String? _recentWorldTitle;
  final WorldLibraryGateway _worldGateway =
      const DeviceWorldLibraryGateway();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    // The book filesystem may be unavailable in widget tests or temporarily
    // unreadable on device. It must not hide an existing RPG save.
    try {
      final campaigns = await CampaignStore().all();
      if (mounted) setState(() {
        // A damaged slot must not become the default "Continue" target.
        final healthy = campaigns.where((item) => !item.damaged).toList();
        _hasSave = healthy.isNotEmpty;
        _recentCampaignId = healthy.isEmpty ? null : healthy.first.id;
        _pilotCount = campaigns.length;
        _campaignCount = _pilotCount + _worldCount;
      });
    } catch (_) {
      // Keep the last known save indicator; do not hide it because a read failed.
    } finally {
      // Do not briefly show "New story" while a saved BookWorld is still
      // being checked. Both independent stores are read before the preview
      // is declared ready; errors in either leave the other intact.
      await _refreshWorldCampaigns();
      if (mounted) setState(() => _saveLoading = false);
    }
  }

  Future<void> _refreshWorldCampaigns() async {
    try {
      final worlds = await _worldGateway.worlds()
          .timeout(const Duration(seconds: 8));
      final campaigns = await _worldGateway.campaigns()
          .timeout(const Duration(seconds: 8));
      final titles = <String, String>{
        for (final world in worlds) world.archiveHash: world.title,
      };
      if (!mounted) return;
      setState(() {
        _worldCount = campaigns.length;
        _campaignCount = _pilotCount + _worldCount;
        _recentWorldId = campaigns.isEmpty ? null : campaigns.first.id;
        _recentWorldTitle = campaigns.isEmpty ? null :
            titles[campaigns.first.worldHash];
      });
    } catch (_) {
      // Keep prior counts; old saved games remain playable even if the new
      // SQLite catalog is unavailable or damaged.
    }
  }

  Future<void> _open(Widget page) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    } finally {
      if (mounted) {
        // Release the navigation lock immediately after pop. Reading local
        // books may be slow or unavailable; it must never prevent Continue.
        setState(() => _opening = false);
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final worldContinue = !_hasSave && _recentWorldId != null;
    final canContinue = _hasSave || worldContinue;
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
                        Text(_saveLoading ? 'ПРОВЕРКА СОХРАНЕНИЙ' :
                            (canContinue ? 'СЕЙЧАС В ИСТОРИИ' : 'НАЧНИ СВОЮ ИСТОРИЮ'),
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
                                  Text(worldContinue
                                      ? (_recentWorldTitle ?? 'Подготовленный мир')
                                      : 'Тайна особняка',
                                      style: text.titleLarge),
                                  const SizedBox(height: 6),
                                  Text(_saveLoading
                                      ? 'Проверяем сохранённые прохождения'
                                      : canContinue
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
                            onPressed: _saveLoading ? null : () {
                              if (worldContinue) {
                                _open(WorldPlayPage(
                                  gateway: _worldGateway,
                                  campaignId: _recentWorldId!,
                                ));
                              } else {
                                _open(StoryReaderPage(
                                  resume: _hasSave,
                                  campaignId: _hasSave
                                      ? _recentCampaignId : null,
                                ));
                              }
                            },
                            icon: Icon(canContinue
                                ? Icons.play_arrow : Icons.auto_stories),
                            label: Text(_saveLoading ? 'Загрузка…' :
                                (canContinue ? 'Продолжить' : 'Начать историю')),
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
                const SizedBox(height: 10),
                _HomeAction(
                  icon: Icons.history_outlined,
                  title: 'Мои прохождения',
                  subtitle: 'Сохранённые кампании: $_campaignCount',
                  onTap: () => _open(const CampaignsPage()),
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
  const LibraryPage({
    super.key,
    this.worldGateway = const DeviceWorldLibraryGateway(),
  });

  final WorldLibraryGateway worldGateway;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final BookStorage _storage = BookStorage();
  final TextEditingController _searchController = TextEditingController();
  List<StoredBook> _books = [];
  List<WorldLibraryItem> _worlds = const [];
  bool _worldLoading = true;
  bool _worldLoadError = false;
  bool _working = false;
  bool _loadingBooks = true;
  bool _libraryLoadError = false;
  String _query = '';
  bool _sortDescending = false;
  final Set<Timer> _loadDeadlines = <Timer>{};
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    unawaited(_refreshWorlds());
  }

  Future<void> _refreshWorlds() async {
    try {
      final worlds = await widget.worldGateway.worlds()
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() {
        _worlds = worlds;
        _worldLoadError = false;
      });
    } catch (_) {
      // A corrupt or unavailable BookWorld DB must not hide TXT/FB2 books
      // or make the existing demo and legacy campaigns inaccessible.
      if (mounted) setState(() => _worldLoadError = true);
    } finally {
      if (mounted) setState(() => _worldLoading = false);
    }
  }

  void _retryWorlds() {
    if (_worldLoading) return;
    setState(() {
      _worldLoading = true;
      _worldLoadError = false;
    });
    unawaited(_refreshWorlds());
  }

  @override
  void dispose() {
    // A future storage read may never complete on an unsupported platform.
    // Cancel its UI deadline when this route is removed. No test-zone timer
    // can survive the widget that created it.
    _loadGeneration++;
    for (final timer in _loadDeadlines) {
      timer.cancel();
    }
    _loadDeadlines.clear();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final generation = ++_loadGeneration;
    final timeout = Completer<List<StoredBook>>();
    final deadline = Timer(const Duration(seconds: 8), () {
      if (!timeout.isCompleted) {
        timeout.completeError(
          TimeoutException('Не удалось прочитать библиотеку за 8 секунд'),
        );
      }
    });
    _loadDeadlines.add(deadline);
    try {
      final books = await Future.any<List<StoredBook>>([
        _storage.all(),
        timeout.future,
      ]);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _books = books;
          _libraryLoadError = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _libraryLoadError = true);
        _error('Библиотеку пока не удалось открыть. '
            'Книги не удалены — повторите попытку.');
      }
    } finally {
      deadline.cancel();
      _loadDeadlines.remove(deadline);
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingBooks = false);
      }
    }
  }

  void _retryLibrary() {
    if (_loadingBooks) return;
    setState(() {
      _loadingBooks = true;
      _libraryLoadError = false;
    });
    unawaited(_refresh());
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
        allowedExtensions: ['txt', 'fb2', 'bworld'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final file = selection.files.single;
      final extension = file.name.split('.').last.toLowerCase();
      if (extension == 'bworld' && file.size > 12 * 1024 * 1024) {
        throw const FormatException('Игровой мир больше 12 МБ');
      }
      if (file.size > 20 * 1024 * 1024) {
        throw const FormatException('Книга слишком большая. Максимум — 20 МБ.');
      }
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('Не удалось прочитать файл');
      if (extension == 'bworld') {
        // Pure Dart/SQLite validation and persistence run on a worker isolate.
        // A rejected package leaves existing books and campaigns untouched.
        final installed = await widget.worldGateway.install(bytes);
        await _refreshWorlds();
        if (mounted) _error('Добавлен игровой мир: ' + installed.title);
      } else {
        final book = BookImporter.parse(file.name, bytes);
        await _storage.add(book);
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Добавлена книга: ${book.title}')),
          );
        }
      }
    } catch (error) {
      _error('Импорт не выполнен: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _deleteBook(StoredBook entry) async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Удалить книгу?'),
        content: Text('«${entry.book.title}» будет удалена из библиотеки вместе с локальной копией. Это действие нельзя отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await _storage.remove(entry.id);
      await _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Книга удалена из библиотеки')),
      );
    } catch (error) {
      _error('Не удалось удалить книгу: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _query.trim().toLowerCase();
    final filteredWorlds = _worlds.where((world) =>
      term.isEmpty || world.title.toLowerCase().contains(term)
          || world.bookworldId.toLowerCase().contains(term)).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
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
      appBar: AppBar(title: const Text('Библиотека')),
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
                  subtitle: const Text('Демо RPG • начать новое прохождение'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const StoryReaderPage())),
                )),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('library-import'),
                    onPressed: _working ? null : _import,
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text('Добавить книгу'),
                  ),
                ),
                const SizedBox(height: 6),
                Text('TXT, FB2 (до 20 МБ) или подготовленный .bworld (до 12 МБ)',
                  style: Theme.of(context).textTheme.bodySmall),
                if (_working)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
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
                if (_worldLoading)
                  const LinearProgressIndicator(),
                if (_worldLoadError)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      const Expanded(child: Text(
                        'Игровые миры временно недоступны; книги сохранены.',
                      )),
                      TextButton(
                        onPressed: _retryWorlds,
                        child: const Text('Повторить'),
                      ),
                    ]),
                  ),
                if (filteredWorlds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Подготовленные игровые миры',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final world in filteredWorlds)
                    Card(child: ListTile(
                      key: ValueKey('library-world-' + world.bookworldId),
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: Text(world.title),
                      subtitle: const Text(
                        'Подготовленная RPG · классический офлайн-режим',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => WorldCampaignsPage(
                              world: world,
                              gateway: widget.worldGateway,
                            ),
                          ),
                        );
                        if (mounted) unawaited(_refreshWorlds());
                      },
                    )),
                ],
                if (_loadingBooks)
                  const LinearProgressIndicator(),
                if (_loadingBooks)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Открываем библиотеку…'),
                  )
                else if (_libraryLoadError)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Не удалось прочитать локальную библиотеку. '
                            'Сохранённые книги не удалены.'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _retryLibrary,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить загрузку'),
                        ),
                      ],
                    ),
                  )
                else if (_books.isEmpty && _worlds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Книг пока нет. Нажмите «Добавить книгу» '
                            'выше, чтобы импортировать TXT или FB2.'),
                      ],
                    ),
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
                    trailing: IconButton(
                      tooltip: 'Удалить книгу: ${entry.book.title}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _working ? null : () => _deleteBook(entry),
                    ),
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
                ListTile(
                  leading: const Icon(Icons.save_outlined),
                  title: const Text('Мои прохождения'),
                  subtitle: const Text('Сохранения RPG, импорт и экспорт .bwsave'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CampaignsPage(),
                    ),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Версия'),
                  subtitle: Text('0.1.0 · M1.6 · тестовая версия'),
                ),
              ],
            ),
          ),
        ),
      );
}
