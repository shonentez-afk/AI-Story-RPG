# AI Story RPG — CURRENT_STATUS_RU

**Срез 2026-11-07.** `main`: `f4331851ef5752e0e2821f328d75703808579ef5` (#130 MERGED). Exact-head CI #823/M0 #908 SUCCESS; post-merge CI #824 SUCCESS. [test-build-824](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-824) — последняя проверенная APK/Windows сборка **после #130**. PR #129 реализовал read-only доказательства знаний; PR #130 — детерминированную проекцию событийной памяти и направленных отношений, без тайной записи в world state. [PR #131](https://github.com/shonentez-afk/AI-Story-RPG/pull/131) — Draft, явный v1 контракт source-locked NPC `learn_fact`/`knows_fact` для rich-v3 с Dart/Python проверками. **Это ещё не готовая 1.0.**

## Что уже в main

1. Читалка TXT/FB2/FB2.ZIP и библиотека; офлайн-игровой runtime и SQLite-кампании.
2. `.bworld` v1/v2/v3, source-lock и Dart/Python валидация, реальные игровые выборы/вещи/факты/журнал.
3. GLM 4.7 Flash с информированными согласиями, ограниченными пакетами, checkpoint/resume; существующие StoryPlan, литературные аудиты и частные игровые сборки.
4. UI диалогов: последовательные подписанные реплики, история, локальные портреты, строго проверенный структурированный текст.
5. NPC карточки с постоянным `character_id` (#126), проверка редакторских отношений по `target_character_id` и `speaker → character_id` только при однозначности (#127).
6. Независимые Dart-пакеты `story_core`, `story_runtime_adapter`, `bookworld_format`, `campaign_manager`; отдельный CLI-проход без Flutter/ИИ и CI-проверки направления зависимостей (#127).

## Один функциональный пакет на review — PR #131

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
