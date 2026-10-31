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
