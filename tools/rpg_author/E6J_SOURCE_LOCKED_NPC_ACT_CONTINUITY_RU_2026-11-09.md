# E6j — verified cross-act NPC knowledge / memory / trust authoring

Версия: 0.3.0a9. Только внешний инструментарий tools/rpg_author и
tests/rpg_author; main, PR #133, Flutter, packages, native CI read-only.

## Новый строгий и явно выбираемый формат

`rpg_author_v4_acts_v2` сохраняет ВСЕ поля старого E6i
`rpg_author_v4_acts_v1` и добавляет поле `npc_actor_review`.
Его формат `rpg_author_v4_npc_act_review_v1`.
Остальные v3/E6h/E6i входы остаются неизменными.

Входная база обязана иметь полностью принятый `--npc-review`
со стабильным `npc_<32hex>` actor_id, `npc_knowledge` v1 и
`npc_social` v5. Новый reviewer заблокирован на exact SHA-256
старых `npc_knowledge` и `npc_social`: подмена истории невозможна.
Имеются поля `format`, `source_fingerprint`,
`base_npc_knowledge_sha256`, `base_npc_social_sha256`,
`user_confirmed=true`, `literary_canon_verified=false`,
`knowledge_grants`, `witnesses`, `memories`, `choice_gates`,
`life_transitions`.

- `knowledge_grants`: scene_id, choice_id, actor_id, fact_id,
  assertion_id; должен существовать единственный соответствующий
  `learn_fact` в точно выбранном ходе. actor и fact уже в catalog.
- `witnesses`: scene_id, actor_id, mode (`present`/`reported`),
  assertion_id; source-пассаж должен быть видим к данному акту.
- `memories`: scene_id, choice_id, observer_id, memory_id, kind,
  related_actor_id, relationship_delta, max_triggers, assertion_id;
  только отмеченная встреча создаёт память, `reported` не даёт
  позитивного доверия или личного воспоминания.
- `choice_gates`: scene_id, choice_id, actor_id,
  required_memory_id, minimum_trust_to_player, assertion_id;
  положительная память должна быть приобретена в РАНЕЕ пройденном
  акте и у конкретного NPC, нельзя ссылаться на будущее или себя.
- `life_transitions`: scene_id, choice_id, actor_id, next_state
  (`present`/`absent`/`dead`), assertion_id; присутствие NPC
  обязательно подтверждено цитатой и конкретным действием.

Во все native payload review вставляется SHA-256 цитаты,
рассчитанный генератором из ранее проверенного индекса книги,
а не переданный на доверии от ИИ. E6j не симулирует trust,
knowledge, NPC life, replay: финальный автор — штатный native
`packages/story_authoring/bin/author_book.dart`. Для клиента
проверяется настоящий `LocalRpgGameApi` через отдельный Dart probe.

## Пример команд

python3 -m tools.rpg_author doctor
python3 -m tools.rpg_author audit-extended --project /private/project --enrichment /private/overlay.json --npc-review /private/npc_base_review.json --extension /private/npc_acts_v2.json
python3 -m tools.rpg_author build-extended --project /private/project --enrichment /private/overlay.json --npc-review /private/npc_base_review.json --extension /private/npc_acts_v2.json --output /private/game_v4.bworld
python3 -m tools.rpg_author verify-extended --input /private/game_v4.bworld --attribution /private/game_v4.attribution.json

## Приёмка, границы и следующая задача

Новый QA: 3 главы оригинального тестового FB2, NPC с одним actor_id,
действие изучения опасности в акте 1, подписанная NPC память
с приростом доверия, в акте 2 закрытое без доверия решение,
открытое после события, уход NPC и импорт .bwsave.
Python негативные случаи: чужой grant, подмена hash, недостоверное
свидетельство, не заработанная память, повторная память,
воскрешение без контракта. Exact-code CI после этого коммита
требуется перед объявлением успешной приёмки.

Формат пока не создаёт новые NPC character_id, диалоговые реплики
с портретами или предметные передачи из ничего. Для последних
нужен отдельный witness/ownership review на нативный v5.
Это механическая проверка вымышленного публичного текста, а не
полноценная адаптация настоящей книги или подтверждение канона.
Реальные две RU FB2, GLM, Android/Windows device E2E ещё не пройдены.

## E6j — окончательная интеграционная приёмка (9 ноября 2026)

**Кодовый SHA:** f087dbb7dac2f85f86b050c38bece1f23be7bd9b.
**Actions:** https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42542369127 —
**COMPLETED SUCCESS**, обе job `author-tests` и `dart-parity`.
Python: 141 unit tests PASS + 37 дополнительных PASS.
Dart parity: native_v4_npc_actor_scoped_cross_act_grants_verified=true,
native_v4_npc_social_memory_trust_and_life_replayed=true,
native_v4_npc_public_api_choice_gates_and_saves=true.
Доказано: отдельный `rpg_author_v4_acts_v2` компилируется настоящим
source-locked Dart v4; NPC получает факт и память о помощи; закрытый
NPC-gated выбор другого акта не раскрывается без события и открывается
после него; `LocalRpgGameApi` / SQLite сохраняют и импортируют исход.
Старые E6g/E6h/E6i регрессии (v3, 203 scenes, NPC Social v5) — PASS.

**Пин движка:** 081fc365efac030be25d8b75aca0ba305a6bcc6c.
На момент записи родственный PR #133 продвинулся до
e3daf03d81cb8a5612a4883e18ea9754beab807f: 5 коммитов,
ни одного изменения среди 27 закреплённых blob-файлов; никакие
хеши контракта не обновлялись и основной PR не изменён.

**Ограничения:** фикстура на оригинальном синтетическом FB2 (3 главы),
а не две реальные книги. Сами источник и пользовательский review
не удостоверяют смысл литературной интерпретации и живой канон.
Не реализовано новое авторство NPC character_id, NPC dialogue
с проверенной расстановкой говорящих и портретами; перенос
владения предметами между NPC в новых актах и физические испытания
Android/Windows остаются отдельными задачами. Установленный
skill ChatGPT всё ещё E6d и сам не обновлялся.

**Следующий цельный функциональный этап E6k:** NPC-диалоги,
предметное владение/передачи между актами с точными source
witnesses, проверка в публичном API и потом двух реальных книг.
