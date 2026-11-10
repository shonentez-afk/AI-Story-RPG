import 'dart:isolate';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:rpg_api/rpg_api.dart' show
    RpgCreationApi, LocalRpgCreationApi, RpgCreationIntent,
    LocalRpgLiteralCanonApi;

import 'book_import.dart';
import 'package:story_authoring/story_authoring.dart'
    show BookSourceSelection;
import 'book_source_analysis.dart';
import 'book_isolate_workers.dart';
import 'source_analysis_checkpoint_repository.dart';
import 'source_index_preview_page.dart';
import 'book_source_index.dart';
import 'quick_rpg_page.dart';
import 'world_library_gateway.dart';
import 'world_play_page.dart';
import 'world_campaigns_page.dart';
import 'world_import_review_flow.dart';
import 'world_import_review_worker.dart';
import 'zai_auto_whole_book_analysis.dart';
import 'zai_whole_book_analysis_page.dart';

/// A single honest entry point for a library book. Neither opening this page
/// nor choosing the AI path sends any text to Z.ai: the downstream analysis
/// page requests an exact, explicit consent before its first POST.
///
/// The long path is still an experimental preparation pipeline, not CANON or
/// a promise that every source event has been understood.
class BookRpgStartPage extends StatefulWidget {
  const BookRpgStartPage({
    super.key,
    required this.book,
    required this.gateway,
    this.indexer,
    this.analysis,
    this.manualCheckpointRepository,
    this.manualCheckpointDecoder,
    this.reviewedWorldInspector,
  });

  final ImportedBook book;
  final WorldLibraryGateway gateway;

  /// Optional read-only intake port. Production verifies through the worker
  /// isolate; deterministic widget tests use the SAME native inspector inline.
  /// Never let this port write or bypass the second pre-install verification.
  final WorldImportInspector? reviewedWorldInspector;

  /// Test seam; production indexes in a worker isolate.
  final Future<BookSourceIndex> Function(ImportedBook)? indexer;

  /// Test seam; real analysis is created only after the user selects AI.
  final ZaiAutoWholeBookAnalysis? analysis;

  /// Same private scope used by the existing local source editor.
  /// Inject only for deterministic offline tests; no extra format is stored.
  final SourceAnalysisCheckpointRepository? manualCheckpointRepository;

  /// Test seam only. Normal operation validates the same immutable source
  /// data in a worker; tests can validate synchronously with the same core.
  final Future<SourceAnalysisSession> Function(BookSourceIndex, String)?
      manualCheckpointDecoder;

  @override
  State<BookRpgStartPage> createState() => _BookRpgStartPageState();
}

class _BookRpgStartPageState extends State<BookRpgStartPage> {
  // One service and one source index for both start and resume. The service
  // only reads local validated checkpoints until the downstream consent UI.
  late final ZaiAutoWholeBookAnalysis _analysis =
      widget.analysis ?? ZaiAutoWholeBookAnalysis();
  late final SourceAnalysisCheckpointRepository _manualCheckpoints =
      widget.manualCheckpointRepository ??
          const FileSourceAnalysisCheckpointRepository();
  int? _selectedChapter;
  RpgCreationIntent _quickIntent =
      const RpgCreationIntent.quickAlterFate();
  static const RpgCreationApi _creationApi = LocalRpgCreationApi();
  bool _opening = false;
  // A confirmation dialog is awaiting the user's decision. Keep navigation
  // locked, but don't animate the underlying route's progress indicator:
  // otherwise Flutter's pumpAndSettle (and reduced-motion accessibility)
  // never settles even though the dialog is already ready for review.
  bool _awaitingReviewedWorldApproval = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedChapter = BookSourceSelection.defaultChapter(widget.book);
  }

  ImportedBook get _activeBook => _selectedChapter == null
      ? widget.book
      : BookSourceSelection.selectChapter(widget.book, _selectedChapter!);

  @override
  void didUpdateWidget(covariant BookRpgStartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.book, widget.book)) {
      _selectedChapter = BookSourceSelection.defaultChapter(widget.book);
      _error = null;
    }
  }

  Future<void> _openOffline() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      _creationApi.inspect(_quickIntent).requireSupported();
      final sourceBook = _activeBook;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => QuickRpgFromBookPage(
          book: sourceBook,
          gateway: widget.gateway,
          indexer: widget.indexer,
          initialIntent: _quickIntent, creationApi: _creationApi,
        ),
      ));
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Не удалось открыть офлайн-пробу: ' + error.toString());
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openWholeBook({bool resumeOnly = false}) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      _creationApi.inspect(const RpgCreationIntent.reviewedAlterFate())
          .requireSupported();
      // Both actions use the SAME validated book index and local checkpoint.
      // No network request, stored consent, or revision inference here.
      final sourceBook = _activeBook;
      final indexer = widget.indexer;
      final index = indexer == null
          ? await indexImportedBookInWorker(sourceBook)
          : await indexer(sourceBook);
      if (!mounted) return;
      var resumeManual = false;
      if (resumeOnly) {
        // Try existing full-book preparation first. This pure-Dart read
        // validates fingerprint, exact source windows and their checksums.
        final restored = await _analysis.read(index);
        if (restored.progress.completed == 0) {
          // The older local authoring route is NOT an alternative runtime.
          // Its independent exact-edition checkpoint can be resumed through
          // its own existing, source-verified UI without a new book scan/POST.
          final raw = await _manualCheckpoints.read(index.sourceFingerprint);
          if (raw == null) {
            setState(() => _error =
                'Для этой редакции книги нет сохранённого анализа. '
                'Выберите «Подготовить книгу через ИИ» или откройте '
                '«Расширенный редактор». В Z.ai ничего не отправлено.');
            return;
          }
          final checked = await (widget.manualCheckpointDecoder == null
              ? decodeSourceAnalysisInWorker(index, raw)
              : widget.manualCheckpointDecoder!(index, raw));
          if (checked.processedCount == 0 && checked.mentions.isEmpty) {
            setState(() => _error =
                'Локальная подготовка ещё не содержит сохранённых '
                'результатов. Исходный checkpoint не изменён.');
            return;
          }
          resumeManual = true;
        }
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => resumeManual
            ? SourceIndexPreviewPage(
                book: sourceBook, indexer: (_) async => index,
                checkpointRepository: _manualCheckpoints,
                checkpointDecoder: widget.manualCheckpointDecoder,
                worldGateway: widget.gateway,
              )
            : ZaiWholeBookAnalysisPage(
                index: index, analysis: _analysis,
                gateway: widget.gateway,
              ),
      ));
    } catch (error) {
      if (mounted) {
        setState(() => _error = resumeOnly
            ? 'Не удалось проверить сохранённую подготовку: $error. '
              'Черновик не удалён, повторной отправки в ИИ не было.'
            : 'Не удалось открыть анализ книги: $error. '
              'Книга и ранее созданные игры не изменены.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Exact full-book textual CANON. This never silently reuses the selected
  /// excerpt of a collection; the whole imported edition is independently
  /// indexed and approved. No cloud request or invented literary events.
  Future<void> _openLiteralCanon() async {
    if (_opening) return;
    setState(() { _opening = true; _error = null; });
    try {
      final index = await (widget.indexer ?? indexImportedBookInWorker)(
          widget.book);
      if (!mounted) return;
      const api = LocalRpgLiteralCanonApi();
      final preview = api.prepareIndex(index);
      if (!preview.canCompile) {
        throw const FormatException(
            'Буква в букву сохранить эту книгу пока невозможно: '
            'проверьте изображения, пропущенные главы или размер текста.');
      }
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Создать CANON всей книги?'),
          content: Text('Исходная редакция: ' + preview.title +
              '. Глав: ' + preview.chapterCount.toString() +
              ', фрагментов: ' + preview.chunkCount.toString() +
              '. Переносится ВЕСЬ оригинальный текст без сокращений, '
              'в порядке книги. Это проверенный буквальный CANON, '
              'но не автоматическая проверка мотивов и всех '
              'литературных обстоятельств. '
              'Свободные действия ИИ будут отдельными '
              'вымышленными вставками и не перепишут книгу. '
              'Никакой текст сейчас не отправляется в сеть. '
              'Будет создана новая частная игра; старые сохранения '
              'и позиция чтения не меняются.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('rpg-start-literal-canon-consent'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Создать частный CANON'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      final expected = preview.approvalDigest;
      final archive = await Isolate.run(() => api.compileIndex(index,
          approvedDigest: expected, userConfirmed: true));
      if (!mounted) return;
      final installed = await widget.gateway.install(archive);
      final id = await widget.gateway.start(installed.archiveHash);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => WorldPlayPage(
            gateway: widget.gateway, campaignId: id,
          )));
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _error = 'Нельзя создать полный CANON: ' +
            error.message + '. Исходная книга не изменена.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось собрать CANON: ' +
            error.toString() + '. Старые игры сохранены.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// The external ChatGPT Skill prepares source-reviewed causal v5 offline.
  /// Flutter only verifies the native package, exact selected edition and
  /// explicit user consent; it never pretends to execute that Skill itself.
  Future<void> _importReviewedCausal() async {
    if (_opening) return;
    setState(() { _opening = true; _error = null; });
    try {
      final files = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bworld'], withData: true,
        allowMultiple: false,
      );
      if (files == null) return;
      if (files.files.length != 1 ||
          files.files.single.size > 12 * 1024 * 1024 ||
          !files.files.single.name.toLowerCase().endsWith('.bworld')) {
        throw const FormatException(
            'Нужен один проверенный .bworld не больше 12 МБ.');
      }
      final bytes = files.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Не удалось прочитать игровой архив.');
      }
      final immutable = Uint8List.fromList(bytes);
      final inspect = widget.reviewedWorldInspector ??
          reviewImportedWorldInWorker;
      final preflight = await inspect(immutable, null);
      if (preflight.formatVersion != 5 ||
          !preflight.sourceLiteralCanonVerified ||
          !preflight.sourceCausalReviewVerified || !preflight.isPrivate) {
        throw const FormatException('Это не проверенный полный '
            'причинный CANON v5. Подготовьте пакет через E6q.1.');
      }
      final index = await (widget.indexer ?? indexImportedBookInWorker)(
          _activeBook);
      if (preflight.sourceFingerprint != index.sourceFingerprint) {
        throw const FormatException('Игровой мир создан для другой '
            'редакции или главы. Выберите точную исходную книгу.');
      }
      if (!mounted) return;
      setState(() => _awaitingReviewedWorldApproval = true);
      final installed = await WorldImportReviewFlow.confirmAndInstall(
        context: context, archive: immutable, gateway: widget.gateway,
        inspector: inspect);
      if (!mounted || installed == null) return;
      setState(() => _awaitingReviewedWorldApproval = false);
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => WorldCampaignsPage(
          world: installed, gateway: widget.gateway,
          inspector: widget.reviewedWorldInspector,
        ),
      ));
    } on FormatException catch (error) {
      if (mounted) setState(() => _error =
          'Нельзя открыть проверенную RPG: ${error.message}. '
          'Оригинальная книга и прежние кампании не изменены.');
    } catch (error) {
      if (mounted) setState(() => _error =
          'Импорт подготовленной RPG не выполнен: $error. '
          'Сохранённые книги и игры не изменены.');
    } finally {
      if (mounted) setState(() {
        _opening = false;
        _awaitingReviewedWorldApproval = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Создать RPG по книге')),
    body: SafeArea(
      child: SingleChildScrollView(
        key: const Key('rpg-start-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.book.title,
                key: const Key('rpg-start-book-title'),
                style: Theme.of(context).textTheme.titleLarge),
            if (_selectedChapter != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Для RPG: ' +
                    BookSourceSelection.chapterLabel(
                        widget.book, _selectedChapter!),
                    key: const Key('rpg-source-selection-summary'),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            // Full eager rendering: all three primary actions exist even
            // when 200% text forces them below the phone viewport.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('rpg-start-resume'),
                      onPressed: _opening ? null :
                          () => _openWholeBook(resumeOnly: true),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Продолжить создание RPG'),
                    ),
                    const SizedBox(height: 5),
                    const Text('Проверим локальные сохранения именно '
                        'этой редакции книги. Без запросов к ИИ.'),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, key: const Key('rpg-start-error'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
            if (_opening && !_awaitingReviewedWorldApproval) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(
                  key: Key('rpg-start-opening-progress')),
              const Text('Проверяем книгу и сохранённую подготовку…'),
            ],
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Быстрая офлайн-проба',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Text('Без сети и ИИ; короткая история по книге.'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      ChoiceChip(
                        key: const Key('rpg-start-quick-follow'),
                        label: const Text('По отрывкам книги'),
                        selected: _quickIntent.plot.name == 'sourceExcerptRoute',
                        onSelected: _opening ? null : (_) => setState(() =>
                            _quickIntent = const RpgCreationIntent.quickFollow()),
                      ),
                      ChoiceChip(
                        key: const Key('rpg-start-quick-alter'),
                        label: const Text('Развилки судьбы'),
                        selected: _quickIntent.plot.name == 'alterFate',
                        onSelected: _opening ? null : (_) => setState(() =>
                            _quickIntent = const RpgCreationIntent.quickAlterFate()),
                      ),
                    ]),
                    Text(_creationApi.inspect(_quickIntent).explanation,
                        key: const Key('rpg-start-mode-explanation')),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('rpg-start-offline'),
                      onPressed: _opening ? null : _openOffline,
                      icon: const Icon(Icons.offline_bolt_outlined),
                      label: const Text('Начать офлайн-пробу'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_selectedChapter == null
                        ? 'Поактовая подготовка всей книги'
                        : 'Подготовка выбранной истории',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Text('Частная ALTER_FATE-адаптация с редакторской '
                        'проверкой. Выбор героя доступен после анализа.'),
                    const Text('Z.ai — только после отдельного согласия.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('rpg-start-ai'),
                      onPressed: _opening ? null : () => _openWholeBook(),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Подготовить книгу через ИИ'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Card(
              key: const Key('rpg-start-literal-canon-card'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Точный CANON всей книги',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Text('Все главы, весь оригинальный текст '
                        'в неизменном порядке. Без необходимости '
                        'выдумывать литературные события.'),
                    const SizedBox(height: 8),
                    const Text('В этой отдельной частной игре ИИ может '
                        'создавать новые неканонические действия, '
                        'меняющие разрешённые игровые ресурсы и журнал. '
                        'Не приписываем их автору книги.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('rpg-start-literal-canon'),
                      onPressed: _opening ? null : _openLiteralCanon,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Создать CANON из всей книги'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Card(
              key: const Key('rpg-start-reviewed-causal-card'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Полная сюжетная RPG по проверенной книге',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('Источник проверен, причины событий и '
                        'последствия NPC подготовлены внешним '
                        'ChatGPT Skill E6q.1. Автономный движок может '
                        'переводить CANON в ALTER_FATE.'),
                    const SizedBox(height: 6),
                    const Text('Сначала подготовьте личный .bworld '
                        'в ChatGPT. На телефоне и Windows можно '
                        'импортировать готовый мир без API и без сети. '
                        'Редакция книги и причинная модель будут '
                        'повторно проверены перед добавлением.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('rpg-start-import-reviewed-causal'),
                      onPressed: _opening ? null : _importReviewedCausal,
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Открыть подготовленную RPG (.bworld)'),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.book.chapters.length > 1) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                key: const Key('rpg-source-scope'),
                title: const Text('Выбрать отдельную сказку или главу'),
                subtitle: Text(_selectedChapter == null
                    ? 'Сейчас: вся книга'
                    : 'Сейчас: ' + BookSourceSelection.chapterLabel(
                        widget.book, _selectedChapter!)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<int?>(
                          key: const Key('rpg-source-chapter'),
                          initialValue: _selectedChapter,
                          menuMaxHeight: 340,
                          hint: const Text('Вся книга'),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Исходный текст для RPG',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null, child: Text('Вся книга'),
                            ),
                            for (var i = 0; i < widget.book.chapters.length; i++)
                              DropdownMenuItem<int?>(
                                value: i,
                                child: Text(
                                  BookSourceSelection.chapterLabel(
                                      widget.book, i),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _opening ? null : (chapter) {
                            setState(() {
                              _selectedChapter = chapter;
                              _error = null;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text('Выбранная история будет отдельным '
                            'источником с собственным отпечатком и '
                            'checkpoint. Исходная книга и сохранения '
                            'других историй не изменятся. Выбор главы '
                            'не доказывает полноту литературного сюжета.'),
                        if (BookSourceSelection.defaultChapter(
                            widget.book) != null)
                          const Text('Пронумерованные версии этой '
                              'сказки — альтернативные редакции, а не '
                              'последовательные акты. По умолчанию '
                              'выбрана только первая версия.'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              key: const Key('rpg-start-details'),
              title: const Text('Возможности и ограничения режимов'),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Единый путь: подготовка книги → проверка '
                          'источника → выбор героя → предметы и '
                          'последствия → NPC (можно 0) → '
                          'проверенная компиляция → автономная игра.'),
                      SizedBox(height: 8),
                      Text('В быстрой пробе используется свободный '
                          'игрок. Режимы «Сохранить сюжет» и «Менять '
                          'сюжет» пока ограничены коротким сценарием, '
                          'а не полными CANON / ALTER_FATE.'),
                      SizedBox(height: 8),
                      Text('В расширенной подготовке можно выбрать '
                          'проверенного героя с постоянным '
                          'character_id. Секреты и знания NPC не '
                          'переходят к игроку автоматически.'),
                      SizedBox(height: 8),
                      Text('Всё индексируется локально. Перед отправкой '
                          'частей книги в Z.ai показываем объём и '
                          'запрашиваем отдельное согласие. Прогресс '
                          'сохраняется по проверенным фрагментам.'),
                      SizedBox(height: 8),
                      Text('Буквальный CANON всей книги доступен '
                          'как отдельная проверенная редакция: текст и '
                          'порядок глав сохраняются. Семантическую '
                          'истинность придуманных персонажем действий '
                          'модель не подтверждает. Новые действия ИИ '
                          'записываются как отдельные неканонические '
                          'игровые события. Чтение и сохранения '
                          'существующих прохождений не меняются.'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
