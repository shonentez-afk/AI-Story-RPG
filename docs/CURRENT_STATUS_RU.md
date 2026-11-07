# AI Story RPG — актуальный статус 2026-11-07

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
