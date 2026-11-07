# AI Story RPG / Story RPG Engine — единый подробный план внедрения лучших идей

**Дата:** 2026-11-07. **Статус:** техническое предложение и справочник для другого чата; не отчёт о реализованном коде.
**Область:** развитие основной программы как независимого движка и согласование с внешним Python-генератором E6e (наследует зафиксированный E6d).
**Актуальная ветка хранения:** feature/external-rpg-author-e6e-parity-20261107, только tools/rpg_author; код main/apps/packages/BookWorld/CI данным документом НЕ изменён.
**Обновление 7 ноября 2026:** генеральный план расширен нормативным [планом внедрения игровых вкладок](GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md). Проверено на main 9c9bdc142495e536b5d11ca5e61680948e45f8fe после принятия PR #131; PR #132 (социальные механики) ещё draft. E6e generator 0.3.0a3 на SHA bfa4190afec7c0f5e00c70e357898a9660c05450 прошёл author-tests и dart-parity [Actions #42297819582](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42297819582). Pin установленного навыка всё ещё E6d 9849c22...; не выдавать новые UI/game mechanics за готовые.

## 0. Начать здесь: источники истины и достигнутая стадия

1. [Главный сводный план внешнего генератора, NPC, редактора и пиксельной графики](https://github.com/shonentez-afk/AI-Story-RPG/blob/feature/external-rpg-author-e6e-parity-20261107/tools/rpg_author/AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md) — продолжает действовать; этот файл раскрывает **конкретные внешние источники, варианты интеграции и порядок**.
2. [Наш START_NEW_CHAT](https://github.com/shonentez-afk/AI-Story-RPG/blob/feature/external-rpg-author-e6e-parity-20261107/tools/rpg_author/START_NEW_CHAT_RU.md) — границы параллельной ветки, проверенный pin E6d, передача новому чату.
3. [План автоматической RPG в основном проекте](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/ROADMAP_AUTOMATIC_RPG_RU_V2_2026-11-05.md), [приёмка 1.0](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/PROJECT_COMPLETION_GATE_RU_2026-11-06.md), [модель NPC](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/NPC_COMPLETE_BEHAVIOR_MODEL_RU_2026-11-07.md), [независимый движок](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/ENGINE_STANDALONE_OPEN_SOURCE_ARCHITECTURE_RU_2026-11-06.md). Основной чат обязан сверить актуальные HEAD/CI/PR при реализации; ссылки /main/ живые и могут меняться.
4. **Исторический срез при подготовке 5–6 ноября, не текущий HEAD:** основной main f4331851ef5752e0e2821f328d75703808579ef5 после [PR #130](https://github.com/shonentez-afk/AI-Story-RPG/pull/130), который принят. [NpcSocialLedger](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_core/lib/src/npc_social_ledger.dart) пока read-only проекция событий/отношений, НЕ новые игровые операции изменения отношений. Exact-head PR CI #823 и M0 #908 success; post-merge CI #824 выполнялся, M0 #909 success на момент среза. Не путать эти факты с готовой 1.0.

**Главная цель НЕ МЕНЯЕТСЯ:** пользователь добавляет собственную книгу -> выбирает поддерживаемого героя и режим -> получает проверенную полноценную RPG по всей книге -> играет офлайн на Windows/Android; редактор необязателен. В будущем эти же независимые Dart-пакеты можно будет публиковать как самостоятельный движок.

**Иерархия планов:** продуктовая цель/приёмка 1.0 из основного roadmap выше приоритета пожеланий; сводный документ E6d определяет внешнюю генерацию и визуальные идеи; этот новый план является **приложением по технике реализации**, а не третьим конкурирующим roadmap. P1/P2 не превращать в блокеры P0.

## 1. Архитектурная договорённость: один авторитетный игровой мир

### Существующие пакеты, не переписывать

- [story_core](https://github.com/shonentez-afk/AI-Story-RPG/tree/main/packages/story_core) — чистый Dart, StoryWorld/WorldState, детерминированные условия, эффекты, фактология, журнал событий с SHA, проверки и replay. Только этот слой утверждает игровые последствия.
- [story_runtime_adapter](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_runtime_adapter/lib/story_runtime_adapter.dart) — публичный доступ к сцене/выборам, выбор/валидация, согласование с уже выбранным сторонним story_engine. Не менять сценарный runtime на Ink/Yarn/Narrat.
- [bookworld_format](https://github.com/shonentez-afk/AI-Story-RPG/tree/main/packages/bookworld_format) — строгий импорт/экспорт .bworld и проверки источника.
- [campaign_manager](https://github.com/shonentez-afk/AI-Story-RPG/tree/main/packages/campaign_manager) — кампании, SQLite, сохранения, recovery/replay. [Пример без Flutter](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/campaign_manager/example/standalone_rpg.dart).
- Flutter, GLM/Z.ai, процедурные пиксели, редактор, внешний генератор и другие клиенты — НЕ имеют права напрямую изменять истину мира.

### Единая цепочка

1. **BookEvidenceGraph**: что действительно сказано в книге, кем, когда, в какой редакции/фрагменте.
2. **BookModel**: идентичности, события, цели, знания, хронология, локации, предметы и неопределённости.
3. **StoryPlan**: игровые ситуации, разрешённые действия, переходы, причинные эффекты, происхождение канон/адаптация.
4. **Validators**: достоверность источников, причинность, достижимость, спойлеры, ограничения формата.
5. **BookWorld compiler**: версионированный единый .bworld, с согласованными Python/Dart контрактами.
6. **story_core**: допустимость действия -> подтверждённое событие -> новое состояние.
7. **story_runtime_adapter**: единственная точка для клиента игры.
8. **Flutter/CLI/AI/Visual**: отображение состояния и отправка ограниченных намерений.

Запрещено создавать второй источник истины для NPC/отношений/инвентаря, второй replay, графовую БД или скрытые world mutations из художественного текста. Строки и цитаты не являются игровыми событиями.

## 2. Анализ книги и игровая адаптация — NovelToGame

**Реальные исходники/методики:**
- [novel-game-analyze/SKILL.md](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/novel-game-analyze/SKILL.md)
- [gameability-protocol.md](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/novel-game-analyze/references/gameability-protocol.md)
- [game-world-design/SKILL.md](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/game-world-design/SKILL.md)
- [narrative-design-method.md](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/game-world-design/references/narrative-design-method.md)
- [game-qa/SKILL.md](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/game-qa/SKILL.md)
- [pipeline-contract.md](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/novel-to-game/references/pipeline-contract.md)

**Перенять принцип, не чужие output-схемы:** source bible (проверенная книга) / game concept (зачем игрок действует) / game design (правила/маршруты) / runtime QA (реальный запуск). Важно извлекать **выполнимые игровые действия**, а не только пересказывать главы.

**Встроить:** уже существующие SourceEvidenceGraph/SourceSemanticCatalog/SourceCharacterDossierIndex/BookModel/StoryPlan и внешние E6 анализ+checkpoint. Не вводить две несовместимые «библии книги». Дополнить единый контракт candidate-полями: source_span UTF-16, edition_fingerprint, evidence_type NARRATED|REPORTED|INFERRED, confirmed character identity, scene/gameplay affordance, uncertainty, canon/explicit adaptation.

**Программа и навык:** оба должны сохранять идентичность source_mention_group -> stable npc character_id -> world actor_id; каждому факту/цели/отношению дать provenance. Результат анализа не равен доказанному факту world runtime, пока не прошёл source review.

**QA:** полное покрытие значимых событий и пропуски по главам, корректность предметов и времён, отсутствие хардкода по «Королю-лягушонку», повторная проверка при иной редакции книги. P0.

## 3. Нелинейный сюжет — Ink + Yarn Spinner

**Ink:** [WritingWithInk.md](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md) — knots/stitches, joins, diverts, tunnels, conditional choices, tracked state. Принцип: после ветвления возвращаться в общую сцену можно, но **состояние и причины не теряются**; иначе игрок получит последствия невыбранной ветви.

**Yarn Spinner:** 
- [ContentSaliencyOption.cs](https://github.com/YarnSpinnerTool/YarnSpinner/blob/main/YarnSpinner/Saliency/ContentSaliencyOption.cs) — ID контента, число пройденных/проваленных условий, сложность.
- [BestLeastRecentlyViewedSaliencyStrategy.cs](https://github.com/YarnSpinnerTool/YarnSpinner/blob/main/YarnSpinner/Saliency/BestLeastRecentlyViewedSaliencyStrategy.cs) — отбор допустимого контента и приоритет менее повторявшегося.
- [SaliencyTests.cs](https://github.com/YarnSpinnerTool/YarnSpinner/blob/main/YarnSpinner.Tests/SaliencyTests.cs) — примеры once/условий/отбора.

**Перенять в AI Story RPG:**
- P0: существующий StoryPlan / IntermediateStoryBlueprint; общие сцены при разных состояниях; причинный branch-delta, терминальная достижимость, никакого перехода на невыбранную ветвь.
- P1 сначала **контекстные группы реплик (line groups)**, затем **группы эпизодов (storylets/node groups)**: допустимость, priority, once/max_visits, tie-breaker, fallback. Не пытаться заменить core engine автоматическим AI-режиссёром.
- Предлагаемая структура для будущей версии данных: storylet_id, arc_id, scene_id, requires/forbids, saliency, visit_policy, fallback_id, source_origin.
- Алгоритм: evaluate predicates through story_core -> filter unavailable -> rank deterministically -> choose -> commit event if selection has gameplay consequences -> render through adapter. Никаких незаписанных случайностей; при необходимости seed/выбор фиксировать для replay.
- По умолчанию CANON не меняет обязательные канонические события; ALTER_FATE может иметь альтернативные игровые ситуации, но с пометкой источника.

**QA:** одинаковый replay после save, нет недостижимых терминалов, история посещений не исчезает, при отсутствии допустимого storylet есть проверенный fallback; один и тот же причинный путь сохраняет эффект. P0 только проверки графа; runtime Storylets P1.

## 4. Обязательства, смысловые последствия и контрпримеры — наш модуль над StoryPlan

**Происхождение идеи:** комбинация ветвей Ink, причинных эффектов Axiom AI, source-grounded QA NovelToGame. Это **наш предложенный контракт**, не скопированная готовая система.

**NarrativeObligation (проект):** obligation_id, kind=promise|debt|mystery|task|threat|conflict, opened_by_event, debtor/beneficiary IDs, preconditions, resolution_event_ids, current_status, source_refs, adaptation flag.

**Сначала в компиляторе (P0):** проверить цепь «взял обязательство -> выполнил/нарушил/обоснованно осталось открытым», отсутствие несуществующего обещания и двойного владельца уникального предмета. Сообщать воспроизводимый counterexample (последовательность choice_id, где правило нарушено). В режиме CANON не требовать искусственных альтернативных финалов; в ALTER_FATE проверять существенную branch-delta по future choices, items, knowledge, relations и terminal consequences.

**Позже в runtime (P1):** если статус обязательства реально влияет на выборы, он должен вычисляться по committed events или явным типизированным effects в story_core; не разрешать локальному аудиторскому JSON самовольно переключать состояние.

**QA:** два маршрута с/без данного обещания; повторное объединение ветвей; незакрытые обязательства объяснимы, а не молча исчезают.

## 5. NPC: постоянная личность, память и социальные отношения — Project Lunar + AI Town

**Project Lunar (ветка у источника именно master):**
- [npc_mind_engine.py](https://github.com/horizonfps/project-lunar/blob/master/backend/app/engines/npc_mind_engine.py) — личные цели, мнения, планы, временные эмоции.
- [memory_engine.py](https://github.com/horizonfps/project-lunar/blob/master/backend/app/engines/memory_engine.py) — многоуровневые краткие/долгие резюме и перспективы.
- [plot_generator.py](https://github.com/horizonfps/project-lunar/blob/master/backend/app/engines/plot_generator.py) — макро-сюжетные дуги и микро-ситуации.

**AI Town:**
- [convex/agent/memory.ts](https://github.com/a16z-infra/ai-town/blob/main/convex/agent/memory.ts) — важность, недавность, релевантность памяти, reflections, retrieval.
- [convex/agent/conversation.ts](https://github.com/a16z-infra/ai-town/blob/main/convex/agent/conversation.ts) — построение контекста разговора; недоверенные воспоминания должны трактоваться как данные, не команды.

**Встроить без второй памяти:**
1. **Идентичность:** existing permanent character_id (npc_ + 32 hex), псевдонимы, source identity mapping; нельзя восстановить ID из имени или придумывать нового NPC при переименовании.
2. **Правда мира:** WorldState.knowledge и WorldEvent; только confirmed learn_fact/effects, в отдельности от литературной авторской заметки.
3. **NPC память:** existing NpcSocialLedger (PR #130), read-only projection по конкретным событиям; дальнейшие typed operations/условия требуют версии формата и одинакового поведения SQLite/replay. Сначала осмысленная проверка observer/presence, затем работающее применение в условиях сцены.
4. **Убеждения/слухи:** отдельно от known fact; слух не превращать автоматически в истинный fact; различать witnessed, reported, inferred, believed false.
5. **Краткие AI-summary:** только для экономии контекста, с указанием фактических event IDs; они НИКОГДА не меняют мир, не могут выдать NPC недоступный факт.
6. **Отношения:** A -> B не равно B -> A; event -> rule -> verified directional change, не «отношение по тексту ИИ»; ограничение повторных начислений.

**Предложение о будущих моделях:** NpcKnowledgeEvidence(actor_id, fact_id, acquired_event_id, route), NpcMemory(observer_id, event_id, kind), NpcDirectedRelation(source_id,target_id,kind/value,last_cause_event_id), NpcPresence(actor_id,scene_id,availability), NpcBelief(actor_id,proposition_id,confidence,origin), NpcGoal. Важно: это НЕ утверждение о существующих типах v3.

**QA:** ранние спойлеры, чужая память, неверный свидетель, персонажи с одинаковыми именами, обратно направленное отношение, альтернативная ветвь, сохранение/восстановление; нет знаний от одной лишь карточки NPC. P0 на знания/отношения/доступ к репликам, P1 на сложную память и AI-context.

## 6. Цели и поведение NPC — LimboAI + GOAP + Convai

- [LimboAI behavior_tree.cpp](https://github.com/limbonaut/limboai/blob/master/bt/behavior_tree.cpp) — условия, selector/sequence, приоритеты, управляемые задачи.
- [GOAP repo](https://github.com/crashkonijn/GOAP) — цель, эффекты, план действий (не тащить Unity/C# runtime).
- [Convai Narrative Design — официальная документация](https://docs.convai.com/api-docs/convai-playground/character-customization/narrative-design) — секции/цели/decision points/event triggers при свободных разговорах.

**Наша минимальная P1 модель NpcGoal:** goal_id, character_id, objective, motivation/source_origin, priority, preconditions, allowed_action_ids, success/failure predicates, optional deadline. Сначала selector из 2–5 разрешённых действий в важных сценах, НЕ универсальный GOAP. Модуль лишь предлагает action_id; story_core проверяет и коммитит. В CANON нельзя самопроизвольно менять характер и каноническую последовательность; в ALTER_FATE альтернативные мотивы явно отмечены.

**QA:** персонаж не действует после смерти/отсутствия; не использует несуществующий предмет; не сообщает тайну, которой не знает; не расходует свои ресурсы без committed event; решения объяснимы.

## 7. Диалоги, реплики, портреты — Yarn Spinner + Dialogic + Convai

- [Yarn Spinner core](https://github.com/YarnSpinnerTool/YarnSpinner) — последовательность line/option/command; line tags, локализация и условия выбора.
- [Dialogic Visual Timeline Editor](https://github.com/dialogic-godot/dialogic/blob/main/addons/dialogic/Editor/TimelineEditor/VisualEditor/timeline_editor_visual.gd) — UX-ориентир.
- [Dialogic Character Editor](https://github.com/dialogic-godot/dialogic/blob/main/addons/dialogic/Editor/CharacterEditor/character_editor.gd) — UI портретов/состояний.
- [Convai Narrative Design](https://docs.convai.com/api-docs/convai-playground/character-customization/narrative-design) — цель диалога, условия смены темы.

**Уже существует:** [DialogueStage](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/apps/story_reader/lib/scene_dialogue_stage.dart), [RichSceneDialogue](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/bookworld_format/lib/rich_scene_dialogue.dart), подписанные реплики и локальные PNG-портреты. Не переписывать UI ради нового фреймворка.

**Постепенное расширение контракта:** stable line_id/turn_id, speaker_character_id, text, scene/event_id, required_fact_ids, required_presence, source_origin, visual_expression, optional topic_id. Перед выводом каждой реплики проверять identity, knowledge, event/presence. Если проверка не пройдена — безопасный отказ/fallback ДО показа текста, без полсекунды спойлера.

**Две формы общения:** CLASSIC полностью офлайн — заранее созданные и проверенные варианты; AI SAY/LOOK/DO — только после согласия на передачу ограниченного контекста, интерпретация -> разрешённое намерение, изменения через choice-gate/core. Отсутствие ИИ не должно блокировать исходную игру.

**QA:** подмена speaker с тем же display name, секрет до события, пустой разговор, пропуск нескольких реплик, сохранение курсора с учётом ветви, офлайн-рестарт.

## 8. Настоящие RPG-механики — Narrat, но без навязывания D&D

- [Narrat quests](https://github.com/liana-p/narrat-engine/blob/main/docs/features/quests.md) — задания с исходом success/fail/несколько исходов.
- [Narrat skills](https://github.com/liana-p/narrat-engine/blob/main/docs/features/skills.md) — выборочные и пассивные проверки навыков.
- [Narrat inventory](https://github.com/liana-p/narrat-engine/blob/main/docs/features/inventory.md) — предметы и применение.

**Уже существует:** игрок/предметы/характеристики/журнал в story_core и Flutter, использовать существующие эффекты и интерфейс. Ввести над ними сценарные профили, а не пять отдельных игровых движков: LITERARY, ADVENTURE, DETECTIVE, SOCIAL, FANTASY_RPG.

**P0:** реальное владение важными предметами, цель/обязательство и осмысленные решения в первой игре; никакого искусственного меча или навыка из отсутствующего исходника. **P1:** QuestDefinition/QuestOutcome и ограниченные SkillCheck (skill_id, difficulty, mode, success/fail effects). Если случайность — зафиксировать seed/roll в committed evidence, replay обязан дать тот же результат.

**QA:** двойное владение уникальным предметом запрещено; потерянный предмет нельзя использовать; недоступный quest не стартует; «другой финал» нельзя подменить изменением одного косметического флага.


### 8.1 Игровые вкладки — связь Narrat/Quest/Ren'Py с нашей архитектурой

**Принимать вместе с генеральным планом:** [GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md](GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md) (действующие API, поэкранные модели, source proof, v3/vNext, 4 смысловых вида журнала, последовательность UI→choice→event→replay, приватность, тестовая матрица). Исходный [аудит реальных программ и текущего Flutter](GAME_PANELS_REFERENCE_AUDIT_RU_2026-11-07.md).

**Что взять, где подключить и не дублировать:**

| Внешний ориентир | Что переносим **как собственную Dart-реализацию** | Наш файл/слой; что уже есть | Новый код и ограничения |
|---|---|---|---|
| Narrat Skills/Status | Характеристики, только нужные книге навыки и проверки | WorldState.stats, WorldGameView, _WorldInfoSheet | P0 — карточки текущих stat; P1 — SkillDefinition/SkillCheck без искусственного XP |
| Narrat inventory + Quest UI | Item cards/categories и active/completed/failed objectives | WorldState.inventory пока Set<String>, gateway names/descriptions, WorldEvent journal | P0 — read-only item cards; P1 — item owner/quantity + typed quests только с version/capability |
| Quest interactive fiction | Контекстные Use/Give/Inspect и объяснение недоступности | story_runtime_adapter.available choices + gateway.choose | Показывать только разрешённый choice_id; не добавлять действие, которого нет в игре |
| Ren'Py History | История произнесённых реплик по персонажам | SceneDialogueStage уже показывает **локальную историю текущей сцены** | P1/P2 — межсцены только по actually displayed, source-approved turn IDs; Skip≠просмотр |
| Dialogic/AI Dungeon Memory | Карточка известного персонажа, сведения, ссылки на связанные разговоры | NPC character_id и per-actor knowledge/story_core, social ledger read-only | Не выводить тайное знание NPC, будущие главы и неподтверждённое ИИ как player facts |
| RPG Maker Status/Equip | Понятная организация характеристик и возможной экипировки | UI может отобразить stats без RPG-допущений | Экипировка не вводится всем героям без такого правила в BookEvidenceGraph |

**Поток P0:** BookWorld importer → campaign_manager/StoryRuntimeAdapter committed events → WorldLibraryGateway immutable view → три read-only панели «Герой/Предметы/Журнал». UI повышает читабельность, но не создаёт новые игровые эффекты и не расширяет нынешний четырёхчленный .bworld v3. Журнал событий по replay, сведения только player known facts; текущая история диалога остаётся в SceneDialogueStage.

**Поток P1:** источник → item/quest/skill author definitions → строгий versioned gameplay contract (не silent v3 extension) → typed effects story_core → transaction/replay/campaign_manager → secure gateway projection → пользовательские карточки/доступные действия. Приоритет отдавать правдоподобному владению предметами, обещаниям и последствиям, а не интерфейсным заглушкам.

**Практическая проверка:** две реальные книги, получение/использование/потеря предмета, как минимум две отличающиеся концовки, описание/знание/отношение NPC после события и до события, journal replay после Save/Restore, Android + Windows навигация, disabled action не выдаёт world effect, отсутствие спойлеров в истории, старые rich-v3 не ломаются. **Число PR:** один UI-P0 PR, NPC отображение внутри принятого native NPC/social пакета, один последующий сквозной GAME-P1 PR с контрактом и E2E. Не PR на каждое поле.

## 9. Время, события вне сцены — Axiom AI + Project Lunar (позже)

- [Axiom AI chronicler.py](https://github.com/Frosoore/AxiomAI/blob/main/axiom/chronicler.py) — пример мира вне непосредственного хода игрока.
- [Axiom AI rules.py](https://github.com/Frosoore/AxiomAI/blob/main/axiom/rules.py) — правила и ограничения.
- [Project Lunar plot_generator.py](https://github.com/horizonfps/project-lunar/blob/master/backend/app/engines/plot_generator.py).

**P2:** логическое игровое время, не системные часы устройства, явные типизированные world ticks / scheduled events, реакция NPC только при наличии авторских/адаптационных правил. Не запускаем скрытую фоновую симуляцию при закрытом приложении или без права на событие. CANON не разрешает выдумывать ключевые книжные события.

**QA:** одинаковая цепочка событий при одинаковых ходах на Android и Windows независимо от часов/таймзоны; расписания не нарушают присутствие и доступность NPC.

## 10. ИИ и свободные намерения — Axiom AI + AI Town + Convai

- [Axiom AI arbitrator.py](https://github.com/Frosoore/AxiomAI/blob/main/axiom/arbitrator.py) — LLM proposal, проверка state changes, санкционированные и отклонённые эффекты.
- [AI Town conversation.ts](https://github.com/a16z-infra/ai-town/blob/main/convex/agent/conversation.ts) — контекст разговора и untrusted memories.
- [Convai Narrative Design](https://docs.convai.com/api-docs/convai-playground/character-customization/narrative-design) — goals/triggers.
- [Наш текущий FreeTextActionGate](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/apps/story_reader/lib/free_text_action_gate.dart) — уже разрешает ограниченные действия; не путать с готовым свободным AI NPC.

**Поток:** SAY/LOOK/DO -> LLM/парсер предлагает кандидатов intent/choice_id -> core валидирует допустимость -> коммитит событие -> narrator/render отражает только подтверждённое. Никакого SQL/произвольного кода/прямой мутации состояния от LLM.

**Фазы:** P0 только перевод текста в уже доступный choice; P1 детерминированная композиция из allowlisted операций; P2 новая сцена только как review+versioned immutable world extension, отдельные разрешения/лимиты расходов. LLM память — contextual cache, не источник доказанных знаний NPC.

**QA:** prompt injection внутри FB2, false rumors, чужие секреты, 429, timeout, retry/idempotency, offline fallback, privacy/opt-in; фраза «дай мне предмет» не создаёт его из воздуха.

## 11. Пиксели и анимации — Flutter CustomPainter / Flame / AI Town

- [Flame GameWidget source](https://github.com/flame-engine/flame/blob/main/packages/flame/lib/src/game/game_widget/game_widget.dart), [официальная документация](https://docs.flame-engine.org/latest/flame/game_widget.html).
- [AI Town персонажи и анимации](https://github.com/a16z-infra/ai-town/tree/main/data) — идеи слоёв, sprite sheet, лёгкой анимации.
- [Flutter CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) — основной путь P2.
- [Sprite Forge repo](https://github.com/paperhurts/sprite-forge) — только обзор идеи; лицензия и применимость исходников не подтверждены, не копировать код/assets.

**Предлагаемый VisualRecipe:** visual_recipe_id, character_id, appearance_seed, palette/style, scene_layout, positions, props, pose/expression, animation_cues, provenance. Внешний E6 создаёт нейтральные, воспроизводимые инструкции; основное приложение отрисовывает их кодом. Доказанные внешние черты отличать от художественной стилизации. Сначала text-only fallback / CustomPainter, затем при измеренной необходимости Flame; визуальный движок НЕ владеет игровыми событиями.

**QA:** одинаковый appearance по seed, Android memory/FPS, отсутствие внешних обязательных PNG и платного image service, эмоция на экране не меняет отношения в core.

## 12. Встроенный редактор — Twine / Inky / Dialogic / Flutter node graphs

- [Twine passage-map.tsx](https://github.com/klembot/twinejs/blob/develop/src/components/passage/passage-map/passage-map.tsx) — интерфейс карты сцен; рабочая ветка источника develop, **не main**.
- [Ink WritingWithInk.md](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md) — текст+структура сценария, пример редакторской модели.
- [Dialogic timeline_editor_visual.gd](https://github.com/dialogic-godot/dialogic/blob/main/addons/dialogic/Editor/TimelineEditor/VisualEditor/timeline_editor_visual.gd).
- [Flutter node_flow](https://pub.dev/packages/node_flow) и [vyuh_node_flow](https://pub.dev/packages/vyuh_node_flow) — сравнить оба на spike, оставить один (не оба).

**Внутри apps/story_reader, не в core:** 3 согласованные визуализации поверх одних данных: граф книги (events/sources/people), граф игры (scenes/effects/storylets), граф NPC (IDs, relations, knowledge, goals). Общие ссылки по ID. Клик узла должен показать доказательство и проверяемую причину сцены, play-from-here только в тестовой кампании с valid state (не теле-порт в недостижимое состояние).

**P2:** необязательный UX, after end-to-end book-to-game. Не дублировать базу или runtime, не заставлять обычного пользователя вручную заполнять NPC после импорта. Twine GPL code не встраивать.

## 13. Тестирование, QA, поиск причин — NovelToGame + LimboAI + Yarn

- [NovelToGame game QA](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/game-qa/SKILL.md) и [pipeline-contract](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/novel-to-game/references/pipeline-contract.md) — проверять actual launch/render/input/core loop/outcome/restart, а не только успешную сборку.
- [LimboAI](https://github.com/limbonaut/limboai) — отладка дерева решений как ориентир.
- [Yarn SaliencyTests.cs](https://github.com/YarnSpinnerTool/YarnSpinner/blob/main/YarnSpinner.Tests/SaliencyTests.cs) — негативные/позитивные test cases.

**Развивать существующие аудиторы, а не второй:** source provenance, unresolved identities, chronology, full-book coverage, branch-delta, narrative obligations, reachable terminals, inventory consistency, event-scoped knowledge, line-before-render, replay, tamper, exact-head CI, Windows/Android physical E2E.

**Отладочные объяснения по событиям:** «почему NPC отказался» -> проверка конкретного condition и event ID; «почему эта сцена» -> выбранное правило/Storylet; «почему не знает секрет» -> отсутствие learn_fact; «почему финал недоступен» -> воспроизводимый путь/состояние; всё без выдуманной AI-рационализации.

**QA-отчёт:** отдельно structural PASS/FAIL, literary REVIEWED/UNREVIEWED, model E2E PASS/FAIL/NOT_RUN и device E2E PASS/FAIL/NOT_RUN; не смешивать. Два разных реальных FB2 + GLM + Windows/Android не заменять синтетическими демо.

## 14. Версионирование .bworld, совместимость E6 и открытый SDK

**Действующая реальность на main после PR #131:** private rich v3 сохраняет четыре строгих ZIP entries; [Dart importer](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/bookworld_format/lib/private_rich_bookworld.dart) уже проверяет **опциональный actor-scoped NPC knowledge grants** и подписанные knowledge-gated реплики по утверждённому контракту #131. Но он **не** поддерживает полный gameplay catalogue item quantity/owner, quests, skill checks, visuals/storylets и произвольные неутверждённые social capabilities. PR #132 — draft, не объявлять новым принятым v3 API. Не запихивать новый формат «как есть» в v3. Нужен утверждённый vNext с **Python writer/verifier + Dart importer** и parity только когда новые данные действительно требуются после P0. Старые v1/v2/v3 остаются поддержанными по явному контракту.

**Возможные логические разделы vNext (не список утверждённых ZIP entries):**
manifest/capabilities, scenario/typed effects, characters/actor mapping, source provenance, authored dialogues, social rules, obligations, optional storylets, gameplay profile, presentation/visual recipes, compatibility hashes. Движок должен отвергать неизвестную обязательную capability, а optional fields пропускать только по спецификации.

**E6e:** активная feature/external-rpg-author-e6e-parity-20261107, версия кода генератора 0.3.0a3, точный проверенный SHA bfa4190afec7c0f5e00c70e357898a9660c05450 и author-tests/dart-parity SUCCESS в run #42297819582. Рассинхронизация с **принятым** PR #131 исправлена без отключения contract guard; следующий social PR #132 ещё не принят и потребует отдельного versioned parity-gate. Отдельный установленный ChatGPT-навык пока закреплён на E6d SHA 9849c22d18e2761b49766b0c213b4a3fb3fe053b, обновлять его только после проверенной процедуры bootstrap. Не менять код основного приложения из внешней ветки без разрешения.

**Open-source:** пакетный API без Flutter, CLI standalone, README с простым примером/semver, независимый тестовый клиент, проверка лицензии. Сейчас исходный репозиторий содержит All Rights Reserved; отдельно решить лицензию до open-source публикации и права на сторонние части. Не публиковать чужие тексты книг, переводы, ключи и частные игры.

## 15. Приоритеты и ответственные — без бесконечных микрошагов

| Этап | Приоритет | Результат | Ответственность и приёмка |
| --- | --- | --- | --- |
| A. NPC P0 | СЕЙЧАС | Event-scoped knowledge + направленные отношения, присутствие, typed effects, допуск реплик до рендера | Основное приложение: story_core + BookWorld parity + save/replay + exact-head CI |
| B. Full book -> game | P0 | Единый полный StoryPlan, обоснованные NPC/предметы/обязательства, готовый .bworld без ручных сцен | Native compiler и внешний E6 в отдельных ветках, одна схема/контракт; реальная сказка |
| C. 1.0 gate | P0 | CANON/ALTER_FATE и герой, простой мастер, две реальные книги и GLM, Win/Android/offline restart | Основной чат; закрытие Issue #118 по подтверждённым артефактам |
| C2. Панели UI-P0 | P0 без задержки C | На действующем world view удобные Герой/Предметы/Журнал, delta events и сохранение ReaderChrome; **без новых эффектов/v3** | Один UI PR, общая Flutter+Android+Windows приёмка на реальной книге |
| D. Контекстные реплики | P1 | Line-groups с проверкой знания, priority, once | После законченной книги; не блокер 1.0 |
| E. Storylets + obligations-runtime | P1 | Динамический подбор подготовленных сюжетных эпизодов | Чистый Dart + файл vNext при необходимости; repeat/replay tests |
| F. NPC Goals + RPG profiles | P1 | Цели NPC, quests, skills/skill checks только при необходимости книги | Не отдельный игровой движок; action proposal -> core commit |
| F2. GAME-P1 сквозной | P1 после C | Item ownership/quantity, QuestDefinition/ObjectiveState, optional skills и связанные панели, только при наличии в книге | Один versioned schema + Python/Dart/SQLite/core/Flutter E2E, old v3 сохраняется |
| G. Scene/decision debugger | P1 | Объяснимое условие/событие/исход, контрпример | Расширение существующих аудиторских отчётов |
| H. Pixel + animation + editor + AI freeform | P2 | Кодовые визуальные рецепты, node editor, AI extras | Flutter/adapter, опционально; после игровых E2E |
| I. Export reusable Engine | Позже | Открытый SDK, документация, примеры, лицензия | Только после стабилизации API и 1.0 |

**Правило работы:** один крупный законченный функциональный результат -> Dart/Python/SQLite/schema/Flutter tests -> stand-alone Dart example -> Windows/Android CI -> merge -> post-merge exact SHA -> обновление статуса. Не создавать PR для каждого нового поля; не разрабатывать P1 как замену закрытию P0.

**Порядок новому чату (актуализация):** PR #130 и #131 уже приняты; сначала довести текущий native NPC/social draft #132 по существующему основному плану и завершить полноценную игру по двум реальным книгам. UI-P0 можно принять без изменения контракта, но P1 GAME-P1, Storylets/GOAP/визуал не должны тормозить P0. Каждую новую capability проверять отдельным согласованным writer/importer/replay gate.

## 16. Реестр прямых ссылок и права на использование

Каждая GitHub-ссылка ниже проверена существованием реального файла в соответствующей ветке источника на 2026-11-07. Для конкретной реализации переходить по ссылке на файл; при расхождении документации проверять source и tests.

| Источник | Действительная ветка | Конкретный вход | Лицензия (по GitHub API) | Допустимая стратегия |
| --- | --- | --- | --- | --- |
| Yarn Spinner | main | [Saliency strategy](https://github.com/YarnSpinnerTool/YarnSpinner/blob/main/YarnSpinner/Saliency/BestLeastRecentlyViewedSaliencyStrategy.cs) | MIT | Идея алгоритма, собственная Dart реализация |
| Ink | master | [WritingWithInk.md](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md) | MIT | Структура ветвлений, без второго runtime |
| Narrat | main | [Quests](https://github.com/liana-p/narrat-engine/blob/main/docs/features/quests.md) | MIT | Профили игрового процесса |
| Project Lunar | master | [NPC Mind](https://github.com/horizonfps/project-lunar/blob/master/backend/app/engines/npc_mind_engine.py) | Лицензия не подтверждена | Только идеи, код не копировать |
| Axiom AI | main | [Arbitrator](https://github.com/Frosoore/AxiomAI/blob/main/axiom/arbitrator.py) | AGPL-3.0 | Идеи без копирования AGPL-кода |
| NovelToGame | main | [Novel analysis](https://github.com/zenstory-ai/novel-to-game/blob/main/skills/novel-game-analyze/SKILL.md) | MIT | Рабочий процесс, адаптация к существующим схемам |
| AI Town | main | [Agent memory](https://github.com/a16z-infra/ai-town/blob/main/convex/agent/memory.ts) | MIT | Retrieval/importance, без TS/Convex зависимости |
| LimboAI | master | [Behavior tree](https://github.com/limbonaut/limboai/blob/master/bt/behavior_tree.cpp) | MIT | Минимальный selector в Dart |
| GOAP | master | [README](https://github.com/crashkonijn/GOAP/blob/master/README.md) | Apache-2.0 | Планирование действий только если нужно |
| Dialogic | main | [Visual timeline editor](https://github.com/dialogic-godot/dialogic/blob/main/addons/dialogic/Editor/TimelineEditor/VisualEditor/timeline_editor_visual.gd) | MIT | UX-ориентир, без Godot-плагина |
| Twine | develop | [Passage map](https://github.com/klembot/twinejs/blob/develop/src/components/passage/passage-map/passage-map.tsx) | GPL-3.0 | Только идея, код не копировать |
| Flame | main | [GameWidget](https://github.com/flame-engine/flame/blob/main/packages/flame/lib/src/game/game_widget/game_widget.dart) | MIT | Опциональная Flutter визуализация |
| Convai | официальный docs | [Narrative Design](https://docs.convai.com/api-docs/convai-playground/character-customization/narrative-design) | Коммерческая платформа | Идея целей/триггеров, SDK не нужен |
| Sprite Forge | main | [Репозиторий](https://github.com/paperhurts/sprite-forge) | Не подтверждена | Только обзор, не копировать |

Точные версии и лицензии заново сверить перед **любым** копированием исходного кода или распространением. Предпочтительнее писать собственную Dart-реализацию идей. Названия proposed моделей в этом документе проектные и **не являются утверждённым API**.

## 17. Что передать другому основному чату

«Прочитай [этот единый план интеграции сторонних идей](https://github.com/shonentez-afk/AI-Story-RPG/blob/feature/external-rpg-author-e6e-parity-20261107/tools/rpg_author/ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md) и [подробный план трёх игровых вкладок](https://github.com/shonentez-afk/AI-Story-RPG/blob/feature/external-rpg-author-e6e-parity-20261107/tools/rpg_author/GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md) и сопоставь его с [действующим основным roadmap](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/ROADMAP_AUTOMATIC_RPG_RU_V2_2026-11-05.md) и [1.0 gate](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/PROJECT_COMPLETION_GATE_RU_2026-11-06.md). Воспринимай как приложение по архитектуре и ссылкам, не начинай все P1/P2 сразу. Доведи P0 NPC, сюжет и игру из книги в текущих пакетах. Не изменяй рабочую внешнюю E6e-ветку или установленный E6d skill pin без отдельного согласования и точной parity-проверки. Новые функции должны иметь typed contracts, source provenance, Dart/Python parity, независимый CLI и Win/Android E2E. Веди крупные законченные этапы и реальный статус». 
