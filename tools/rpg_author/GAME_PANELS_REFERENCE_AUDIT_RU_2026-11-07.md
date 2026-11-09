# Аудит аналогов: «Герой», «Предметы», «Журнал» и связанные RPG-модули
**7 ноября 2026. Статус:** проверка документации/исходников сторонних проектов и read-only аудит нашего `main=9c9bdc142495e536b5d11ca5e61680948e45f8fe`. Это **исследование**, не реализованный код и не поручение менять Flutter-приложение из ветки E6e. Использовать вместе с [планом внешних источников](ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md), [общей спецификацией](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md) и приёмкой 1.0.

## 1. Таблица реально существующих возможностей, не фантазировать «родные вкладки»

| Проект | Герой/состояние | Инвентарь | Журнал/история | Что полезно именно нам |
|---|---|---|---|---|
| **Narrat** (движок narrative RPG) | Skills: level/XP/checks, HUD stats, персонажи/портреты | Встроенный inventory UI, иконки, описания, количество, использование, категории/вкладки | Встроенный quest log, цель/подцель, скрытие/открытие, успех/неудача; achievements отдельно | **Главный образец трёх игровых панелей** и разделения отображения/правил. **Не** отдельный готовый character sheet для любой книги |
| **RPG Maker MZ** | Отдельные Status, Skills и Equip; характеристики героев | Items + оружие, броня, key items, использовать/экипировать | **Не** универсальный встроенный Quest Journal: он зависит от проекта/плагина | Категории предметов, отключение невозможных действий, не добавлять боевую систему всем книгам |
| **Quest 5** (interactive fiction) | Статус/здоровье/деньги — по настройкам конкретной игры | Боковая панель Inventory, предметы/места/объекты, глагольные действия use/give/drop | Journal можно запрограммировать отдельным хранимым объектом, **не** обязательная стандартная вкладка | Контекстные действия и проверяемое владение предметом; история не должна опираться на текстовое предположение |
| **Ren'Py** (VN-движок) | Character UI создаёт автор через screens, нет универсальной RPG-карточки | Пользовательские screens, не стандартный RPG-инвентарь | **Встроенная dialogue history** с именем говорящего и текстом | История реплик — не то же самое, что журнал игровых действий |
| **Dialogic 2** (Godot диалоги) | Character definitions, портреты/варианты, переменные | Нет подтверждённого штатного универсального inventory player tab | Подсистемы `History` и `Glossary`; другие UI по проекту | Связь speaker→character ID, отдельная история диалога и энциклопедия терминов |
| **AI Dungeon** (AI narrative) | Story Cards для персонажей/мест, Plot Essentials, summary; **не** детерминированная sheet RPG | В официальной справке нет гарантированного event-verified стандартного inventory panel | Story Summary, Memory Bank, Story Cards, история; ИИ-память тематическая, не source-of-truth | Контекстная память и «известное об этом NPC», но **не** замена event log/инвентаря |
| **Ink/Inky, Yarn Spinner, Twine** | Сценарная логика/переменные/диалоги, готовая вкладка героя не гарантируется | Задаёт конкретный клиент/автор; нельзя называть встроенной общей вкладкой | Историю/журнал реализует клиент, если нужно | Структура choice/line, условия и UX редактора; не второй runtime |
| **AI Town, Project Lunar** | Память, цели, поведение NPC | Не источник готовой player-facing вкладки инвентаря | NPC conversation memory/summary, не журнал подтверждённых действий героя | Внутренняя архитектура NPC, не копировать интерфейс игровых панелей |
| **The Secret of Darkwoods** (независимая текстовая RPG, иллюстрация) | На одном развороте Character/Skills/Condition | Рядом категории Armor/Book/Consumable/Quest Item | На той же странице Quests | Удачный визуальный **настольный** справочник, но на смартфоне такой плотный макет не копировать |

### Проверенные первичные источники

1. Narrat: [официальный обзор меню](https://narrat.dev/features/), [inventory/categories и действия](https://docs.narrat.dev/features/inventory.html), [quests/objectives и успех/провал](https://docs.narrat.dev/features/quests.html), [skills и XP](https://docs.narrat.dev/features/skills.html), [обсуждение UX инвентаря с иллюстрацией](https://narrat.discourse.group/t/potential-change-to-inventory-ui/69). Точный код: [inventory-store.ts](https://github.com/liana-p/narrat-engine/blob/main/packages/narrat/src/stores/inventory-store.ts), [quest-log.ts](https://github.com/liana-p/narrat-engine/blob/main/packages/narrat/src/stores/quest-log.ts), [skills.ts](https://github.com/liana-p/narrat-engine/blob/main/packages/narrat/src/stores/skills.ts). Inventory state имеет `id, amount`; quest state хранит `hidden|unlocked|completed`, objectives, optional ending; skills — `level,xp`. Скриншот предложения интерфейса в форуме сам по себе не доказывает, что именно этот дизайн выпущен; документированная категория табов подтверждена отдельно.
2. RPG Maker MZ: [официальное руководство меню](https://rpgmakerofficial.com/product/MZ_help-en/01_06.html); [официальный пример мобильного меню](https://rpgmakerofficial.com/product/mz/course/game-play/ui.html).
3. Quest 5: [UI/game panes](https://docs.textadventures.co.uk/quest/ui-game-play.html), [пример создаваемого вручную журнала](https://docs.textadventures.co.uk/quest/keeping_a_journal.html), [начальный инвентарь](https://docs.textadventures.co.uk/quest/guides/starting_inventory.html).
4. Ren'Py: [Dialogue History](https://www.renpy.org/doc/html/history.html), [screens/navigation и добавление Codex](https://www.renpy.org/doc/html/gui.html).
5. Dialogic 2: [подсистемы History/Glossary/Character и Save](https://github.com/dialogic-godot/documentation/blob/main/documentation/classes/class_dialogicgamehandler.md), [официальные релизы](https://github.com/dialogic-godot/dialogic/releases).
6. AI Dungeon: [Plot/Story Cards](https://help.aidungeon.com/understanding-settings), [Memory Bank/Story Summary](https://help.aidungeon.com/faq/the-memory-system), [объединение контекста](https://help.aidungeon.com/faq/what-goes-into-the-context-sent-to-the-ai).
7. Обзор иллюстрированной книги-интерфейса The Secret of Darkwoods: [скриншот на форуме](https://tavernrpg.com/threads/the-secret-of-darkwoods-open-world-illustrated-text-based-rpg-released-on-march-21.252/page-2).

## 2. Что сейчас реально реализовано у нас на main

Прямой аудит:
- [game_panels.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/apps/story_reader/lib/game_panels.dart): `GameQuickBar` — 3 нижние кнопки «Герой», «Предметы», «Журнал», `GameInfoSheet` для старого pilot; не считать тестовый особняк обязательным игровым содержанием.
- [world_play_page.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/apps/story_reader/lib/world_play_page.dart): `WorldPlayPage` для импортированного реального `.bworld`, нижняя панель `GameQuickBar`, компактная модальная `_WorldInfoSheet`. Герой показывает имя, описание, числовые stats, tick, известные факты; Предметы — список `id → name/description`; Журнал — пронумерованные подтверждённые решения и эффекты.
- [world_library_gateway.dart](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/apps/story_reader/lib/world_library_gateway.dart): `WorldGameView` содержит `stats, inventory, knownFacts, journal, names/descriptions`. Journal **не сочиняется ИИ**: `WorldEventView` строится на replay подтверждённых `WorldEvent`, сравниваются state/hash и реальные дельты inventory/stats/knowledge. Подписанные NPC реплики проходят knowledge-guard до UI.
- [story_runtime_adapter](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_runtime_adapter/lib/story_runtime_adapter.dart): факты и replay/events, проверки допустимости. `campaign_manager` — сохранения. Эти контракты должны остаться единственным источником истины.
- Сейчас **не доказаны** штатные игроковые QuestBoard, полноценный предметный `use/equip/transfer`, игровые skill checks/XP, отдельная «История реплик» внутри Journal, player NPC encyclopedia по полным импортированным картам — наличие редакторской NPC карточки само по себе не означает player UI. Не объявлять их реализованными по архитектурному плану.

## 3. Рекомендация: ТРИ постоянных кнопки, вложенные группы только по наличию данных

**Нижняя панель** на Android остаётся `Герой | Предметы | Журнал` (в режиме чтения/полного экрана показывается кратковременно при касании, как в существующем UX). Не добавлять постоянные 4–7 кнопок, иначе кнопки перекроют текст. Windows: эти же панели можно открывать боковыми выдвижными шторками или разделами в окне.

**Герой:**
- Шапка: имя, portrait (только если действительно есть), роль в выбранной книге, актуальная сцена/глава.
- `Обзор`: отображать только реально существующие характеристики, не создавать базовые `HP/XP/сила/уровень` для сказки, где они не используются.
- `Умения`: только если сценарий определил `SkillDefinition` и реальную механику skill check; результаты из `story_core`, seed/roll записывать для replay.
- `Отношения`: только если социальные отношения приняты в авторитетный runtime и отображаются на основании доказанных событий; направленные изменения и NPC ID, без спойлеров/показателей из сырого ИИ текста.
- `Знания`: факты героя можно выводить здесь ссылками, но полную энциклопедию лучше открыть из Журнала.
- `Происхождение` — сворачиваемый раздел только при доказанной привязке книги/адаптации; не показывать внутренние SHA в игровом UI.

**Предметы:**
- `Все` + условные фильтры `Сюжетные / Расходуемые / Снаряжение / Документы` — появятся только когда реальные каталоги сценария поддерживают категории. Не классифицировать произвольно по имени.
- Карточка: название, иконка только при наличии ресурса/процедурной рецептуры, описание, количество (только если введены quantities), текущий владелец, откуда/когда получено, применимость в текущей сцене.
- Действия `Осмотреть`, `Применить`, `Передать`, `Экипировать` только когда runtime явно выдаёт проверенный enabled choice/action. **Никаких локальных UI-mutations** и «кнопок-фантазий».
- Использованные, переданные и потерянные предметы не остаются «в кармане»; история судьбы вещи может быть в журнале. Уникальный предмет одновременно у двух персонажей запрещён.

**Журнал** — одно окно с контекстными разделами, а не три несовместимых лога:
- `События`: хронологические committed choices + изменения предметов, stats, знаний и отношений. Уже есть; улучшить типографику, фильтры и подробную карточку события. Привязывать к `event_id / scene_id / choice_id`, не парсить сюжетный текст.
- `Задачи`: открытые/выполненные/проваленные, цель, подзадачи и связанный NPC/место. Показывать только если введён versioned `quest/obligation` contract и source-locked причинная связка; не делать отдельный фиктивный список «квестов» для линейного рассказа.
- `Сведения`: известные герою персонажи/места/важные факты, без NPC тайного знания и неизведанных глав. Не копировать `AI Dungeon Story Cards` в authoritative state — использовать только подтверждённые source facts/committed learn_fact, а AI summary держать как необязательный контекст.
- `Диалоги`: история **реально показанных** подписанных реплик/выбранных ответов, при обязательном spoiler redaction до записи history. Это не то же самое, что `WorldEvent` для игровых последствий. Показ речи ≠ подтверждённый world effect.
- Если в книге нет quests/contacts/skills, соответствующие разделы **не показывать**, не писать «0 заданий» при отсутствии контракта.

**Связь панелей:** нажал предмет → виден event получения и герой-владелец; нажал изменение stat → видно решение; нажал персонажа/знание → только безопасные уже открытые сведения; открывая выполненный квест → видишь цепочку событий. Всё определяется одной историей committed events, допустимых сценарных данных и их подтверждённых отображений.

## 4. Приоритеты, чтобы не затянуть P0

**P0.1 UI без нового формата:** превратить текстовую `_WorldInfoSheet` в аккуратный rich-list с заголовками и карточками и фильтром `Все / Изменения` для `Journal`; герой использует существующие hero/stats/knownFacts, предметы — существующие itemNames/itemDescriptions, журнал — event deltas. Никаких дополнительных игрового XP, quests, inventory transfers, NPC cards, кнопок Use. Без нового .bworld schema, всё read-only projection. Проверить Android/Windows, accessibility, релиз, сохранения.

**P0.2 после стабилизации NPC-социального пакета:** подключить только принятые per-NPC состояния, которые реально доступны в `WorldGameView` и `story_core`; никакой отдельной конкурирующей памяти. В той же функциональной приёмке social/knowledge/privacy/replay, не отдельный PR на экран.

**P1 только по сценарному контракту:** versioned quests/objectives/obligations + item quantities/categories/ownership/use/transfer + optional skills, narrative portraits. Python writer+Dart importer parity, snapshot/replay, два настоящих FB2 и negative privacy tests. Не ставить искусственные RPG классы, HP, экипировку и случайные боевые броски для каждой книги.

**P2:** богатая экранная энциклопедия, configurable filters, дизайнерские темы и процедурные визуальные элементы, дополнительные достижения; лишь после полного book→game E2E.

**Приёмка одного крупного пакета:** полный demo + по настоящему FB2: получение/потеря предмета, смена характеристик, две альтернативные ветви, NPC-знания до/после событий, спойлеры скрыты, журнал совпадает с SQLite event/replay и после перезапуска, окно не мешает чтению на Android. Готовить один функциональный PR на связанный набор, не отдельные PR по полям/вкладкам.

## 5. Что НЕ брать

- Не переносить UI/Vue/Pinia Narrat, Godot Dialogic, C# RPG Maker, Quest или чужой runtime: только паттерны; хранение событий и правила остаются в нашем Dart story_core.
- Не смешивать **dialogue history**, **narrative event journal**, **quests** и **AI memory bank** в единую неизбирательную ленту.
- Не давать LLM выдавать предметы, статистику, тайное знание NPC и выполненные задания по художественной фразе без committed choice/effect.
- Не копировать большой редактор или классические RPG stats, требующие ручного редактирования FB2; главное обещание остаётся «загрузил книгу → получил готовую игру».
- Не менять `main/apps/packages/tools/bookworld` из E6e-ветки без отдельной явной команды пользователя. Этот документ — передача требований основному чату, не код.
