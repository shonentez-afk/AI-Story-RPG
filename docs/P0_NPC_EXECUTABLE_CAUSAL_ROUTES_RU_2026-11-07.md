# P0 — исполнимые причинные маршруты NPC (StoryWorld, не граф глав)

**Дата:** 2026-11-07. **Рабочая ветка:** `feature/p0-bookwide-gameplay-readiness-20261107`, PR #133 Draft. **База до реализации:** `bdbd836` (последний проверенный код `a45fa88`, основной CI #949 SUCCESS). Новая реализация **ожидает exact-HEAD CI**. Никаких правок E6d и `main`.

## Зачем этот блок

Ранее `RichNpcDialogueKnowledge.validate` требовал постоянный character_id NPC, точную цитату-источник, доказанную выдачу факта одним `learn_fact`, структурную связь между сценами и runtime-гейт по хэшированному событию. Но простая проверка `_reachable` по графу переходов **не означает, что игрок способен выполнить событие**. Например: решение «рассказать секрет» доступно только после флага, который никогда не установить; сцены соединены, но NPC никогда не узнает секрет, и утверждённая реплика никогда не станет доступна.

## Что добавлено

1. `packages/story_core/lib/src/causal_route_audit.dart` — чистый `StoryCausalRouteAudit.find`, работающий на `StoryWorld.fork/apply`, `NpcSocialLedger`. Без Flutter, Python, Z.ai или SQLite и без второго DSL.
2. Вход: `targetSceneId`, необязательные `requiredPriorChoiceId` / `forbiddenChoiceId` (для проверки исхода альтернативы), точный `actorId`, список `requiredFactIds`, `requiredMemoryId`, `minimumTrustToPlayer`, проверенный `NpcSocialRulebook`. Все идентификаторы и правила валидируются строго.
3. Поиск — детерминированный BFS с устранением повторов по состоянию, а не только по ID сцены: флаги, характеристики, вещи, **познания каждого actor**, игровое время до максимального порога `tick_at_least`, committed previous choice, память, направленное доверие, жизнь и фактическое владение предметом. Разные пути не смешиваются. Все переходы исполняются через актуальный `StoryWorld.apply`; отрицательные/недоступные choices пропускаются.
4. Положительный результат включает **кратчайшую цепочку choice_id и WorldEvent** с `beforeStateHash/afterStateHash`, проходящую независимый `StoryWorld.replay`. `CausalRouteStatus.unreachable` допустим **только если пространство различимых состояний исчерпано**. При превышении `maxStates` или `maxMoves` возвращается `inconclusive`, не ложное «невозможно».
5. `RichNpcDialogueKnowledge.auditExecutableRoutes` — отдельная стадия авторского preflight для NPC-turn, имеющих knowledge/event/memory/trust prerequisites. Требует существующий **хотя бы один исполнимый** путь к сцене с выполненными предпосылками; другой путь без секрета остаётся допустимым, и `redact` скрывает его слова.
6. `RichNpcDialogueAuthoring.propose` вызывает preflight **до** выдачи `approvalDigest`; `NpcKnowledgeRichWorldBridge.prepare` повторяет уже с итоговым социальным rulebook перед сборкой мира. Графовый/источниковый контракт `RichNpcDialogueKnowledge.validate` и собственно runtime-redaction **не ослаблены**.

## Что НЕ меняем

- `.bworld` rich-v3, `manifest.json`, сериализация `StoryBlueprint`, Dart/Python ZIP importer и `model_provenance` не получают новых полей. Это **новая предсборочная проверка авторства**, а не декларация, будто Python проверяет маршруты. Уже готовые миры запускаются по-старому.
- Свободный художественный текст, слухи, цели и мотивы NPC не исполняют эффекты: только typed choices, source-locked явное согласие и существующая модель событий.
- `main` не затрагивается, внешний компилятор E6d параллелен и в этом пакете не меняется.

## Приёмка

Новые тесты `packages/story_core/test/causal_route_audit_test.dart` и `packages/bookworld_format/test/npc_causal_route_preflight_test.dart`: исполнимый `wait → help` с `learn_fact`, идентичный replay/hash, NPC B не наследует знание, альтернативное `leave` не даёт знания, графово соединённая но закрытая `wait` ветвь не проходит, source-reviewed proposal не утверждает невозможный NPC-turn, социальная память/направленное доверие доступны только после committed action, ограничение шагов выдаёт `inconclusive`, поддельный actor/choice отклоняется. Затем обязательны exact-HEAD CI Dart/Python/Flutter/M1.7, сборка Windows/Android и M0.

**Ограничение:** BFS подтверждает **структурно-игровую достижимость** под действующими typed rules, а не смысловую правдивость книги. Литературную причинность (мотив, ложь, спорность, нежелательные спойлеры) должен отдельно проверять автор и последующий полный сценарный компилятор. Это инфраструктура для будущего анализа всей книги, не готовый book-wide generator.
