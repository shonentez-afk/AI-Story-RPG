# P0: автономная подготовка книг и независимый сценарный движок — фактический прогресс

Дата 8 ноября 2026. **PR #133 (Draft)**, кодовый commit `0ce8ea2f2da81d58885c43d8e8c8f4ff3924f0d5`. Эта запись относится к текущему крупному функциональному пакету, **не объявляет завершение 1.0**.

**Прежде чем менять единый GUI мастер**, прочитать [подробный проект пути «книга → RPG»](DESIGN_UNIFIED_BOOK_TO_RPG_PATH_AND_AUTONOMOUS_AUTHORING_RU_2026-11-08.md) и [матрицу разрывов core → rich-v3 → UI](ENGINE_FORMAT_UI_GAP_AUDIT_RU_2026-11-08.md). Инварианты: **один движок `story_core`**, сохранённые книги и миры, независимое offline исполнение, строгий source lock, защита NPC знания/памяти, 0/1/2 NPC, CANON отдельно от ALTER_FATE, ИИ-черновики не являются игровыми правилами. E6d и `main` не менять.

## СДЕЛАНО В КОДЕ

**Три связанных переноса внутри одного Draft PR (не отдельные PR):**

1. **Исходник/индекс/компилятор:** новый pure-Dart пакет `packages/story_authoring`, в нём без Flutter 4 уже существовавших модуля `book_import`, `book_model`, `book_text_decoder`, `book_source_index`; app-импорты стали thin `export`, а не копией. Сохраняются UTF-16 offset, source fingerprint, FB2/TXT/FB2.ZIP, иллюстрации и точный source proof.
2. **Локальная проверка текста:** в том же пакете находятся 11 существовавших модулей source mentions, source evidence, narrative extractor, reviewed assertions, source relations, semantics, offline semantic provider, dossiers и chronology. `OfflineBookAnalyzer` даёт bounded офлайн-анализ, `OfflineScanCheckpoint` — exact-edition hash-checked Resume. В stdout только метаданные/счётчики; приватные checkpoint с цитатами остаются на устройстве.
3. **Причинная логика книги:** ещё 10 существовавших модулей `NarrativeBookModel`, `StoryPlan`, source-locked causal audit, bounded repair, dilemma generator/quality gate, act planner, book-wide story plan composer, source event→choice attachment. Для отделения облака введены pure `BookEventOutline`/`BookEventProposal` и pure `ZaiStoryDilemmaPreview` DTO; app Z.ai остаётся подключаемым клиентским адаптером. Один тип сценария, без второй реализации `StoryWorld`.
4. **CLI (не Flutter):** `dart run bin/author_book.dart inspect-source <file>`, `scan-source <file> [--checkpoint <private-file>]`, `build-reviewed <file> <review.json> <out.bworld>`, `verify-world <out.bworld>`. `build-reviewed` принимает уже утверждённые `blueprint` и `provenance` с точной редакцией книги, использует существующий Dart `RichPrivateBookworldWriter` и тут же проверяет `RichPrivateBookworldImporter`. **CLI НЕ утверждает CANON и не сочиняет полную RPG самостоятельно.** Наличие Google/GLM ключа не требуется для offline.
5. **Непрерывность/CI:** GitHub CI проверяет пять независимых Dart-пакетов, `dart analyze/test` автономного authoring, исходный rich-v3 через второй независимый Python importer, Flutter analyze/widget и платформенные сборки. Введён тест pure Dart `StoryPlan` на двух реальных буквальных цитатах синтетического источника; ни Flutter, ни модель не участвуют.

## ПРОВЕРКА ФАКТОВ

- [Основной CI для code SHA 0ce8ea2](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42448890904) — при составлении этого checkpoint Python reference, Dart engine/scenario, standalone Dart authoring test и независимый Python source-locked ZIP importer **SUCCESS**; Flutter/widget, весь M1.7 и Windows/Android ещё не объявлены полным PASS без окончательной отметки GitHub.
- [M0 для code SHA 0ce8ea2](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42448890906) — **SUCCESS**.
- External RPG author tests (E6d) исторически **FAIL**; не смешивать с новой автономной main-app библиотекой, **не изменять** `tools/rpg_author` без отдельного решения.
- Старый кодовый baseline `6c3750ba` имел полный SUCCESS, но это НЕ подтверждение данного нового кода. Новые checks должны ссылаться на `0ce8ea2` или на следующий точный кодовый SHA.

## ЧТО ЕЩЁ НЕ АВТОНОМНО — БЛОКЕРЫ ПОЛНОГО РЕЗУЛЬТАТА

- Полный `FB2→литературно подтверждённый StoryPlan→NPC/диалоги/предметы/проза→`.bworld`` по одному CLI: части редакторов NPC/героя, consent и связанных компиляторов/сессий остаются в `apps/story_reader`, а модельный Z.ai сервис привязан к app adapter. Нужен **один** pure-Dart authoring сервис со стабильными model/file/checkpoint ports, а не второй генератор.
- `isFullBookRpg`/literary meaning/chronology still false: реальный CANON для private, role-specific verified initial knowledge/inventory, NPC authored gameplay, 192-scene rich-v3 limits и полная проверка книги не закрыты. Нельзя ослаблять импортер/корректность ради флажка готовности.
- Единый мастер и игровые панели ещё требуют реализации по заранее утверждённому проекту: `Герой/Предметы/Журнал/NPC`, портреты, spoiler filter future NPC, сцены, диалоги, consent, 0-NPC, AI allowlist, 280dp, 200% text, сохранения.
- Физические Android/Windows скриншоты, перенос `.bwsave` между устройствами, live GLM и два разных настоящих RU FB2 с литературной проверкой — **UNTESTED**.

## Один рабочий маршрут, без дробления

Продолжение **одного большого authoring + UI функционального пакета**: завершить выделение чистых NPC/hero/prose/compile, подключить безопасный provider-neutral AI port, затем построить **один** пошаговый мастер по заранее описанным 16 этапам с общим preflight/Resume. Вторым крупным пакетом согласовать versioned rich-v3 или новый формат для CANON/knowledge/time/масштабирования и полной книжной причинности. Финальная приёмка единая: exact-head CI/M0, Python/Dart parity, реальные RU FB2/GLM, Windows/Android и UX без спойлеров.

**Не делать** отдельные микро-PR/задачи для каждого экрана, файла, поля или теста; `main` и параллельный E6d не менять. **Issue #118 OPEN, PR #133 Draft.**
