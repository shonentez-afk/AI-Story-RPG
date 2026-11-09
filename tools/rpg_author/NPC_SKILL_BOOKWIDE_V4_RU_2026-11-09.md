## ПРИНЯТО: единый ChatGPT Skill NPC Social v5 / многоактовый v4

**Рабочий код:** `1f154a0eda9d046b7f355d4399f2b79cb2a3e2d3` (0.3.0a13).
**GitHub Actions #42554315131:** https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554315131 — **COMPLETED SUCCESS** на этом SHA: 171 основных и 37 дополнительных Python тестов, Dart parity SUCCESS.

В одном пакете `author-book` навык ChatGPT создаёт source-locked `npc_dossiers`, из точных SOURCE_PASSAGE / NARRATED свидетельств формирует постоянные `character_id` без вымышленных хешей, затем готовит подтверждённый `npc_review` (знания, память, отношения, NPC Social v5), направляет их в `enrichment` и межактовый `v4_acts_v2`. При наличии отдельно подтверждённой цепочки разговоров/вещей поддерживает `v4_acts_v3`. Результат проверяется **существующими** native BookWorld, Dart `LocalRpgGameApi` и SQLite; отдельного игрового движка или внешнего ИИ API нет.

В CI: оригинальная синтетическая 3-главная FB2 → source-derived NPC `character_id` → native v3 review → native v4 → Dart importer/API → NPC memory/knowledge + portable SQLite save. Маркер проверки `native_skill_source_bound_npc_v4_dart_replay=true`. Сохранены прежние rich-v3/v4 и диалоговые регрессии, 203 сцены, native item custody, две законченные концовки и SQLite.

**Границы:** этот результат не подтверждает литературное качество на реальной книге, автоматическое создание полного многоактного v3 диалога/передачи предмета навыком для разных произведений, полное покрытие любых длинных романов и реальное Windows/Android E2E. Инсталлированный Skill E6d не заменяется автоматически; новый skill.zip только подготавливается для установки. Исходники пользователя в репозиторий/CI не попадали. Изменения только `tools/rpg_author` и `tests/rpg_author`; ни `main`, ни PR #133, ни native/Flutter не тронуты.

**Следующий крупный блок без микро-PR:** полные AI-авторские NPC диалоги и предметные отношения v3 из двух настоящих приватных FB2 + литературный аудит всей книги и общая приёмка через Windows/Android.

---

# Единое авторство NPC, диалогов и последствия решений из книги

Дата: 9 ноября 2026. **ПРИНЯТО: версия 0.3.0a13 на коде
`1f154a0eda9d046b7f355d4399f2b79cb2a3e2d3`; общий CI #42554315131,
171 основных + 37 дополнительных Python, Dart parity SUCCESS.**

## Один пакет, не микро-PR

Пользователь передаёт FB2/TXT через навык ChatGPT. После подтверждения
каждого исходного утверждения Skill сама авторит два новых
литературных слоя и использует их в уже существующем
`enrichment` / `extension` / `literary_review`.

### 1. NPC-досье до обогащения RPG

Skill ответ `npc_dossiers.json` с полями
`characters:[{ref,name,description,source_scene_id,assertion_id}],
absence_reason`. Для каждого настоящего NPC обязательна
точная NARRATED цитата из ORIGINAL SOURCE_PASSAGE и упоминание
имени в этой цитате. Программа вычисляет actor_id
`npc_` + первые 32 hex SHA256 от canonical
`{source_fingerprint,npc_ref,identity_assertion}`; AI не задаёт
actor_id и не выбирает фальшивый SHA. На повторном запуске
сохраняется источник и проверяется неизменность ID/цитаты.
Отсутствие NPC допустимо только с развёрнутым объяснением,
но не подтверждает объективное отсутствие NPC в книге.

Результат `WORKDIR/npc_dossiers.json` передаёт ID в
следующее задание `enrichment`, так что `learn_fact` и
`knows_fact` могут иметь реального адресата.

### 2. Авторство NPC Social v5 по событиям книги

Skill создаёт `npc_review` по формату
`rpg_author_skill_npc_review_v1`: knowledge_grants,
witnesses, rules, choice_gates, item_grants, item_transfers,
life_transitions и dialogue_knowledge. Каждая исходная
запись имеет `scene_id,assertion_id` из актуальной книги;
Python проверяет наличие самого события в этой сцене,
тип NARRATED для очевидцев, исходную видимость и хеш цитаты,
который вычисляет **сама** программа. Выдуманный ID/событие
и ссылку на будущую главу программа отклонит.

Сформированный `WORKDIR/npc_review.json` — строго v3
`rpg_author_reviewed_npc_overlay_v1` с native
`ai_story_npc_knowledge_grants_v1` и
`ai_story_npc_social_witness_v5`. Его настоящую схему и
эффекты проверяют прежние `rich._npc_social`,
`rich._npc_knowledge` и `RichPrivateBookworldImporter`.
Для существующих отдельно утверждённых карт NPC
`--npc-review` продолжает работать без изменения ID.

### 3. Многоактовые NPC и подписанные диалоги

Если NPC есть, ответ этапа `extension` должен содержать
`npc_actor_review` с источником для межактовых знаний,
памяти, доверия, NPC-встреч и life transitions.
На этом основании автоматически выбирается
`rpg_author_v4_acts_v2`. При **действительных**
сценах с подписанным разговором и историей получения и
передачи предмета может быть предложен также
`npc_scene_review` → `rpg_author_v4_acts_v3`.
Все digest base NPC Social и knowledge и digest полного
NPC actor review вычисляются внутри Python после компиляции
базы — ChatGPT их не придумывает. Существующий движок
запрещает раскрывать будущие знания в NPC-репликах,
требует реального владельца предмета и проверяет
достижимость игры и сохранение после импорта.

Окончательное `finalize-extended` по-прежнему проверяет
настоящие два пути через LocalRpgGameApi и SQLite.
Приватные исходники и ответы не публикуются в Actions.

## Границы готовности

- Нет автоматического создания портретных изображений.
- Нет независимой литературной сертификации истинности
  книг/канона; approval — декларация владельца, не доказательство.
- Нет полного E2E на двух реальных личных FB2/Win/Android.
- Слишком большая книга или сложная NPC история могут быть
  отвергнуты неизменными нативными лимитами.
- Тесты на синтетическом оригинальном FB2 только технические.
