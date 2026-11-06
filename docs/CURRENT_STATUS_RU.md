# AI Story RPG — CURRENT_STATUS_RU

**Главный факт 2026-11-07:** [PR #131](https://github.com/shonentez-afk/AI-Story-RPG/pull/131) **MERGED**, main `9c9bdc142495e536b5d11ca5e61680948e45f8fe`. Exact-head CI #855 **SUCCESS** (Python, Dart, SQLite, Flutter, Win/Android), M0 #940 **SUCCESS**, External E6d #128 **SUCCESS**. Post-merge CI #856, M0 #941 и E6d #129 **SUCCESS**; [test-build-856](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-856) соответствует main `9c9bdc14`. Всё это технический NPC-пакет, а не готовая full-book 1.0. Никаких E5-архивов/миграций не требуется.

**Новый крупный этап в [feature/p0-npc-presence-social-gameplay-20261107](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/p0-npc-presence-social-gameplay-20261107):** source-locked NPC присутствие и свидетели реальных событий, promises/rumors/relations, ownership/actions и последствия через отделяемый движок, переносимый schema + UI + общие тесты. НЕ делать микропиар и не выдавать preview за авторитетное игровое состояние; не менять отдельный skill E6d без версионного согласования.

## Текущая реализация: один PR #132 (DRAFT)

В `feature/p0-npc-presence-social-gameplay-20261107` реализуются **вместе**: `NpcSceneWitness` (личное наблюдение/слух), запрет памяти без присутствия и фарминга доверия, переносимый `npc_social` private-v3 со source refs и author consent, независимые валидаторы Dart/Python, двусторонние ZIP-сборки и ручная классификация в прежнем диалоге подготовки NPC. **Ещё не готово:** авторитетное social gating, NPC-предметы/состояние жизни, журнал/диалоговые последствия и общий exact-head CI. Внешний E6d pin для расширения #132 требует review. Спецификация `docs/P0_NPC_SOCIAL_PRESENCE_RU_2026-11-07.md`. Нет отдельного PR для карточки/поля.

## Что уже в main

1. Читалка TXT/FB2/FB2.ZIP и библиотека; офлайн-игровой runtime и SQLite-кампании.
2. `.bworld` v1/v2/v3, source-lock и Dart/Python валидация, реальные игровые выборы/вещи/факты/журнал.
3. GLM 4.7 Flash с информированными согласиями, ограниченными пакетами, checkpoint/resume; существующие StoryPlan, литературные аудиты и частные игровые сборки.
4. UI диалогов: последовательные подписанные реплики, история, локальные портреты, строго проверенный структурированный текст.
5. NPC карточки с постоянным `character_id` (#126), проверка редакторских отношений по `target_character_id` и `speaker → character_id` только при однозначности (#127).
6. Независимые Dart-пакеты `story_core`, `story_runtime_adapter`, `bookworld_format`, `campaign_manager`; отдельный CLI-проход без Flutter/ИИ и CI-проверки направления зависимостей (#127).

## Принятый единый пакет #131 — уже в main

Содержит **единый путь** из редакторских NPC-правил к source-locked rich-v3 через `NpcKnowledgeRichWorldBridge` и локальный `compileReviewedNpcRichPrivateBookworldInWorker`, явное согласие и цитаты по ID правила; независимый Dart/Python архив/SQLite/replay; обязательные списки требований к каждой именованной реплике, постоянные speaker character_id и сокрытие недоступного текста **до показа** через `WorldLibraryGateway`. Новых вспомогательных экранов и второго движка нет. Старые player-only v3 и v1/v2 не меняются.

**Приёмка не завершена:** PR Draft, exact-head CI и External RPG author pin review E6d проверяются отдельно. Пользовательские книги и API-ключи не публиковать. Не разбивать этот комплекс на PR по полям.

## До 1.0 НЕ доказано

- Полные **event-scoped** NPC знания и изменения отношений по конкретным событиям, не только хранилище карточек/проверка ID.
- Автоматическая связная адаптация **всей** книги, включая мотивы, принадлежность предметов, последовательность фактов и финалы.
- Настоящий выбор героя и проверенные режимы CANON/ALTER_FATE.
- Цельный простой мастер «книга → согласие → готовая RPG».
- Реальные GLM E2E по **двум разным FB2**, физические Windows/Android испытания, офлайн восстановление игры.

## Следующий шаг

**Единый P0: event-scoped NPC knowledge/relationship effects**, затем полный book-to-RPG. Правила только в `story_core`, UI/авторский источник отдельно. Не вводить новый engine и не переносить текущие пакеты в отдельный репозиторий до стабилизации API; не трогать отдельную ветку E6d.

Документы: [START_NEW_CHAT](../START_NEW_CHAT_RU.md), [архитектура](ENGINE_STANDALONE_OPEN_SOURCE_ARCHITECTURE_RU_2026-11-06.md), [приёмка](PROJECT_COMPLETION_GATE_RU_2026-11-06.md), [Issue #118](https://github.com/shonentez-afk/AI-Story-RPG/issues/118). Предыдущие исторические срезы — в git history.
