# AI Story RPG — единая архитектура: книга → граф → игра → процедурные пиксельные сцены

Дата анализа: **2026-11-06**. Статус: **техническое решение / исследование, НЕ реализовано**.
Основной репозиторий: `shonentez-afk/AI-Story-RPG`. Проверенный основной `main`: `74f2eec302ad9693a61620002c859ba6d5cbfd5d` (после принятия PR #122; `a19f7ea...` — его кодовая база).
Внешний генератор: только `tools/rpg_author/`. Базовая проверенная версия внешнего генератора E6d: `9849c22d18e2761b49766b0c213b4a3fb3fe053b` / 0.3.0a2; установленный навык pin не изменять без отдельного тестового прохода. Текущий план E6e (единое завершение сборки+проверок) приоритетнее новых необязательных графических функций.

> **ИСТОРИЧЕСКИЙ ДОКУМЕНТ:** актуальный ЕДИНЫЙ генеральный план находится в [AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). Он дополнен главными требованиями: навык создаёт **полную готовую игру и всех NPC самостоятельно**, конечный результат **один .bworld**, редактор только по желанию, целевой строгий новый формат с визуальными рецептами, безопасные AI-NPC диалоги и интеграция с текущим main. При расхождениях использовать новый план. Этот файл сохранён для истории решений.

## 1. Согласованные цели (все договорённости)

1. Пользователь передаёт книгу FB2/TXT; система анализирует её целиком, учитывает явное согласие при сетевом ИИ, строит проверенный сценарий и отдаёт приватную `.bworld` для Windows/Android. Генерация игры не должна зависеть от наличия пиксельной графики.
2. **Единый каталог/граф** книги: события, персонажи и варианты имён, утверждения и их статус `NARRATED/REPORTED/INFERRED`, места, предметы, знания персонажей, ссылки на точные фрагменты исходника, текстовая последовательность и *отдельно* не всегда известное мировое время. Постоянные идентификаторы; цитата — свидетельство текста, а не автоматическое подтверждение интерпретации.
3. Две отделённые модели: **граф произведения** (что заявлено в книге) и **граф игры** (играбельные сцены/выборы/альтернативы). SOURCE_PASSAGE vs EXPLICIT_ADAPTATION не смешивать; игровые вымыслы не объявлять каноном.
4. Будущий редактор показывает графы событий, связей персонажей, знаний, вариантов истории; по нажатию на блок — источник/цитата, причины, риск противоречия, игровая постановка и предпросмотр. Изменение расположения узлов не меняет сценарий; изменение логики создаёт ревизию и инвалидирует литературные/механические проверки.
5. **Сцены строятся исключительно кодом, а не нейросетевой картинкой.** Генератор выдаёт **типизированный recipe**, а приложение процедурно рисует пиксельную геометрию и при желании лёгкую анимацию. Не нужно заранее рисовать или импортировать PNG-спрайты, фоны, тайлсеты.
6. Три режима: `text`, `pixels_static`, `pixels_animated`. Все читают один и тот же игровой state, имеют те же решения и сохранения. Отключение анимации, системный reduced-motion, энергосбережение; визуальная ошибка/неполное покрытие -> текстовый fallback.
7. Только существующий `story_core` определяет условия, изменения знаний, владение предметами и финалы; `story_engine` навигация, `story_runtime_adapter` согласование, `campaign_manager` SQLite/replay. Рендерер НИКОГДА не вызывает `choose` и не влияет на game state.

## 2. Что в проекте уже есть — НЕ писать повторно

| Фактический компонент (main 74f2eec...) | Наличие | Вывод |
|---|---|---|
| `book_source_index.dart` и Python `source_adapter.py` | Source-locked индекс с fingerprint, чанками, UTF-16 привязкой | Продолжить использовать; не вводить второй парсер книги |
| `narrative_book_model.dart`, `source_character_dossiers.dart`, chronology/evidence | Промежуточная модель событий, assertions, групп упоминаний, ссылок, неопределённостей; `mention_group_id` ещё не `world_actor_id` | Согласовать схему каталога с этой моделью, не объявлять предположение о личности фактом |
| `draft_scene_graph_overview.dart` + panel | Обзор чернового графа, недостижимые сцены, потерянные ссылки, циклы, переход назад по главам | Развить в графический viewer/editor, не писать структурные проверки заново |
| `story_core`, `StoryWorld`, `WorldEvent` | `scene_id, choice_id, next_scene_id, revision, event/state sha`; атомарно применяемые typed effects и replay | Не менять для анимации |
| `story_runtime_adapter`, `campaign_manager` | Синхронизация сценария и состояния, SQLite journaling, portable saves | Не вводить новую схему игрового сохранения |
| `WorldGameView` + `WorldPlayPage` | Текущая сцена, текст, stats/items/flags/player knowledge, UI выборы/панели | Точка read-only монтажа визуального виджета и выбора режима |
| `SceneDialogueScript/Stage` | Атрибутированные реплики, UI прогресс, портреты | Нужны структурные `turn_id` и безопасный callback visible beat для cue |
| `book_model.dart` | `GameMediaRole, SpoilerPolicy, SceneMediaBinding` | Предварительная image-oriented идея, не готовый procedural scene renderer |
| `tools/rpg_author` E6d | rich-v3 compiler, source/citation validation, gameplay/dialogue audit | Добавить позже граф/visual-plan, но не менять `.bworld v3` сейчас |

## 3. Выбор сторонних решений (проверено по официальным источникам и репозиториям)

### Модели интерактивного сюжета: учиться, НЕ внедрять второй engine

- **Arcweave** — boards/elements/links/variables/components (персонажи/предметы/локации), playtest/отладка: https://docs.arcweave.com/project-items/overview и https://docs.arcweave.com/project-tools/play-mode/overview . Коммерческая платформа; забрать организационный подход, не встраивать её API или закрытый код.
- **Twine** (`klembot/twinejs`) — наглядные passages и choice links: https://github.com/klembot/twinejs . Код GPL-3.0; **не копировать в Flutter** — берём только UX-принципы.
- **Inky/ink** — source-linked diagnostics и `play-as-you-write`, запоминание пути при правке: https://github.com/inkle/inky . MIT. Не заменять `story_engine` на ink.
- **Yarn Spinner editor** — graph view, диалоговый preview, line/character control, экспорт DOT/Mermaid: https://www.yarnspinner.dev/editor/ . Не переносить Yarn runtime.
- **Dialogic 2** — визуальная timeline событий (реплика, появление героя, условие, анимация): https://github.com/dialogic-godot/dialogic . MIT, но требует Godot 4.5+; только UX-модель, не Godot integration.
- **BookNLP** — хороший образец реестра entity, alias/coreference, цитат и speaker; https://github.com/booknlp/booknlp . **Английский язык**, не подменять им русский анализ.
- **Natasha** — Python/Russian NLP и NER/морфология/выделение фактов: https://github.com/natasha/natasha . Возможный **необязательный** offline extractor; модель ориентирована преимущественно на новости, литературные гипотезы требуют независимой проверки.

### Графическое отображение каталогов: выбрать ОДНУ Flutter-библиотеку по результатам spike

- **Mermaid** (MIT; https://github.com/mermaid-js/mermaid) — самый ранний этап: экспорт графа `.mmd` из Python, предпросмотр в GitHub/docs. Никакая зависимость в Android APK не нужна.
- **graphview** (Flutter/MIT; https://pub.dev/packages/graphview) — компактная read-only навигация с автоматической tree/layered/Sugiyama/layout. Это **не полноценный редактор**.
- **vyuh_node_flow** (Flutter/MIT; https://pub.dev/packages/vyuh_node_flow) — основной кандидат редактора: pan/zoom, группы, comments, minimap, JSON serialization, callbacks. Больше зависимостей, включая `flutter_mobx`, `mobx`, `http`. Проверить CI size/performance.
- **node_flow** (Flutter/MIT; https://pub.dev/packages/node_flow) — лёгкий альтернативный редактор, почти только Flutter SDK; nodes/ports/edges, zoom, minimap; **сохранение и undo/redo придётся реализовать у нас**, молодой пакет.
- **diagram_editor** (Flutter/MIT; https://pub.dev/packages/diagram_editor) — резерв при проблемах первых двух.
- **Рекомендация:** сперва `Mermaid` + текущий source-safe graph overview; затем отдельный benchmark `vyuh_node_flow` vs `node_flow` с 100/500/1000 узлами на Windows/Android. Выбрать один. `graphview` использовать только если нужен простой viewer; не ставить все библиотеки одновременно.

### Процедурные пиксели: способы рендеринга, а не PNG-ассеты

- **PixelForge** (`KodoRe/pixel-forge`), MIT по README/заголовку JS: https://github.com/KodoRe/pixel-forge . Самый близкий пример **JSON -> canvas**: `seed, palette, actor/item/tile/tree/building, layer, animation`. Проверка git-tree: на 2026-11-06 в репозитории **4 файла** (`README.md`, `SKILL.md`, `demo.html`, `pixel-forge.js`), нет `pubspec.yaml`, Dart-реализации и тестового каталога; не внедрять JS runtime, npm или WebView. **Кандидат на выборочное переосмысление/портирование алгоритмов** с отдельными тестами, после проверки исходных лицензий/атрибуции.
- **Sprite Forge** (`paperhurts/sprite-forge`), README заявляет MIT: https://github.com/paperhurts/sprite-forge . Пример layered 32x32 фигур (волосы, костюм, лицо, аксессуары, эмоции), deterministic seed. Это одностраничный HTML/JS; маленький, без автоматических tests и не package. Идеи форм/параметров, не production dependency.
- **pixel-sprite-generator** (`zfedoran/pixel-sprite-generator`), MIT LICENSE: https://github.com/zfedoran/pixel-sprite-generator . Проверяемый простой алгоритм маска + симметрия + seeded variation. Не решает композицию книги и анимацию, может служить исходным алгоритмическим тестом для мелких существ/узоров.
- **Flutter CustomPainter/Canvas** — встроенная технология для программной отрисовки; минимальная зависимость. https://api.flutter.dev/flutter/rendering/CustomPainter-class.html
- **Flame 1.x** (Flutter/MIT, Android + Windows; https://pub.dev/packages/flame) — включать **только если нужен** развитый timeline/component tree/camera; `GameWidget`, `ShapeComponent`, `CameraComponent.withFixedResolution`: https://docs.flame-engine.org/latest/flame/components/shape_components.html и https://docs.flame-engine.org/latest/flame/camera.html . Flame даёт цикл и компоненты, но **сам не умеет превращать смысл книги в пиксельный мир**. Не использовать PNG-dependent SpriteAnimation как основной способ.
- **НЕ нужно:** Ren'Py/Godot/Unity как runtime, Tiled/Aseprite/LibreSprite как обязательная часть, импорт готовых ассетов, генераторы text-to-image или генерация нового Dart/JS/Python исходника на каждую книгу.

**Лицензии:** при фактическом переносе исходного кода сохранять текст лицензии, copyright/атрибуцию и проверить зависимости. Декларация `MIT` в README PixelForge/Sprite Forge сама по себе не заменяет юридический аудит конкретной копии; до этого использовать идеи/спецификации и независимую реализацию.

## 4. Единая система данных, без повторных «истин»

```text
FB2/TXT
  -> existing source index (exact spans, chapter/chunk, source_fingerprint)
  -> BookKnowledgeGraph (events/characters/claims/locations/items/relations/evidence)
  -> reviewed StoryPlan (scenes/choices/flags/gameplay/dialogue, canon-vs-adaptation)
  -> current .bworld v3 (strict existing 4 ZIP entries, source/verifier)
          |
          +--> OPTIONAL procedural_visuals_v1 sidecar
                 (refs to exact compiled archive SHA, blueprint/story/source)
                 -> validator
                 -> presentation controller
                 -> code-only Canvas renderer
                 -> optional animations
```

Три идентификатора **не сливать по совпадению имени**: `source_mention_group_id`, `reviewed_character_id` и `world_actor_id`. Для каждого перехода должна существовать явно проверенная связь. Один персонаж/место/предмет получает стабильный procedural seed из **криптографического хеша канонического списка** `source_fingerprint, entity_id, style_version` (не `hashCode()` языка — он не предназначен для долговременной межплатформенной идентичности).

### Предлагаемые проектные форматы, ещё НЕ API текущего приложения

A. `book_graph_v1.json`:
- `source_fingerprint`, `source_index_sha256`;
- `characters` (id, verified aliases, appearance facts, uncertain traits, citation_ids);
- `events` (id, chapter, narrative_position, source_citation_ids, actor/recipient/prop/location IDs, epistemic state);
- `claims` (exact quote, assertion_kind, negation/polarity, whether actually established, knowledge/ownership time);
- `relations` typed: `mentioned_in`, `before_world_time`, `causes` **только если проверено**, `proposed_causes`, `knows_after`, `owns_after`, `same_as_reviewed`;
- `uncertainties` и evidence provenance с точными исходными spans.

B. `visual_plan_v1.json` (до компиляции): разбор визуально значимых событий и объектов; сцены без достоверного вывода имеют `unsupported_reason`; статус COVERED/PARTIAL/TEXT_ONLY. Полная литературная проверка обязательна перед привязкой спойлеров.

C. `procedural_visuals_v1.json` (после компиляции; пока отдельный приватный sidecar):
- `world_archive_sha256`, `blueprint_sha256`, `story_sha256`, `source_fingerprint`, `renderer_version`, `schema_version`, `visual_plan_sha256`;
- `scene_id`, `palette`, `environment`, `location_id`, `lighting/weather/time`, `layers`;
- `actors`: `character_id`, reviewed `world_actor_id` если есть, `archetype`, stable `appearance_seed`, approved visual traits, pose, anchor;
- `props`: item_id, procedural shape ID, visibility from **allowed actual world facts**, attachment to actor/body;
- `cues`: fixed opcode enum, `scene_enter` / `dialogue_turn` / `choice_committed` (exact from/choice/to/revision), duration and easing from allowlist.

Не путать две последовательности: «анимация жеста передать мяч» не выдаёт предмет. В игре предмет выдаётся `story_core` после подтверждённого выбора; визуальное появление в инвентаре и кадре — **проекция уже подтверждённого состояния**. При восстановлении не воспроизводить старые `grant_item`-анимации.

**Безопасность:** JSON recipe — данные, не исполняемый код; только фиксированные builtin generators/poses/actions, строгий allowlist, bounds для числа объектов/кадров, отсутствие eval/shaders/JS/shell/remote URLs. Unsupported visual command => skip/fallback, а не падение игры.

**Текущее ограничение:** `.bworld v3` требует строго четыре ZIP entry; не подмешивать туда `visuals.json` или менять `scenario/blueprint.json`. Sidecar пока проектная идея: он ещё НЕ импортируется приложением, нужен согласованный Dart importer + Python validator. Будущий embedded package — только отдельная версия формата и обе стороны проверки.

## 5. Воспроизводимая логика procedural scene

1. Смысловой анализ (ИИ с разрешения / локальная эвристика) предлагает состав сцены по точным цитатам: локация, действующие персонажи, реальные предметы, последовательность действий; спорные выводы отмечать для проверки.
2. `VisualDirector` сопоставляет source IDs и проверенные story IDs, выбирает **ограниченные** `scene_archetype`, `object_generator`, `actor_template`, `lighting`, `palette`, `animations`; не генерирует исходники и картинки.
3. `ProceduralGeometry` детерминированно строит фон/планы/классические объекты из пиксельных фигур, шаблонных масок и seeded noise; узнаваемых героев — из частей тела, одежды и выражений; объекты и палитры общие для книги.
4. `SceneStateProjector` накладывает player-visible flags/items/knowledge (не раскрывать секреты NPC). Варианты сцены определяет verified current state.
5. `AnimationScheduler` запускает лишь косметические временные состояния `idle/blink/talk/turn/move/appear/give/react/water/rain`. Знак `choice_committed` применяется только к confirmed+nonduplicate world transition; rejected/stale/duplicate -> никакой анимации последствий. `DialogueStage` требует стабильных turn keys, а не угадывания speaker из текста.
6. `PixelRenderer` рисует кодом на логической целочисленной сетке, ближайшее масштабирование, статические слои кэширует **в памяти**; никаких image generation/file assets. Переключение режима не меняет `StoryWorld`/save.
7. При повторной загрузке базовый кадр создаётся из того же recipe + state; прошедший timed gesture не переигрывается, сцена остаётся согласована с сохранением.

**Практический дизайн:** первая тестовая сцена 320x180, <=16 цветов одной палитры, 2 персонажа, 1 предмет, 2-3 статических плана, 3 простых cues; масштабировать на реальном Android/Windows только после профильных тестов. Параметры демонстрационные, не подтверждённые аппаратными бенчмарками.

## 6. Этапы без затягивания основного релиза

| Приоритет | Этап | Конкретный готовый результат | Не блокирует |
|---|---|---|---|
| P0 | E6e закончить внешний `finalize` / литературный и механический QA | Проверенный `.bworld v3`+attribution+report+snapshot (диалоги по применимости) | Визуальный редактор и картинки |
| P0 | Полная проверка настоящей сказки + второй различной книги | Утверждённый анализ, диалоги, две реальные ветви, сохранения, ручной Windows/Android E2E | Анимации |
| P1 | E6f согласовать `book_graph_v1` с native `narrative_book_model.dart` | Source-linked machine-readable catalog, chronology/identity uncertainty, citations, coverage, `.mmd` экспорт | UI граф-редактора |
| P1 | Внешний `visual-plan` + независимые validators | JSON schema, coverage/TEXT_ONLY, source/game IDs, verified story/world hash | Изменение `.bworld` |
| P1 | Отдельный кодовый рендерер (новый Dart presentation package) | Один Canvas-proof: pond/princess/frog/ball, stable seeds; offline/no PNG; 3 modes | Замена story engine |
| P1 | Лёгкий `AnimationScheduler` + gateway UI binding | `dialogue_turn` и post-commit cue, правильный cancel/reopen, reduced motion | Схема сохранения |
| P2 | Граф редактора (Vyuh vs NodeFlow spike) | Одна выбранная библиотека, выбор узла → source/scene preview, интерактивная правка с re-review | Базовое воспроизведение |
| P2 | Расширение процедурных архетипов | Дома, города, леса, озёра, фабрики, животные, сцены разных жанров; coverage report | Картинки |
| P2 | Переносимое визуальное оформление | Отдельный согласованный пакетный контракт/upgrade, Python/Dart verification, backward compatibility | Старый `.bworld v3` |

Ограничение ответственности: по действующим правилам внешняя ветка может **документировать и реализовать только tools/rpg_author/**. Перечисленные изменения Flutter/пакетов нельзя выполнять без **нового явного разрешения**. Результат текущей работы — технический план, а не feature implementation.

## 7. Приёмочные проверки — обязательные

**Источник / смысл:** полное покрытие книги, exact quote offsets, подтверждённые identity/ownership/knowledge, separated reported/inferred, альтернативы marked GAME_FICTION, отсутствие спойлеров и невозможных движений.

**Структура / replay:** native Python/Dart agree on hashes, source hash and valid v3; 2 distinct reachable endings for текущего external ALTER_FATE baseline, no dead ends, valid two paths, dialogue-turn completeness; `.bwsave` previous games still import.

**Визуальный протокол:** sidecar wrong world/source/story/renderer/hash/unknown opcode/bad duration/bad ID -> reject visual only, game continues in text; no executable code/URLs; every cue references real scene/choice/turn and approved actor.

**Рендерер:** same seed -> same semantic pixel-primitive stream between Windows/Android, stable appearance across scenes; no requirement for byte-identical GPU raster. No art files/network. Fallback when archetype unknown.

**Анимация:** deny/duplicate/stale no new gesture; success exactly one cue after commit, item visible iff actual state; scene switch/cancel/reload while animation active -> correct stable frame; no game state mutation; user can disable and system reduced motion works.

**Устройства:** Flutter unit/widget/golden, Windows+Android CI builds, separately *real* device launches, memory/FPS/battery/resize/fonts/scroll/focus/restart, long book and 100/500/1000-node editor spike. Do not claim device E2E without evidence.

## 8. Не забыть в следующих чатах

- **Не повторять:** готовый Python source adapter, native narrative book model, structured draft graph overview, core runtime, SQLite save, native dialogue stage/portrait picker, audited `.bworld v3` compiler.
- **Не нарушать:** E6d pinned skill SHA и отсутствие миграций старых E5 архивов; main/read-only; книжные данные не в публичном GitHub.
- **Не делать:** новый game engine, генерация нейросетевых растров/спрайтов, runtime arbitrary code generated per book, готовая sprite library dependency, непрозрачное смешивание проверенной прозы и визуальных гипотез.
- **Начать с проверки:** E6e завершение и литературный E2E; следующей небольшой параллельной задачей подготовить JSON schema визуальной постановки на 1 синтетической сцене, без Flutter modifications.
- **Архитектурная ссылка:** `tools/rpg_author/PROCEDURAL_PIXEL_SCENES_RU.md` и `tools/rpg_author/E6F_VISUAL_RUNTIME_COMPATIBILITY_RU_2026-11-06.md`.

Примечание: у `vyuh_node_flow`, `flame` и других пакетов могут появляться новые релизы; перед конкретным PR фиксировать версию и проверять на актуальном SDK/CI. Сведения о пакетах в этом документе — результаты исследования, не доказательство тестов внутри нашего приложения.


## 9. Дополнение E6g: сторонние компоненты, встроенный редактор и свободный AI-диалог

**Актуальное зафиксированное решение:** [E6G_THIRD_PARTY_AND_AI_FREE_INTERACTION_DECISIONS_RU_2026-11-06.md](E6G_THIRD_PARTY_AND_AI_FREE_INTERACTION_DECISIONS_RU_2026-11-06.md).

- Редактор **встроен** в основное Flutter-приложение (полный Windows, адаптивный Android); единые source-locked book/game graphs, персонажи/знания/NPC persona, сценическая постановка и ограниченные анимации.
- Сторонние решения не становятся новыми движками: Mermaid graph export; после spike выбрать **один** из `vyuh_node_flow`/`node_flow`; кодовый рендерер Canvas, Flame только по необходимости; PixelForge/Sprite Forge как **алгоритмические ориентиры**. Twine/Inky/Arcweave/Yarn Spinner/Dialogic — UX/схемы, не runtime.
- AI Dungeon (Do/Say/Story + world cards), Convai Narrative Design (goals/triggers), AI Town (persona, memory/messages отдельно от world), Rasa CALM (LLM intent, deterministic flows), chasm (NPC perceived knowledge) используются как **сравнительные архитектурные модели**, без облачных SDK и второго gameplay engine.
- В `main` **УЖЕ** есть `FreeTextActionGate/Panel/WorldGatewayPort`, `ZaiGameplayChoiceAdvisor`, opt-in Z.ai/BYOK, `npc_knowledge_rulebook`. Текущий API **сопоставляет с доступным choice ID**, но **не** ведёт свободные, основанные на знаниях NPC беседы. Дополнение: `SAY` с речевым стилем/памятью/знаниями, `LOOK` из доступных фактов, `DO`/`INTERACT` только через существующий gateway, `STORY` — лишь отдельный будущий экспериментальный режим.
- Генератор готовит отдельные строгие `npc_profile_v1`, `npc_conversation_policy_v1`, `scene_interactions_v1`, `npc_memory_v1`, `ai_interaction_contract_v1` и visual recipe; версии/идентичность/приватность проверяются отдельно от `.bworld v3` (строго четыре ZIP entries).
- **Не доверять модели эффекты:** никакая реплика/намерение/визуальная команда не меняет `story_core` или SQLite без уже разрешённого выбора, подтверждения игрока и успешного commit. NPC знание строго ограничено проверенными источниками и подтверждёнными событиями; memory claims — не канон. API off by default, показывать точный передаваемый контекст и отдельно просить согласие на новые поля; никаких скрытых глав/целиком книг.
- Не откладывать P0 E6e, полную литературную проверку двух книг и Windows/Android E2E ради новых функций. Код `main/apps/packages/tools/bookworld` read-only до нового разрешения.
