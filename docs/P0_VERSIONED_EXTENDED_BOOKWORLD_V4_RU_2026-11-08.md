# P0 — версионированный частный BookWorld v4 и автономная сборка

**Дата: 2026-11-08.** Один Draft PR [#133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), **кодовый SHA `f30e59007a913724f6466f3e70b27b926025bceb`**. `main` и внешний `tools/rpg_author` (E6d) НЕ изменялись. Это развитие того же [согласованного единого плана](DESIGN_UNIFIED_BOOK_TO_RPG_PATH_AND_AUTONOMOUS_AUTHORING_RU_2026-11-08.md), а не серия микро-PR.

## Результат в коде

- `packages/bookworld_format/lib/private_rich_bookworld.dart`: существующий `RichPrivateBookworldImporter` теперь различает **строгую неизменённую v3** и явно объявленную `format_version=4` с `build_status=private_extended_structural`. Новые условия не включаются в v3.
- v4 структурно допускает **3–1024 сцен, до 64 флагов, 96 предметов, 128 фактов, 16 характеристик**. Количество достижимых игровых состояний ограничено **8000**. Проверка включает доступные действия, два финала, замкнутые циклы без выхода и точное сравнение с SQLite.
- По сравнению с v3 допускаются **исходный инвентарь, знание каждого конкретного актёра, исходный tick и типизированные `tick_at_least`/`advance_time`**. Повторяемые шаги ожидания проверяются с эквивалентностью времени относительно фактических порогов, без ложного бесконечного перечисления.
- Nonempty initial data требуют `initial_state_review` версии `ai_story_private_initial_state_review_v1` (явное `user_confirmed`, `literary_canon_verified=false`, точные item/fact/actor IDs, SHA цитаты SOURCE_PASSAGE исходной главы 0, её `visible_after_chapter=0`). Этим подтверждается только источник/частное игровое допущение, **не доказанный канон сюжета**.
- `RichPrivateBookworldWriter.build(expanded: true)` собирает v4; `build()` оставляет прежний v3 без автоматической конверсии и без E6d contract drift. Новый `VerifiedRichPrivateBookworld.formatVersion` позволяет приложению узнать версию.
- `packages/story_authoring/lib/src/authoring_engine.dart`, `bin/author_book.dart`: автономная команда `build-extended book.fb2 reviewed_v4.json full.bworld`; старый `build-reviewed` продолжает создавать v3. `inspectPrivateWorld` и `verify-world` проверяют новые архивы через того же строгого импортёра. Без Flutter, сети и второго игрового движка.

## Проверка и доказательства

- `packages/bookworld_format/test/private_extended_bookworld_v4_test.dart` строит приватный мир из **203 сцен**, проверяет реальные переходы, начальный инвентарь/знание игрока, время, детерминированный `StoryWorld.replay`; отдельно запрещает v3 принять расширенные правила и отклоняет неподписанную/ложную исходную фактографию.
- `packages/story_authoring/test/story_authoring_test.dart` проверяет **явный** выбор v3/v4 в автономном Dart-компиляторе.
- `tools/ci_verify_private_extended.py` независимо сверяет Python ZIP, SHA, привязку к редакции, 203 scene IDs, законность initial-state review и точное соответствие SQLite. **Это структурная Python-проверка, НЕ полный независимый Python v4 causal verifier.** Формальные переходы проверяет существующий Dart `story_core` и расширенный строгий импортёр.
- Новый [AI Story RPG CI #42458636957](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42458636957) и [M0 #42458636967](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42458636967) относятся к точному SHA `f30e590`. При создании этого файла Python reference и Dart engine scenarios уже SUCCESS; остальные шаги требуют проверки фактического итогового conclusion, **не объявлять их PASS на основании частичных шагов**.
- Предыдущая кодовая база `3c1a7aa` прошла [CI #42455037055](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42455037055) и M0 #42455036949 SUCCESS. Этот факт НЕ заменяет проверку v4.

## Что ещё не реализовано и почему нельзя объявлять «вся книга → готовая игра»

**Формат v4 и полный генератор — разные уровни готовности.** Книжные `StoryPlan` и `IntermediateStoryBlueprint` пока ограничены 192 сценами и 32 флагами; `BookwideStoryPlanComposer` — 12 авторскими актами; `MultiActTrialCompiler` пока использует legacy v2→v3 мост. Он НЕ выбирает v4 автоматически, а неявное повышение ёмкости запретили специально. Отдельные режимы CANON / CUSTOM / AI_FREEFORM и хронология с независимым лором не стали реальными через смену версии. Пользовательские права, мотивация/факты/NPC, полная память/инвентарь/роль героя, карты всех событий и литературная истина требуют проверок. `E6d` отдельно отложен. Ни один созданный архив не разрешён к публичному распространению.

**Следующий ОДИН крупный функциональный пакет в PR #133:** интегрировать scene/flag v4 ёмкость в `StoryPlan`, `IntermediateStoryBlueprint`, `BookwideStoryPlanComposer`, `MultiActTrialCompiler` и source-reviewed direct rich-v4 compiler **без обхода старых семантических/литературных и causal gate**. Проверить >192 по актам, полный список исходных событий без молчаливого усечения, NPC 0/1/2, реальный runtime/SQLite и межъязыковую паритетность. Затем один UI-мастер и единая приёмка Windows/Android/двух настоящих RU FB2.

**Принцип:** один `story_core`, private `.bworld`, общий authoring пакет, крупные логические функции, `main`/E6d не трогать, PR #133 Draft пока нет полного acceptance.
