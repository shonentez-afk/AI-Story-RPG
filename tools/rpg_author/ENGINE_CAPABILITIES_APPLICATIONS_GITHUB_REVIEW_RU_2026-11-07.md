# AI Story RPG — возможности движка, дорожная карта и применимость

**Аудит:** 7 ноября 2026 года. Это обзор, **не реализация новых модулей**.

**Проверенная исходная основа:** [main 81fb75b](https://github.com/shonentez-afk/AI-Story-RPG/commit/81fb75b77f11b8f82cafa1e7604afa9fe9bbb678), принят PR #132, [общий CI #42333580182 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42333580182). Внешний E6f 0.3.0a4 на [2d6b94e](https://github.com/shonentez-afk/AI-Story-RPG/commit/2d6b94e001d7e049af765ebb1ef7469b6b30a8bd) прошёл [author-tests и Dart parity #42341605734](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341605734). [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) о полной книге/выборе роли ещё OPEN DRAFT, не принят. На main отдельный старый E6d author workflow был красным после обновления контрактов; E6f согласован в собственной ветке. Встроенный навык ChatGPT пока pinned к старому E6d, не обновлён автоматически.

## 1. Система как пять уровней

1. **Авторский генератор / компилятор:** прочитать FB2/TXT по фрагментам, собрать source-anchored события, персонажей и StoryPlan, проверить литературную причинность, сформировать enrichment/согласованные знания NPC, собрать и проверить приватный игровой архив. Полностью автономная адаптация целой реальной книги пока не доказана.
2. **Навигация:** используемый сторонний pure-Dart [story_engine](https://github.com/ErikSchultheiss/story_engine), версия 0.1.0-alpha.1, отвечает за сценарные переходы.
3. **Наш story_core:** авторитетный мир WorldState, typed rules, WorldEvent и его replay, NPC social ledger. story_runtime_adapter координирует навигацию и состояние, не давая разойтись двум независимым действиям.
4. **Сохранения/формат:** строгий Blueprint DSL, private rich BookWorld .bworld format_version=3 с ровно четырьмя ZIP-частями, отдельные SQLite кампании и портируемый .bwsave v2.
5. **Клиент:** Flutter Windows/Android, книжная читалка, сцены/выборы, подписанные диалоги, герой/предметы/журнал. Web и Flame пока проектируются.

Исходники: [story_core/engine.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_core/lib/src/engine.dart), [blueprint.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_core/lib/src/blueprint.dart), [npc_social_ledger.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_core/lib/src/npc_social_ledger.dart), [story_runtime_adapter.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_runtime_adapter/lib/story_runtime_adapter.dart), [campaign_manager.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/campaign_manager/lib/campaign_manager.dart), [world_library_gateway.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/apps/story_reader/lib/world_library_gateway.dart).

## 2. Реализованные свойства и честные границы

| Свойство | В main реально есть | Чего пока нет |
| --- | --- | --- |
| Детерминированные сцены/развилки | Условия по наличию предмета, флагу, стату, знанию NPC, времени; корректная достижимость | Нет полной адаптации любого источника «один файл→готово» |
| Typed world effects | grant/consume item, stat_delta, set_flag, learn_fact per actor, advance_time | Нет общего quest/skill/stackable equipment-контракта |
| Мир и события | state ревизия, tick, факты, предметы, флаги, hash-linked event chain, expectedRevision, actionId anti-duplicate, точный replay | Хэш не равен цифровой авторской подписи или доказательству литературного канона |
| NPC социальная логика | witness present/reported, memory, directed trust/relationships, choice gates, item custody/transfer, life present/absent/dead; native social v1–v5 | Нет самостоятельных планирующих NPC-агентов с открытым LLM |
| Представление | SceneDialogueStage, имена/реплики/портреты, игровые три вкладки, реальный SQLite журнал | Полный интерфейс quests/skills, межсценовая dialogue history, процедурный skin |
| Формат и сохранение | private rich-v3, source fingerprint/provenance, SQLite и portables | Web storage/Yandex cloud и автоматическая публикация пока только план |
| Внешний автор E6f | source SHA, exact review привязки, команда build/verify/finalize, Dart parity с NPC v5 на синтетике | Реальные две полные книги, автоматизированная безошибочная литературная редактура, device E2E не подтверждены |

**Важное:** текущий StoryBlueprint перечисляет возможные роли PROTAGONIST, CUSTOM, BOOK_CHARACTER, режимы CANON/ALTER_FATE/FREE_WORLD и CLASSIC/HYBRID/AI_FREEFORM, но действующий private runtime пропускает только PROTAGONIST + ALTER_FATE + CLASSIC. Объявленные в JSON значения **не являются автоматически готовыми пользовательскими режимами**. Это открытая задача draft PR #133.

## 3. Для чего применим движок

| Сфера | Пример продукта | Возможность без смены core | Что нужно добавить |
| --- | --- | --- | --- |
| Литературные игры | Интерактивная книга, RPG-сказка, литературный квест | Сцены, решения, последствия, предметы, NPC, сейвы | Автоматический full-book author + реальная литературная приёмка |
| Детективы | Осмотр улик, опрос NPC, открытие сведений по доказательствам | Факты per actor + inventory + choice gates | Доска улик и удобный game UI |
| Визуальные новеллы | Реплики, портреты, сюжетные развилки | SceneDialogueStage, story engine, save | Visual/audio asset renderer, межсценовый history |
| Игры для обучения | Ошибки и последствия в ситуационных кейсах | Детерминированные branching outcomes | Rubric, scoring, LMS/SCORM/xAPI и экспертный авторский review |
| Тренажёр решений | Производственный инструктаж, диалоги с клиентом, процедурная диагностика | Preconditions, flags, facts, event log | Специальный контент/интерфейс, подтверждение экспертами; не управлять оборудованием напрямую |
| Музей/экскурсия | Исторический персонаж рассказывает только уже открытые факты | NPC knowledge/scene conditions | Геолокация/QR, редактор, лицензии |
| Исследование AI агентов | Проверить, соблюдает ли агент предметные условия, ведёт ли память/знания | Воспроизводимый мир, отклонённые действия, replay | Headless API/Gym-подобный интерфейс и автоматизированные метрики |
| Пиксельные приключения | Ходить по локации, находить предметы, разговаривать | Общие сюжетные факты/предметы/NPC уже могут обслуживать такой клиент | Flame, процедурные карты, collision/pathfinding, spatial-save |
| Web/Яндекс Игры | Отдельный готовый релиз по одной истории | Детерминированный game data | Плеер Flutter Web, browser save/SDK, права, moderation; никаких интерактивных AI запросов на Яндекс |

## 4. GitHub-аналоги и конкретные идеи

- [ErikSchultheiss/story_engine](https://github.com/ErikSchultheiss/story_engine): **уже выбран и используется** для сценарной навигации; наша собственная часть — состояние, социальные правила, ZIP/provenance и SQLite adapter. BSD-3-Clause.
- [inkle/ink](https://github.com/inkle/ink): зрелые сценарии с переменными/ветвями. Идеи авторского сценарного представления; MIT, не переносить отдельный runtime.
- [YarnSpinnerTool/YarnSpinner](https://github.com/YarnSpinnerTool/YarnSpinner): диалоговые графы, conditions/variables, «once» и storylets, локализация, тест реплик. Идеи graph debugger и runtime topic gating; MIT.
- [liana-p/narrat-engine](https://github.com/liana-p/narrat-engine): полноценный UI Narrat Inventory/Skills/Quests/Achievements, checks/роли. Доказанная потребность в RPG UI; MIT. У нас меньше готовых RPG механик.
- [microsoft/TextWorld](https://github.com/microsoft/TextWorld): генератор комнат/предметов и многошаговых solvable quests, RL sandbox. Идеи автоматического puzzle/quest QA и headless агентных испытаний.
- [h5p/h5p-branching-scenario](https://github.com/h5p/h5p-branching-scenario): неигровые образовательные разветвлённые кейсы, scoring/feedback. Идея применения нашего engine в обучении, но scoring/LMS ещё не реализованы.
- [a16z-infra/ai-town](https://github.com/a16z-infra/ai-town): социальная симуляция и автономные NPC. В будущем GOAP/LLM proposal с верификацией всех world effects нашим engine; MIT.
- [RSamaium/RPG-JS](https://github.com/RSamaium/RPG-JS): 2D top-down, карты, NPC, events, shops, combat и multiplayer. Ориентир для EXPLORE_2D, но не переносить TypeScript runtime; MIT.
- [flame-engine/flame](https://github.com/flame-engine/flame): Dart/Flutter 2D World/Camera/Joystick/Collision/GameWidget. Будущий пространственный renderer, не новый сценарный core.
- [klembot/twinejs](https://github.com/klembot/twinejs): редактор узлов и нелинейных историй, полезные UX-паттерны; GPL-3.0 для кода — не копировать напрямую в закрытые/иные проекты без анализа совместимости.

**Неутверждённое сходство — не доказательство оригинальности:** у большинства конкурентов есть ветвления, переменные и сцены; у нас интересна именно **связка source-to-game + actor-specific knowledge + committed replay + приватная офлайн RPG**. Но полного публичного сравнительного benchmark пока нет.

## 5. Будущие пакеты и ограничение объёма

**P0:** закрыть реализацию полной книги через PR #133 и внешний автор: настоящие русские FB2, все значимые события/персонажи, честные CANON/ALTER_FATE, реальный выбор героя, правильные причинные связи и концовки, GLM+offline классический режим, импорт и настоящее Android/Windows прохождение. Ни красивые пиксели, ни Web не являются необходимым условием этого этапа.

**P1:** полноценный QuestDefinition/ObjectiveState, обязательства, optional skills, richer Hero/Items/Journal, безопасный codex NPC, история диалогов, storylets, проверяемые цели персонажей. Существующий NPC social v5 и item custody не дублировать, а расширять только типизированными capabilities.

**P2:** общий программный PixelSceneRenderer + один книжный StyleBible/UI skin, процедурные окна, иконки и пиксельные сцены без AI PNG; текст — нативный масштабируемый Flutter. Отдельно optional Flame для top-down ходьбы и интерактивных карт, проверка достижимости, синхронизация с story_core.

**P2-Web:** standalone HTML5 только готовой игры для Яндекс Игр и generic плеер готовых .bworld на своём сайте, без генератора книг в браузере. Встраиваемая игра не требует ИИ; отдельно rights gate на исходные тексты и перевод.

**P3+ исследование:** свободные LLM-NPC через proposal+validation (без права ИИ напрямую менять WorldState), GOAP/планирование NPC, локальные/облачные LLM, открытый Dart SDK, оценки обучающих ситуаций, локационные сценарио-проекты, аудио/переводы. Multiplayer, 3D и action-combat — самостоятельные дорогие ветви, не заявлять текущими возможностями.

## 6. Возможные самостоятельные продукты

- **AI Story RPG Reader**: клиент Windows/Android, где открывают готовые игры и книги.
- **Book-to-Game Author**: генератор, выпускающий source-bound .bworld; E6f проверен на синтетике, реальные полные книги ещё gate.
- **Narrative World SDK**: future библиотека для других Dart приложений, после стабилизации API, семантики лицензии и docs.
- **Serious Games Authoring**: future обучающие сценарии и кейс-тренажёры с rubric/scoring и отчётами.
- **Standalone Story Publisher**: future экспорт отдельных готовых игр на Web/Яндекс.
- **Procedural 2D Adventure Studio**: future «сценарий → локации → проходимая 2D игра».

**Главный принцип:** один источник авторитетного world state и events, разные виды контента, интерфейсов и дистрибуции. Не объявлять реализацией документ, синтетическую parity, ссылку на сторонний GitHub-проект или декларацию будущей capability. SHA защищает историю от несогласованного replay, но сам не удостоверяет художественный канон или право публикации.

**Граница:** этот текст добавлен только в tools/rpg_author внешней ветки E6f. Основная программа и native CI не изменены.
