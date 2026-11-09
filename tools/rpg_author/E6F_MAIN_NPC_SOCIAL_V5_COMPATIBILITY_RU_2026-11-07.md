# E6f — проверенная совместимость внешнего RPG-генератора с NPC social v5

**Дата:** 7 ноября 2026. **Рабочая ветка:** [E6f](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6f-npc-social-v5-20261107).

**Исходная основная программа:** [main 81fb75b77f11b8f82cafa1e7604afa9fe9bbb678](https://github.com/shonentez-afk/AI-Story-RPG/commit/81fb75b77f11b8f82cafa1e7604afa9fe9bbb678), PR #132 **MERGED**. **Проверенный исполняемый код E6f:** [2d6b94e001d7e049af765ebb1ef7469b6b30a8bd](https://github.com/shonentez-afk/AI-Story-RPG/commit/2d6b94e001d7e049af765ebb1ef7469b6b30a8bd), версия **0.3.0a4**. [GitHub Actions #42341605734](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341605734) — **SUCCESS**: author-tests SUCCESS и dart-parity SUCCESS на том же SHA. После него только коммиты документации [skip ci], они не являются новыми проверенными исполняемыми SHA.

## 1. Как изменился контракт main

В принятом PR #132 добавлены opt-in версии внутреннего NPC social расширения — при прежнем **BookWorld format_version=3** и тех же четырёх ZIP members:

- ai_story_npc_social_witness_v1: подтверждённые свидетели и память;
- ai_story_npc_social_witness_v2: условия выбора по памяти/отношениям NPC;
- ai_story_npc_social_witness_v3: проверенная передача предметов NPC и владение;
- ai_story_npc_social_witness_v4: source-backed первое получение и выдача предметов;
- ai_story_npc_social_witness_v5: подтверждённые жизненные переходы present/absent/dead. Смерть необратима; отсутствующий/погибший NPC не может участвовать в требующих присутствия действиях и репликах.

Сохранились actor-scoped NPC knowledge grants (ai_story_npc_knowledge_grants_v1), подписанные scene_dialogues и scene_dialogue_knowledge, проверка по событиям/сохранению. Это **НЕ новая версия .bworld v5**. Старые player-only миры и ранее поддержанные версии NPC должны открываться.

Проверенные входы main: [Python rich writer](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/tools/bookworld/private_rich_bookworld.py), [Dart NPC social contract](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/bookworld_format/lib/npc_social_contract.dart), [Dart StoryWorld](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_core/lib/src/engine.dart), [NpcSocialLedger](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/story_core/lib/src/npc_social_ledger.dart), [SQLite campaign_manager](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/packages/campaign_manager/lib/campaign_manager.dart) и [WorldLibraryGateway](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/apps/story_reader/lib/world_library_gateway.dart).

## 2. Что добавлено во внешнем генераторе

**npc_review.py:** проверяемый по исходной книге, StoryPlan и enrichment приватный обзор. Требует source_fingerprint, точные sha256 StoryPlan/enrichment, постоянные отсортированные character_id (npc_ + 32 строчных hex), согласие автора на частную игровую адаптацию, исходные цитаты и корректные записи native npc_knowledge, npc_social v1–v5, dialogue_knowledge. Никаких автоматических домыслов о присутствии NPC, владении предметом, раскрытии секрета, смерти или согласии.

**rich_package.py / project.py / cli.py:** добавлен необязательный параметр **--npc-review** к build/build-rich/finalize и gameplay-audit проекта. Обзор проходит валидацию до сборки, NPC IDs заносятся в blueprint, знакомые схемы добавляются в provenance, сцены с подписанной речью проверяются вместе с speaker review; существующий Python rich writer/верификатор остаётся единственным источником истинности формата. book_id зависит от точной редакции review, чтобы не спутать сохранения. Сборка без нового флага сохраняет старый player-only путь.

**finalize.py / gameplay_quality.py:** source-review входит в контроль до сборки; в отчёте фиксируются точный review SHA и версия social. Литературный смысл не объявляется доказанным одним флагом согласия.

**compatibility.py, compatibility.json, npc_compatibility_probe.py:** doctor запускает native Python v5 writer/reader, проверку 4 ZIP записей, sidecar, 9 отрицательных v5 сценариев; оставлена старая проверка npc knowledge. Пин обновлён после сравнения исходников и теперь охраняет **17 файлов** Python, Dart, story_core, SQLite, gateway и adapter, чтобы следующий дрейф не спрятался.

**tests/rpg_author/test_npc_review.py и run_dart_parity.py:** проверены source/review digest, различие book_id между версиями, old player-only, подмена цитат/ID/согласия, передача NPC реального предмета, уход NPC, Dart import и SQLite replay/restart/fork/portable save. Всё на синтетическом источнике; приватные книги в CI не загружались.

## 3. Строгий входной формат npc_review.json

Корневые **обязательные поля**:
- format = rpg_author_reviewed_npc_overlay_v1;
- source_fingerprint = точный SHA256 книги/индекса;
- story_sha256 = canonical digest принятого StoryPlan;
- enrichment_sha256 = canonical digest принятой игровой надстройки;
- actors = отсортированный список постоянных npc_XXXXXXXX... IDs, не имена;
- npc_knowledge = точно подписанный source-review native v1 с grants;
- npc_social = выбранная native версия v1–v5 с необходимыми witnesses/rules/gates/transfers/item_grants/life_transitions;
- dialogue_knowledge = полный по сценам review подписанных говорящих (пустой объект допустим, когда сцены не содержат структурированных диалогов).

Сквозной native writer перепроверяет: цитата относится к SOURCE_PASSAGE нужной сцены, не из будущей главы; observer/actor находится среди подтверждённых персонажей; required-memory и trust не берутся из ещё не произошедших событий; item grant и transfer соответствуют одному реальному typed choice/effect; невозможные lifetime transitions, дубликаты, false canon, неразрешённые секреты и неподписанные реплики отклоняются.

**Важно:** user_confirmed=true в приватном review может присутствовать только после реального подтверждения пользователем/автором. Он не доказывает литературную правду или права публикации, а точные NPC/quote/choice данные нельзя выдумать по примеру. NPC-ID надо один раз выдать и хранить в приватном checkpoint/snapshot. Готовое review должен подготовить ChatGPT по полной книге и затем независимо проверить; создание всех сведений пока **не полностью автоматизировано**. Документ/CI не подменяют этого этапа.

## 4. Как пользоваться

Все private файлы и результаты находятся вне публичного checkout.

    python3 -m tools.rpg_author doctor
    python3 -m tools.rpg_author build --project /private/project --enrichment /private/enrichment.json --npc-review /private/npc_review.json --output /private/game.bworld
    python3 -m tools.rpg_author verify --input /private/game.bworld --attribution /private/game.attribution.json
    python3 -m tools.rpg_author gameplay-audit --project /private/project --enrichment /private/enrichment.json --npc-review /private/npc_review.json --strict

Полный E6f/E6e финал при наличии независимого литературного отчёта и полного реестра интерактивных вопросов:

    python3 -m tools.rpg_author finalize --project /private/project --enrichment /private/enrichment.json --npc-review /private/npc_review.json --review /private/review.json --output /private/game.bworld --dialogues /private/dialogues.json --question-inventory /private/question_inventory.json

Если действительно **нет** интерактивных вопросов, заменить два последних параметра на --no-interactive-questions; это явное заявление автора, не автоматически проверенный факт. **Не** использовать тот же output после отдельной сборки build: все файлы предназначены только для новой записи и не перезаписываются. Подписанные scene_dialogues и интерактивные dialogue topics — **разные** типы данных.

## 5. Подтверждённое, незавершённое и дальнейшие ворота

**Подтверждено exact-head CI:** Python author-tests + v5 probe; Dart importer; SQLite save/restart/portable/fork; синтетический вариант без NPC и с NPC memory/life/item ownership; verifiers и отрицательные тесты. Проверенный код SHA 2d6b94e..., run #42341605734, оба задания PASS.

**Не подтверждено:** полная настоящая книга «Король-лягушонок» и второй независимый FB2, все реальные NPC и мотивы, автоматическое end-to-end создание литературно проверенного review без отдельного прохода, реальный GLM, настоящий Windows/Android UI и физические устройства. Это не статус USER_READY.

**PR #133**, P0 full-book gameplay/readiness, оставался [DRAFT](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), **не входит в этот baseline**. После его принятия потребуется новая отдельная проверка конкретных изменённых contract files и exact Python/Dart parity, а не синхронизация по каждому незавершённому коммиту.

**Установленный навык ai-story-book-to-rpg по-прежнему закреплён на E6d SHA 9849c22d18e2761b49766b0c213b4a3fb3fe053b (0.3.0a2).** GitHub E6f **не переключает** его bootstrap/использование автоматически. Для обновления установленного навыка нужна отдельная проверенная процедура. Старых пользовательских E5-проектов нет — миграцию не начинать.

**Неприкосновенная область:** изменены только tools/rpg_author и tests/rpg_author внешней ветки, main/apps/packages/tools/bookworld/общий CI неизменны; приватные книги/секреты/цитаты не публиковать.

Соподчинённые планы: [генеральный](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md), [игровые вкладки](GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md), [история E6e](E6E_FINALIZATION_RU_2026-11-07.md).
