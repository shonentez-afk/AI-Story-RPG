# Архитектура и технические контракты
**Источник пользовательских требований:** [TZ_RU.md](TZ_RU.md). Этот документ содержит проектные решения, которые ещё предстоит подтвердить реализацией.

## Модули
- `apps/story_reader` — Flutter Windows/Android UI; позже iOS.
- `packages/story_core` — чистый Dart (без Flutter и сети): состояние мира, условия, эффекты, таймер, NPC, валидатор действий, RNG seed, рендер доступных вариантов.
- `packages/bookworld` — чтение/версионирование `.bworld`, валидация и миграции.
- `packages/campaign` — независимые прохождения, ветвления, экспорт/импорт `.bwsave`, event log.
- `packages/llm_client` — адаптеры только для свободного ввода/текстовых ответов; no-op в CLASSIC.
- `tools/book_compiler` — отдельный Python импорт/анализ, НЕ включать в обязательный Android runtime.
- `shared_schemas` — общие JSON Schema и golden test fixtures, версии форматов.

## Границы доверия
BookWorld **не является исполняемым кодом**. Внутри только проверяемые данные; никакого eval, динамического импорта, shell, сетевых URL ресурсов из архивов. Проверять zip-slip, decompression bombs, размеры, checksum и UTF-8.
Source text is untrusted: инструкции из книги никогда не становятся системными инструкциями модели.
LLM не имеет прав напрямую менять базу: `player_text -> structured_action -> deterministic_validate -> atomic_commit -> narrator`. Если проверка не пройдена, ход отклоняется или уточняется без изменения мира.

## Сценарные состояния
Каждая сцена: `id, body, location, prerequisites, choices, transitions, source_refs, visibility`.
Каждый выбор: `id, label, preconditions, effects, next_scene_id?, outcome_text`.
Каждый факт: `id, content, provenance(chapter,span), status(immutable/adaptable/open/conflicted), evidence`.
Каждое событие кампании: `sequence, timestamp, actor, operation, previous_hash?, payload, witnesses`.
На уровне мира хранить персонажей, реальные факты и последствия отдельно от персональных знаний, слухов и убеждений NPC.
Во избежание exponential branching хранить базовый событийный граф + условные действия и редкие развилки, а не копии всего романа.

## Сценарный режим и способ взаимодействия — ортогональны
- ROLE = CUSTOM | PROTAGONIST | BOOK_CHARACTER.
- PLOT = CANON | ALTER_FATE | FREE_WORLD.
- INTERACTION = CLASSIC | AI_FREEFORM | HYBRID.
- Каждый BookWorld объявляет `supported_modes`; 27 сочетаний **не гарантируют** 27 полноценных игровых сценариев.
- CLASSIC: только проверяемые, предварительно подготовленные действия/ответы.
- AI_FREEFORM: интерпретатор может предлагать новые действия, но изменения разрешает только rule engine.
- HYBRID: классические действия + свободный текст при наличии доступного провайдера.
- Переключение AI->CLASSIC возможно лишь при нахождении совместимого заранее подготовленного продолжения; иначе предложить fork на предыдущую точку или продолжение с ИИ.

## Форматы
### BookWorld (.bworld)
Контейнер ZIP с `manifest.json`, `book.sqlite`, `assets/`, `source_refs/` (при наличии прав). В manifest: `schema_version, book_id, title, author, source_sha256, compiler_version, languages, supported_modes, coverage, assets_manifest, rights_metadata`.
Пакет считается неизменяемым; правки сценария = новый version/hash.
Изначально предоставить ручной демонстрационный fixture, затем генерировать через компилятор. Хранение текста оригинала внутри пакета **не обязательное** и зависит от прав и желаемого режима чтения.

### Campaign save (.bwsave)
ZIP/JSON+SQLite экспорт, включающий `schema_version, book_id, bookworld_hash, campaign_id, role/plot/interaction, world_state, event_log, rng_seed, checkpoints, last_scene`.
Нельзя использовать save с неподходящей версией BookWorld без миграции/подтверждения. Никаких ключей API и кеша полного текста отправляемых запросов.

## Процесс компиляции
1. Import: файл -> нормализованный текст и source_map.
2. Segmentation: главы/сцены/чанки + checkpoint.
3. Extract: строго схемные факты/профили/связи/временная шкала + ссылки.
4. Aggregate: слияние алиасов, поиск конфликтов, все главы учтены.
5. Plan: причинный граф, точки решений, альтернативные ветви.
6. Compile: сцены/выборы/условия/эффекты с предсказуемым исполнением.
7. Validate: все ссылки существуют, концовки достижимы, не допускается утечка скрытых сведений, явно отмечена неполная обработка.
8. Package: `.bworld`, manifest, hashes, QA отчёт.

## Наблюдаемость
Сохранять диагностические идентификаторы и стоимость запросов, но не исходные тексты книг/ключи API в логах по умолчанию. Метрики: coverage, retry, invalid JSON, dropped fact, spoiler rejection, deterministic state hash per turn.

## Выбор сценарного движка (M0, решение утверждено)
На M0 протестировать на одном демо два кандидата: `ErikSchultheiss/story_engine` (BSD-3-Clause, чистый Dart) и `dennerkrans/ink_dart` + `flutter_ink` (MIT). До итогового ADR победитель **не выбран**; нельзя параллельно исполнять одной кампанией два runtime.
Интеграция выбранного движка только через собственный `StoryRuntimeAdapter`: загрузка, список выборов, подтверждённые события, snapshot, восстановление, диагностика. `story_core` остаётся единственным авторитетным владельцем инвентаря, отношений, знаний и журнала событий. `.bworld`/`.bwsave` не должны зависеть от внутренних классов внешней библиотеки. Подробности и критерии: [основное ТЗ, раздел 6.1](TZ_RU.md) и [аудит движков](TEXT_RPG_ENGINES_GITHUB_AUDIT_RU.md).

## Временный формат встроенного демо (M1.6.6)
`apps/story_reader/lib/pilot_save_codec.dart` создаёт `.bwsave` только для `ai_story_m1_intro`; подробности: [BWSAVE_PILOT_FORMAT_RU.md](BWSAVE_PILOT_FORMAT_RU.md). Это промежуточная переносимая обёртка над legacy снимком `story_engine`, не целевой engine-neutral `.bwsave` из раздела выше. Не использовать для произвольных `.bworld`, не подменять им будущие схемы и не импортировать без пробного восстановления snapshot. Совместимость и миграции — обязательные задачи M1.7.

## M1.7.1 — первый реальный `story_core` (2026-11-02)
`packages/story_core` содержит типизированные, сериализуемые без исполнения сценарного кода контракты `StoryBlueprint`, `WorldState`, `StoryWorld` и `WorldEvent`. Схема JSON и оригинальный fixture — `shared_schemas/`. Это **первый модуль авторитетной модели мира**, но текущий Flutter пилот пока использует прежний `GameProgress`; двух одновременно исполняющих миров нет. Все будущие изменения состояния должны пройти координацию с выбранным `story_engine` согласно ADR-001. Полный контракт, ограничения и последовательность интеграции — [M17_STORY_CORE_RU.md](M17_STORY_CORE_RU.md).

## M1.7.2 — StoryRuntimeAdapter и граница транзакций
В `packages/story_runtime_adapter` реализован `StoryEngineCoordinator`: `StoryWorld.fork` и `StoryEngine.restore` позволяют отдельно рассчитать и проверить обе стороны выбора без изменения активного состояния. Core — единственный хозяин инвентаря/фактов/журнала; story_engine — только сценарная навигация. Сверка сцен обязательна до публикации кандидатов. `checkpoint` и `restore` пересчитывают подтверждённый event log с ревизией, ожидаемым hash и версиями blueprint, затем перепроверяют навигацию story_engine. Это **in-memory**, не ACID; SQLite migration и старый пилот остаются отдельными до M1.7.4. Подробности: [M17_STORY_RUNTIME_ADAPTER_RU.md](M17_STORY_RUNTIME_ADAPTER_RU.md).

## M1.7.3 — отдельный пакет BookWorld
`tools/bookworld/bookworld.py` (Python offline compilation) записывает канонический `scenario/blueprint.json`, нормализованный `world.sqlite` и `manifest.json` со всеми version/hash/rights/capability полями в ZIP. `packages/bookworld_format` (native Dart, вне Flutter UI) проверяет структуры, размеры, CRC, SHA, полный SQLite integrity/catalog и возвращает только валидированный `StoryBlueprint`; затем в тесте `StoryEngineCoordinator` начинает мир. Исполняемых сценарных скриптов внутри пакета нет. Схема/формат версии 1 ограничены ORIGINAL_DEMO/CLASSIC и тремя членами ZIP. Это не runtime Python, не новый save API и не ACID DB для кампаний. Полная схема: [M17_BOOKWORLD_FORMAT_RU.md](M17_BOOKWORLD_FORMAT_RU.md).

## M1.7.4a — SQLite owner of durable world events
Новый `packages/campaign_manager` принимает только валидированный `VerifiedBookworld` через `BookworldImporter`, сохраняет неизменный world blob по SHA-256 и независимые кампании с ключами BookWorld. Каждая команда синхронно подтверждается через `StoryEngineCoordinator`, после чего event log+revision/state hash обновляются в одном `BEGIN IMMEDIATE` / `COMMIT` SQLite транзакционном блоке. Восстановление начинается с точного world и полного verified replay, без исполнения текстов/файлов игры. Новый save v2 JSON+hash только для original-demo/CLASSIC. Старая M1.6 SharedPreferences не мигрирована и не изменена. Подробнее `M17_CAMPAIGN_SQLITE_RU.md`.

## M1.7.4b1 — Flutter adapter без второго источника истины
`WorldLibraryGateway` отделяет видимый Flutter UI от синхронного `BookworldCampaignStore`; `DeviceWorldLibraryGateway` выполняет все ZIP/SQLite/replay операции внутри `Isolate.run` с приватным `getApplicationSupportDirectory`. DTO `WorldGameView` содержит подтверждённое состояние, историю и lockReason; UI не применяет правила сам и не меняет сцену до завершения `commitChoice`. Старая библиотека с BookStorage/BookReaderPage сохраняется; в `LibraryPage` одна CTA импорта .txt/.fb2/.bworld, отдельные карточки для BookWorld, без объединения хранилищ. Работа legacy M1.6 не мигрирована; см. `M174B_FLUTTER_BOOKWORLD_RU.md`.
