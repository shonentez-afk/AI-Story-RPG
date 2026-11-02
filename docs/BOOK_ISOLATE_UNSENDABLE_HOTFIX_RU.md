# Hotfix: Invalid argument(s) / Illegal argument in isolate message при открытии книг

Дата: 2026-11-02. Ветка: fix/unsendable-isolate-book-opening-20261102 (от принятого UX/UI PR #12).

## Симптом
Сообщение пользователя: Invalid argument(s): Illegal argument in isolate message: object is unsendable. В стеке — _AsyncCompleter, _firstFrameCompleter, WidgetsBinding, RenderParagraph и StatefulElement.
Это ошибка передачи объекта Flutter-дерева в изолят, а не кодировки TXT/FB2. Без полной трассировки нельзя доказать единственную исходную строку. В main до исправления были рискованные Isolate.run closures в методах State; некоторые прямо ссылались на widget.index и widget.graph и могли захватить State, BuildContext и объекты рендеринга.

## Исправление
- Новый apps/story_reader/lib/book_isolate_workers.dart: только top-level compute entrypoints и явные параметры из plain-Dart данных, без State/BuildContext/RenderObject/plugin callback. Большая книга и индексация остаются в фоне, не блокируют интерфейс.
- home_page.dart: TXT/FB2 импорт через parseImportedBookInWorker(filename, bytes); BookWorld .bworld не переписывается.
- book_storage.dart: compute(_scanFiles, path) после получения пути на UI isolate; не передаётся BookStorage, rootDirectory и виджеты.
- source_index_preview_page.dart: фоновая индексация, кодирование/декодирование checkpoint и batch упоминаний — data-only worker functions.
- source_narrative_review_panel.dart: evidence decode/encode/scan в top-level workers.
- source_relations_review_panel.dart: создание, decode/encode, chronology и решения по relations в top-level workers.
- Сохранения игр, файлы книг, прежний UI и приватные checkpoint-форматы не изменяются.

## Проверки
apps/story_reader/test/book_isolate_workers_test.dart проверяет вызов worker из живого StatefulWidget с AppBar и ScrollController, настоящий разбор UTF-8 TXT и индексирование, M2b1 обработку и codec, M2b3b evidence codec, M2b3c связи/хронологию и самостоятельное сканирование JSON библиотеки.

Приёмка только по GitHub Actions точного PR HEAD: Flutter analyze/widget, Python/Dart/game contracts, Windows portable, Android APK. Ручной запуск той же книги на настоящем устройстве, FilePicker, длинные FB2, accessibility и power-loss отдельно. До этого не заявлять, что пользовательская ошибка гарантированно устранена на устройстве.

## Handoff
Если CI FAIL — исправлять в ветке и повторять. После 6/6 squash merge и обновить START_NEW_CHAT_RU.md, STATUS_RU.md, ROADMAP_RU.md точным run/commit. Принятый UX PR #12 сохранён, PR #13 закрыт как дубликат, независимый PR #14 может оставаться открытым. M2b4 не начат.
## 2026-11-02 — ПРОВЕРЕНО И ПРИНЯТО: hotfix открытия книги / Illegal argument in isolate message
- Реальный скриншот пользователя: Invalid argument(s): Illegal argument in isolate message: object is unsendable; в trace WidgetsBinding._firstFrameCompleter / RenderParagraph / StatefulElement. Предыдущий UX/UI аудит не исправлял именно этот класс crash.
- PR #15 https://github.com/shonentez-afk/AI-Story-RPG/pull/15 MERGED (squash code SHA a03d2a522b78bbd1a6d30c8bcae6a9733fd4688a); точный протестированный HEAD e26224f570e314fcbae4dbb868503ccf307ab96a.
- GitHub Actions https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41417818152 completed/success, 6/6 jobs PASS, Flutter analyze PASS, 155/155 Flutter tests PASS, Python PASS, Dart PASS, world/SQLite contracts PASS, Windows portable PASS, Android debug APK PASS. M0 run 41417818123 PASS. Артефакты AI-Story-RPG-Windows-portable и AI-Story-RPG-Android-debug подтверждены на этом run.
- Исправление: book_isolate_workers.dart с top-level typed compute worker entrypoints. home_page.dart импорт TXT/FB2; book_storage.dart JSON library scan; source_index_preview_page.dart индексация/checkpoints; source_narrative_review_panel.dart evidence; source_relations_review_panel.dart chronology/relations. Не передавать State, BuildContext, RenderObject, plugin/method closures в workers; не возвращаться к Isolate.run closure, объявленному внутри StatefulWidget State.
- Регрессия book_isolate_workers_test.dart: реальные compute операции для парсинга, индексирования, mentions/evidence/relations/chronology, сканирование библиотеки. Existing book_open_library_audit_test.dart: UI путь Подготовить → назад → Читать. WidgetTester FakeAsync не предназначен для ожидания настоящего isolate с pumpAndSettle; тесты используют корректные async зоны/ограниченные navigation frames.
- Сохраняется существующая одна библиотека, импорт, тексты, книга, игровые SQLite/.bwsave, три независимых checkpoints. Нет миграции и удаления данных.
- Физический запуск на ТОМ ЖЕ файле пользователя под Windows и Android НЕ проводился; CI не доказывает устранение всех возможных device-dependent багов. Для проверки нужна НОВАЯ сборка из Actions 41417818152; ранее установленный exe не меняется автоматически. Если ошибка повторится — получить полную трассировку, формат/размер файла, путь Читать или Подготовить к RPG.
- Отчёт docs/BOOK_ISOLATE_UNSENDABLE_HOTFIX_RU.md.

## 2026-11-02 — UX/UI PR #14 также принят
- PR #14 https://github.com/shonentez-afk/AI-Story-RPG/pull/14 MERGED squash SHA 97d82e4f4eeaaa91ad34f44d412c5eed779dc87e, проверенный HEAD b9a96fa41fc48d1d8e179d60581c393c2ada7d50, Actions 41414920106 6/6 PASS и 153/153 Flutter tests. Явная кнопка «Готово» в настройках чтения добавлена. PR #12 full UX/UI audit ранее принят, #13 закрыт дубликатом.
- Последний main после двух кодовых PR и этих документационных [skip ci] может отличаться от кодовой точки 97d82e4; следующий функциональный этап M2b4 semantic-provider требует собственного CI и ручного QA.