# E6g+ — Зафиксированные сторонние решения, встроенный редактор и свободное взаимодействие с ИИ

Дата: **2026-11-06**. Состояние: **архитектурное решение / исследование. Не реализация.**
Проверенный `main` на начало аудита: `959c8134f4ef20cd00dd4039d8d131638f502f60` (параллельная основная разработка продолжается). Внешний E6d pin остается `9849c22d18e2761b49766b0c213b4a3fb3fe053b`, 0.3.0a2. Состояния GitHub/CI зафиксированы на момент исследования, не выдаются за сегодняшнее E2E.

## 1. Что пользователь утвердил

- Единая система: FB2/TXT -> точный индекс -> проверенный граф событий/персонажей/знаний/цитат -> сценарий -> rich `.bworld` -> процедурный визуальный рецепт -> существующая Windows/Android игра.
- **Навык ChatGPT** `ai-story-book-to-rpg` загружает проверенный SHA исходников генератора из нашего GitHub и управляет анализом, проверками и сборкой. Сам навык НЕ копирует полный Dart/Flutter runtime.
- `tools/rpg_author` создает машиночитаемые каталоги/игры/рецепты, **без нейросетевых изображений**. Кодовый Dart-рендерер в игре рисует пиксельную геометрию, лёгкие анимации и диалоги; не мутирует `story_core`.
- **Редактор встроен в основное Flutter-приложение**, а не отдельная программа: Windows — полный graph/character/scene/timeline workbench; Android — компактные экраны редактирования. Обязательных ручных правок для обычного пользователя нет.
- Подключаемый через API ИИ должен уметь вести естественный диалог с NPC, понимать свободно сформулированные действия/осмотр/взаимодействия и при этом не обходить факты книги, знания NPC и правила игрового мира. Офлайн-классический режим обязательно сохраняется.

## 2. Аудит: что уже есть в main и почему нельзя дублировать

| Код / функция | Состояние на просмотренном main | Решение |
|---|---|---|
| `apps/story_reader/lib/ai_connection.dart` | BYOK Z.ai `glm-4.7-flash`, opt-in OFF by default, `FlutterSecureStorage` для ключа, HTTPS allowlisted endpoint, no redirect/no request logs | Переиспользовать для нового провайдерского адаптера; не изобретать новую небезопасную сеть/хранилище |
| `zai_gameplay_choice_advisor.dart` | По каждому отдельному согласию отправляет только ввод игрока и метки доступных видимых действий, получает `{"choice_id": id|null}` и валидирует; max 3 attempts для разрешённых ошибок | Сохранить как `intent -> allowed-choice`; это **ещё не генератор реплик NPC** |
| `free_text_action_gate.dart` | Offline token overlap, `previewAiChoice`, validation fresh campaign/scene/revision/fingerprint и enabled choice | Критическая защита для свободного "Сделать". Не добавлять альтернативный прямой writer `story_core` |
| `free_text_world_gateway_port.dart` + `FreeTextActionPanel` | Предложение -> отдельное подтверждение -> действующий `WorldLibraryGateway.choose` -> проверенный SQLite коммит | Сохранить; новая вкладка "Сказать" должна быть отдельна от транзакционных выборов |
| `npc_knowledge_rulebook.dart`, `npc_knowledge_world_bridge.dart` | Review/approval-based `learn_fact` и actor IDs с источниковой привязкой; raw note text не отправляется в облако | Использовать для разграничения знаний NPC; не отождествлять `mention_group_id` с `world_actor_id` без редакторской сверки |
| `scene_dialogue_stage.dart` | Атрибутированные, последовательные реплики и локальная позиция чтения; пока нет стабильного `npc_id`/`turn_id` в runtime-contract | Согласовать spoken-turn ID / persona и UI callback; не перебирать авторов по именам |
| `WorldGameView`, `story_core`, `story_engine`, `campaign_manager` | Единственный авторитет игрового state, replay, bounded choices, event+hash, SQLite | Нельзя передавать ИИ право напрямую менять scene/flags/items/facts/journal |
| `narrative_book_model.dart`, `source_character_dossiers.dart` | События, подтверждения, source provenance, группировка упоминаний, неопределённости | Перенести **проверенные** данные в NPC profile/context; не отправлять в prompt всю книгу |

**Не путать:** утверждённые `npc_knowledge` правила и реально подтверждённые NPC знание/состояние — разные этапы. Не приписывать каждому персонажу автоматически все сведения из оригинала.

## 3. Зафиксированный список чужих проектов — внедрение vs идеи

| Проект / официальный источник | Что конкретно берём | Статус интеграции / ограничения |
|---|---|---|
| **Twine, Inky, Arcweave** (https://github.com/klembot/twinejs ; https://github.com/inkle/inky ; https://docs.arcweave.com/) | UX сценарного графа, source links, разветвления и playtest, отделение library components | Только **идеи**. Не копировать GPL Twine/коммерческую платформу; не заменять свой game engine |
| **Yarn Spinner** (https://www.yarnspinner.dev/editor/) | Stable `line_id`, `speaker_id`, conditions, dialogue preview, interactive branch tests | Идеи контракта/редактора, НЕ встраивать чужой runtime |
| **Dialogic 2** (https://github.com/dialogic-godot/dialogic) | Timeline "say -> emotion -> gesture -> visible choice", изоляция dialogue editor | Идеи; Godot не подключать. Repo MIT, но код не переносить без отдельного review |
| **Mermaid** (https://github.com/mermaid-js/mermaid) | Экспорт `book_graph`/scene/choice map в текстовые `.mmd` для GitHub/debug | Использовать как **необязательный формат экспорта**, без JS runtime в APK; MIT |
| **vyuh_node_flow** (https://pub.dev/packages/vyuh_node_flow) | Встроенный Flutter graph editor: ports/edges, pan/zoom, minimap, groups, JSON serialization, custom nodes | **Первый кандидат** после spike и сравнения. 0.32.0 (проверено 2026-11-06), MIT; Flutter Android+Windows, есть mobx/flutter_mobx/http зависимости. В main НЕ добавлен |
| **node_flow** (https://pub.dev/packages/node_flow) | Более лёгкий Flutter node editor: nodes/edges/ports/zoom, только Flutter SDK | **Запасной кандидат** после сравнительного spike; не ставить одновременно с vyuh. Отдельно проверить persistence/undo/redo |
| **PixelForge** (https://github.com/KodoRe/pixel-forge) | JSON sprite spec, reusable procedural generator, seed/palette, shape/layer/animation | **Изучать алгоритмы**, сделать собственную Dart-версию. Repo JS, не нужный Flutter runtime. В metadata GitHub license не объявлен, хотя README говорит MIT: перед переносом кода проверить реальные лицензионные файлы/авторство |
| **Sprite Forge** (https://github.com/paperhurts/sprite-forge) | Послойная детерминированная внешность героя, одежда/аксессуары/эмоции | **Изучать идеи**, рисовать самостоятельно в Dart; в GitHub metadata лицензия не указана, README заявляет MIT, не копировать код без проверки |
| **pixel-sprite-generator** (https://github.com/zfedoran/pixel-sprite-generator) | Пиксельные маски/симметрия/seed для небольших объектов | Малый алгоритм-кандидат, MIT LICENSE; включать только при реальной необходимости и с attribution |
| **Flutter Canvas / CustomPainter** (https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) | Основной процедурный pixel renderer без PNG/сетевых изображений | **Выбранный стартовый renderer**: Flutter SDK уже есть |
| **Flame** (https://docs.flame-engine.org/latest/) | Camera/components/effects и игровой tick для более сложных анимаций | **Резерв**, после профилирования Canvas на Windows/Android, не второй gameplay engine |
| **AI Dungeon** (https://help.aidungeon.com/new-player-guide ; https://help.aidungeon.com/faq/the-memory-system) | UX "Say / Do / Story" и world/story cards + summaries, выбор релевантного контекста | **Идеи UX и локальной памяти**. Не копировать коммерческий сервис, не брать AI Dungeon image generation |
| **Convai Narrative Design** (https://docs.convai.com/api-docs/convai-playground/character-customization/narrative-design) | Узлы-секции с NPC objective, решениями и точными triggers; гибкий разговор в рамках сюжетного графа | **Ключевой ориентир для диалогового редактора**, но не встраивать Convai cloud/SDK/voice вместо BYOK |
| **AI Town** (https://github.com/a16z-infra/ai-town ; https://github.com/a16z-infra/ai-town/blob/main/ARCHITECTURE.md) | NPC persona, relevant memory retrieval, conversation logs отдельно от authoritative world state, controlled game inputs | **Ключевой архитектурный ориентир**; MIT, но Convex/TS/PixiJS/спрайты не подходят для нашего Flutter+кодовой графики |
| **Rasa CALM** (https://rasa.com/calm) | "LLM понимает свободный язык -> flow/rules принимают решение", repair/clarification flow | **Ключевой шаблон правил**, не внедрять платформу Rasa или серверную бизнес-инфраструктуру |
| **chasm** (https://github.com/chasmlol/chasm) | NPC viewpoint "что видел", разрешённый каталог действий, частный NPC journal | **Только экспериментальный ориентир**: автор сам указывает экспериментальность; repo GitHub metadata без licence, код не копировать |
| **LangGraph** (https://docs.langchain.com/oss/python/langgraph/overview) | Понимание checkpoints/HITL/interrupt в длительном multi-step AI workflow | Архитектурные идеи, **не добавлять зависимость**: у внешнего генератора уже есть checkpoints |
| **Natasha** (https://github.com/natasha/natasha) | Предварительное выделение русских имён/сущностей | Опциональный локальный extractor; не заменяет смысловую/литературную проверку. BookNLP (английский) не обязательный |

**Выбранный минимальный набор для старта:** существующие Python/Dart модули; Mermaid export; Flutter CustomPainter; позже **ровно один** node editor по spike; НИКАКОГО нового игрового runtime/JS/Convex/Rasa/Godot/Convai SDK. Если копируется исходный MIT-код, сохранить правообладателей и лицензии, проверить transitive dependencies. AI-образы, готовые PNG/tile assets, генерация изображений — запрещены как обязательный способ процедурных сцен.

## 4. Режимы взаимодействия — независимы от сюжета и оформления

Три независимые оси, не смешивать:

1. **Режим сюжета:** канон / изменённая судьба / в перспективе отдельная экспериментальная импровизация (только при явно определённых правилах; нельзя выдавать за CANON).
2. **Взаимодействие:** `CLASSIC_OFFLINE` (кнопки и текущий offline free-text matcher), `AI_ASSISTED` (ИИ подбирает существующие разрешённые действия), `AI_CONVERSATION` (живые свободные реплики NPC + assistive action matching). Это UX-названия, не существующие enum значения в `.bworld v3`.
3. **Визуализация:** `text` / `pixels_static` / `pixels_animated`, все на том же подтверждённом game state.

Переключение UX не меняет сценарные идентификаторы, эффекты, ревизию, предметы и игровое сохранение. Облачная функция отключена по умолчанию; без интернета остаётся офлайн-игра и детерминированные действия.

## 5. Где разрешён свободный ввод

`SAY`: выбрать присутствующего, **проверенного** `npc_id`, задать вопрос/ответить/пошутить/уговорить; ИИ генерирует **только текст реплики** и мягкие `emotion/gesture` из allowlist. Отказ/незнание возможны. Реакция NPC — не обещание автоматически выполненной механики.

`DO`: "Осмотрю берег", "Попробую открыть дверь", "Подниму мяч" — local lexical matcher либо согласованный API `intent` resolver выбирает **только существующий видимый разрешённый choice_id**; затем user-confirm, `WorldLibraryGateway.choose` и post-commit animation. Если choice нет: безопасный ответ "сценарий пока не предусматривает", возможно harmless observation/talk, НЕ выдуманный эффект.

`LOOK`: текстовое описание наблюдаемой сцены/объекта **только из доступных персонажу и читателю фактов**; может быть детерминированная offline projection, ИИ добавляет стиль, но не новые hidden facts. При отсутствии source evidence "Не удалось осмотреть".

`INTERACT`: социальное действие, просьба, торговля, обещание, убеждение, помощь — natural language -> typed proposal на *already authorized* choice/action templates; NPC произносит гибкую реакцию, но flag/item/fact меняется ТОЛЬКО после подтверждённого перехода. Свободный ввод не создаёт секретные предметы, места, сцены или обход условий.

`STORY/IMPROVISE` (ПОЗЖЕ, экспериментально): если пользователь хочет "придумать неожиданный ход, которого нет в графе", это отдельный sandbox/reviewed branching mode с явной пометкой game fiction и новой проверкой сценария. Не выдавать за поддерживаемый текущим `.bworld v3`; не писать LLM reply напрямую в SQLite.

Реплики могут существовать **между сюжетными узлами** (как Conversation Loops), но сюжетный переход совершает только поддержанный choice. Граф хранит "якорные" обязательные события и доказанную хронологию, свободная речь их не отменяет.

## 6. NPC: Character Card + подтверждённое знание + личная память

**Генератор заранее выпускает (будущие схемы, НЕ реализовано):**

- `npc_profile_v1`: `character_id`, reviewed dossier/source IDs, `world_actor_id` только при подтверждённой identity mapping, persona/речевой стиль (source-supported vs `EXPLICIT_ADAPTATION`), цели/мотивация, отношения, seed внешности, `known_facts_by_scene`, `forbidden_spoilers`, `citations`.
- `npc_conversation_policy_v1`: scene+NPC allowed topics, talkable? distance/visibility/state predicates, current motivation, `allowed_action_ids`, review of possible promises, tone and expressive cue IDs.
- `scene_interactions_v1`: which NPC or object exists, `SAY/LOOK/DO/INTERACT` affordances, source-backed labels, map to established `choice_id`, coverage/TEXT_ONLY.
- `npc_memory_v1` for **private, campaign-scoped** conversational history: actual player utterance, NPC reply, who heard, source kind `PLAYER_CLAIM` vs `CONFIRMED_WORLD_EVENT`, per-revision; bounded window and user-clear control. AI summary is a *note/belief*, NOT an established world fact.
- `ai_interaction_contract_v1`: response schema and validator, source/world/scene/revision hashes; no executable code.

**Context firewall при разговоре:**
- Current scene + *only currently visible* NPC and valid current status.
- NPC knows only explicitly approved rules + witnessed confirmed events **that this NPC could perceive**; not the whole book or player-only facts.
- Player utterances are untrusted reports, never magically `learn_fact`; permanent knowledge only via existing approved rules/events.
- Private memory per campaign and actor, filtered by knowledge/chronology, not global common notebook. Clear/revoke API consent also stops sending memory; include delete-memory action.
- No prompt with future story, unrevealed characters, inaccessible source quotes or saved SQLite blob. Source excerpts beyond local context require **separate explicit informed consent**; existing free-text consent only covers user's text and visible choice labels. Do NOT silently broaden it.
- Character cannot assert a known spoiler as truth just because model's pretraining suggests it; apply typed fact/forbidden-claim checks and semantic review where available. **No absolute guarantee** for hallucination-free free text: provide safe fallback and clear distinction between improvised speech and canon.
- Control character style, emotion and procedural gestures through finite allowlist; an `emotion` suggestion never changes affection/flags by itself.

## 7. Pipeline одного AI-хода (новая опциональная часть)

```text
Игрок вводит SAY/DO/LOOK/INTERACT
   -> load current immutable verified WorldGameView
   -> target NPC/object existence+visibility+knowledge gate
   -> build privacy-redacted source/world/persona snapshot
   -> show exact API data disclosure + per-request or explicitly configured scoped consent
   -> optional Z.ai provider adapter (BYOK, bounded retries/size/cost/time)
   -> strict JSON typed response parser and consistency gate
     |-> SAY: show bounded NPC reply, UI-only gesture, optional private memory note
     |-> LOOK: observed-facts description, no new game effect
     |-> DO/INTERACT: map to enabled choice, ask player confirmation
   -> re-load fresh head, validate (scene + revision + fingerprint + ID)
   -> existing WorldLibraryGateway.choose -> SQLite commit
   -> commit result changes game panels and THEN triggers visual cue
   -> reopen/branch -> restore confirmed state, no duplicate effect
```

**Не делаем два вида истин:** spoken response/memory — UI/user utterances, `StoryWorld` — authoritative facts/item/scene/flags. ИИ не может писать `learn_fact`, `grant_item`, `set_flag`, `next_scene_id`, `event_hash`. "I promise you a key" — пока всего лишь слова; выдача ключа только после подтверждённого choice with effect. При отказе/устаревшем мире не делать optimistic UI. При сетевой неопределённости не отправлять commit повторно, а перечитать реальный journal.

**Набросок строго типизированного ответа (не внедрён):**

```json
{
  "format": "npc_ai_reply_v1",
  "scene_id": "pond_meeting",
  "npc_id": "frog",
  "revision": 3,
  "kind": "SAY",
  "reply": "Сначала расскажи, что ты собираешься делать.",
  "emotion": "curious",
  "gesture": "turn",
  "proposed_choice_id": null
}
```

Ответ ограничить по длине и ключам, map `npc_id` только из validated live context, `revision`+source ID строго сверять. `reply` — **сгенерированная реплика**, не каноническая цитата и не игровое действие. `proposed_choice_id` разрешён только среди currently enabled choices; игрок видит preview before commit. Для изменения игрового мира такого JSON недостаточно.

## 8. Встроенный редактор игры — дополнительные вкладки

- **Сюжет:** два графа ("книга" source evidence и "игра" choices), переход к цитате, происхождение CANON vs GAME_FICTION, проверка недоступных узлов, выбор редактора graph widget после spike.
- **Персонажи:** appearance recipe (только код), persona/манера речи/цели, подтверждённые identity aliases, статус знания и его источники, что скрыто от NPC, разрешённые темы, ограничения на ответы, карточки памяти кампании.
- **Сцены:** JSON recipe visualized by Canvas, object positions, visible NPC/object interaction hotspots, входные условия, text fallback/coverage.
- **Диалоги и AI:** scripted `turn_id`, свободные вопросы между beats, цель NPC, разрешённые темы/намерения, действительные `choice_id`, шаблон корректного "не знаю", allowlisted emotion/gesture, симулятор тестовых вопросов и spoof attempts.
- **Анимация:** небольшие кодовые timeline cues при `scene_enter`, `dialogue_turn`, `choice_committed`; никакой связи с gameplay commit.
- **Проверка:** literary source links, spoiler/knowledge leakage, 2 branch reachability, stale action, missing facts, privacy preview, exact source/story/world hashes.

Windows — полный рабочий стол, Android — мобильные вкладки/адаптивный просмотр и простая правка. Готовую игру можно запускать без открытия редактора.

## 9. Версионирование и совместимость с `.bworld`

- Действующий `.bworld v3` — **строго 4 entries ZIP**, никаких дополнительных AI policy/visual files и новых полей внутри текущего строгого schema. Нельзя обещать, что `npc_profile_v1` уже импортируется.
- На этапе прототипа sidecars в приватной папке с точными `world_archive_sha256`, `blueprint_sha256`, `story_sha256`, `source_fingerprint`, `npc_policy_sha256`, `renderer_version`; importer rejects mismatch and falls back to current text/offline gameplay.
- Переносимость бесед между устройствами — отдельное решение: исходный `.bwsave` содержит только доказанные события, никакого model reply. Временная память отдельно, с clear/export/privacy и привязкой к campaign/world; перенос только после отдельного согласованного контрактного расширения.
- Skill downloads **pinned tested generator** only; не выполняет prompt-generated code; APIs NPC работают на устройстве (или в будущем через отдельный доверенный adapter), а не во время компиляции книги.
- Генерация NPC карточек на основе source graph возможна и в offline Python project. Живая генерация произвольных ответов требует доступного API/локального языкового model, и **не заменяется** offline keyword matching.

## 10. Проверки при реализации (не выдавать за выполненные)

**Сценарий и персонажи:** другой NPC не знает чужого секрета; NPC знает факт только после approved `learn_fact`/witness; не помнит фразу другого игрока/кампании; не "угадывает" будущие места по source text.

**Действия:** unknown action -> no state write; enabled matching action -> preview -> confirm -> one commit; denied/stale/duplicate -> zero commits/repeat animations; player phrase "дай ключ" не порождает ключ без valid rule, даже если NPC согласился словами.

**Диалоги/свобода:** one-vs-two speaker, correct target, user interruptions, 429/5xx/cancel/timeouts, max length, no dangerous/unbounded retries, deterministic fallback, Android keyboard and tiny screen, non-blocking dialogue stage, spoken replies don't skip choice gate.

**Приватность:** API off by default, exact payload preview, key OS vault, no hidden source/chapter/SQLite/whole book upload, user-approved bounded context only, separate revocation/forget conversation, no retries after cancellation, no storage of keys/responses in plaintext logs.

**Формат:** Python+future Dart validators strict, hashes & IDs; old v3/bwsave unchanged; no JS/eval/dynamic code, no cloud requirement for scenes/rendering, optional sidecar wrong hash -> text mode.

**E2E:** test real GLM with synthetic story + two distinct real FB2 privately; sequential NPC questions, secret-before/after, social attempt, look at scene, gesture, save/restart on Windows/Android; collect measurable latency/memory/cost. NO E2E claims until actual tests.

## 11. Реализация короткими этапами

**P0:** завершить уже запланированное E6e/полный литературный E2E без визуального блока; сохранить имеющиеся `FreeTextActionGate` и Z.ai-инфраструктуру.

**P1a:** в `tools/rpg_author/` согласовать `npc_profile_v1`, `scene_interactions_v1`, source-linked knowledge gates, privacy/response schema, synthetic data + отрицательные tests; отдельно закладывать совместимость с renderer recipe.

**P1b:** после **нового явного разрешения** на `apps/packages`: встроенный `NPCConversationController` c `SAY` без gameplay effects, persona + gated knowledge + exact-contents consent, cancellation, memory separation и tests.

**P1c:** `LOOK/DO/INTERACT` через existing matcher/gateway, established choices only; voice optional long-term, no new engine. `SAY` emotions -> procedural cue after validation; `choice_committed` -> visual-only transition.

**P2:** встроенный Flutter editor + 2 independent graph views + NPC/scene/AI dialog policies + pixel preview; выбрать `vyuh_node_flow` vs `node_flow` по реальному Windows/Android spike на 100/500/1000 узлах; подключить Flame только при необходимости.

**P3 (опционально):** separate experimental reviewed sandbox world-actions/quests/LLM-directed branch generation с полным compile/reachability/literary re-audit до применения. Это НЕ входит в текущий v3 и не должно задерживать первую полноценную книгу.

## 12. Неподвижная граница работ

Текущая ветка внешнего генератора может изменять только `tools/rpg_author/`, его схемы/тесты и собственную документацию. `main`, `apps/`, `packages/`, `tools/bookworld/`, основной CI и пользовательские сохранения — READ-ONLY до отдельного разрешения. Новые UI и runtime здесь **описаны**, не реализованы. Не трогать PIN навыка E6d без проверки кода.

Связанные документы:
- `MASTER_BOOK_GRAPH_PROCEDURAL_PIXEL_PLAN_RU_2026-11-06.md` — единая архитектура книги/визуализации.
- `PROCEDURAL_PIXEL_SCENES_RU.md` — CODE-ONLY графика.
- `E6F_VISUAL_RUNTIME_COMPATIBILITY_RU_2026-11-06.md` — совместимость игрового движка.
