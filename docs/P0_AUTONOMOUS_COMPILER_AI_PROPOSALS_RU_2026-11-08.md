# AI Story RPG — автономное авторство: проверяемые предложения ИИ, NPC и сборка v3

Дата: 8 ноября 2026. PR [#133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) остаётся **OPEN / DRAFT**. Новый код принят на ветке коммитами `faf5e5a`, `d2d6a36`, `9bd477a`, исправление analyzer `df592c97599b9d977e4f8aaf5deac913c024533b`. Это **одно связанное развитие существующего PR**, не самостоятельные микро-PR. `main` и отложенный внешний `tools/rpg_author` (E6d) не изменяли.

**Перед новым GUI:** см. обязательный [проект единого пути «книга → RPG»](DESIGN_UNIFIED_BOOK_TO_RPG_PATH_AND_AUTONOMOUS_AUTHORING_RU_2026-11-08.md). Не создавать мастер, дублирующий runtime `story_core`, компилятор, типы NPC и состояния SQLite.

## Подтверждённый код

1. **Независимый анализ и проверка результатов ИИ.** `SourceLockedEventOutline` использует все фрагменты индексированной книги и точные UTF-16 цитаты, отбрасывает чужую редакцию/перестановку/повреждённый Unicode; `StoryProposalValidator` сверяет выбранные события с разрешённым списком и создаёт только `ZaiStoryDilemmaPreview` / `StoryPlan`. **Один валидатор** вызывается из действующего Z.ai-адаптера в Flutter и из CLI. Истинность смысла, знания NPC и CANON этим **не доказаны**.
2. **Нативный книжный компилятор вынесен из приложения.** Теперь исходные `NpcCharacterCard`, `NpcEditorialNotebook`, `NpcKnowledgeRulebook`, bridges, `PrivateClassicScenarioTranslator`, `PrivateAdaptationPreflight`, `MultiSceneDraftWorkbench`, item/knowledge и `native_private_bookworld_compiler` находятся в `packages/story_authoring` (pure Dart). UI-файлы стали `export`, без второй реализации. Три фоновые сборки используют Dart `Isolate.run`, а не Flutter `compute`. Вся ZIP/SQLite/runtime проверка выполняется прежним `bookworld_format` и независимыми импортёрами.
3. **Сценарий из реальных утверждённых контрольных точек.** `PortableReviewedDraftCompiler` проверяет `source_fingerprint`, полный source-evidence checkpoint, semantic catalog, editorial review, `IntermediateStoryBlueprint`, `PrivateAdaptationPreflight` и собирает частный rich-v3. Опциональный NPC пакет повторно проверяет identities, notebook, rulebook, source quote hashes и положительное подтверждение человека; поддерживаются approved social, items, dialogue turns, speaker bindings. Без NPC тот же API работает с одной ролью player. `ReviewedStoryComposer` тоже находится в pure Dart.
4. **CLI (запуск без Flutter/сети):**
   - `inspect-source <book>`
   - `scan-source <book> [--checkpoint <private>]`
   - `review-plan <book> <events.json> <model_reply.json> <plan_review.json>` — только черновик, не playable world
   - `build-draft <book> <reviewed_checkpoints.json> <out.bworld>` — проверенный private rich-v3, без внешней модели
   - `build-reviewed <book> <review.json> <out.bworld>` — совместимый исходный API
   - `verify-world <out.bworld>`
   Точка входа: [packages/story_authoring/bin/author_book.dart](../packages/story_authoring/bin/author_book.dart); [README и поля пакета](../packages/story_authoring/README.md).

## Проверки — только подтверждённое

Точный кодовый SHA `df592c97599b9d977e4f8aaf5deac913c024533b`:
- [M0 #42452212571](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42452212571) **SUCCESS**.
- [Главный CI #42452212594](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42452212594): Python reference и Dart scenario **SUCCESS**, автономные Dart analyze/test + native source-locked output check + независимый Python импорт нового reviewed-editor архива **SUCCESS** (подтверждено по step-status). Полный workflow Flutter/Windows/Android проверять отдельно; в момент фиксации отчёта выполнялись и НЕ названы PASS.
- External RPG author tests на E6d: **FAIL** (до и после кода). Внешний генератор делается отдельно, **не менять его контракт или скрывать проверки**.

## Что осталось до «сам передал книгу → получил полный литературный RPG-мир»

**НЕ завершено:** перенос `multi_act_trial_compiler`, `whole_book_npc_campaign`, role/hero catalog, полного литературного reviewer, prose/writing batches и Z.ai HTTP/consent storage adapters из UI (через независимые порты); модельные предложения для всех актов пока не проходят единую программную цепь от автоматического анализа до final `.bworld`. Нет полного private CANON, стартовых знаний/предметов героя и снятия 48/192 scene/act caps с проверенным масштабированием. Любой нерешённый смысл, причинность, алиас, скрытые знания или неверное владение предметом должен блокировать playable. UI-экран мастера и физический UX ещё не готов; мы сознательно не создаём второй неполный UI до фиксации engine authoring API.

**Следующий цельный пакет:** сделать независимыми многоактовую сборку и герой/NPC authoring, затем добавить interface `AuthoringModelPort` для Z.ai или локальной модели (Cloud BYOK — отдельный адаптер с per-window consent), с bounded checkpoint/resume и source-locked visual/lore review. После этого построить **один** GUI-мастер по заранее записанным 16 шагам и единые экраны RPG. Приёмка: две реальные RU FB2, 0/1/2 NPC, проба масштабирования без 48/192 усечения, cloud 429/offline, Python/Dart parity, Windows/Android, сохранения `.bwsave`, безопасность UI. **Не объявлять готовым раньше.**
