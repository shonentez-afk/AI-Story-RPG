# P0 — полная карта книги и проверенные много-NPC диалоги для автономного BookWorld v4

**8 ноября 2026. Кодовый SHA `b337b3a6d46f7ee675b2b4fc3b63485f675160b9`.** Ветка `feature/p0-bookwide-gameplay-readiness-20261107`; единый Draft [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133). `main` и E6d не изменялись.

## Цель единого пакета

Устранить регрессию, когда готовый расширенный `StoryPlan` отклонялся старым v3-валидатором внутри `BookwideActPlanner.compareWithStoryPlan`. Не раздувать функции и PR: согласовать версию во ВСЕЙ цепочке «индекс/события → акты → последствия → NPC/герой → rich-v4 → `story_core` → SQLite», сохранив строгую v3 и источник доверия. Модель/литературные гипотезы не имеют права напрямую создавать знания/предметы.

## Реализованные изменения

- `BookwideActPlanner.compareWithStoryPlan(expanded: true)`: условная v4-вместимость сохраняется при сверке ВСЕХ source event IDs и исходных глав. Её передают `BookwideStoryPlanComposer`, `CrossActConsequenceGate` и `MultiActTrialCompiler`; неявная v3-валидация больше не обрывает длинный сценарий.
- `WholeBookNpcSourcePlan`: использует `draft.expanded` в ёмкости событий, подтверждении героя, исходных сценах, полном исходном покрытии и `compileBase`. Для v4 `planDigest` включает явную версию и полный JSON плана; согласие с v3 не превращается в согласие на v4. Существующий v3 digest сохранён. Архив, предъявляемый на NPC-рецензию, обязан иметь соответствующий `formatVersion`.
- `ReviewedNpcCampaignBookworldWriter`: поверх независимо проверенного rich-v4 собирает те же проверенные `npc_knowledge`, `npc_social` и `scene_dialogue_knowledge`, сохраняет **формат 4** и все прежние точные SHA цитат и actor IDs. NPC получает `learn_fact` и social memory только в исполнимом диалоге; `knows_fact`, память и trust gating обязательны для ответа. Каталог фактов по v4 допускает 128 фактов (v3 до 64). В 32 возможных эпизодах не создаётся новый игровой runtime.
- `StoryCausalRouteAudit.find(projectDormantFlags:true)` и `RichNpcDialogueKnowledge.auditExecutableRoutes`: для v4 проверяют настоящие `StoryWorld.apply` пути до 2000 ходов (v3 сохраняет 128) с проекцией только незначимых для будущего исходов. Реальный hash-chain, NPC knowledge, социальная память, trust, inventory и флаги в сохранениях НЕ сжимаются. Невыполнимые диалоги остаются заблокированными; `inconclusive` никогда не считается PASS.
- CI надёжность: скачивание официального `inklecate_linux.zip` версии 1.2.1 сначала по обычному URL, при 504 — по GitHub Releases asset API. Любой полученный ZIP строго сверяется с официальным SHA-256 `1997ff5bca618c90003ecd5fecb286e7468abb955005a2a185042949642f8fb5`; проверку Ink нельзя молча пропустить.

## Сквозная приёмка

- В `apps/story_reader/test/bookwide_npc_campaign_test.dart` добавлена расширенная синтетическая книга на **18 актов, 144 разных source событий, >192 сцен, 3 постоянных NPC, 161 исполняемое действие**. 8 source suggestions/window — существующий предел `SemanticPreviewWireContract`; никакого ослабления лимита ради теста.
- Отдельно проверяются: отрицательный случай «нет встречи → NPC-ответ заблокирован»; редактирование видимых реплик через `RichNpcDialogueKnowledge.redact` со скрытием недоступного текста; `StoryWorld.replay` с тремя фактами памяти; SQLite commit каждого действия, перезапуск после 112-го шага, финальная загрузка хеша и `knowledge[character_id]`.
- Прежний 18-актовый сценарий на **216 source events / 233 SQLite actions** в `bookwide_large_event_campaign_test.dart` сохранён: это отдельная проверка основной истории БЕЗ NPC. Нельзя выдавать эти два разных эксперимента за один.
- Предыдущий [CI #42463600007](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42463600007) показал реальную пропущенную передачу `expanded` через карту книги. [CI #42465943218](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42465943218) и #42466193146 выявили четыре nullable-замечания Flutter, затем два лишних `!` и внешние HTTP 504 Ink. Все исправлены в кодовом SHA выше.
- **Точный заключительный CI:** [#42466457691](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42466457691); [M0 #42466457759](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42466457759). На момент создания отчёта Python reference и Dart engine/Ink — SUCCESS; Flutter static analyze — SUCCESS; M1.7 и Flutter widget ещё выполняются. ПЕРЕПРОВЕРИТЬ заключения по этим exact run ID, иначе полноценный PASS не заявлять.
- Отдельный E6d CI может оставаться красным из-за отложенного контракта: `tools/rpg_author` не менялся и не относится к приёмке P0.

## Невыполненные крупные работы

Это ещё НЕ универсальный литературный компилятор CANON и НЕ интерфейс свободного мира с автономным офлайн LLM: `StoryBlueprint` пока действительно исполняет private ALTER_FATE/CLASSIC; модельные предложения не становятся правдой без source/role/editorial доказательств; произвольная книга требует ручной проверки событий, мотивов и времени. Формат способен хранить начальные знания/предметы, но автоматическая фактическая атрибуция их всему роману и литературный аудит ещё не приняты. **Портреты NPC, имена реплик, герой/вещи/журнал, свободный ИИ и игровые экраны не получили нового UI в этом пакете.**

**Следующий ОДИН крупный пакет после зелёной кодовой приёмки:** связать режимы, источник согласий, сценарные актовые статусы, выбранного героя, полноценный NPC/диалог, предметы/журнал и локальный/облачный ИИ в едином понятном мастере с возобновлением. Произвести 0/1/2 NPC и 2 реальных RU FB2, CLI ↔ Flutter parity, spoiler-safe/redaction, Windows/Android responsive, транзакционный SQLite replay/backup. Внешний E6d и `main` не трогать. Один Draft PR до финальной приёмки.
