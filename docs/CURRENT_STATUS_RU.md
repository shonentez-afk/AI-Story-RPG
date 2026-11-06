# AI Story RPG — CURRENT_STATUS_RU

**Проверено 2026-11-07.** `main` = `9c9bdc142495e536b5d11ca5e61680948e45f8fe`; PR #131 MERGED, post-merge AI CI #856 и M0 #941 SUCCESS, [test-build-856](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-856) (Windows portable, Android APK). **RPG 1.0 не завершена.**

## Единый текущий PR #132 — реализация, но НЕ merge

[PR #132](https://github.com/shonentez-afk/AI-Story-RPG/pull/132), `feature/p0-npc-presence-social-gameplay-20261107`, DRAFT. Один связанный функциональный пакет, никакого PR на отдельное поле или служебный экран.

- Присутствие NPC (`present/reported`), verified source refs, `character_id`, память фактических событий и направленное доверие; слух не равен очевидцу. Не выдавать редакторские знания за автоматически доказанный канон.
- **Геймплей:** `NpcSocialChoiceGate` в `story_core` не позволяет принять решение без требуемой подтверждённой памяти/доверия; проверка до `WorldEvent`. Запрещены самопорождающие условия, циклические prerequisites, future-chapter источники (Dart/Python).
- **Предметы NPC:** `NpcItemTransfer` в независимом Dart-ядре, детерминированная проекция владельца по `grant_item/consume_item` и точным committed event SHA; запрет вернуть не принадлежащий NPC предмет, отдать чужой, создать копию у героя, когда предмет у NPC. Спекулятивная проверка проводится до публикации следующего state/журнала.
- **Перенос:** private rich `.bworld` format_version=3 + опциональные source-reviewed `npc_social` версии v1/v2/v3; строгая Dart/Python parity, независимый CLI, `campaign_manager` SQLite и `.bwsave` replay. Никаких изменений старых миров.
- **UI:** прежний NPC build dialog позволяет явно подтвердить событие, очевидца/слух, память/доверие для диалога и решений; `WorldLibraryGateway` получает точный сохранённый социальный контракт; вкладки «Предметы» и «Журнал» показывают доказанные передачи. Секретная реплика блокируется до UI.
- **Тесты в ветке:** core отрицательные случаи и циклы, Python/Dart версионные ZIP tamper/replay, реальный SQLite close/reopen и альтернативные ветви, предмет у NPC до/после рестарта. **Итоговые Actions сверять по последнему точному SHA**; зелёные прошлые коммиты ≠ приёмка нынешнего HEAD.

## Что не готово

1. Встроенный `PrivateClassicScenarioTranslator` пока отдаёт `items: []`. Нужно связать реальные подтверждённые предметные эффекты сценария, владение/передачу NPC и согласие автора с существующим UX без нового движка/сложного редактора. Rich-v3 импорт уже способен исполнять и проверять item transfer, но стандартный book→game автор ещё не выпускает такие действия.
2. Длительное присутствие, перемещение, отсутствие, гибель NPC и последствия для контактов/диалогов; причинность при другой ветви и таймлайне.
3. Доказательство полной книги: multi-act GLM, цельный CANON/ALTER_FATE, выбор героя, мастер, 2 реальные русские FB2 с реальным GLM и устройствами Android/Windows; не обозначать mock как E2E.
4. Общая приёмка PR #132: exact-head Dart/Python/SQLite/Flutter/Win/Android/M0, SHA, merge и post-merge. Документация не заменяет эти проверки.

**E6d: отложено по решению пользователя до окончания основной программы.** Не тратить время, не менять pinned skill или другую ветку, не считать внешний contract_drift блокером текущей разработки основного приложения. Пересогласование — отдельным этапом позже.

## Независимость движка

`packages/story_core` — единственный владелец правил и событий; `story_runtime_adapter` — клиентский контракт/навигация, `bookworld_format` — парсинг/подтверждение источника, `campaign_manager` — SQLite/save/replay, Flutter — оболочка. Не импортировать `apps/`, Flutter, SQLite или сетевой код в `story_core`; после полного игрового E2E готовить стабильный публичный SDK, не второй движок.

Ссылки: [START_NEW_CHAT](../START_NEW_CHAT_RU.md), [социальный NPC контракт](P0_NPC_SOCIAL_PRESENCE_RU_2026-11-07.md), [gate 1.0](PROJECT_COMPLETION_GATE_RU_2026-11-06.md), [Issue #118](https://github.com/shonentez-afk/AI-Story-RPG/issues/118), [PR #132](https://github.com/shonentez-afk/AI-Story-RPG/pull/132).
