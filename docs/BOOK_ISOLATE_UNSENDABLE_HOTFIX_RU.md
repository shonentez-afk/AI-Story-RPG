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