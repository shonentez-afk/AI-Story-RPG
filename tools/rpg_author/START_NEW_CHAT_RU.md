## E6j 0.3.0a9: actor-scoped NPC continuity across reviewed v4 acts

9 ноября 2026: внешний генератор, не основной движок.
Новый опциональный контракт rpg_author_v4_acts_v2 +
rpg_author_v4_npc_act_review_v1 связывает знания NPC, доказанные
встречи, воспоминания, доверие, выборы другого акта и уход персонажа
с точной редакцией FB2, текущими scene/choice IDs и цитатами.
Невозможно выдать NPC факт, создать память или доверие без
отдельной user-confirmed source-bound проверки. Нельзя менять
actor_id, симулировать социальный движок на Python или приписывать
подтверждённый литературный канон.

Доказательная CI-фикстура: оригинальная синтетическая FB2 на 3 главы,
2 акта, NPC с постоянным character_id, 3 маршрута. Проверки через
настоящий native Dart v4 и публичный rpg_api, включая закрытый выбор
без ранее заработанного доверия, NPC memory/life и SQLite .bwsave.
**E6j ПРИНЯТ по exact-code:** SHA f087dbb7dac2f85f86b050c38bece1f23be7bd9b, [CI #42542369127](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42542369127) COMPLETED SUCCESS: author-tests SUCCESS (141 Python tests + 37 supplemental OK), dart-parity SUCCESS. Реальный Dart v4 и публичный rpg_api подтвердили NPC actor-scoped fact grant, память и доверие между актами, отказ в выборе без памяти, последующий доступ, уход NPC, portable SQLite save/replay. Синтетическая 3-главная FB2, не литературный реальный роман.
Не изменять main, PR #133, packages, apps или основной CI.
Проверенная предыдущая база E6i: 96d4cfa; синхронизация native
pin 081fc365. Установленный skill ChatGPT по-прежнему E6d.

Раздел E6j: E6J_SOURCE_LOCKED_NPC_ACT_CONTINUITY_RU_2026-11-09.md.

---
## E6i accepted native-head integration (exact code)

2026-11-09. External author generator version 0.3.0a8.
ACCEPTED CODE SHA: 96d4cfac79586bfb58f2302ed5192a830fac2ab9
NATIVE PR #133 PIN: 081fc365efac030be25d8b75aca0ba305a6bcc6c (Draft, not merged).
CI: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42540898271
COMPLETED SUCCESS: author-tests SUCCESS, dart-parity SUCCESS.
Python unit acceptance: 135 tests OK plus 37 supplemental tests OK.
Actual Dart parity log includes native_v4_three_chapter_two_act_branching_verified=true
and native_v4_stateful_knowledge_gate_and_save_replayed=true;
legacy v3 and v4 E6h 203-scene and NPC-social regression also all PASS.
Upstream contract: 27 exact git blobs; 24 unchanged; 3 reviewed and pinned.
External changes preserve engine as single native API, no Python game-rule fork.
Existing ChatGPT skill still E6d, NOT updated by this branch.

LIMITS: Original synthetic FB2 only (3 chapters, 2 acts and 3 paths).
No independently verified full literary two-book authoring, no tested private
RU FB2 on devices, no new authored NPC actor knowledge/social witness.
Do not claim literary canon or book-to-game product readiness.
Next functional block: source-verified NPC continuity/actor-scoped grants
and real multi-chapter literary editorial testing, avoiding micro-PRs.

---
## E6i синхронизирован с native PR #133 (081fc36)

Разрешён только внешний генератор: base native точный SHA 081fc365efac030be25d8b75aca0ba305a6bcc6c; все 27 pinned Git blob SHA-1 сверены, 24 совпали, 3 намеренно изменены после проверки диффа: world_library_gateway.dart теперь использует публичный rpg_api; story_authoring/src/authoring_engine.dart имеет неизменяющий правила getter sourceFingerprint; story_authoring.dart только публикует новые workflow exports. Ни один core/BookWorld/compiler/SQLite rule не менялся. Из внешнего E6i перенесены только tools/rpg_author и tests/rpg_author. Native PR #133 остаётся Draft, main не меняем.

**Текущая CI после merge ожидает приёмки**; старый успешно проверенный E6i SHA ea9e8f0 имеет Python + Dart SUCCESS, но это доказательство старой зависимости. Точный новый merge SHA и результаты необходимо зафиксировать после полного CI. Не объявлять USER_READY, не подменять литературную/Windows/Android проверку и не обновлять установленный ChatGPT skill (он pinned E6d).

Документ: E6I_NATIVE_PR133_HEAD_SYNC_RU_2026-11-09.md.

---

## E6i 0.3.0a8 - источник/событие/выбор/причинность v4

Внешний генератор получил отдельный контракт rpg_author_v4_acts_v1: акты по главам, уникальные события и доказательные цитаты, настоящие альтернативы, эффекты для предметов, знаний, флагов, характеристик и времени. Только штатный Dart проверяет исполнимость, Python не копирует механики. Новые NPC-grants запрещены без отдельного проверенного reviewer-контракта. Старая версия E6h поддерживается. Новый тест: 3 главы оригинального синтетического FB2, 2 акта, 3 маршрута, SQLite replay/save. Этот код ещё требует exact SHA Python + Dart CI; НЕ ОБЪЯВЛЯТЬ СДАННЫМ до успешной приёмки. main, PR #133 и packages не изменять. Установленный ChatGPT skill остаётся pinned E6d.

Подробности: E6I_MULTI_ACT_STORY_EVENTS_RU_2026-11-09.md.

---

# E6h 0.3.0a7 — внешняя ветка, source-locked v4 расширение (9 ноября 2026)

**Новый функциональный пакет:** `tools/rpg_author/v4_expansion.py`,
`build-extended --extension`, `audit-extended`, 203+ сцены,
редакторское подтверждение начального состояния v4, реальные
Python и Dart/SQLite контракты. Подробности:
[E6H_V4_SOURCE_LOCKED_EXPANSION_RU_2026-11-09.md](E6H_V4_SOURCE_LOCKED_EXPANSION_RU_2026-11-09.md).
Новый `audit-extended` — только preflight; готовность литературы
не заявляется. Новый native PR #133 продвинулся по сравнению с
закреплённым SHA `233c6c3`; контракт не обновлять вслепую.
Никаких изменений `apps/`, `packages/`, `main`, `tools/bookworld/`.
**E6h CI ПРИНЯТ:** [External RPG author tests #42516846711](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42516846711), проверенный код SHA c4334298c3e3eb5b512a73631d6c11281d0a1cba — оба job author-tests и dart-parity COMPLETED SUCCESS. Лог Dart подтверждает 203 source-locked сцены, обе завершённые ветви, native v4 компиляцию/импорт и проверенный initial item/tick. Это синтетический механический тест, НЕ автоматически написанная длинная литературная игра. Для новой версии PR #133 потребуется отдельная повторная сверка 27 pinned blobs. Встроенный ChatGPT skill остаётся старым
E6d, его pin не изменён.

---

# Актуальное продолжение E6g — синхронизация с PR #133 (8 ноября 2026)

**Ветка:** [feature/external-rpg-author-e6g-pr133-compat-20261108](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6g-pr133-compat-20261108). **Текущая интеграция:** native PR #133 HEAD `233c6c31abeae0768c36a60c4dd3add94916ec03`; E6g merge `8ce1017426c809c677a7c2de8db2c1e1c848a756`, исправление regression expectation `f2caf69ab6c932cbe660c912554e4c74e24130af`. Основной PR остаётся Draft, изменений `main` нет.

- Сопоставлены 27 exact Git blobs; 25 без изменений, изменились только `world_library_gateway.dart` (перенос Flutter/gameplay facade в независимый `rpg_gameplay`) и `story_authoring.dart` (новые экспорты authoring API без удаления старых). Контрактные хэши заменены **после анализа диффа**, защита fail-closed сохранена.
- Все файлы внешнего генератора/тестов E6g перенесены поверх **настоящего HEAD** PR #133 объединяющим коммитом с двумя родителями. Другие native папки не редактировались.
- Первичный [CI #42502499413](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42502499413): Python 120/121 успешны, один тест ожидал исторический baseline `7c4401c`, исправлен без ослабления хеш-проверки. **Итоговая приёмка** [CI #42502540208](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42502540208), exact code SHA `f2caf69ab6c932cbe660c912554e4c74e24130af`: `author-tests` **COMPLETED SUCCESS** и `dart-parity` **COMPLETED SUCCESS**. Последующие документационные коммиты `[skip ci]` не изменяют этот кодовый pin.
- Аудит и продолжение: [E6G_PR133_HEAD_SYNC_AUDIT_RU_2026-11-08.md](E6G_PR133_HEAD_SYNC_AUDIT_RU_2026-11-08.md). Проверка `doctor` на объединённом дереве прошла; исходная атрибуция E6g native-v4: [E6G_NATIVE_V4_BRIDGE_RU_2026-11-08.md](E6G_NATIVE_V4_BRIDGE_RU_2026-11-08.md).
- Встроенный ChatGPT skill всё ещё старый E6d. Реальный >192 StoryPlan, source-locked initial-state/tick v4, 2 FB2 + device E2E **не сделаны**. Не пересматривать legacy checkpoints, не копировать приватные книги в GitHub, не сливать в `main` до приёмки native PR #133.

---

# AI Story RPG — актуальный handoff E6g, native v4 (8 ноября 2026)

**Текущая версия внешнего генератора:** `0.3.0a6`. **Единственная текущая ветка:** [feature/external-rpg-author-e6g-pr133-compat-20261108](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6g-pr133-compat-20261108). **Native dependency:** рабочий код [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), проверенная база `7c4401c25b77e4643cf23000c28a717cb22dabca`, Draft (последующий PR #133 двигается, требуется актуальная re-pin проверка при интеграции).

**Сначала читать [E6G_NATIVE_V4_BRIDGE_RU_2026-11-08.md](E6G_NATIVE_V4_BRIDGE_RU_2026-11-08.md)**, затем [E6G_PR133_NATIVE_STORY_AUTHORING_COMPATIBILITY_RU_2026-11-08.md](E6G_PR133_NATIVE_STORY_AUTHORING_COMPATIBILITY_RU_2026-11-08.md). **27 точных upstream code blobs** в `compatibility_v2`; `doctor` FAIL-CLOSED при drift. Из E6f перенесены доказанные npc_social v5, rich-v3, author checkpoints, literary/dialogue QA и Python/Dart tests; изменялись исключительно `tools/rpg_author/`, `tests/rpg_author/`.

**Новый реальный CLI (v4 opt-in, v3 по умолчанию):**

```sh
# Требуется установленный Dart SDK; локально разрешить story_authoring заранее.
(cd packages/story_authoring && dart pub get)
python3 -m tools.rpg_author doctor
python3 -m tools.rpg_author build --project /private/project --enrichment /private/enrichment.json --output /private/game_v3.bworld
python3 -m tools.rpg_author build-extended --project /private/project --enrichment /private/enrichment.json --output /private/game_v4.bworld
python3 -m tools.rpg_author verify-extended --input /private/game_v4.bworld --attribution /private/game_v4.attribution.json
```

**Подтверждённое native-v4 доказательство:** [CI #42495808223](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42495808223), code SHA `3c06489798fd74b5281488a935b8210b7661f99a`, оба `author-tests` и `dart-parity` **SUCCESS**: из E6g Python-review → реальный Dart `build-extended` → rich v4 → replay/две концовки → SQLite resume/fork/portable → NPC-social v5 + negative sidecar. **Итоговый E6g 0.3.0a6 [CI #42496185581](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42496185581) — COMPLETE SUCCESS в обоих заданиях**, точный проверенный кодовый SHA `835fda3f6699f853acb3c9d6ded8ef3eb8610df6`. Дополнительно проверены Python-only negative cases и работа приватного TXT через `dart --packages` с неизменным source title. Последующие документационные [skip ci] коммиты не изменяют этот кодовый SHA.

**Ограничения:** v4 **реально выпускается**, но пока только из проверенного E6g StoryPlan старых лимитов (≤192 сцены); нет автономного E6g >192 или initial_state/tick review. Для этого нужен новый source-locked authoring/semantic/cross-act контракт. Не обещать полную книгу только из успешного package-test. Источник, приватные checkpoints, .bworld, цитаты и секреты не публиковать.

**Installed ChatGPT skill пока E6d (0.3.0a2, pinned `9849c22…`)** — обновить его отдельно после проверки нового генератора; обновление README не переподключает установленный skill. Native main/apps/packages/tools/bookworld/CI не изменяли. Не создавать PR в main до приёмки PR #133. Старые E6d/E6f project snapshots сохраняют свои toolchain SHA, их не мигрировать самовольно.

---

## Архив E6g 0.3.0a5 — предыдущая проверенная интеграция

**8 ноября 2026 — теперь E6g 0.3.0a5:** рабочая ветка внешнего автора [feature/external-rpg-author-e6g-pr133-compat-20261108](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6g-pr133-compat-20261108), **основана непосредственно на native [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) кодовом SHA `7c4401c25b77e4643cf23000c28a717cb22dabca`**. Из E6f перенесён внешний Python-автор и его тесты без изменений `main`, `apps/`, `packages/` или native `tools/bookworld/`. Историческая E6f ниже теперь *архив предыдущей реализации*, не текущий pin.

**Читать [E6G_PR133_NATIVE_STORY_AUTHORING_COMPATIBILITY_RU_2026-11-08.md](E6G_PR133_NATIVE_STORY_AUTHORING_COMPATIBILITY_RU_2026-11-08.md) перед дальнейшими действиями.** Зафиксировано 26 blob-level контрактов (новый `compatibility_v2`, `doctor` fail-closed). Dart parity теперь импортирует `package:story_authoring/story_authoring.dart` и зависит от правильного самостоятельного Dart package; прежняя ошибка PR #133 «Couldn't resolve story_authoring» устранена на уровне тестов без копирования исходников. **Только rich-v3 запись через внешний Python-генератор; native v4 — отдельный opt-in и пока не поддержан внешним E6g.**

**Подтверждено CI:** [E6g #42492729690](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42492729690) *COMPLETED SUCCESS* (author-tests + Dart parity) на интеграционном коде до повышения версии. [E6g 0.3.0a5 #42493017684](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42493017684) — точный последний кодовый SHA `3e0d7c6e2124f2dfe4e57b5e31889cc6842cc336`, **COMPLETED SUCCESS — оба job `author-tests` и `dart-parity`**. Считать E6g 0.3.0a5 проверенной на указанном code SHA; это только синтетическая Python↔Dart/SQLite parity, не полный книжный E2E. Любые последующие документационные [skip ci] коммиты не заменяют тестовый SHA.

**Неприкосновенные ограничения:** `tools/rpg_author/`, `tests/rpg_author/` — единственная рабочая область E6g; основной движок read-only, native PR #133 остаётся Draft; не публиковать приватные книги/цитаты/ключи; не сливать в `main` до его приёмки. Старые checkpoint `toolchain_sha256` не переписывать. Установленный навык ChatGPT по-прежнему pinned к E6d 0.3.0a2 и не обновляется автоматически. Цель дальнейшего этапа: реальный 2-книжный литературный E2E, затем отдельно проверенный source-locked native v4 adaptor при необходимости, без фиктивного CANON.

---


## Архив E6f — предыдущая проверенная интеграция

**Дата архива:** 7 ноября 2026. **Историческая ветка внешнего Python автора:** [feature/external-rpg-author-e6f-npc-social-v5-20261107](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6f-npc-social-v5-20261107). E6e и E6d — сохранённая история, **не продолжать их старые base refs как текущий код**.

## 1. Базовая версия и подтверждённая совместимость

- **Главная программа:** main SHA [81fb75b77f11b8f82cafa1e7604afa9fe9bbb678](https://github.com/shonentez-afk/AI-Story-RPG/commit/81fb75b77f11b8f82cafa1e7604afa9fe9bbb678). PR #132 **MERGED**: NPC social v1–v5 (свидетельства, память, доверие, choice gates, выдача/передача предметов, уход/возврат/гибель NPC, signed dialogues, SQLite replay). **.bworld по-прежнему format_version=3 с четырьмя ZIP entries**, npc_social_witness_v5 — расширение, не .bworld v5.
- **Генератор:** версия **0.3.0a4**, проверенный исполняемый SHA **2d6b94e001d7e049af765ebb1ef7469b6b30a8bd**. [Exact-head GitHub Actions #42341605734](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341605734): **author-tests SUCCESS** и **dart-parity SUCCESS**, включая авторский NPC v5 архив, реальный Dart importer, SQLite restart/fork/portable save и предметную передачу с уходом NPC. Коммиты после этого SHA только документация с [skip ci]; не считать их новым отдельным кодовым CI.
- **Проверенная инструкция по E6f:** [E6F_MAIN_NPC_SOCIAL_V5_COMPATIBILITY_RU_2026-11-07.md](E6F_MAIN_NPC_SOCIAL_V5_COMPATIBILITY_RU_2026-11-07.md). Она содержит поля приватного npc_review.json, source-locked правила и команды.
- **Встроенный ChatGPT-навык НЕ обновлялся:** его bootstrap всё ещё прикреплён к E6d SHA 9849c22d18e2761b49766b0c213b4a3fb3fe053b (0.3.0a2). Никаких утверждений, что новое E6f автоматически загружается из установленного навыка. Отдельная процедура обновления только после проверки версии.
- **PR #133** по полной книге и выбору роли был **OPEN DRAFT**, а не принятой частью main при последней проверке. Сверить HEAD перед дальнейшим кодом; только принятый контракт можно сделать новым pin.
- **Граница:** этот чат пишет **только tools/rpg_author и tests/rpg_author** в отдельную feature branch. Из main/apps/packages/tools/bookworld/native CI только читать. Пользовательские FB2, контрольные точки, частные NPC review, авторские цитаты и API ключи **не в public GitHub**.

## 2. Как изменён авторский процесс

Старый полностью player-only E6e путь **не сломан**. Новое **необязательное** входное дополнение --npc-review = приватный source-bound review для стабильных character_id и exact actor-scoped NPC grants + social v1–v5. Authoring source, StoryPlan SHA, enrichment SHA связываются со всеми NPC-данными. Нельзя делать самостоятельный вывод о присутствии, вещах, secret, true-canon, жизни или доверии по нейросетевой реплике.

Новые поддерживаемые пути:

    python3 -m tools.rpg_author doctor
    python3 -m tools.rpg_author build --project /private/project --enrichment /private/enrichment.json --npc-review /private/npc_review.json --output /private/game.bworld
    python3 -m tools.rpg_author verify --input /private/game.bworld --attribution /private/game.attribution.json
    python3 -m tools.rpg_author gameplay-audit --project /private/project --enrichment /private/enrichment.json --npc-review /private/npc_review.json --strict

При закрытии игры с литературным отчётом и диалогами:

    python3 -m tools.rpg_author finalize --project /private/project --enrichment /private/enrichment.json --npc-review /private/npc_review.json --review /private/review.json --output /private/game.bworld --dialogues /private/dialogues.json --question-inventory /private/question_inventory.json

Если интерактивных вопросов **действительно** нет, --no-interactive-questions заменяет последние два аргумента. Не перезаписывать уже собранные файлы, не выводить из слова модели подтверждённый WorldEvent и не объявлять статус USER_READY без реальной книги и реальных устройств.

**РЕШЕНИЕ ПО ГРАФИКЕ СКИНОВ (7 ноября 2026):** пользователь выбрал **тот же программный пиксельный рендерер, что и для сцен**. Никаких генерируемых нейросетью картинок или обязательных PNG/спрайтов для интерфейса: рамки, орнаменты, фактуры, иконки и декоративные части кнопок рисуются из ограниченных JSON Canvas/CustomPainter primitives, с общим StyleBible/seed. **Текст, фокус, доступные кнопки и прокрутка остаются нативными Flutter Widgets**, не пиксельными текстурами. Допускается внутренний кеш вычисленного рисунка в RAM для производительности. Прочитать [PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md, §2.1](PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md) и новую норму [генерального плана, §8.1](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). **Только план, код P2 ещё не внедрён; main и v3 не изменять.**

**Новое решение P2 — индивидуальный скин для каждой книги:** [PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md](PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md). Пользователь просит, чтобы внешний генератор готовил не только пиксельные сцены, но и стилизацию всего игрового интерфейса: окно текста, диалоги, имя говорящего, иконки, меню, кнопки, Герой/Предметы/Журнал, сохранение и финал. Нормативный §8.1 и P2-гейты внесены в [генеральный план](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). Один Style Bible/seed для пикселей и UI, theme data-only, стабильна на книге и доступна для явной регенерации без изменения сейвов. Текущий rich-v3 НЕ расширять (четыре ZIP entries), future vNext + Dart importer/QA только после P0 реальной полной книги. **Сейчас утверждён план, SkinRenderer/ThemePack ещё не реализованы**. Это решение не меняет E6f code pin/CI.

**GitHub research по книжным скинам:** [GITHUB_DYNAMIC_SKIN_SOURCE_REVIEW_RU_2026-11-07.md](GITHUB_DYNAMIC_SKIN_SOURCE_REVIEW_RU_2026-11-07.md) — проверены 11 GitHub-проектов с точными ссылками на реализацию и лицензии. Вывод: game-hud — template+12 skins, Flame — NineTileBox для рамок, Material Color Utilities Dart — контрастные палитры, PixelForge/LovecraftUI — процедурные иконки/фактуры по seeded JSON, BlockUI — accessibility/themes; использовать **архитектурные идеи**, не копировать JavaScript/React/Godot в Flutter. PixelForge (README MIT, LICENSE отсутствует) и BlockUI (root Apache vs packages MIT) требуют отдельной правовой проверки перед копированием. Реализовывать **одним P2 пакетом с пиксельными сценами**, после проверки P0 игры из реальных книг. Скин и формат ещё не реализованы; E6f CI code baseline неизменен.

**Уточнение по шрифтам персонального скина:** в [PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md, §2.2](PER_BOOK_DYNAMIC_SKIN_DESIGN_RU_2026-11-07.md) утверждено разделение текста и декора. Генератор автоматически выбирает по книге читабельный кириллический body/dialogue/UI font и декоративный heading font из небольшого офлайн-каталога предварительно лицензированных OFL семейств (Noto Serif, Noto Sans, Cormorant Garamond, Russo One, Pixelify Sans). **Без сгенерированных картинок букв и без новых font-файлов на каждую книгу**; разрешены программные пиксельные буквицы и оформление заголовков. Flutter сохраняет Text/RichText, font scale, доступность, русскую локализацию и fallback. Установленный в приложении каталог и schema vNext ещё НЕ реализованы, main/bookworld v3 не менять из внешнего чата. Новое решение включено в [единый генеральный план](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md).

**Новое направление Web/Яндекс Игры (7 ноября 2026):** [WEB_STANDALONE_YANDEX_GAMES_PLAN_RU_2026-11-07.md](WEB_STANDALONE_YANDEX_GAMES_PLAN_RU_2026-11-07.md), включено в [генеральный план §11.4](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). Пользователь предпочёл **не создавать игру из книги в браузере**. Для Яндекс Игр приоритетен **отдельный HTML5-релиз одной полностью готовой лицензированной игры**, без загрузки произвольных .bworld/FB2, GLM/интерактивного ИИ, редакторов и чужой библиотеки. На собственном сайте позднее возможен универсальный web-player *только готовых* .bworld. Условия Яндекс 27.10.2026: interactive AI запрещён, готовый AI-контент допустим, ZIP до 100 МБ распакованного, обязательный Yandex SDK и Guest, cloud Player Data до 200 КБ; осторожно с **дубликатами** (разная кожа/рассказ не гарантирует модерацию), антология для однотипных коротких историй, и с правами на саму книгу/конкретный русский перевод. В main Web пока не реализован; текущий native код использует dart:io/Isolate/sqlite3. Для будущего standalone web нужен thin player+browser storage+Yandex bridge без переписывания story_core. Не пускать эту разработку раньше завершения P0 реальной книги/Windows/Android. Никаких изменений apps/packages/main из этой внешней ветки.

**Новое будущее направление (7 ноября 2026) — настоящая пиксельная RPG с ходьбой:** [WALKABLE_PIXEL_RPG_FLAME_INTEGRATION_RU_2026-11-07.md](WALKABLE_PIXEL_RPG_FLAME_INTEGRATION_RU_2026-11-07.md), внесено в [генеральный план, §8.2 и P2-WALK](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). По просьбе пользователя генератор должен в будущем уметь создавать НЕ ТОЛЬКО pixel scenes, но и top-down локации с реальным перемещением, препятствиями, NPC, дверями, предметами и сценическими взаимодействиями. **Рекомендация: Flame GameWidget/Camera/Collision/Joystick как движок 2D-координат на Flutter поверх НАШЕГО story_core, НЕ Godot/Unity и НЕ второй engine правил/сохранений.** Режимы NARRATIVE/EXPLORE_2D/HYBRID; генератор производит source-bound LocationGraph/MapLayoutRecipe и тест проходимости BFS/A*, procedural pixels без AI-картинок; шаги не превращаются в WorldEvent; сюжетные действия всегда через native core/SQLite; старый v3 остаётся валиден. Это опциональный P2-WALK после закрытия полной P0 игры; понадобится новая schema и real Flutter/Web/Android/Windows QA, **сегодня не реализовано**. Установка Flame/изменение main только в отдельно разрешённой native ветке, не из E6f.

**Аудит применимости движка (7 ноября 2026):** [ENGINE_CAPABILITIES_APPLICATIONS_GITHUB_REVIEW_RU_2026-11-07.md](ENGINE_CAPABILITIES_APPLICATIONS_GITHUB_REVIEW_RU_2026-11-07.md). Описаны уже реализованные ядро/story_engine/story_core, NPC social v5, события/SQLite, ограничения ролей, проверенный E6f, стадии P0–P3 и области повторного применения: интерактивные книги, детективы, новеллы, обучение/тренажёры, исследовательские игровые симуляторы, 2D/Web. Сравнение с GitHub: Ink, Yarn Spinner, Narrat, TextWorld, AI Town, H5P, RPG-JS, Flame. **Это обзор возможностей и направлений, не реализация SDK/Scoring/LMS/Flame/Web.** Приоритет полной реальной книги P0 не изменён. 

**Новое исследование: генератор самостоятельных оригинальных сюжетов (7 ноября 2026):** [ORIGINAL_STORY_GENRE_PRESETS_GITHUB_RESEARCH_RU_2026-11-07.md](ORIGINAL_STORY_GENRE_PRESETS_GITHUB_RESEARCH_RU_2026-11-07.md), включено в [генеральный план §1.1 и P1-ORIGINAL](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). Пользователь хочет будущий второй источник: вместо FB2 выбирает *романтика/фэнтези/детектив/НФ/триллер/ужасы/приключения и сочетания*, героя, тон, объем, ограничения → ИИ **заранее** придумывает собственный внутренне согласованный мир, проверяемые события/NPC/диалоги и **готовый offline game.bworld**. Один StoryPlan, один story_core/SQLite и одни визуальные пиксельные/skin-компиляторы. GitHub: monomyth (структура seed/жанры), par-storygen (пресеты и wizard), lore-forge (StoryBible/consistency), questgen/QuestMasterAI/TextWorld (механическая разрешимость), taleweaver (world blueprint/QA), Narraitor/Project Lunar (настройки героя и мира). **Это план после текущего P0 по полной реальной книге, код ещё не реализован.** Для оригинальной истории нужен честный generated-origin provenance/rights contract, нельзя имитировать SOURCE_PASSAGE чужой книги или подменять текущий строгий 4-member rich-v3. Native main/apps/packages и installed skill pin не трогать без новых явных разрешений и cross-language CI. Риски лицензий: TaleWeaver code MIT, встроенные приключения CC BY-NC; у Project Lunar README MIT, но корневого LICENSE нет.

## 3. Согласование с большим планом

1. Главный нормативный план: [AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md) — конечная цель «полная книга → один готовый game.bworld → offline Android/Windows», сценарий, NPC, диалоги, визуал, редактор.
2. Проверенные источники/архитектура: [ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md](ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md).
3. Нормативная реализация трёх панелей: [GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md](GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md), ссылки [GAME_PANELS_REFERENCE_AUDIT_RU_2026-11-07.md](GAME_PANELS_REFERENCE_AUDIT_RU_2026-11-07.md). Свериться с PR #132: часть native item custody/NPC life уже реализована, но UI-P0 и полная игровая авторская адаптация не объявлены готовыми.
4. Документ текущего кода: [E6F_MAIN_NPC_SOCIAL_V5_COMPATIBILITY_RU_2026-11-07.md](E6F_MAIN_NPC_SOCIAL_V5_COMPATIBILITY_RU_2026-11-07.md); историческая E6e финализация: [E6E_FINALIZATION_RU_2026-11-07.md](E6E_FINALIZATION_RU_2026-11-07.md).

**Сохранять общую приоритетность:** P0 закончить реальную адаптацию полной книги; P0 вместе с основным чатом NPC social и UI с реальными сохранениями; P1 дополнительные quests/skills/vNext только при необходимости книги; P2 визуал, редактор, свободный ИИ после E2E. Не заводить микропиары по отдельным полям.

## 4. Что делать после передачи

- Перед новой правкой повторно проверить main/PR #133/contract hash. Следующую E6 синхронизацию делать по принятому exact main, не копировать/угадывать API из Draft. На contract_drift остановиться, а не обновлять SHA вслепую.
- Для **настоящей** книги навык должен отдельно пройти полный анализ персонажей/событий/мест/предметов/обязательств, create source-linked NPC review с сохраняемыми character_id, мотивами и подтверждёнными фактами; собрать и независимо проверить две реальные сюжетные ветви (CANON/ALTER_FATE по принятым режимам), затем выполнить E6e/E6f finalization. Это ещё не завершено и не проверено физическими устройствами.
- Старые E5 проекты отсутствуют; не разрабатывать миграцию. Приоритет — один рабочий game.bworld, а не ещё один план.

---

## ИСТОРИЧЕСКАЯ ПЕРЕДАЧА E6e/E6d — старые статусы могут быть неактуальны

# AI Story RPG — актуальная передача нового чата (E6e + генеральный план)

**Дата актуализации: 7 ноября 2026.** Для продолжения работ читать **этот верхний раздел**. Ниже после разделителя лежит история E6d/старых main-PR: её старые статусы OPEN DRAFT/CI_PENDING и указание «начать finalize» **не являются текущими задачами**.

## 1. Рабочая ветка, проверенное состояние и границы

- **Единственная актуальная ветка нашего внешнего автора:** [feature/external-rpg-author-e6e-parity-20261107](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6e-parity-20261107). Сохранять ход проекта здесь и в tools/rpg_author. Историческую E6d-ветку не продолжать как новую.
- **Проверенный исполняемый код E6e 0.3.0a3:** SHA bfa4190afec7c0f5e00c70e357898a9660c05450, [GitHub Actions #42297819582](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42297819582): **author-tests SUCCESS, dart-parity SUCCESS**. Следующие коммиты в данной ветке изменяют документацию ([skip ci]), поэтому **не называть новые docs-HEAD дополнительно проверенными кодовыми SHA**.
- **Основная программа на момент снимка:** main 9c9bdc142495e536b5d11ca5e61680948e45f8fe после принятого [PR #131](https://github.com/shonentez-afk/AI-Story-RPG/pull/131); [PR #132](https://github.com/shonentez-afk/AI-Story-RPG/pull/132) по NPC social — **OPEN DRAFT** на момент последней проверки. Перед следующими программными действиями повторно посмотреть HEAD/PR/CI.
- **Установленный навык ai-story-book-to-rpg всё ещё закреплён на E6d SHA 9849c22d18e2761b49766b0c213b4a3fb3fe053b**, не заменять pin на docs-HEAD. Восстановление/bootstrap навыка только после отдельного тестирования. E6e git branch и установленный навык — не одно и то же.
- **Граница:** main, apps/, packages/, tools/bookworld/, общий CI и встроенный генератор — только чтение из этой ветки. Не переносить туда документацию/код без нового явного разрешения. Приватные FB2, текст/цитаты, игровые snapshots и API-ключи не коммитить в public GitHub.

## 2. Действующая иерархия крупных планов — без раздвоения roadmap

1. **Генеральный план (главный):** [AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md) — вся книга, готовый один game.bworld, NPC, факты, диалоги, события, предметы, процедурные сцены и будущий необязательный редактор. **Обновлён раздел 11.3 и P0/P1-гейты по игровым вкладкам.**
2. **Технический справочник сторонних идей:** [ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md](ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md) — source links, один двигатель, правила внедрения, этапы; **добавлен §8.1** по Narrat/Quest/Ren'Py/UI.
3. **Подробный план внедрения игровых вкладок:** [GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md](GAME_PANELS_IMPLEMENTATION_PLAN_RU_2026-11-07.md) — точные Flutter/core/gateway/BookWorld места подключения, Hero, Inventory, Journal Events/Quests/Knowledge/Dialogue, контракты, безопасность, P0/P1 пакеты и тестовая матрица.
4. **Основание решений и проверенные аналогии:** [GAME_PANELS_REFERENCE_AUDIT_RU_2026-11-07.md](GAME_PANELS_REFERENCE_AUDIT_RU_2026-11-07.md).
5. **E6e CLI финализация:** [E6E_FINALIZATION_RU_2026-11-07.md](E6E_FINALIZATION_RU_2026-11-07.md), уже реализована команда python3 -m tools.rpg_author finalize, есть unit и synthetic end-to-end. Команда не выдаёт художественное/устройственное USER_READY без реального независимого прохода.

Все пять документов подчинены **основной цели 1.0**, не означают автоматический запуск P1/P2. У другого основного чата есть [main roadmap](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/ROADMAP_AUTOMATIC_RPG_RU_V2_2026-11-05.md) и [1.0 acceptance](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/PROJECT_COMPLETION_GATE_RU_2026-11-06.md); эти native docs в текущей внешней ветке read-only.

## 3. Что фактически сделано, а что нет

**Сделано:** E6e code синхронизирован с принятым #131 без отключения contract checks; исправления E6d диалогов и регрессионные проверки, источник/сборка/verify, проверки gameplay, dialogue, literary-report coverage; единый finalize, синтетический CI green на exact-head. В приложении уже есть три кнопки Герой/Предметы/Журнал, WorldGameView и replay journal; signed текущие диалоги/локальная history существуют.

**Не сделано и не заявлять готовым:** автоматическая полная адаптация настоящей книги с литературно подтверждёнными NPC и целым сценарным runtime; тесты «Король-лягушонок» + второй FB2 на реальных Android/Windows; full-device E2E; обновление pinned навыка; сам runtime QuestDefinition/ownership/skillcheck; полноценная межсценовая история диалогов; полноценные карточки UI; формат vNext с такими capabilities; social #132 пока не принят.

## 4. Следующие шаги, сгруппированные по приёмке

**A. Немедленная цель P0:** довести действительно полную книгу→игру по актуальному проверенному генератору и подтвердить офлайн Android/Windows, два маршрута, знание/причинность/передачи вещей, сохранения и replay. Закрыть дальнейшую интеграцию NPC social только после принятого API/отдельного parity. Сохранить реальные приватные checkpoint/review/enrichment/dialogues/инвентаризацию тем и итоговые отчёты вне checkout.

**B. Один UI-P0 пакет в основном чате (только после явного разрешения):** расширить чтение WorldGameView через 3 компактные панели без нового .bworld, без нового состояния. Flutter/widget/Windows/Android acceptance. Не плодить PR на каждое поле.

**C. Один следующий GAME-P1 пакет:** item owners/quantity/use/transfer + quests/objectives и optional skill checks — только если они нужны книге; один versioned vNext writer/importer/story_core/SQLite/Flutter/provenance/replay contract, не вставлять молча в v3. NPC знание/социальное состояние подключать в существующий пакет социальной функциональности, не отдельной параллельной моделью.

**D. Позже:** по желанию пиксельные visual recipes, dialogue history всех реально показанных реплик, codex, живые API NPC, необязательный редактор. Эти функции не имеют права задерживать законченную текстовую v3 игру.

**Acceptance и запреты:** одни verified events/state для всех панелей; чужие/будущие сведения не отображать; нельзя использовать/передать отсутствующий предмет, повторить эффект двойным кликом или скрыть ещё нужный важный выбор. Одна настоящая игра и соответствующий импорт лучше десятков новых микрофункций. Конкретные негативные сценарии — в подробном плане.

---

## АРХИВНЫЕ сведения прежнего чата E6d (не использовать статусы/сроки как новые)

# Продолжение внешнего генератора AI Story RPG — E6d

## ОБЯЗАТЕЛЬНЫЙ НОВЫЙ ПЛАН: проверенные источники и единая архитектура (2026-11-07)

**Начинать с:** [ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md](https://github.com/shonentez-afk/AI-Story-RPG/blob/feature/external-rpg-author-e6d-handoff-20261106/tools/rpg_author/ENGINE_BEST_PRACTICES_INTEGRATION_PLAN_RU_2026-11-07.md) — подробные технические решения по BookModel, StoryPlan, Storylets, обязательствам, NPC, памяти, отношениям, целям, диалогам, RPG, времени, AI, процедурной графике, редактору, QA, формату .bworld, CI и отдельному движку. Внутри **прямые проверенные ссылки на файлы сторонних GitHub-репозиториев**, с правильными ветками main/master/develop и сведениями о лицензиях.

**Согласование:** [основная программа — roadmap](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/ROADMAP_AUTOMATIC_RPG_RU_V2_2026-11-05.md); [приёмка 1.0](https://github.com/shonentez-afk/AI-Story-RPG/blob/main/docs/PROJECT_COMPLETION_GATE_RU_2026-11-06.md); [генеральный план нашей внешней ветки](https://github.com/shonentez-afk/AI-Story-RPG/blob/feature/external-rpg-author-e6d-handoff-20261106/tools/rpg_author/AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md). Новый документ **дополняет, а не заменяет** их; P1/P2 после доказанной полной игры. Не расширять P0 ради Storylets/GOAP/визуального редактора.

**Срез основного main 2026-11-07:** [PR #130](https://github.com/shonentez-afk/AI-Story-RPG/pull/130) MERGED, основной SHA f4331851ef5752e0e2821f328d75703808579ef5. NpcSocialLedger пока read-only по подтверждённым событиям; реальный runtime effect/присутствие/допуск реплики остаются задачами. Exact-head CI #823 / M0 #908 SUCCESS; post-merge #824 ещё выполнялся, M0 #909 SUCCESS. ПЕРЕД любым следующим кодом обязательно получить актуальные SHA/CI/PR: этот пункт — исторический срез. Внешняя E6d по-прежнему только tools/rpg_author, пакеты/Flutter/main read-only; закреплённый pin не менять без parity gate.

**Задача другого основного чата:** продолжить P0 NPC и завершить «полная книга → игра» с самостоятельным Dart engine и сохранениями. **Задача нашей ветки:** развивать внешний генератор по уже принятому API, не создавать конкурирующие schema/runtime. Новые идеи сторонних проектов — ориентиры, не инструкция копировать чужой код.


Обновлено: **6 ноября 2026 года**.
Репозиторий: https://github.com/shonentez-afk/AI-Story-RPG
Рабочая ветка: `feature/external-rpg-author-e6d-handoff-20261106`.
Этот файл: `tools/rpg_author/START_NEW_CHAT_RU.md`.

## PR #126 — новая native NPC-карточка: реальный код уже есть, merge ещё нет (6 ноября 2026)

В GitHub основной программы **[PR #126](https://github.com/shonentez-afk/AI-Story-RPG/pull/126)**: постоянный `character_id = npc_ + 32 hex` (128 случайных бит `Random.secure()`) и поля `aliases, role, biography, appearance, personality, speech_style, motivation, goals, portrait_asset_id`; `display_name` пока находится в соседнем `NpcDraftProfile`. Редактор умеет менять/сохранять карточку, `NpcKnowledgeWorldBridge` использует ID для `StoryWorld` актёра и `learn_fact/knows_fact`. Никогда не менять ID при переименовании/новом источниковом анализе. **Наша Python-подготовка должна выдавать эти же поля, а random ID один раз сохранять в приватном snapshot** (`secrets.token_hex(16)`), а не заново вычислять по имени/книге.

**Пока НЕ готово:** отношения по стабильным character IDs (сейчас targetDossierId), provenance каждого поля, event-scoped knowledge across full book, speaker→ID, NPC карточки внутри полного `.bworld`, AI NPC разговоры/пиксельные сцены. PR #126 — **OPEN DRAFT**, head `a5f88437e7807239c087b184354c1fcd33c457fe`, на момент проверки M0 #864 SUCCESS, Flutter/Dart/Python stages #779 SUCCESS, Windows/Android CI ещё выполняются. **Ничего в основной программе не меняли**. Читать [E6I_PR126_NATIVE_NPC_CARD_CONTRACT_AUDIT_RU_2026-11-06.md](E6I_PR126_NATIVE_NPC_CARD_CONTRACT_AUDIT_RU_2026-11-06.md) перед синхронизацией E6. Не менять E6d pinned skill без нового полного parity gate.

## Согласование с новой полной карточкой NPC основного приложения (2026-11-06)

Пользователь сообщил, что параллельно разрабатывается **единая карточка персонажа** с 5 разделами: (1) постоянный `character_id`, имя/прозвища, роль, внешность/портрет; (2) темперамент/мотивация/цели/манера речи; (3) отношения строго по `character_id`; (4) знания и подтверждённые события их получения; (5) происхождение каждого утверждения: цитата, вывод ИИ или явная игровая адаптация. **Наш навык и Python-генератор обязаны заполнять именно этот единый контракт АВТОМАТИЧЕСКИ, без второго конкурирующего `npc_profile` формата и без необходимости вручную дописывать NPC после импорта.** Проектный `npc_profile_v1` из прошлых документов не является принятым API.

Отдельно закреплены неизменяемый ID и явный mapping `source_mention_group_id -> character_id -> world_actor_id`, relations по IDs, знания по времени/игровым веткам, provenance у каждого свойства/отношения/знания, code-only pixel-портрет по одному appearance seed (локальный PNG допустим, но необязателен), строгий privacy context для будущего AI разговоров. Детали: **раздел 6 документа [AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md)**.

Проверка live GitHub: `main=4f94fc3d2dcdba3258ba5418faff37fc366b4ff9`, [PR #125 принят](https://github.com/shonentez-afk/AI-Story-RPG/pull/125), но в main ещё **не подтверждён целый новый schema этой пятичастной карточки**. Перед программной адаптацией дождаться/сверить реальный принятый Dart contract, Python parity tests и BookWorld importer/writer; main/apps/packages/CI остаются read-only для внешнего навыка. Не выдавать рабочую идею за готовую функцию.

## СРОЧНОЕ обновление интеграции с основным main — после PR #124 (2026-11-06)

Основной `main` **`6711011c0e55ca14f43c0ad0cab1f9976754c08a`**, [PR #124 MERGED](https://github.com/shonentez-afk/AI-Story-RPG/pull/124). [Подробный аудит изменений и блокеров CI](E6H_MAIN_PR124_INTEGRATION_AUDIT_RU_2026-11-06.md) — читать **после** единого архитектурного плана, **до** внесения следующей программной правки генератора.

Новое: `RichSceneDialogue` + optional `presentation.scene_dialogues` в прежних четырёх ZIP-файлах `.bworld v3`, проверка Dart/Python, `WorldGameView` и `DialogueStage` воспроизводят подписанные `speaker/text`; старые v3 читаются. **Не писать второй parser и не утверждать, что в v3 нет никаких структурированных диалогов.** Полных `character_id/turn_id`, NPC profile/AI memory и code-only visual recipes в v3 всё ещё нет.

**Важный CI-risk:** post-merge main #770 ещё в процессе на момент аудита, PR-head #769 success, M0 #855 success; отдельные E6d author tests #94 FAILED (step `Check pinned application compatibility` и `dart-parity`). PR #124 изменил три pinned файла Python/Dart, поэтому текущий E6d compatibility lock расходится с main. **НЕ отключать checks, НЕ редактировать SHA вручную.** Проверить новые контракты/паритет, затем согласовать обновлённый tested pin отдельной задачей. Действующий skill E6d `9849c22d...` **не обновлялся**; последний релиз с исходной main `959c8134` = `test-build-761` (без #124). Закрыть полную книгу/реальный E2E до ухода в редактор.

## ЕДИНЫЙ ГЛАВНЫЙ ДОКУМЕНТ: полная игра из книги, генератор, редактор, AI-NPC, пиксели (2026-11-06)

**Начинать с [AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md](AI_STORY_RPG_COMPLETE_GAME_UNIFIED_SPEC_RU.md).** Это основной нормативный план, объединяющий все решения из прежних MASTER/E6f/E6g заметок и дополнительно закрепляющий главное требование: навык **сам** создаёт готовую игру и **полные профили всех нужных NPC**; конечный игрок импортирует **ОДИН .bworld**, редактор встроен в Windows/Android-приложение и **не обязателен**. Свободные AI-NPC ответы/осмотр/ввод действий опциональны и не могут менять `story_core` в обход choice gates; pixельные сцены строятся кодом, а не картинками.

**Технический факт:** строгий v3 содержит только 4 ZIP entries и не поддерживает встроенные visual recipes/NPC cards. Следовательно целевой single-file визуальный мир требует **новой согласованной версии**, условно v4, с Python writer/verifier и Dart importer; в существующем E6d всё ещё только tested textual rich-v3. Не считать новый проектный формат реализованным. Прежние документы остаются историческими, но при расхождениях руководствоваться единым главным. Настоящая следующая программная задача всё ещё E6e и full-book QA, не начинать редактор до завершения готовой игры.

**Коммиты документации:** основной единый документ создан/дополнен в ветке внешнего генератора; пользовательский skill pin E6d и main/apps/packages/BookWorld/CI **не менялись**. Старых E5 пользовательских миров нет, миграция не требуется.

## Текущее состояние: последнее поручение выполнено

Пользователь поручил:
1. Исправить два недостатка проверки диалогов.
2. Обновить навык на проверенную версию генератора.
3. Всё отметить для нового чата.

**Оба исправления сделаны, тесты и CI прошли, установленный навык обновлён и сохранён.**
Не начинать эти задачи заново. Следующая незавершённая программная задача — единая завершающая команда сборки и проверок (см. ниже).

**Старых проектов E5 у пользователя нет. Миграцию и перенос E5 исключить из плана. Новые игры создавать закреплённой проверенной версией.**

Цель: пользователь передаёт книгу в ChatGPT; ассистент анализирует её и создаёт сценарий, запускает внешний Python-компилятор в своей среде, выдаёт `.bworld v3` для импорта в приложение. Пользователю не нужен Python или запуск скриптов на ПК/телефоне.

## Проверенная версия

| Объект | Состояние |
| --- | --- |
| Генератор | **0.3.0a2**, этап E6d |
| Точный коммит кода, закреплённый в навыке | `9849c22d18e2761b49766b0c213b4a3fb3fe053b` |
| Toolchain SHA-256 | `a14e569534779556c62727abbab0c031be0cdcffb122ed698e7920e365496d34` |
| Основа рабочей ветки | `53eb4c452d142f3fd1c96b50818ba4bdc7733d30` |
| CI коммита кода | [External RPG author tests — success](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42180380079) |
| Слияние E6d в main | В этом чате не выполнялось |
| Установленный навык | Обновлён на указанный SHA; сохранение и повторная сверка файлов подтверждены |

Ветка может быть впереди закреплённого SHA из-за обновлений этого документа. Это нормально: навык получает **точный коммит кода**, а состояние разработки читать по последней версии этого файла в рабочей ветке. В закреплённом коммите находится промежуточная версия заметки — она не заменяет этот актуальный статус.

Основной main развивается независимо и может быть новее основы ветки. Не подменять проверенную версию последним main автоматически.

## Граница работ

- Развивать `tools/rpg_author/`, `tests/rpg_author/`, `schemas/rpg_author/`, документацию внешнего генератора и его отдельный CI.
- Основное приложение, `apps/`, `packages/`, `tools/bookworld/`, общий CI и корневые файлы передачи основного приложения — только чтение в рамках этой задачи.
- Последнее изменение кода затронуло только внешний аудитор, его тесты, номер версии и документацию. Основное приложение не менялось.
- Не сливать ветку в main автоматически.
- Книги, реальные сценарии, игровые архивы и отчёты с содержимым книг держать вне публичного GitHub. В тестах использовать синтетические истории.
- Не добавлять новые подсистемы вместо завершения указанной следующей задачи.

## Исправлено в E6d

### Предварительное знание

Файл: `tools/rpg_author/dialogue_quality.py`.

`requires_fact` теперь проверяется **до выполнения вопроса**, по входному состоянию. Если вопрос сам выдаёт требуемое знание эффектом `learn_fact`, это больше не скрывает отсутствие предпосылки.

Если ответ впервые сообщает информацию без предварительного условия, у темы должен быть `requires_fact: null`, а новое знание оформляется эффектом `learn_fact`. Если знание нужно заранее, ограничить выбор условием `knows_fact`.

В `UNAUTHORIZED_DISCLOSURE.example_route` включается именно проблемный вопрос, а не произвольный короткий путь в ту же сцену ответа.

### Полный маршрут повторного вопроса

Аудитор восстанавливает путь от состояния после первого вопроса до состояния, в котором вопрос снова доступен. В `example_route` входят:
- путь от начала игры до первого вопроса;
- первый вопрос;
- все переходы возврата/обхода;
- повторный вопрос.

Пример теперь: `ask_one → back → ask_one`.
Работает также для обходных сцен, сброса флага, короткого альтернативного входа в ответ и вопроса, возвращающего в ту же сцену.

Аудитор сообщает об ошибке и исполнимом примере; сценарий самостоятельно не переписывает.

### Регрессионные проверки

Добавлены 8 сценариев в `tests/rpg_author/test_dialogue_quality.py`:
1. Вопрос не может выдать сам себе обязательное предварительное знание.
2. Начальное знание удовлетворяет условию.
3. Знание, полученное предыдущим действием, открывает вопрос.
4. Ответ может сообщить новое знание, если это не заявлено предпосылкой.
5. Простой повтор содержит оба вопроса и возвращение.
6. Повтор через обход и сброс флага имеет полный маршрут.
7. Короткий альтернативный вход в ответ не подменяет первый вопрос.
8. Вопрос с переходом в ту же сцену показывает оба выполнения.

Маршруты повтора дополнительно проигрываются в тестах с проверкой доступности каждого выбора. До исправления новые проверки воспроизвели дефекты; после исправления проходят.

Семантика описана в `tools/rpg_author/E6C_DIALOGUE_QUALITY.md`.

## Что изменилось в установленном навыке

Навык `ai-story-book-to-rpg` уже обновлён в постоянном пользовательском каталоге; изменения сохранены и повторно сверены после сохранения.

- `scripts/bootstrap.py` закреплён на E6d `9849c22...`, версия `0.3.0a2`.
- Загрузчик получает точный SHA до исполнения Python; новые коммиты документации в ветке больше не сбивают закреплённую загрузку.
- Проверяются чистота checkout, `doctor`, версия и наличие `gameplay-audit` / `dialogue-audit`.
- В обязательный порядок добавлен `gameplay-audit --strict`.
- При интерактивных вопросах обязателен `dialogue-audit --strict` с полным приватным `dialogues.json`.
- При отсутствии вопросов записывается явная причина неприменимости. Обычные подписанные реплики всё равно проверяются литературно.
- Добавлены `references/quality-checks.md`, обновлены совместимость, порядок сохранения и шаблон передачи.
- `dialogues.json` и отчёты нужно сохранять рядом со snapshot: текущий `checkpoint.py` автоматически включает из дополнительных материалов только review/enrichment.
- Миграция E5 исключена из плана.

Проверка навыка:
- Формат, синтаксис скриптов и относительные ссылки — OK.
- Подготовка из GitHub в чистой папке — `pinned_checkout_verified`; фактический SHA и версия совпали, checkout чистый.
- Команды аудита доступны и поддерживают `--strict`.
- Отдельно проверено, что продвижение ветки сохраняет выбранный pin; `--verify-only` работает; неверный SHA и локальные изменения отвергаются.

**Единой новой команды ещё нет:** навык уже выполняет проверки как последовательность существующих команд.

## Выполненные проверки кода

На коммите `9849c22d18e2761b49766b0c213b4a3fb3fe053b`:
- `python3 -B -m tools.rpg_author doctor` — OK, rich v3.
- `python3 -B -m unittest discover -s tests/rpg_author -q` — **98 тестов, OK**.
- `python3 -B -m unittest discover -s tools/bookworld/tests -q` — **21 тест, OK**.
- `git diff --check` — OK.
- [CI](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42180380079): `author-tests` и `dart-parity` — success.

Лог Dart parity подтвердил 22 сравнения исходного индекса, принятие Python v3 настоящим Dart-импортёром, игровые состояния/панели, два маршрута v3, SQLite, перезапуск, ветвление и переносимые сохранения.

В этом этапе не создавалась новая игра по реальной книге и не выполнялся ручной проход на Android/Windows. Не выдавать автоматические проверки и подготовку генератора за проверку конкретной адаптации на телефоне.

## Что остаётся

### Следующая программная задача: единый завершающий процесс

Реализовать одну внешнюю команду:
принятый проект + enrichment → сборка v3 → проверка архива и атрибуции → gameplay-audit → dialogue-audit при интерактивных вопросах → проверка литературного отчёта → сводный отчёт.

Требования:
- Сохранять причины отказов и привязку отчётов к точным входам и хешу архива.
- Предупреждения качества не должны позволять объявить игру готовой.
- Отсутствие вопросов отражать явно. Список тем при наличии вопросов проверять на полноту; нынешний аудитор сам не находит пропущенные темы.
- Не называть структурный успех доказательством литературного качества или прохождения на устройстве.
- Не забыть темы и отчёты в сохраняемом результате.
- Название и интерфейс команды пока не выбраны.
- После реализации и проверок снова обновить закреплённую версию навыка.

### Затем — реальная игра

Подготовить игру текущей версией и пройти в актуальном приложении на телефоне: диалоги, предметы, журнал, сохранение, закрытие и повторное открытие. Для подтверждения Windows нужен отдельный Windows-проход. При недоступности устройства честно оставить эту проверку незавершённой.

## Уже готовые возможности — не реализовывать повторно

- E5 / [PR #101](https://github.com/shonentez-afk/AI-Story-RPG/pull/101): обычные `build` / `verify` работают с rich v3, sidecar сверяется с архивом.
- E6a / [PR #110](https://github.com/shonentez-afk/AI-Story-RPG/pull/110): анализ достижимых состояний, декоративных ресурсов, одинаковых последствий, недоступных выборов.
- E6c / [PR #113](https://github.com/shonentez-afk/AI-Story-RPG/pull/113): структурный аудит подготовленных тем диалогов.
- В приложении приняты [#115](https://github.com/shonentez-afk/AI-Story-RPG/pull/115) — поочерёдные подписанные реплики и история, [#117](https://github.com/shonentez-afk/AI-Story-RPG/pull/117) — локальные PNG-портреты. Наличие портретов не означает их упаковку внешним генератором.
- Лимит аудита — 2500 состояний; превышение возвращает ошибку.
- Атрибуцию v3 создаёт действующий компилятор. Старое обязательное `none/null` относится к v2; не подставлять выдуманный идентификатор модели.
- Литературный `review_gate.py` проверяет полноту и привязку отчёта, не истинность выводов.
- `docs/RPG_AUTHOR_STATUS_RU.md` исторически описывает E5 и устарел; для следующего шага использовать этот файл.

## Новые архитектурные решения: граф книги и процедурные пиксельные сцены (2026-11-06)

Сохранён единый исследовательский документ:
**[MASTER_BOOK_GRAPH_PROCEDURAL_PIXEL_PLAN_RU_2026-11-06.md](MASTER_BOOK_GRAPH_PROCEDURAL_PIXEL_PLAN_RU_2026-11-06.md)**.
Он объединяет каталог персонажей/событий/утверждений/цитат, будущие блок-схемы, автоматическую генерацию пиксельных сцен **кодом (не AI image)**, лёгкую анимацию, совместимость `story_core`/`story_engine`/`campaign_manager` и проверку сторонних Arcweave/Twine/Inky/Yarn Spinner/Dialogic, Mermaid/Flutter graph libraries, PixelForge/Sprite Forge, Flame.

**Это исследование, не реализованный функционал и не смена P0.** Сначала закрывать E6e и настоящую игру/QA. Main, Flutter, пакеты, BookWorld и общий CI остаются read-only до нового отдельного разрешения. Pin проверенного навыка E6d не менять без тестов.

## Архитектурное решение E6g: какие чужие проекты используем и как подключим живой ИИ (2026-11-06)

Сохранён проверенный обзор и согласованная схема: **[E6G_THIRD_PARTY_AND_AI_FREE_INTERACTION_DECISIONS_RU_2026-11-06.md](E6G_THIRD_PARTY_AND_AI_FREE_INTERACTION_DECISIONS_RU_2026-11-06.md)**.

**Встроенный редактор** будущего: в том же Flutter Windows/Android, граф книги + граф сюжета, NPC persona/знания/темы, редактор code-only пиксельных сцен и лёгких анимаций. Конкретные чужие технологии: optional Mermaid-export, на spike выбрать `vyuh_node_flow` или `node_flow` (не обе); Flutter Canvas и позже при необходимости Flame. PixelForge/Sprite Forge использовать как идеи, а не JS runtime. Twine/Inky/Arcweave/Yarn/Dialogic как ориентиры редактора. AI Dungeon, Convai Narrative Design, AI Town, Rasa CALM, chasm как ориентиры контролируемых freeform NPC.

**Уже сделано в main:** офлайн `FreeTextActionGate`, Z.ai `ZaiGameplayChoiceAdvisor` только для сопоставления с уже разрешёнными `choice_id`, отдельно проверяемые `npc_knowledge` правила. Это **НЕ** свободные реплики NPC. Будущие `SAY` (NPC ответ в рамках persona/verified knowledge, отдельная память), `LOOK` (только доступные факты), `DO/INTERACT` (только подтверждённые enabled choices). `STORY` не в текущем v3, отдельный эксперимент только после аудита. API opt-in, точный payload consent; нельзя тихо отправлять главы, журнал или скрытые знания. Все эффекты через `WorldLibraryGateway.choose` / story_core, не через LLM.

**Статус: только документы, НЕ реализовано.** P0 по-прежнему E6e/настоящий E2E книги. Основное приложение, `main`, все `apps/packages/tools/bookworld` read-only; E6d pinned skill unchanged. Новых миграций E5 не делать.

## Начало нового чата

1. Прочитать последнюю версию этого файла в рабочей ветке.
2. Проверить, не закрыта ли следующая задача другим чатом; изучить актуальные ветку и навык.
3. Продолжать с единой завершающей команды, если пользователь поручает дальнейшую разработку.
4. Сохранять проверенные коммиты, результаты и остаток работ здесь.
5. Не возвращать миграцию E5 в план и не вмешиваться в основное приложение.
