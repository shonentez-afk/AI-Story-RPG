# P0 NPC — единый пакет присутствия, памяти, отношений, предметов и последствий

**Дата:** 2026-11-07. **Рабочая ветка:** `feature/p0-npc-presence-social-gameplay-20261107`, [PR #132](https://github.com/shonentez-afk/AI-Story-RPG/pull/132) — Draft. `main`: `9c9bdc142495e536b5d11ca5e61680948e45f8fe` (#131 accepted, test-build-856). Не дробить этот пакет на PR по полям.

## Фактическая архитектура в ветке #132

1. `packages/story_core/lib/src/npc_social_ledger.dart`: `NpcSceneWitness` с `present/reported`, `NpcSocialRule` (память, обещания, помощь/предательство, слух, однонаправленная репутация), `NpcSocialChoiceGate` (source-approved memory/trust), `NpcItemTransfer` и неизменяемый `NpcSocialSnapshot` (владелец каждого предмета, хэш цепочки, зафиксированные события). Вспомогательные актёрские названия/цитаты не меняют world.
2. `packages/story_core/lib/src/engine.dart`: `StoryWorld` связывается с точным `NpcSocialRulebook`; проверяет условия choices до эффекта, не принимает циклические или самопорождающие зависимости, учитывает владельца предмета, возвращает отказ на попытку отдать чужой предмет или выдать дубликат, спекулятивно проверяет весь следующий event до публикации. Данные восстанавливаются из исходного blueprint + hash-chained `WorldEvent` (социальная проекция подписана digest rulebook и event head; NPC вещи НЕ записываются во вторую SQLite-таблицу и не считаются отдельным движком).
3. `packages/bookworld_format/lib/npc_social_contract.dart`, `private_rich_bookworld.dart`, `private_bookworld_writer.dart` + `tools/bookworld/private_rich_bookworld.py`: приватный `.bworld` с `format_version: 3`; **отдельная версия capability** в `manifest.npc_social_format` и `source/provenance.json:npc_social`: `ai_story_npc_social_witness_v1` (свидетель/память), `_v2` (+ `choice_gates`), `_v3` (+ `item_transfers`). Обязательны ровно разрешённые поля, подписанные source scene IDs/доступные SHA цитат, постоянный `character_id`, явно подтверждённый private review. У NPC-передачи обязан быть точный типизированный `grant_item`/ `consume_item`, при личном присутствии NPC, на том же action. Python/Dart проверяют независимо.
4. `packages/story_runtime_adapter` / `campaign_manager`: один и тот же signed social rulebook задаёт `choices`, `commitChoice`, SQLite close/reopen, `.bwsave`, fork и replay. Старые v1/v2/v3 без `npc_social` не мигрируют.
5. Flutter `NpcKnowledgeRulesPage`: старый диалог подготовки NPC сохраняет выбор свидетеля/слуха, обещания/реакции, условия подписанных реплик и решения по памяти/доверию, подтверждённые отдельными цитатами. `WorldLibraryGateway` проверяет и скрывает запрещённую реплику до UI; `WorldPlayPage` показывает вещи NPC в старой вкладке «Предметы», в «Журнале» — передачу/возврат вместо неверного «использовано».

## Реальные проверки, пока БЕЗ утверждения полного успеха

- `packages/story_core/test/npc_social_ledger_test.dart`: очевидец против слуха, репутация без фарма, недоступное решение до обещания, replay/подмена, циклы памяти, NPC передача/возврат/подделка владельца.
- `tools/bookworld/tests/test_rich_npc_social.py` и `packages/bookworld_format/test/private_rich_bookworld_writer_test.dart`: исходная цитата/время, версионированные social v1/v2/v3, Dart-built→Python verified ZIP и Python-built→Dart verified ZIP, tamper/unknown item/actor/quote.
- `packages/campaign_manager/test/npc_social_sqlite_replay_test.dart`: настоящий private sqlite store, ветка с обещанием против альтернативной без знания, закрытие базы с предметом у NPC, replay, duplicate refusal и возврат, сохранение hash и `.bwsave`.
- CI, Flutter, APK, Windows portable и M0 должны быть проверены **на exact HEAD после всех изменений**. Не считать отменённые на прошлых коммитах прогоны успехом. Не объявлять синтетический тест настоящим E2E книги.

## Продолжать в ЭТОМ ЖЕ PR #132

- **Главный функциональный пробел:** стандартный `PrivateClassicScenarioTranslator.translate` по-прежнему создаёт `items: []`. Нужно добавить проверяемые автором предметные эффекты `grant_item/consume_item` в существующий путь подготовки книги и типовые правила отдачи/получения NPC. Не добавлять ещё один сложный редактор или второй компилятор; использовать source-locked evidence/consent и текущую rich-v3 инфраструктуру. Пока предметы NPC работают при импорте проверенного v3, но не генерируются из стандартного сценария.
- **Состояние NPC:** присутствует/ушёл/недоступен/погиб и права на разговор/передачу/свидетельство; нельзя оживлять персонажа повторным выбором, перемещать без сцены или игнорировать причинность. Должно восстанавливаться по event log.
- **Полная продуктовая приёмка:** NPC gameplay с двумя реальными литературно разными FB2/GLM, персонажем/событиями/вещами/режимами, Windows/Android, сохранениями, UX, честным описанием ограничений. Это часть проекта 1.0, ещё не исполнено.
- Зафиксировать exact-head CI, обновить START/STATUS/Issue #118, объединить как один PR. Границы движка `story_core` / `story_runtime_adapter` / `bookworld_format` / `campaign_manager` сохранять.

**E6d отложен пользователем до завершения основного приложения.** Ничего в нём не изменять; не тратить время на его SHA pin или external contract drift. Пересогласовать отдельно позже; внешний тест может пока быть красным, он не доказывает отказ основных Dart/Python/Flutter checks.

Ссылки: [handoff](../START_NEW_CHAT_RU.md), [статус](CURRENT_STATUS_RU.md), [релизный критерий](PROJECT_COMPLETION_GATE_RU_2026-11-06.md), [Issue #118](https://github.com/shonentez-afk/AI-Story-RPG/issues/118).
