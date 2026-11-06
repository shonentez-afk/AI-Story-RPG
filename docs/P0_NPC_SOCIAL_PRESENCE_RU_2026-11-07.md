# P0 NPC social — source-locked присутствие, память и последствия

**Ветка** `feature/p0-npc-presence-social-gameplay-20261107`, [PR #132](https://github.com/shonentez-afk/AI-Story-RPG/pull/132) **DRAFT**. Основной main после #131: `9c9bdc142495e536b5d11ca5e61680948e45f8fe`, CI #856/M0 #941/External #129 SUCCESS, тестовый [test-build-856](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-856). Это не выпуск 1.0. **Один функциональный PR, не PR по полю NPC или вспомогательному экрану**.

## Уже добавлено в текущую ветку, но ещё не принято

1. **Отделяемый Dart core:** `NpcSceneWitness(sceneId,actorId,mode)`, `NpcWitnessMode.present/reported`, `NpcSocialRulebook(requireReviewedWitnesses:true)`. Событие нельзя запомнить без утверждённого присутствия в той же сцене. Вторичный слух допускается лишь как `rumorHeard` без положительного доверия; повторное событие ограничено `maxTriggers`, память и отношения направленные, восстанавливаются из подтверждённых `WorldEvent`. Старые preview-rulebooks не ломаются.
2. **Опциональный private rich-v3 capability:** `manifest.json:npc_social_format=ai_story_npc_social_witness_v1`, `source/provenance.json:npc_social` с `format`, `review_scope=user_declared_private_game_fiction`, `source_fingerprint`, `user_confirmed`, `literary_canon_verified=false`, `witnesses`, `rules`. Каждый witness и каждый event-rule связан с точным `source_quote_sha256`, `scene_id` и `character_id`; chapter must be visible. Никаких новых обязательных ZIP-частей, старые v1/v2/v3 остаются совместимыми.
3. **Dart/Python parity:** `packages/bookworld_format/lib/npc_social_contract.dart` и `tools/bookworld/private_rich_bookworld.py` независимо проверяют цитаты/гла́вы/дубли/типы/свидетелей и запрещают использовать слух как доказательство присутствия/доверия. Импортёр возвращает проверенный `NpcSocialRulebook`. Есть синтетические positive/negative тесты и двухсторонняя проверка точных Python→Dart / Dart→Python ZIP в CI. E6d обязан обновлять pin только после review.
4. **Тот же пользовательский экран:** существующий `NpcKnowledgeRulesPage` предоставляет явный выбор категории события (наблюдение, обещание, нарушение, помощь, предательство, слух), источника знания NPC и направленного доверия. Выбор `none` не создаёт социального события; автоодобрений нет. `NpcKnowledgeRichWorldBridge` принимает только отдельно подтверждённый `reviewedNpcSocial` и передаёт в старый rich-writer. Не создан второй движок, обязательный редактор или новый экран.

**Ограничения подтверждения:** связь цитаты с главой и ручное `user_confirmed` **не означает** литературную истинность интерпретации и не удостоверяет действительное присутствие без независимого review. Авторские заметки/весь текст книги/ключи не должны попасть в repo, snapshot или публичный release.

## Оставшиеся действия в ЭТОМ ЖЕ пакете

**Внесено как вертикальный игровой срез, но ждёт общей приёмки:** `scene_dialogue_knowledge.required_social_memory_id` и `minimum_trust_to_player` в подписанной реплике допустимы только когда `npc_social` source-locked правило существует и speaker actor совпадает. `RichNpcDialogueKnowledge.validate` / Python `_presentation` отвергают неизвестный memory или неподтверждённый positive directed relation. `RichNpcDialogueKnowledge.redact` блокирует текст до нужного события/порога; клиент `WorldLibraryGateway` сам восстанавливает `StoryWorld.replay` из SQLite и вычисляет `NpcSocialLedger`. Условия выбираются вручную в той же форме авторства. Тесты до/после события, избыточный порог и перезапуск должны пройти точный CI. **Не путать** этот gate реплик с авторитетным gate игровых choices.

- Превратить память/отношения из read-only проекции в детерминированные **реальные условия выбора/диалога** через один авторитетный `StoryWorld` и верифицируемый контракт, не в UI-флаги; запретить спойлеры.
- Ввести персонажное владение и передачу/потерю предмета (NPC ↔ герой), включая проверки, если получатель отсутствует, предмет не принадлежит отправителю или NPC погиб. Сохранять StateHash, item-log и точную ветку.
- Проверять длительность присутствия, уход, смерть/недоступность, слухи/факты, выполненные/нарушенные обещания на альтернативных маршрутах.
- Показать проверяемые последствия в существующих «Герой / Предметы / Журнал» и диалоге, без новых служебных страниц.
- Завершить CI для этого SHA: contract/engine boundaries, Python/Dart, настоящее SQLite close/reopen/replay и fork, Windows/Android, M0, E6d pinned-contract; real FB2/GLM на двух разных книгах остаётся отдельным P0 приёмки 1.0.
- Поддерживать `START_NEW_CHAT_RU.md`, `CURRENT_STATUS_RU.md`, Issue #118 при каждом крупном проходе; не считать отменённые/старые Actions зелёными.

**Следующему чату:** открыть эту спецификацию и PR #132, проверить последний HEAD в GitHub и результаты Actions, продолжать **тот же PR**, а не начинать отдельные микропиар. Внешний автор E6d обновляется другим чатом после реального diff review. Никаких старых архивов E5/компаний не требуется.
