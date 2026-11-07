# AI Story RPG — актуальный статус 2026-11-07

**NEW #133: реальные дополнительные события книги в игровом маршруте.** Новый `bookwide_source_encounters.dart` добавляет в обычный `StoryPlan` source-locked `act_N_source_encounter` на выбранный дополнительный event этого акта. Имеются 2 действия: изучить/пройти мимо; выбранный choice реально коммитится в `WorldEvent` и живёт в SQLite. Встроенный экран показывает и даёт отдельно подтвердить точную цитату, меняя план/историю только после consent, сбрасывая прошлые model approvals при новой выборке. Единственное `MultiActTrialCompiler`/ rich v3/Python/Dart importer, условия межактовой связи и типизированные предметы/знания могут сосуществовать, т.к. план вычисляется один раз из текущих ревизий. Добавлены отрицательные тесты на чужой/повторный event и согласие, E2E с двумя актами/двумя дополнительными событиями и SQLite close/reopen, UI widget. **Ограничение: одно дополнительное событие на акт, хотя целевая RPG должна охватить всю существенную книгу без слайдов и без ложного канона.** На текущем кодовом коммите точный CI ещё не объявлять успешным. E6d отложен.



**Интеграция контракта предметов и межактовых последствий в #133 (ещё проверить точный CI):** UI теперь может предложить source-locked item/fact candidates для точно того же `continuity.plan`, который будет скомпилирован; старые одобрения от базового плана не допускаются. Оба согласия локальные/явные, GLM сам не вызывается от открытия. Кандидаты вносятся после независимого route auditor и дополнительного approval digest, `.bworld` и SQLite не подменяются. Сквозной тест с кольцом и сохранением двух вариантов добавлен. Литературная проверка старой редакции при включённой причинности не переиспользуется.



**Новый функциональный инкремент PR #133:** `CrossActConsequenceGate.applyReviewedActChain` обеспечивает реальную причинную связку ВСЕХ соседних актов. От принятого либо отвергнутого решения зависит доступность предложения следующей части; меняются именно `StoryPlan` conditions и `StoryWorld` choices, а не UI-надпись. Источник проверяется, фиктивная причинность явно подтверждается пользователем; совместимость существующих без галочки не меняется. E2E для 4 актов с двумя маршрутами и реальным SQLite добавлен, результат нового exact-head CI ещё проверить. Это не готовый CANON и не автоматическая целая книга. E6d отложен.



## Подтверждено

- **PR #132 MERGED**, [merge SHA `81fb75b`](https://github.com/shonentez-afk/AI-Story-RPG/commit/81fb75b77f11b8f82cafa1e7604afa9fe9bbb678). Уже в `main`: независимое ядро NPC memories/trust/choices, предметы, event-sourced статус (present/absent/dead), проверяемые source citations, private rich-v3 `npc_social` v1–v5, replay/SQLite и интерфейс.
- Exact pre-merge [CI #920](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42331504767) **SUCCESS**: Python, Dart, M1.7, Flutter/widget, Windows portable, Android APK; [M0 #1005](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42331505079) **SUCCESS**.
- Post-merge main [CI](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42333580182) и [M0](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42333580205) запущены; их финальное состояние **проверить живым инструментом**. Публикация тестовых артефактов не равна ручному QA.
- Внешняя E6d имеет отдельный `contract_drift`; **отложена** до конца основного приложения по распоряжению пользователя. Не менять `tools/rpg_author`, pin или её PR.

## Следующий P0

[PR #133 DRAFT](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), рабочая ветка `feature/p0-bookwide-gameplay-readiness-20261107`: единый путь **полная книга → связный сценарий → выбор настоящего героя/реального режима → приватный playable BookWorld**. [План и критерии](P0_BOOKWIDE_AUTHOR_PATH_RU_2026-11-07.md).

- Уже существует short/multi-act пробный ALTER_FATE с source-locked цитатами, игровыми выборами, SQLite, GLM proposals после согласия и ограниченной редакторской проверкой.
- Первый инкремент следующего пакета вводит source coverage без доверия к AI-оценке, выбранную пользователем **подпись** героя в `presentation.hero.name`, честный UI «только пробный ALTER_FATE». Подпись — не подлинный выбор литературного NPC. Это не готовый CANON/1.0.
- Требуется не только обнаружить события всего произведения, но и **включить** их в причинные игровые маршруты, сохранить знания/предметы NPC при вариантах, полную хронику и концовки; затем 2 реальные FB2, реальный GLM, устройства Windows/Android.

## Принципы и приёмка

Никаких микропиар по полям, никакого второго движка. Всё через `story_core`, существующий формат rich-v3, проверяемые offline game/save/replay. Каждый функциональный пакет — точный HEAD CI Dart/Python/schema/Flutter + Windows/Android + M0, затем merge и CI main. История прежних стадий доступна по git; [полные критерии 1.0](PROJECT_COMPLETION_GATE_RU_2026-11-06.md), [Issue #118](https://github.com/shonentez-afk/AI-Story-RPG/issues/118).
