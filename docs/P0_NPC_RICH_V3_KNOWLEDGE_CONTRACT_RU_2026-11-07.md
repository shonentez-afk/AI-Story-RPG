# P0 — переносимое NPC-знание в частном BookWorld rich v3

**Статус 2026-11-07:** [PR #131](https://github.com/shonentez-afk/AI-Story-RPG/pull/131) Draft, требуется полный exact-head CI/M0 и E6d compatibility review. База main `f4331851` (PR #130). Не объявлять функциональность выпущенной до merge и post-merge.

## Почему нужен этот этап

В `story_core` после PR #129 уже существуют `learn_fact`/`knows_fact` для любых актёров, `actorKnowsFact`, `factLearningEvents`, `missingKnowledgeForActor`. PR #130 добавил событийную память и направленные отношения как **read-only** проекцию. Но строгие rich-v3 Dart/Python импортеры **до PR #131** разрешали знания только герою, а Python проверял общий набор фактов. Отсюда риск: проверенная карточка NPC есть, но импортированный мир не способен сохранить/проверить знания NPC.

## Явный v1 NPC-knowledge контракт

Только для **частного** rich-v3 `.bworld`, со старым `format_version: 3`, новым versioned capability и теми же четырьмя ZIP-членами:

- `manifest.json` получает `npc_knowledge_format: ai_story_npc_knowledge_grants_v1`.
- `source/provenance.json` получает обязательный `npc_knowledge` объект с `format: ai_story_npc_knowledge_grants_v1`, `review_scope: user_declared_private_game_fiction`, точным `source_fingerprint`, `user_confirmed: true`, `literary_canon_verified: false`, и `grants`.
- Каждый grant — строго `scene_id`, `choice_id`, `actor_id`, `fact_id`, `source_quote_sha256`. Он должен один-к-одному соответствовать настоящему `learn_fact` в исполняемых эффектах указанного выбора и цитате `SOURCE_PASSAGE`, доступной по главам.
- `scenario/blueprint.json`: все NPC в `actors` имеют постоянный `npc_`+32 hex `character_id`; начальное `knowledge` содержит **пустые** наборы для `player` и каждого NPC; `knows_fact` проверяет знания **своего** `actor`.
- Существующая строгая конечная симуляция всех достижимых состояний теперь различает `{ actor_id: [known_fact_ids] }`: нельзя выдать секрет одному NPC и автоматически разрешить реплику/вариант другому, нельзя получить факт за счёт порядка глав и нельзя пройти тупиковый маршрут.

**Совместимость:** если в книге есть только `player`, ни один новый ключ не нужен и прежние v3 миры остаются принимаемыми. Внешний пакет E6d не меняется этим PR. Переход `npc_knowledge` — **опциональный, строго проверенный, явно помеченный versioned extension**, а не ослабление старого формата или переименование в несуществующий v4.

## Запреты и ограничения

1. Source quote лишь связывает редакторский выбор с источником. Она **не доказывает** литературный факт, слова, осведомлённость или присутствие NPC: перед публикацией нужен source-locked литературный review, а `user_confirmed: true` нельзя проставлять без реального согласия.
2. Эта версия разрешает проверенные `learn_fact/knows_fact`. Социальные `NpcSocialLedger` воспоминания и отношения всё ещё не сериализуются и не блокируют игровые choices. Для этих механик нужен следующий **отдельно версионированный** контракт, Python+Dart parity и событийное состояние.
3. Существующий `gameplay_review` несовместим с одновременными NPC grants, пока не разработан единый подписанный обзор. Вместо молчаливого объединения пакеты должны отклоняться до соответствующего этапа.
4. `packages/story_core` остаётся детерминированным и независимым от Flutter/SQLite/LLM; `story_runtime_adapter` — публичный API; `bookworld_format` — архив/правила импорта; `campaign_manager` — сохранения.
5. Приватные FB2, перевод, цитаты, фото и API-ключи не коммитятся: только синтетические, некоммерческие fixtures. Не вносить изменения во внешнюю E6d-ветку параллельного чата.

## Приёмка PR #131

- Python tests: правильный NPC-архив, старый player-only, отсутствие review, чужой actor ID, будущая/подменённая quote, двойной learn, grant в заблокированном выборе, первоначально известный секрет.
- Dart tests: writer→importer, событие до/после знания, две развилки, факт только у указанного NPC, `StoryWorld.replay` с тем же state SHA, отрицательные признаки.
- CI: **Dart writer → Python validator** и **Python writer → Dart importer/runtime replay** для двух независимо созданных архивов, сохранение SHA256, без выключения SQLite/source/format проверок.
- Windows/Android builds, Flutter, engine boundaries, независимый Dart CLI, точный PR HEAD CI/M0, после merge main CI и release SHA.

## Внешняя E6d: что должен сделать параллельный чат

GitHub Actions `External RPG author tests` на первом SHA PR #131 сообщил `contract_drift` для `tools/bookworld/private_rich_bookworld.py`, `packages/bookworld_format/lib/private_rich_bookworld.dart`, `packages/bookworld_format/lib/private_bookworld_writer.dart`. Это ожидаемая защита pinned-контракта, а не автоматическая ошибка Python проверки. **Ветка E6d не изменялась.** Её разработчику следует после просмотра принятого diff обновить pin и добавить новый NPC-grant fixture в свои независимые тесты; до обновления совместимость нового расширения с внешним генератором не заявлять.

## После этого этапа

Следующее крупное интеграционное задание: связывать `NpcKnowledgeRulebook`/`NpcKnowledgeWorldBridge` с явным UI-review и `npc_knowledge` в source-bound v3 writer, затем memory/relations/presence/dialogue line gates, реальный full-book CANON/ALTER_FATE и E2E на двух FB2. Сроки и статус определяются только проверенным кодом, а не номером мини-этапа.
