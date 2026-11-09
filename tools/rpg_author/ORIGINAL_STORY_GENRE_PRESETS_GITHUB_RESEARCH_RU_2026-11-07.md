# AI Story RPG — самостоятельная генерация оригинальных игр по жанру и предпочтениям

**Исследование:** 7 ноября 2026. **Статус:** проверенные GitHub-источники + проектный план, не готовый код. Нормативное дополнение к [генеральному плану](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). Сохранять границу: внешняя ветка E6f работает только с tools/rpg_author, tests/rpg_author и их документацией; native main/apps/packages/BookWorld общий CI — read-only. Текущий основной P0 (полная реальная книга → готовый мир) не задерживать.

## 1. Предлагаемая функция

В будущем стартовый экран создания предлагает **два источника, но один исполняемый RPG-движок**:
- ИЗ КНИГИ: пользовательский FB2/TXT → анализ и проверка по текстовым цитатам → StoryPlan / NPC / gameplay / .bworld.
- ОРИГИНАЛЬНАЯ ИСТОРИЯ: жанр, смешение жанров, обстановка, герой, настроение, объём, сложность и пожелания → сначала сценарный структурный план и внутренний выдуманный канон → source-of-truth review → те же StoryPlan / NPC / gameplay / .bworld.

Важно: «роман» как литературный объём произведения и «любовный роман» как жанр — разные настройки. Возможны романтика/отношения, фэнтези, детектив, научная фантастика, киберпанк, космоопера, триллер, ужасы, приключения, историческая/альтернативная история, бытовая драма, комедия. Выбирать главный жанр + дополнительный, а не строить отдельный код для каждого жанра.

**Конечный пользовательский результат** тот же: полностью законченный game.bworld, автономный Windows/Android CLASSIC, проверяемые характеры/диалоги/факты, не менее двух разных альтернативных достижимых концовок когда генерация открытого сюжета это предусматривает; в будущем общая процедура пиксельных сцен и индивидуального скина. ИИ нужен во время создания (локальный или облачный на выбор и по возможностям), но не обязан вызываться при прохождении.

## 2. Найденные GitHub-аналоги (фактические README и модули)

| Приоритет | Проект, точный путь | Подтверждённый подход | Что взять для своего Python генератора | Ограничение |
| --- | --- | --- | --- | --- |
| **A1, архитектура** | [Goldziher/monomyth](https://github.com/Goldziher/monomyth), [genre profile](https://github.com/Goldziher/monomyth/blob/main/crates/monomyth-genre/src/profile.rs), [procedural passes](https://github.com/Goldziher/monomyth/blob/main/crates/monomyth-gen/src/passes/mod.rs) | Детерминированный branching DAG, source-separated генерация beat/map/cast/items; жанр параметр, художественное заполнение отдельным LLM-проходом, не влияющим на RNG/структуру | Generic StorySpine + GenreProfile + seed; сюжетные факты сначала; текст и стили только потом | MIT, pre-1.0 experimental. Некоторые возможности README отмечены будущими, не считать production |
| **A1, UX предпочтений** | [paulrobello/par-storygen](https://github.com/paulrobello/par-storygen), [wizard](https://github.com/paulrobello/par-storygen/blob/main/src/storygen/screens/wizard.py), [шесть TOML пресетов](https://github.com/paulrobello/par-storygen/tree/main/src/storygen/presets), [noir detective](https://github.com/paulrobello/par-storygen/blob/main/src/storygen/presets/noir_detective.toml) | 8-шаговый мастер: theme/tone/narration/art/length/reader level/characters; шесть готовых жанров, custom presets, история и endings gallery | Маленький мастер + «Случайная история» / «Уточнить» / сохранить набор пожеланий; версии preset и пользователя | MIT; в оригинале сцены создаются при игре с LLM и иллюстрациями, не переносить зависимость на offline gameplay |
| **A1, Story Bible** | [immane/lore-forge](https://github.com/immane/lore-forge), [genre scaffolds](https://github.com/immane/lore-forge/tree/main/templates), [narrative RPG](https://github.com/immane/lore-forge/tree/main/templates/narrative_rpg), [5 agents](https://github.com/immane/lore-forge/tree/main/agents), [7 consistency prompts](https://github.com/immane/lore-forge/tree/main/prompts) | Structured interview → world rules → characters psychology → timeline/dependencies → dialogue → consistency review. Шаблоны narrative RPG, visual novel, interactive fiction | Минимальный CreativeBrief и версионированный OriginalStoryBible: биографии, цели, отношения, места, хронология, главы, финалы; отдельный аудитор | MIT, авторский workflow/scaffold, не готовый автоматически работающий игровой runtime |
| **A2, проверка приключения** | [jschm42/taleweaver](https://github.com/jschm42/taleweaver), [blueprint validator](https://github.com/jschm42/taleweaver/tree/main/backend/engine/blueprint), [rules](https://github.com/jschm42/taleweaver/tree/main/backend/engine/rules), [ASSETS](https://github.com/jschm42/taleweaver/blob/main/ASSETS.md) | World Generator, editor scenes/NPC/items/quests/map/containers; graph QA и semantic review; местами пользовательские Python-scripts в игре | Отдельный construction audit графа, предметных препятствий и целей; **не** разрешать Python code, произвольные scripts или внешние assets в нашем .bworld | Код MIT, **bundled adventure blueprints CC BY-NC 4.0**, art/audio с отдельными условиями; для коммерческого экспорта не копировать готовые приключения |
| **A2, quest builder** | [the-tale/questgen](https://github.com/the-tale/questgen), [quests](https://github.com/the-tale/questgen/tree/master/questgen/quests), [predicates](https://github.com/the-tale/questgen/blob/master/questgen/facts.py), [restrictions](https://github.com/the-tale/questgen/blob/master/questgen/restrictions.py) | Нелинейные вложенные квесты с начальными и несколькими терминальными узлами, constraints, world facts и rollback при несостоятельном графе | Шаблоны конфликтов/обязательств, требования предметов, проверка отрицательных причинных путей, ретраи генерации при нежизнеспособном графе | BSD-3-Clause, библиотека не является автоматическим автором текста |
| **A2, планировщик** | [umbertocicciaa/QuestMasterAI](https://github.com/umbertocicciaa/QuestMasterAI), [agents](https://github.com/umbertocicciaa/QuestMasterAI/tree/main/src/questmaster/agents) | Story/lore → PDDL domain/problem → проверка разрешимости Fast Downward → reflection/repair → генерация интерактивного фронтенда | На будущий этап — независимый solvability checker сложных цепей «получи ключ → открой дверь» и объяснимые контрпримеры. Начать с нашего собственного bounded state search | MIT, ранняя экспериментальная реализация, не зависеть от LLM-generated UI |
| **A2, настройки мира** | [jerseycheese/Narraitor](https://github.com/jerseycheese/Narraitor) | Пользователь создаёт правила/характеристики мира и героя, выбирает действие, использует skills, inventory, journal, endings, private browser saves | Мир как данные, выдуманные жанровые правила не форсируют D&D на драматический роман; отдельные статистики только по жанру | MIT; по README генерация каждого игрового хода требует модель/ключ — наш offline-first путь должен отличаться |
| **B1, авторское направление** | [horizonfps/project-lunar](https://github.com/horizonfps/project-lunar), [scenario setup](https://github.com/horizonfps/project-lunar/blob/master/README.md) | Setup Wizard вопросов автора, переменные подстановки и сюжетный cold-open с памятью; genre-neutral narrative engine | Не заставлять пользователя писать длинный промпт: несколько осмысленных вопросов → сюжетные ограничения; хранить ответы в creative brief | В README заявлен MIT, **LICENSE в корне отсутствует, metadata license пустая**; брать только идеи до разрешения условий. LLM во время игры |
| **B1, тестовый генератор** | [microsoft/TextWorld](https://github.com/microsoft/TextWorld), [CLI tw-make](https://github.com/microsoft/TextWorld/blob/main/README.md) | Генерация текстовых заданий по world-size, objects, quest-length, seed; Gym-like environment для проверки, достижим ли финиш | Автоматическая **проверка результата** при разных жанрах, героях, seed, оценка тупиков и лишних вещей | Ядро TextWorld на Python и внешних инструментах; не подключать в Dart runtime |

**Проверка репозиториев 07.11.2026:** GitHub metadata (названия, ветки, licences, archived, README), корневые папки и конкретные файлы выше. Это в основном небольшие/экспериментальные проекты, **не** сертификат готовности и не гарантия высокого художественного качества. Для внедрения любого чужого кода требуется точный file-level LICENSE/NOTICE и анализ зависимостей; алгоритмические идеи можно воссоздать самостоятельно.

## 3. UX: минимальный мастер без технических настроек

Вход: «Создать игру» → «Из книги» / «Придумать свою историю». Если выбрано второе:
1. **Жанр/смесь жанров:** романтика, детектив, фэнтези, НФ, ужасы, приключения, историческая драма, комедия; выбрать до двух; пользовательские пожелания свободным текстом опциональны.
2. **Главный герой и обстановка:** пол/возраст/имя — только если пользователь хочет, роль (сыщик, студент, маг, путешественник, журналист и т.д.), эпоха/город/мифический мир, запреты тем.
3. **Атмосфера и ставки:** лёгкая/мрачная/загадочная/героическая; уровень романтической линии, насилия и сложных решений, читательская возрастная категория. «Роман» различать как формат длинной прозы и как любовный жанр.
4. **Продолжительность и геймплей:** короткая история (30–60 мин), средняя (несколько эпизодов), длинная многоглавая; NARRATIVE (реальный уже существующий базис), позже HYBRID/EXPLORE_2D; напряжение/сложность и разветвлённость.
5. **Предпросмотр концепции:** краткая аннотация, несколько главных персонажей, сюжетный конфликт, ожидаемое число концовок; «Создать», «Другой вариант», «Уточнить». Ни обязательных карточек NPC, ни детального редактора, ни вопросов после генерации.

**Пример входного пожелания:** «Детектив + научная фантастика, город-станция на спутнике, героиня — инженер, напряжённая атмосфера, 3 часа, сложная загадка и несколько подозреваемых; без боёв».

**Реальный смысл:** генератор сначала выбирает **единую скрытую правду** — кто что сделал, почему, куда переместил важный предмет, что знают свидетели — затем создаёт расследуемые подсказки и две различные достижимые концовки. Если генерация просто напишет «три подозреваемых» и 20 абзацев, это **не игра**.

## 4. Как делать оригинальные истории без переписывания ядра

    UserCreativeBrief + GenreProfile + preset_version + seed
                         |
                         v
       OriginalWorldBible + Cast + Location/Fact/Item graphs
                         |
                         v
        PlotPlanner: causality, conflicts, branches, endings
                         |
                         v
       LockedGeneratedCanon (validated original-facts source)
                         |
                         v
            Shared StoryPlan / rich enrichment
                         |
                         v
       NPC social memory, conditions, item ownership,
           dialogue review + mechanical reachability
                         |
                         v
             Versioned writer + Dart importer
                         |
                         v
               SAME game.bworld -> story_core
                          |
                          v
                 Offline Windows/Android

**Новый адаптер источника нужен; новый игровой движок — нет.** После этапа построения источника обе ветви используют общий StoryPlan, NPC IDs, rules, replay, сохранение и presentation. Независимый compiler producer обязан производить весь литературный и структурный контент **до** установки игры; игрок не обязан каждый ход обращаться к модели.

**Самая важная граница контракта:** текущий StoryBlueprint и rich-v3 private-adaptation привязаны к фактическому source_fingerprint и rights_status=private_adaptation (либо original_demo без книги). **Запрещено выдавать новую, полностью выдуманную генерацию за «прочитанную книгу», создавать фиктивные SOURCE_PASSAGE или молча подменять native rights_status.** Для нового производственного пути требуется явный контракт origin_kind=original_generated, отдельные CreativeBrief SHA / OriginalWorldBible SHA, evidence_kind USER_BRIEF / GENERATED_CANON / REVIEWED_GENERATED_CANON, авторский origin marker, строго валидируемый native Python writer и Dart importer. Возможна совместимая будущая capability внутри согласованного BookWorld, но нельзя заранее утверждать, что текущий strict 4-entry v3 уже принимает такое поле. Требуется cross-language parity и negative tests.

**Проверяемая оригинальность:** сгенерированная история не обязана опираться на литературный оригинал, но её **внутренний канон обязателен**. Факт в StoryBible должен быть неизменным после утверждения, а NPC получают новое знание только через committed WorldEvent. Редактирование creative brief, seed или значимых facts означает новую ревизию и переоценку сюжетных paths. LLM не создаёт игровые предметы/факты во время обхода; он может заполнить текст только в пределах объявленных ролей и проверяемых событий.

**Термин seed:** seed делает воспроизводимой процедурную структуру, выбор шаблонов и future pixel scenes; **не гарантирует одинаковый ответ внешней LLM**. Чтобы получить побайтово одинаковую готовую игру, после заполнения необходимо фиксировать утверждённый StoryPlan, редакцию промптов/модели, body text hashes и генерационный lock. Reroll = новая редакция проекта без случайной подмены уже установленной игры.

## 5. Шаблоны должны определять причинность, а не только палитру

| Шаблон жанра | Центральные механики/ограничения | Что проверять |
| --- | --- | --- |
| Романтика/драма | Мотивация и отношения, конфликт целей, границы и согласие | Реальные разные ответвления отношений, не только разные комплименты |
| Детектив | Заранее определённое преступление/тайна, улики, свидетели, подозреваемые, дедукция | Истинное решение достижимо, нет обязательной улики после замка, NPC не знают будущее |
| Фэнтези | Магия с ограничениями, фракции, цели, артефакты, обещания | Способности и предметы не появляются из воздуха, нельзя нарушить правило магии |
| Научная фантастика | Технология, причинные ограничения, ресурсы, риски, этика | Последствия технологии/знаний/предметов согласованы |
| Ужасы/триллер | Ограниченная информация, напряжение, выбор риска и безопасности | Нет непроходимой ловушки, границы контента соблюдены |
| Приключения | Поиски, путешествия, предметы, обязательства, сторонние задачи | Проверены доступность маршрутов и событий; карта позже после Flame |
| Комедия/бытовая драма | Общение, репутация, ошибки и восстановление доверия | Юмор не отменяет фактические последствия или границы героя |
| Историческая или альтернативная история | Отдельные verified historical facts и придуманные игровые события | Нельзя выдавать выдуманные события за реальные без отдельной проверки источников |

**Не принуждать каждую историю к бою/HP/XP и не использовать «злодей напал» для закрытия каждого акта.** Настройки жанра — конфигурация моделей мира и сюжетных рисков, а не простой шаблон prompt «напиши фэнтези». Поддерживать комбинации жанров, но объединять только совместимые механики; жанры должны контролировать разнообразие сюжетных структур, а не стирать причинность.

## 6. QA: что значит «игра создана»

- Содержательный: мир и герои имеют цели и ограничения, сюжет отличается от другого seed и не является перестановкой слов; мотивы/реплики согласованы со StoryBible, две разные концовки осуществимы, собственные шаблоны не вынуждают пользователя вручную чинить сюжет.
- Механический: проверка всех NPC/предметов/флагов/знаний, dead/absent, преждевременных секретов; DFS/BFS по разрешённым состояниям и пути до концовок. Отрицательные пути подтверждают отсутствие дубликата предмета и необратимых softlocks.
- Тестирование разнообразия: по 10+ seeds на жанр/совместимые смеси (после прототипа), zero unsupported rule ops, все сцены/финалы проверяемы, все state changes only typed core.
- Контрактный: generated-origin без SOURCE_PASSAGE книжного происхождения, согласованный native importer, refusal upon unknown field, 4-entry v3 не менять молча, portable .bwsave и SQLite replay не ухудшены, real Android/Windows gameplay.
- Политика публикации: самостоятельные вымышленные истории не дают автоматически универсальных прав на каждую AI-формулировку/сюжет в любой стране. Сохранять происхождение модели и проверять условия провайдера, совпадения с узнаваемыми защищёнными произведениями/персонажами и права на чужой текст. На Яндекс Играх экспортировать только предварительно подготовленную игру, без online AI.

## 7. Согласование с текущим планом

**Сейчас:** P0 закончить полноценную литературную RPG из одной реальной книги и второй независимый E2E, Windows/Android. PR #133 ещё DRAFT. **Не менять current E6f code pin, не объявлять готовый original-origin импортер.**

**После P0 (P1-ORIGINAL):** один новый функциональный пакет в tools/rpg_author: CreativeBrief + GenreProfile + presets registry + StoryBible + PlotPlanner + game mechanical critic; общий StoryPlan/review pipeline. На первом шаге — синтетический оригинальный проект **без ложного native package claim**. Затем отдельная согласованная версия generated-origin вместе с основным native writer/importer/StoryCore и Dart parity, только по явному разрешению родного чата. Объединить related changes, не создавать микропиары по жанру или полю.

**После готового генератора:** общего VisualStyleDirector достаточно, чтобы для фантастики/детектива/романтики выдавать и тематический процедурный пиксельный skin, слайд-сцены и later Flame top-down. Web standalone/Yandex для **готовых и разрешённых к публикации** оригинальных игр — отдельный future exporter, без создания в браузере.

**Отдельная продуктовая ценность:** Book-to-Game Author становится **Story-to-Game Author** — создаёт игры как из существующего текста, так и из нового концепта. Основной Dart сюжетный движок/сохранения остаются автономными.

**Следующее действие:** по окончании P0 сделать P1-ORIGINAL minimal proof: 3 пресета (романтика, детектив, фэнтези), по 3 seeds, два отличающихся конца, подтверждённые NPC item/knowledge rules, фиксация StoryBible и отказ при невозможном сценарии. Не добавлять пробный generated-original в текущий BookWorld, пока не согласована native writer/importer схема.
