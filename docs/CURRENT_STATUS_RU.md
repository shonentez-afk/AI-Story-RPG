# P0 UI PARITY — БОЛЬШОЙ ПАКЕТ РЕАЛИЗОВАН В PR #133, ПРИЁМКА В CI

**Кодовый SHA:** `b7daca6f058f53956226474c8abca4d251d561f9`. Единственный [Draft PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) в `feature/p0-bookwide-gameplay-readiness-20261107`. [Основной CI #1127](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42619715731) **IN PROGRESS при записи**; [M0 #1212](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42619715969) SUCCESS; [native author CI #488](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42619715796) IN PROGRESS. Этот docs-only коммит **[skip ci]**, НЕ меняет тестированный исходный код; последующий чат должен сверить итог job, исправить обнаруженные проблемы в ЭТОМ ЖЕ PR и обновить SHA и статус.

**Реализован один связанный пакет Flutter UI ↔ автономный движок:**
- Новый `apps/story_reader/lib/world_ui_presenter.dart`: read-only presentation `WorldGameView`, NPC-целей/памяти/обещаний/автономных действий, hero/journal/inventory, `alternatePlotContinuity`, и детального typed `FreeformActionDraft` preview; НЕ собственный UI-движок сюжета.
- `world_play_page.dart`: полноценные панели Герой, Предметы, Журнал и NPC; доказанные текущие цели, открытые обещания, самостоятельные решения, последние изменения; сюжетные обязательства и направления ALTER_FATE; source-scene/диалоги/портреты сохранены.
- `free_text_action_panel.dart`: перед вторым подтверждением действия ИИ видны NPC, передача факта/предмета, доверие, обещание, цель, сюжетная ветка/маршрут, откр./закр. обязательства и typed resolution proofs; всё до commit НЕ считается записью.
- `book_rpg_start_page.dart`: новая явная дорожка `E6q.1 external ChatGPT Skill` → готовый подписанный `.bworld` → проверка `sourceCausalReviewVerified` и **точного sourceFingerprint выбранной книги/сказки** → стандартный `WorldImportReviewFlow` и отдельный пользовательский consent → `WorldCampaignsPage`. Никакой скрытый Z.ai, Python-симулятор или новый тип игрового сохранения не внедрены.
- `RpgWorldIntakePreview` дополнен `sourceCausalReviewVerified`, `heroName`, `dynamicAiActionsAvailable` только из проверенного импортёром v5 / подписанного blueprint. Нельзя принять буквальный CANON за полный причинный.
- `world_import_review_flow.dart` и `world_campaigns_page.dart` объясняют истинные возможности архива, авторскую роль и наличие AI freeform перед началом прохождения. `WorldCampaignsPage` читает оригинальный .bworld через тот же native intake, не угадывает формат по названию и не прерывает существующую кампанию при недоступности дополнительного метаотчёта.
- `world_ui_capability_parity_test.dart`, `reviewed_causal_start_ui_test.dart`, `world_integration_test.dart`: узкий экран/200% текст; Журнал/Герой/Инвентарь/NPC; отсутствие скрытых будущих NPC; typed preview с планом; native source-causal v5+SQLite → Flutter → real CANON→ALTER_FATE; импорт подписанного v5/отказ в literal-only и чужой редакции.

**Пока не обещать готового QA:** только после зелёных Flutter widget/M1.7/Windows/Android и нового проверенного SHA считать этот P0 пакет автоматически принятым. Остаются реальное устройство, визуальное screenshot QA, две разные настоящие RU FB2 и содержательная литературная проверка. `main` не трогать, PR #133 Draft, никаких микро-PR. Генератор E6q.1 в своей ветке, не дублировать. Приоритет UI теперь ПЕРЕД литературными испытаниями и релизом.

---

# СРОЧНАЯ ПОПРАВКА ПРИОРИТЕТА — 09.11.2026: UI parity ПЕРЕД ЛИТЕРАТУРНЫМ QA

**СЛЕДУЮЩИЙ КРУПНЫЙ ПАКЕТ — ОБЯЗАТЕЛЬНОЕ СОГЛАСОВАНИЕ ВСЕГО FLUTTER-ИНТЕРФЕЙСА С АВТОНОМНЫМ RPG-ДВИЖКОМ.** В предыдущих передаточных документах его ошибочно поставили после тестирования реальных книг. Это неверно: **сперва реализовать и принять полный UI parity** по [аудиту + единому техническому плану](docs/FLUTTER_ENGINE_UI_PARITY_P0_RU_2026-11-09.md), и только потом две реальные FB2, GLM, Windows/Android E2E и релиз.

Подтверждённые пробелы: карточки NPC не выводят `currentGoal/openPromiseIds/autonomousDecisionIds`; Журнал не представляет `alternatePlotContinuity`; подтверждение свободного AI-хода не раскрывает весь typed NPC/plotBeat/proof результат; экран создания предлагает быстрый режим, Z.ai и буквальный CANON, но ещё не даёт единый путь установки/запуска reviewed E6q.1 causal v5. Внешний Skill не превращать скрытно во встроенную модель. Дополнительно проверить Герой, Предметы, диалоги с портретами, выборы, сохранения и адаптивность Flutter. **Это НЕ готово/НЕ принято**, зелёный CI #1120/#478 подтвердил прежнюю функциональность, а не новую полную UI parity.

Реализовать ОДНИМ большим пакетом в PR #133 с общей UI/API/widget/visual приёмкой, без микро-PR; автономный Dart core и исходные сохранения не переписывать. Текущий code baseline `92ef5d701637957e31e3e6e090f63d1e0bdb4173`, PR Draft; main не изменять. Эта docs-only запись [skip ci] не меняет кодовый baseline.

---

# ПРИЁМКА ТРЁХ БОЛЬШИХ ПАКЕТОВ — 09.11.2026 — АКТУАЛЬНЫЙ ФИНАЛЬНЫЙ СТАТУС

**Проверенный КОД:** `92ef5d701637957e31e3e6e090f63d1e0bdb4173` в Draft PR #133. [Полный Native CI #1120](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597681279) **COMPLETED SUCCESS на этом SHA**: Python reference, Dart runtime, BookWorld+SQLite+M1.7+API, Flutter analyze/widget, Windows portable и Android debug APK — все SUCCESS. Артефакты Windows portable (15.4 MB) и Android debug (89 MB) доступны внутри #1120; отдельный job Publish test release был SKIPPED, поэтому НЕ утверждать, что опубликован отдельный GitHub Release. [M0 #1205](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597681258) SUCCESS; [Native External author #476](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597681193) SUCCESS.

**Генератор E6q.1:** проверенный код `0b7283653c9dc23a3a1380ca42bb68caf4451993`, workflow/doc SHA `8915286e7fe591bfeefa124850a427c8611aae7f`. [Его External RPG Author CI #478](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42598495752) **COMPLETED SUCCESS** по всем jobs: Python author-tests, Dart parity, реальный двухветочный синтетический E2E (исходная RU FB2 → полный source causal v2 review с NPC → штатный Dart CLI → .bworld v5 → SQLite gameplay → экспорт/импорт .bwsave и одинаковый state hash). Исправлена временная модификация SQLite pubspec hook в CI; обе проверки git diff --exit-code остаются строгими. Предыдущий #477 superseded/cancelled; не считать его окончательным.

**Три технических направления закрыты ПО КОДУ И CI:** (1) source-wide причинные предпосылки, необратимые дальние противоречия и CANON→ALTER_FATE; (2) знания, обещания, обмен предметами, социальные состояния и самостоятельно исполняемые в будущем signed NPC delayed decisions; (3) альтернативные сцены с проверкой предшественника, целей/персонажей, долговременных обязательств и конкретных typed-effect доказательств исполнения. Один автономный story_core/rpg_api/SQLite, Flutter/CLI/HTTP — только клиенты. Старые приватные saves сохранены.

**ЧЕСТНОЕ ПРОДУКТОВОЕ ОГРАНИЧЕНИЕ:** успешные механические тесты на синтетических и тестовых FB2 НЕ доказывают литературную полноту и мотивации всех героев произвольного реального романа. NPC-решения пока bounded source-reviewed, а не безгранично самостоятельный генеративный разум. Отдельная содержательная проверка двух различных реальных RU FB2, продолжительные варианты прохождения и физический Windows/Android E2E НЕ подтверждены. Сохранять `arbitraryBookCanon=false`, `semantic_canon_automatically_verified=false`; PR #133 оставить Draft, `main` НЕ менять до отдельной продуктовой приёмки.

**ВАЖНО ДЛЯ НОВОГО ЧАТА:** эта верхняя запись актуальна; нижележащие старые записи о незавершённых механизмах — исторические. Не повторять выполненную разработку и не создавать микро-PR. Документный [skip ci] commit не меняет проверенный кодовый SHA.

---
# ПЕРЕДАЧА 09.11.2026 — ТРИ БОЛЬШИХ ПАКЕТА CANON / NPC / ALTER_FATE

**Последний точный код автономного движка:** `92ef5d701637957e31e3e6e090f63d1e0bdb4173`, [Draft PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), ветка `feature/p0-bookwide-gameplay-readiness-20261107`. [Основной CI #1120](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597681279) — был В РАБОТЕ при подготовке; [M0 #1205](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597681258) SUCCESS; [native author #476](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597681193) SUCCESS. Проверять исход #1120 на ТОЧНОМ кодовом SHA, документационный [skip ci] commit не меняет код.

**Отдельный генератор E6q.1 (0.3.0a21):** ветка `feature/external-rpg-author-e6g-pr133-compat-20261108`, последний код `0b7283653c9dc23a3a1380ca42bb68caf4451993`. [Его CI #477](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42597944505) — был В РАБОТЕ при подготовке. Введён сквозной тест двух GitHub checkout: синтетическая русская FB2 → native literal BookWorld v5 → ChatGPT Skill-first source-window причинный обзор всех сцен → настоящая команда Dart `compile-reviewed-causal-v5` → `.bworld` → автономный CLI и SQLite ход → экспорт/import .bwsave, совпадение stateHash. **Проверка CI #477 обязательна**, не подменять фактом существования теста.

## Пакет 1. Причинность

`BookCausalGraph` содержит ровно по одному source-reviewed узлу на каждую исходную сцену v5 с source quote SHA, возможными предшествующими событиями, знаниями, предметами, памятью, отношениями, целями, жизненным состоянием и обещаниями персонажей. Движок проверяет обязательные предпосылки до перехода, сохраняет CANON при существовании допустимого книжного маршрута, переключает в `ALTER_FATE` при несовместимости. Новая `breaksAnUnavoidableFuture` обнаруживает необратимое противоречие даже в ДАЛЬНЕМ непосещённом событии (уже известное знание при обязательном незнании, имеющаяся память при обязательном отсутствии, необратимая смерть). Изменяемые цели, доверие и имущество проверяются в момент соответствующей сцены.

## Пакет 2. Свободные действия и NPC

`FreeformNpcInteraction` исполняет source-reviewed предупреждения, помощь/предательство, знание, имущество, доверие, долгосрочные цели. `promise_received/fulfilled/broken` имеют идентификатор обещания: невозможно исполнить неполученное или повторить закрытое. `NpcAutomaticReaction` может немедленно передать проверенное знание второму NPC, а новый `NpcDelayedDecision` через 1–32 реально зафиксированных последующих ходов **без нового разговора с персонажем** создаёт подписанное решение `NpcMemoryKind.autonomousDecision`, меняет цель и влияет на будущую книжную причинность. Действия восстанавливаются по одному hash-chain/SQLite/.bwsave, без фонового ИИ и без нового движка. Публичный API показывает `autonomous_decision_ids` и `open_promise_ids`, Flutter использует общую проекцию.

## Пакет 3. Динамическая история

Каждый новый `AlternateStoryBeat` связывает `thread_id`, `previous_beat_id`, цель и ведущего героя/NPC, участников, открытые и закрытые обязательства. Закрытие обязательства теперь требует `resolution_proofs`: совпадающего в том же подтверждённом ходе действительного типизированного изменения флага, предмета, знания либо закрытия NPC-обещания. Нельзя окончить сюжет словами «всё выполнено» без исполнения эффекта; нельзя перепрыгнуть к книжному абзацу после несовместимого исходного события. Предыдущие v1-сохранения без новой метаинформации воспроизводятся.

**Публикация/консистентность:** `story_core / rpg_api / campaign_manager` — единственный чистый Dart-движок; Flutter, CLI, HTTP — клиенты, Python ChatGPT Skill-first authoring НЕ симулирует правила. Нативный CLI получил команды `prepare-literal-canon-v5`, `compile-literal-canon-v5`, `compile-reviewed-causal-v5` и повторную проверку source evidence. Сборка Windows/Android проверяется по CI #1120, а не прошлому SHA. PR #133 остаётся Draft, `main` не менять, без микро-PR.

**Остающийся ЧЕСТНЫЙ продуктовый критерий:** смысловая литературная причинность и мотивы произвольной книги не доказываются хешами автоматически. E6q.1 использует авторское приватное ChatGPT чтение с `PrivateResponseInbox`, все окна должны быть одобрены человеком, а при сомнении процесс не выдаёт готовый игровой мир. Отложенные решения NPC — источник-зависимые проверенные правила, НЕ бесконечное самостоятельное агентное планирование любого NPC. В этом чате нет двух частных настоящих русских FB2 для независимой литературной проверки и не выполнены физические Windows/Android прохождения; не объявлять их PASS и не менять `arbitraryBookCanon=false`. Следующая работа только по реальному QA, если оба CI завершатся SUCCESS; если FAIL — исправить конкретную ошибку в этих же ветках.

---

## 2026-11-09 — ПРИНЯТО: source-wide v2 causal graph, NPC-реакции, автономный replay

**Код `f368f8c068a39592464c66fd518d155b705d596f`**; [Native CI #1111](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42584271223), [M0 #1196](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42584271237) и [Author #460](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42584271206) — всё SUCCESS на том же SHA. Windows portable/Android APK опубликованы. Полный source-v5 graph по сценам, подтверждённые факты/предметы/воспоминания/отношения/цели/обязательства, автоматический переход в ALTER_FATE, свободная передача знаний и владения NPC, approved auto-react/rumor relay между двумя NPC, replay и multi-client API. Старые v1/v3/v4 сохранения остаются совместимыми. **Не завершены:** автоматический литературный source-wide authoring в ChatGPT Skill E6p, два реальных RU FB2 QA, физические устройства. Draft #133, main не менять.

---

# АКТУАЛЬНАЯ РАБОЧАЯ ПЕРЕДАЧА — 9 НОЯБРЯ 2026: CAUSAL GRAPH + NPC DYNAMIC

**Новый связанный пакет в Draft PR #133:** source-wide review v2 для BookWorld v5, `BookCausalGraph` с явным source quote SHA для КАЖДОЙ канонической сцены, зависимостями (только прошлые), проверенными условиями фактов/памяти/доверия/целей/владения предметом/состояния NPC/флагов, source-reviewed typed эффекты по выходу из сцены. Движок автоматически выбирает ALTER_FATE при нарушении проверенного будущего causal event вследствие динамического NPC-действия, не возвращая игрока в исходный текст. Добавлены согласованные прямые передачи предметов игрок↔NPC и подтверждённая передача знания от героя NPC в том же едином journal/SQLite replay, через существующий API и Flutter. Формат v1 и старые save не получают новых обязательных полей.

**Требование приёмки:** на финальном HEAD должны быть SUCCESS основной CI (Python, Dart, Flutter, Win/Android), M0, External author source pin + native Dart parity. Наличие коммитов, проход отдельных tests или синтетического one-NPC E2E **не** доказывают автоматически литературу всей книги. Исторические утверждения ниже о полном отсутствии причинности/динамических NPC устарели. Генератор E6p 0.3.0a19 в другой ветке; его расширение для автоматического литературного authoring v2, реальный FB2 QA и физические устройства остаются отдельными непроверенными критериями. Не трогать main, без микро-PR.

---

## 2026-11-09 — ПРИНЯТО: источник → книжный герой → его реальные игровые действия

Code SHA `46308802b15be6ed6afc2c191ae902ba24322aa5`, [CI #1090 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42562198099), [M0 #1175 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42562198620). Принят **единый крупный пакет BOOK_CHARACTER-start**: только подтверждённый постоянный источник/персонаж, начальные собственные вещи и известные игроку факты первой главы, настоящие `has_item`/`knows_fact` условия исполнимых решений, новый частный BookWorld v4, source / SHA / consent проверки, SQLite replay/save и отрицательные случаи. Flutter/NPC-мастер использует публичный API; все три прямых Rich importer вызова удалены. Подключены Dart API и JSON operations для внешних клиентов. Windows и Android артефакты #1090 опубликованы. **Не путать с полноценным CANON или AI-GM** — эти флаги остаются false.

Генератор сейчас **0.3.0a18**, независимый CI #429 SUCCESS; native author CI #430 FAIL (старый contract_drift + unresolved `story_authoring` в parity). Следующий единый блок: честный source-wide CANON, настоящие новые причинные действия AI-GM, long-term BOOK_CHARACTER, затем native↔generator parity и реальные литературные/платформенные испытания. Не повторять готовое API, transfer и SQLite; Draft PR #133, без микро-PR.

---

## Новая игровая функциональность 2026-11-09 — действительное стартовое состояние книжного героя

Native PR #133, baseline code `071ed2b07bec9cc863aa22583288688337ed9eae` [CI #1087 PASS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128159). Готовится один новый крупный пакет, **пока требует собственный exact-code CI**: проверенный permanent characterId + источник первой главы + начальные предметы/факты, source-linked условия реальных выборов, новый проверяемый private v4 мир, RpgBookCharacterStartApi + JSON для внешних клиентов, показ проверенной роли в Flutter через движок, удаление двух прямых вызовов форматного импортёра NPC-мастером. [Техническая реализация и обязательные отрицательные тесты](RPG_BOOK_CHARACTER_START_INTEGRATION_RU_2026-11-09.md). CANON и свободный динамический AI-GM остаются открытыми; не размазывать пакет на микро-PR.

---

## 9 ноября 2026 — ПРИНЯТО: самостоятельный игровой API и перенос кампаний между клиентами

Код `071ed2b07bec9cc863aa22583288688337ed9eae` имеет **полный точный [CI #1087 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128159)**: Python reference, Dart, headless M1.7, Flutter, Windows Portable, Android APK; **M0 #1172 SUCCESS**. Replayed v3/v4 `.bworld` и private `.bwsave` можно одним self-contained `RpgCampaignTransfer` импортировать в чистое другое SQLite-хранилище (с явным согласием); тесты сравнивают проверенные `state_hash`, NPC/предметы/журнал/сцену. `journal_page` и `confirm_suggestion` проверяют revision/fingerprint и source authorization; Python HTTP-клиент работает без Flutter, без второй игровой логики и без HTTP_PROXY. **Не считать CI физическим UX или литературным QA.**

Детальный [аудит автономности](RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md) подтвердил оставшиеся пробелы: CANON/BOOK_CHARACTER/действительно свободный AI-GM, полные внешние authoring DTO/порты, портреты/media, browser/FFI/cloud, два прямых `RichPrivateBookworldImporter` вызова в Flutter NPC-мastере, реальная литература и устройства. Генератор **E6m/0.3.0a16 CI #420 PASS**, общий native External author #423 FAIL (старые pin/legacy parity). **Только один PR #133, Draft, не merge; main и E6m ownership не трогать.**

---

## 2026-11-09 — большой пакет client portability и проверка независимости

Native baseline `43930247ef0d2b3e67de7d05ac629fe5a9dd45a4` — [CI #1084 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42555732659), Python/Dart/M1.7/Flutter, Windows, Android. **Новый пакет требует НОВЫЙ exact-HEAD CI:** клиентонезависимый `RpgCampaignTransfer` (вместе исходный ZIP .bworld, .bwsave, checksum, source campaign, revision, stateHash), проверенная повторная установка в чистую библиотеку только с согласием и replay, `confirm_suggestion` (исключает незаметный AI ход), `journal_page`, stateHash из story_core, Python direct loopback без системного HTTP_PROXY. Проверки: v3/v4 native SQLite + два Python/Dart клиента в разных процессах + отрицательные и state/CAS случаи. [Обязательный аудит автономности](RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md).

Внешний генератор уже **E6m / 0.3.0a16** [CI #420 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42556984326). Прежний native External author CI #415 FAIL (6 pinned blobs / старый Dart parity), генераторная ветка отдельно зелёная, это НЕ единая совместная приёмка. Не менять main/генератор. Следующий крупный блок — настоящий CANON, подтверждённая роль героя, динамический AI-GM и полный literary book-to-RPG, потом реальные FB2/устройства.

---

# СТАТУС 9 НОЯБРЯ 2026 — ПРОВЕРЕННАЯ MULTI-CLIENT RPG-ОСНОВА

**Первый большой пакет принят:** [CI #1083](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554271712) полный SUCCESS на `31372b0b657fb0d0fa37476c1fcbc9fe614be525`, включая Python/Dart/M1.7/Flutter, Windows release bundle и Android debug APK. [M0 #1168](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554271699) SUCCESS. Готов отдельный Python-клиент, token-auth loopback HTTP host, единый чистый `RpgClientProtocol` v1 и настоящее SQLite/.bwsave сквозное E2E. До физического QA и продакшен Web/gRPC далеко.

**Второй функциональный пакет:** read-only `inspect_world`, native `audit_world` с `playable/blocked/inconclusive`, `suggest_action` только разрешённых choiceId и E2E по v3/v4 через Python; **точную новую приёмку смотреть после кода**, не выдавать прошлый #1083 за новый проход.

**Внешний автор 0.3.0a13** — stage E6k+ несмотря на старый branch E6g, [CI #414 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554315131). Но `External RPG author tests #413` в PR #133 FAIL: pin source `contract_drift` и не найден Dart пакет `story_authoring` в старом external probe. Согласование без отключения безопасности, права на другой branch не захватывать.

**Главные P0:** настоящий книжный CANON/BOOK_CHARACTER, dynamic AI GM с проверенным подписанным событием, полный source-locked whole-book pipeline, общий native/E6k+ compatibility, 2 реальные RU FB2 и физический Win/Android E2E. Только один Draft PR #133, без микро-PR и правок main.

---

# ТЕКУЩИЙ СТАТУС — 2026-11-09: мультиклиентный RPG-движок (приоритет)

**План:** [RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md](RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md). **Передача:** [START_NEW_CHAT_RU.md](../START_NEW_CHAT_RU.md). Записи ниже исторические, старые E6g/E6d-ярлыки неактуальны.

- Native Draft PR #133 на code SHA `8ba62b197d2b61f3f17a83f4da95ba80072a002a`, семь Flutter-independent Dart пакетов, локальный Dart API 0.1.0, Flutter + CLI; **нет** готового HTTP/gRPC/Web client gateway.
- CI #1082 **FAIL**: четыре Flutter теста ожидают «Добавить книгу» вместо «Добавить книгу или RPG»; Python/Dart/M1.7 PASS; Windows/Android SKIPPED. M0 #1167 PASS. Не объявлять общий CI зелёным.
- Генератор **E6k+ 0.3.0a12**, functional `44521f48250b804ce95eb4d79085c51e819b46f5`, docs `6c0eb8cacf1459a4ef8d3137b417f609cb25b9ad`. Историческое имя ветки всё ещё содержит E6g. Автор: ChatGPT Skill, приватные задания, Python/Dart native validator без обязательного Z.ai. External CI #409 PASS, синтетический, а native PR external parity FAIL (`contract_drift` и `story_authoring` dependency resolution).
- Открыто: multi-client versioned API + transport adapter, CANON/BOOK_CHARACTER/AI_FREEFORM, полная книга/роли/NPC/causal, совместная native↔generator parity, 2 реальные русские FB2 и Win/Android E2E. Не дробить PR #133, main и generator-owned код не трогать.

---

## 2026-11-09 — доверенная книга внутри игрового API

Единым функциональным блоком в PR #133:
- Исправлена ошибка Dart `assignment_to_final_local`, блокировавшая
  публичный импорт и множество Flutter-тестов на предыдущем HEAD.
- `RichPrivateBookworldImporter` возвращает проверенные origin+глава
  каждой сцены v3/v4 и количество проиндексированных глав.
  `RpgGameplayEngine` передаёт Flutter **только происхождение текущей
  достигнутой сцены**; нет преждевременной публикации будущих
  персонажей, цитат или неоткрытых событий.
- В `WorldPlayPage` появляются «По книге»/«Альтернативный сюжет»
  и номер физической главы, а после .bwsave происхождение
  восстанавливается из канонического ZIP.
- `RpgWorldIntakeApi` теперь сравнивает заявленный генератором охват
  с действительно проверенными `SOURCE_PASSAGE` по всем главам;
  длинные маршруты до 512 ходов поддерживаются без старого лимита 24.
- `RpgBookGameplayAuditApi` по запросу выполняет независимый
  `StoryCampaignCausalAudit` с настоящим `StoryWorld`, памятью,
  доверием и состоянием предметов NPC. Исходы:
  **playable / blocked / inconclusive**, различаются строго.
  Flutter запускает проверку в isolate; доказанный тупик блокирует
  установку, недостаток лимита не объявляется успешной приёмкой.
  Отчёт генератора НЕ является криптографическим доказательством
  прохождения двух маршрутов на устройстве.
- Добавлены тесты BookWorld v4 на 203 сцены, native SDK/SQLite
  и Flutter-отображения; форматы .bworld/.bwsave не перепаковывались.

Проверенная внешняя сборка E6: `658eac6ab4cc324cd2f22417c54936935610e68c`,
CI #42547920109 PASS (синтетическая книга).
**Текущий новый native PR коммит требует полного CI.**
Остаются: реальный CANON, полная семантика BOOK_CHARACTER,
динамический AI GM, генерация редакторских данных из всей книги
и испытания на 2 настоящих русских FB2 + Windows/Android.
Не трогать E6, main; не создавать микро-PR.

## 2026-11-09 — приём готовых миров внешнего генератора через RPG API

Внешний автор 0.3.0a11 уже использует native PR #133 и
`LocalRpgGameApi`, но последний генераторский CI для
`finalize-extended` сообщил `campaign_not_private`
(входной `rights_status`, а не нарушение native runtime).
Не менять generator-owned `tools/rpg_author` в этом чате.

Добавлен отдельный **не мутирующий игру** `RpgWorldIntakeApi`:
импорт готовой игры v1/v2/v3/v4 проходит настоящие Dart
`BookworldImporter`/`PrivateBookworldImporter`/
`RichPrivateBookworldImporter`, выдаёт статус сцен,
предметов, NPC, финалов, fingerprint/SHA. Необязательный
отчёт `*.readiness.json` генератора v4 проверяется на
точный SHA256 игры/источника, охват сцен и глав,
2 различные терминальные концовки и идентификаторы
native-route отчёта; неверный отчёт отклоняется,
**но не считается криптографическим доказательством
действительного воспроизведения партий на устройстве**.
Литературный канон и публикация НЕ подтверждаются.
Flutter `LibraryPage` показывает отдельный предпросмотр,
позволяет приложить отчёт, установить игру только по
явному решению, повторно проверяет архив перед установкой.
Библиотека/SQLite и прежние сохранения не очищаются.
Предпросмотр работает в isolate, подключение .json
остаётся действием клиента. Добавлены SDK negative tests,
native API install/start и Flutter widget review tests.

Всё в Draft PR #133; `main` и ветка внешнего генератора
остаются нетронутыми. **Exact SHA CI нового коммита требуется**.
Дальше — сценарный API для полноценной литературной
автоматизации и реальный E2E на двух русских FB2, без
дробления задач на микро-PR.

## 2026-11-09 — один проверяемый контракт создания RPG

Вместо новых микроэтапов одним функциональным пакетом связываем
короткий офлайн-путь и поактовую подготовку:
`RpgCreationIntent` и `RpgCreationPolicy` в независимом
`story_authoring`; `RpgCreationApi` в `rpg_api`;
экран выбора режима `BookRpgStartPage` и `QuickRpgPage`
используют один режим от выбора до компиляции.
`QuickRpgBuilder` теперь вызывается только через публичный API,
а не напрямую из Flutter. Поактовые компиляторы сверяют тот же
контракт с проверенной карточкой выбранного героя.
Приёмка включает независимое создание реального короткого
`.bworld`, отрицательные проверки неподдерживаемых режимов,
экранный тест переноса выбора режима и запрет прямых вызовов.
`CANON`, свободный мир и динамический AI-мастер **не включены** —
строго отказываем вместо подмены другим режимом. Роль героя
`character_id` — подтверждённая личность, не импорт чужих секретов.

**Проверить полный CI на точном новом HEAD.** Не изменять
`main`, не вмешиваться во внешний E6g и не дробить пакет на PR.

## 2026-11-09 — единый многоактовый компоновщик сюжета

`MultiActTrialPlanComposer` вынесен в `story_authoring`.
Его вызывает и `MultiActTrialCompiler`, и независимый
`RpgMultiActTrialApi.composePreviewPlan`; Flutter перестал
собирать игровой план локально. Добавлен headless-тест
паритета двухактового плана и безопасного `includeNpc:false`.
Проверка границ CI теперь запрещает возврат сборки
`BookwideSourceEncounters.attach` в Flutter.
Новые изменения в Draft PR #133 требуют приёмки CI
на точном текущем HEAD, прежде чем их считать завершёнными.
Основное приложение и внешний генератор E6g не смешивать.

## 2026-11-09 — MultiActTrialPage подключён к публичному API

После успешного основного CI #1070 (`e3daf03d`) добавлен
`RpgMultiActTrialApi` и `LocalRpgMultiActTrialApi`: старый
`MultiActTrialPage` передаёт в них полную многоактовую
компиляцию, проверку предметов, подтверждённые эффекты и
финальную проверку приватного мира. Правила используют
существующие методы `story_authoring`, без дублирования.
Старые UI, согласия, черновики, NPC и семантические проверки
сохранены, `.bworld`/`.bwsave` не изменялись.
Есть автономный тест публичного API и CI-boundary.
**Приёмку текущего HEAD необходимо подтвердить результатами CI.**

Далее: единство редакторских сценариев, CANON/ALTER_FATE,
реальные роли, проверяемые свободные действия ИИ.
Main и параллельный E6g не изменять.

## 2026-11-09 — Flutter использует единый автономный RPG Workflow API

После CI #1065 SUCCESS на `081fc365` экран
`WholeBookNpcCampaignPage` переведён на `RpgCampaignWorkflowApi`.
Теперь базовый мир, принятие предметов, NPC и оба финальных пути
художественного текста проходят через один state-gated API движка.
`CampaignProsePage` получила клиентские колбэки для подтверждённого
возврата, прежний интерфейс и локальные данные сохранены. Добавлены
widget-тесты делегирования и CI-boundary против возврата прямой
сценарной логики во Flutter.

**Новые коммиты требуют отдельной полной приёмки CI на HEAD.**
`main` и параллельный E6g не трогать. Следующий блок —
остающиеся экраны/долговременное состояние мастера,
CANON/ALTER_FATE, обобщённые роли и тесты с реальной книгой.

## 2026-11-09 — единый автономный кампанийный сценарный процесс

Добавлен `ReviewedCampaignWorkflow` в `story_authoring` и публичный
`RpgCampaignWorkflowApi` в `rpg_api`. Объединены существующие строгие
проверки исходной книги, героя, предметов, NPC, художественного текста,
причинного аудита и итогового `.bworld`, без второго runtime.
У этапов `base/gameplay/dialogue/complete` зафиксированы SHA256 мира,
sourceFingerprint, plan/hero/story digests; переход только по точному
согласию. Возможен путь без облака и без NPC/предметов.
Добавлены автономные E2E-тесты 2 актов с offline-финалом,
свежими согласиями и полным художественным этапом с CAS.
**CI по новому HEAD нужно проверить, пока не объявлять PASS.**
Внешний E6g и main не изменять. Далее — режимы CANON/ALTER_FATE,
обобщённый NPC/hero state и крупный E2E реальной книги.

## 2026-11-09 — проверенный путь полной прозы через независимый RPG API

В Draft PR #133 код `story_authoring/campaign_prose_contract.dart` теперь
содержит `CampaignProseManifest`, `CampaignProseRequest`,
`CampaignProseCheckpointCodec`, `CampaignProseBatchVerifier`,
`CampaignProseFinalizer`. Публичный `RpgCampaignProseApi` доступен
Flutter и CLI; `BookToRpgWorkflow` подготавливает **все сцены**
уже компилированного source-bound мира. Flutter сохраняет только
файловый порт, CAS, UI, cloud consent/Z.ai и isolate worker.
Контрольные точки остаются обратносуместимыми, прежние `.bworld`
и `.bwsave` не мигрируются. Добавлены headless регрессии сцен/финала.
[Архитектура](docs/RPG_API_CLIENT_BOUNDARY_RU_2026-11-08.md).

**Приёмка нового кода ещё не подтверждена до CI на точном HEAD.**
Следующие цельные блоки: контекстно-управляемый оркестратор проверенного
авторства, поддержка CANON/ALTER_FATE и ролевой модели, AI-freeform
как проверяемое предложение, реальные русские FB2 и Win/Android E2E.
Main и отдельный E6g не трогать.

# AI Story RPG — статус полного сценарного потока

## 2026-11-09 — Модельные предложения проверяются автономным RPG API

В том же Draft PR #133 перенесены все чистые проверки ответа Z.ai в
`packages/story_authoring`: NPC, проза, предметы/знания, литературная
критика. `RpgProposalReviewApi` обеспечивает одинаковый контракт для
Flutter и других клиентов; prompts/валидация теперь не принадлежат UI.
Flutter только сеть, ключи, согласие, retry и преобразование ошибок.
Добавлен независимый полный набор контрактных тестов.
Документ: `docs/RPG_AI_PROPOSAL_CONTRACT_RU_2026-11-09.md`.

Приёмка на **новом SHA обязательна**: не объявлять зелёный CI без
точного GitHub Actions PASS. Ранее CI #1052 SUCCESS на `77c59cd0`.
Остались пакетная оркестрация, полная проза, CANON/ALTER_FATE,
персонажи/AI_FREEFORM и E2E реальных FB2 в Win/Android.
Main и внешний E6d не трогать, PR #133 оставить Draft.

## 2026-11-09 — Pure-Dart авторство через RPG API, второй функциональный пакет

В рамках того же Draft PR #133 перенесены 4 автономные авторские проверки
(NPC continuity, graph overview, cross-act evidence, readiness) из Flutter
в `packages/story_authoring/lib/src`. Flutter-файлы теперь *только* export,
остались без смены UI/логики. Добавлены самостоятельные тесты NPC/графа
и `BookToRpgWorkflow`: точная редакция/отдельная сказка, resumable
offline scan, готовность, только подтверждённая строгая компиляция.
`packages/rpg_api` экспортирует эти проверки и методы
`RpgAuthoringApi.openSource/prepareBook`; CI проверяет, что правила
не вернулись в приложение. `docs/RPG_API_CLIENT_BOUNDARY_RU_2026-11-08.md`
обновлён.

Следующее: выделить чистые проверки AI/NPC-прозы, пакетные сценарные
операции и согласованный финальный управляющий workflow (cloud consent
как подключаемый порт). Затем полная поддержка режимов/ролей и второй
самостоятельный клиент. **Не объявлять CI зелёным для нового SHA без
GitHub Actions PASS.** main, E6d и старые .bworld/.bwsave не менять.

## 2026-11-08 — Flutter как клиент, самостоятельный RPG API (архитектурный пакет)

Принято принципиальное решение: **движок предоставляет API**, Flutter — только один клиент.
Новый `packages/rpg_api` описывает независимые контракты `RpgGameApi` и
`RpgAuthoringApi`; локальные реализации делегируют в прежние
`rpg_gameplay` и `story_authoring`, не создавая второй логики и форматов.
Flutter `DeviceWorldLibraryGateway` и `book_isolate_workers` теперь используют API.
CI получил проверку седьмого pure-Dart пакета, отдельный без-Flutter API E2E
и verified SQLite source hook. Документ:
[docs/RPG_API_CLIENT_BOUNDARY_RU_2026-11-08.md](docs/RPG_API_CLIENT_BOUNDARY_RU_2026-11-08.md).

**НЕ объявлять CI PASS до фактического результата нового коммита.**
Открыто: перенести остальные не-платформенные проверки и сценарный
оркестратор из Flutter, формализовать CANON/ALTER_FATE/роль и единый workflow,
испытать независимых клиентов и реальные книги. PR #133 оставить Draft,
main и внешний E6d не трогать.


## 2026-11-08 — RPG-движок и авторство отделены от Flutter (код 480c0e4)

Главный документ: [docs/ENGINE_AUTONOMOUS_RPG_COMPLETION_RU_2026-11-08.md](docs/ENGINE_AUTONOMOUS_RPG_COMPLETION_RU_2026-11-08.md).
Работы в **одном Draft PR #133**. Кодовый SHA `480c0e448a818e624809936a7c7485683c5a4adc`.
`rpg_gameplay` держит все игровые RPG-проекции/FreeText/журнал/социальную
память и SQLite-переходы; `story_authoring` — полный исходный сценарный
конвейер, NPC и предметные последствия, source review, причинность,
ручную привязку и приватную компиляцию. App — платформа, экран, ключи/consent,
путь SQLite, файлы и cloud-адаптер, не второй движок.

Мандат в CI: `tools/ci_check_engine_boundaries.py` (6 пакетов),
`packages/rpg_gameplay/test`, standalone CLI, `packages/story_authoring/test/headless_*`.
Exact-code CI #42497799413 пока идёт; не объявлять финальную приёмку
и Windows/Android успешными до фактических jobs. E6d отдельно,
main не менять, Issue #118 не закрывать. Следом две реальные русские FB2,
литературный CANON/ALTER_FATE, live GLM только с согласием,
реальный Win/Android UX.



## 2026-11-08 — защита проекции NPC в игре и отображение текущей сцены

**Актуальный КОДОВЫЙ SHA `e397ed4591987d94ff99db2d0d2f80d7b6e4cfeb`**, единый Draft PR #133. [Предыдущий крупный CI #42486852024](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42486852024) **COMPLETED SUCCESS**: Python, Dart, M1.7, Flutter/widget, Windows portable и Android APK; M0 #42486852053 SUCCESS. Это подтверждает синтетические source-locked 0/1/2 NPC, реальный SQLite и `.bwsave` roundtrip. Не путать с полным литературным CANON, физическими устройствами или live GLM.

**Новые изменения `e397ed4`:** `WorldLibraryGateway._view` после подписанного NPC dialogue review и SQLite replay выдаёт Flutter только встреченные NPC-имена, текущие life-state и владельцев предметов. Раньше `WorldPlayPage` фильтровал будущих владельцев локально, но сам `WorldGameView` всё ещё содержал future actor/custody/life metadata; теперь безопасный фильтр на границе runtime → UI, независимо от нового экрана. `WorldPlayPage` показывает название ТОЛЬКО достигнутой сцены из importer-verified `sceneNames` — не историю будущих глав. Раздельные Flutter тесты: 280dp и текст 200% с двумя NPC, scrollable NPC card, текущая сцена видна/будущая скрыта. В реальной 1/2-NPC SQLite/portable интеграции добавлены проверки отсутствия будущих имён/владельцев/жизней до события и точного восстановления проекции после хода/импорта. Никаких изменений в `story_core`, sqlite format, `.bworld` или E6d.

**Новая exact-code CI**: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42489208304. На момент записи Python reference, Dart engine/scenario SUCCESS, Flutter widget и M1.7 ещё выполняются; M0 https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42489208295 SUCCESS. НЕ объявлять Windows/Android для этого SHA принятыми до успешных jobs и артефактов. External E6d FAIL отдельно, не менять. При необходимости исправить точную ошибку в этом же Draft PR.

**Дальше крупными пакетами:** после exact-head CI — единый реальный UX-режим с готовой книгой/игрой на Windows и Android, проверка theme/280dp/200%, панели Герой/Предметы/Журнал/NPC, диалоги и локальные портреты, системные backup pickers. Реальные 2 разные русские FB2 с полноценной source-bound причинностью, CANON/ALTER_FATE и live Z.ai с явным consent остаются НЕ готовыми. Цель — полноценно автономный движок и авторство без второго engine. Issue #118 пока открыта, PR #133 Draft, main/E6d не трогать.


## 2026-11-08 — единый UI↔engine NPC acceptance: идентичность, приватность и реальный SQLite

**Последний кодовый SHA [48d58f6](https://github.com/shonentez-afk/AI-Story-RPG/commit/48d58f6c9aed8e05aa2c6f661c62b3944ee6b8ee)**, всё в исходном Draft PR #133, main/E6d не менять. Вошли логически связанные коммиты 0791a8f, 7f4624d, af8feb7, b9aa019, df66621 и исправление контрольной Python-фикстуры 48d58f6. Ни второго движка, ни новых форматов .bworld/.bwsave, ни новых PR.

- `WorldLibraryGateway._view`: после строгой проверки `scene_dialogue_knowledge` и `RichNpcDialogueKnowledge.redact` строится **только текущая разрешённая** карта именованных реплик в постоянные actor IDs; одинаковые имена и будущие/закрытые реплики исключаются. `WorldGameView.portraitStorageKeyFor` никогда не подбирает фото по имени в source-reviewed NPC-сцене.
- `RichNpcDialogueKnowledge.redact` теперь скрывает имя вместе с закрытыми словами (speaker=null); Flutter `DialogueStage` показывает «Скрытая реплика» с замком и без загрузки портрета. После фактического события память/знание возвращают точного говорящего. Старый legacy name-key PNG по имени допускается только в старых unreviewed сценах; текущие verified NPC используют actor_id и локальные фото. Локальные фото **не входят в переносимый `.bwsave`**; нельзя объявлять обратное.
- `WorldPlayPage` теперь ограничивает список предметов других героев только NPC, уже подтверждёнными `npcRelations`, и показывает передачу в той же карточке NPC. Ни неизвестные предметы, ни будущие владельцы не раскрываются. Реальная SQLite-цепочка и сторителлинговые правила не менялись.
- В CI для Flutter есть две **только синтетические, source-locked private** rich-v3 фикстуры `NPC_One_Rich_Items_v3.bworld` и `NPC_Two_Rich_Items_v3.bworld`, собранные штатным Python-автором. Тест `world_integration_test.dart` проводит реальный `DeviceWorldLibraryGateway`/SQLite до и после разрешённого `wait`, проверяет 1 и 2 NPC, блокировки, actor_id, memory/trust, владельца карты, journal, `.bwsave` экспорт/импорт и открытие всех панелей в `WorldPlayPage`. Существующий River тест покрывает 0 NPC и hero/items/journal/SQLite. Это **не** доказательство литературного CANON и не тест GLM.

**CI кодового коммита**: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42486852024. На момент записи Python reference, Dart engine/scenario, M1.7 **SUCCESS**; Flutter widget suite ещё выполняется, Windows/Android итог не объявлен. M0: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42486852053 — SUCCESS. Предыдущий M1.7 FAIL из-за переносов строк в 2-NPC fixture исправлен через chr(10) и строгую проверку четырёх реплик; контракт не ослаблялся. E6d external FAIL — отдельный блокер, оставить в параллельной работе.

**Приёмка ещё не полная**: проверить exact-head CI и APK/Windows, испытать два разных настоящих русских FB2 и live GLM только по consent; нужны реальные screenshots/device UX, доступность при 280dp/200%, взаимодействие по канону, а также полная семантика CANON/ALTER_FATE и AI_FREEFORM (текущий free-text лишь выбирает разрешённый choice_id). Issue #118 НЕ закрывать. Дальше продолжить единым крупным функциональным пакетом, не создавать микро-PR.


## 2026-11-08 — ПРИНЯТ единый UI-этап Resume / 0 NPC / адаптивный игровой экран

**Точный КОДОВЫЙ SHA [`372d271403cd630871f8628e887e21d5a76dce11`](https://github.com/shonentez-afk/AI-Story-RPG/commit/372d271403cd630871f8628e887e21d5a76dce11)**, только Draft PR #133. [Основной CI #42483916378](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42483916378) **COMPLETED SUCCESS**: Python reference, Dart engine/scenario, M1.7, Flutter analyze + весь widget-suite, Windows portable release bundle, Android debug APK — каждый SUCCESS. [M0 #42483916343](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42483916343) SUCCESS. External RPG author E6d #42483916341 — отдельный FAIL, отложен, НЕ исправлять в этом PR. Publish Windows + Android test release в данном запуске SKIPPED (не объявлять релиз опубликованным). Сборки не равны физическим испытаниям устройств.

Проверенные артефакты запуска: `AI-Story-RPG-Windows-portable` (artifact ID 13618124725, 15 247 288 байт) и `AI-Story-RPG-Android-debug` (artifact ID 13618494689, 88 630 023 байта); также `AI-Story-RPG-BookWorld-demo` и публичная русская Grimm Frog Prince FB2. Они доступны в Artifacts запуска #42483916378 (архив GitHub Actions; НЕ прямой опубликованный APK).

Сделано внутри ОДНОГО PR: source-locked `BookRpgStartPage` «Продолжить создание RPG» направляет к существующим `ZaiWholeBookAnalysisPage` / `SourceIndexPreviewPage` по проверенным checkpoint и fingerprint исходной книги. Не отправляет облачный запрос без отдельного согласия, не восстанавливает consent, не подменяет повреждённые/чужие данные. Экран переделан в `SingleChildScrollView` с eager-компоновкой всех 3 главных действий (Resume / офлайн-проба / полная подготовка через ИИ), подробные ограничения в `ExpansionTile`; ошибки показываются рядом с Resume. Это закрыло физически недоступные кнопки при 320dp/200% и связанные CI-ошибки.

Связанные изменения предшествующего кода: 0-NPC компиляция и проверка конкретного базового BookWorld ZIP без выдумывания NPC; адаптивная GameQuickBar Герой/Предметы/Журнал/NPC; блокировка future-NPC спойлеров; локальные портреты по однозначному встреченному actor_id с legacy read; явное ограничение свободного ИИ-ввода разрешёнными `choice_id`; Stop для попыток Z.ai. Все Flutter widget-тесты этого пакета теперь PASS, тест реально проверяет нулевой NPC-пакет без отключения компилятора.

**НЕ объявлять полную RPG 1.0 завершённой, Issue #118 НЕ закрывать.** Следующий большой пакет — ОДНА сквозная UI↔signed runtime приёмка 0/1/2 NPC через `story_core`, источник/роль, литературные реплики и портретные ID, предметы/владельцев, последствия, журнал, реальный SQLite restart и переносимый `.bwsave`; затем 2 разных РЕАЛЬНЫХ русских FB2 с проверенным каноном, отдельно согласованный live GLM, физический UI аудит Windows/Android на малых экранах, accessibility/контраст/резервные копии. Подмена подписанных фактов моделью запрещена. Полноценные CANON и ALTER_FATE по произвольной книге и AI_FREEFORM-master НЕ готовы.

**Границы проекта:** автономный `story_core` и pure Dart `story_authoring` остаются одним движком и компилятором; Flutter — UI/провайдер/файловый адаптер. Никаких новых PR, изменения только в Draft PR #133, не менять main/E6d. Сначала крупный пакет, затем единая приёмка; не дробить по полям/экрану.


## 2026-11-08 — единый проверяемый Resume для облачного и офлайн-авторства

Основной кодовый SHA: 3f0f16ac5195edc00316c5c3fef783afa9e8079b, тот же Draft PR #133. Коммиты 20bebee9 (первый source-locked Resume), 6b27342 (исправление flutter analyze), 3f0f16a (точное восстановление как анализа всей книги, так и локального исходного редактора). НИКАКИХ новых PR, second engine, main, E6d.

Единая библиотечная точка «Создать RPG» содержит «Продолжить создание RPG». Книга индексируется в существующем worker; по source fingerprint читается реальный ZaiAutoWholeBookAnalysis.read — pure-Dart PortableWholeBookAnalyzer проверяет целиком source windows/checkpoint. При завершённых сохранённых фрагментах открывается ТОТ ЖЕ ZaiWholeBookAnalysisPage, далее прежний BookActDraftPage/редакторы. Если нет сохранённого AI-анализа, проверяется прежний локальный SourceAnalysisSession (scope mentions): decodeSourceAnalysisInWorker сверяет checksum, exact indexed chunks и реальные обработанные задания, затем открывает тот же SourceIndexPreviewPage с общим исходным индексом. Пустой/чужой/повреждённый checkpoint — отказ без автоповтора или уничтожения. Ни одна кнопка Resume НЕ отправляет POST, не восстанавливает consent, не устанавливает непроверенный BookWorld.

Новые Flutter widget-регрессии: 1) частичный AI-анализ восстанавливается без дополнительного POST; 2) другая редакция и отсутствие данных fail closed; 3) повреждённый checkpoint не удаляется; 4) локальная сохранённая проверка действительно открывает SourceIndexPreviewPage; 5) пустой локальный анализ не считается прогрессом. Также дотестированы прокрутка фактов героя и real isolate в 0-NPC редакторе; Flutter CI ещё не объявлен PASS.

Предыдущий CI #42476509269 для a158fdd FAILED только по двум widget assertions (zero-NPC fake clock и lazy hero facts); Python/Dart/M1.7 SUCCESS. Первый CI #42481426029 на 20bebee9 остановился на лишнем импорте в тесте; он удалён кодом 6b27342. Exact-code [CI #42481673634](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42481673634) на 3f0f16a: Python/Dart SUCCESS, M1.7/Flutter в прогрессе на момент записи. M0 [#42481673632](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42481673632) SUCCESS. Проверить финальный результат Android/Windows; не отмечать зелёным до фактических jobs. E6d external FAIL — отдельная ветка, не трогать.

После exact-head CI: улучшить step UI по созданию игры, сохранить выбранного героя и NPC roles во всех экранах (0/1/2), сквозная SQLite проверка 2 реальных русских FB2, offline полностью без сети, живой GLM только с consent, Windows/Android UX / backups / accessibility. Полный CANON и динамический AI_FREEFORM не выполнены; не заявлять готовности до всех gate. Имеющийся free-text AI только ищет разрешённый choice_id, не придумывает действия.


## 2026-11-08 — реальная приёмка игрового UI и исправление Flutter-регрессий

Последний кодовый SHA a158fdd5a7f240d1f1f084c8f513c353978f944e в том же Draft PR #133. Предыдущий CI #42475112000 FAILED: ровно 8 widget-тестов; Python, Dart, M1.7 SUCCESS, Win/Android SKIPPED. M0 #42475112012 SUCCESS. Не считать это готовностью релиза.

Причины по GitHub-логам: тесты ожидали старое название «Подготовить к RPG» вместо нового «Расширенный редактор»; прежний всегда видимый technical role ID заменён раскрываемой диагностикой; длинные пояснения переполняли Column информационного sheet на 320×640 при 200% шрифте; открытый свободный ввод создавал поле за физическим viewport; новый zero-NPC widget-тест ожидал pumpAndSettle во время ещё незавершённого UI цикла. Исправлено без отключения проверок: пояснения перемещены в прокручиваемое тело, диагностика героя также там; тесты прокручивают до доступного поля и проверяют фактическое состояние, старые ожидаемые подписи обновлены.

Exact-code CI для SHA a158fdd: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42476509269 . На момент записи Python/Dart/M1.7 SUCCESS, Flutter widget IN_PROGRESS, Windows/Android ещё не запущены. M0: https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42476509262 . Точный окончательный результат ПЕРЕПРОВЕРИТЬ; не объявлять общий CI зелёным на основании синтетических тестов.

Следующий единый функциональный блок: объединить уже существующий checkpoint/Resume анализа книги и редакторские сохранения NPC в один экранный маршрут «Продолжить создание RPG» по source fingerprint/revision, без автоматического восстановления consent. Затем E2E 0/1/2 NPC, проверяемые Hero/Items/Journal/portrait speaker identity, SQLite restart и физическая Win/Android приёмка. Не создавать второй движок, вторую библиотеку или микро-PR. Полные CANON/ALTER_FATE, реальные два FB2/live GLM и свободный AI-authoring остаются незавершёнными.

main и E6d не трогать; PR #133 до всех gate остаётся Draft.


## Интеграция единого UI и маршрута без NPC — 8 ноября 2026

Кодовые коммиты d1f604a и e81bea1 в существующем Draft PR #133. Выполнен единый первый инкремент UI: проверенная базовая игра с нулём NPC теперь не отклоняется редактором, строгий NPC-writer не вызывается с пустыми разговорами, исходный архив и эффекты привязаны к SHA и ревизии. Обычные 1/2 NPC идут прежним strict путём. Общие проверки source, hero, narration, import, install и SQLite сохраняются.

Игровая панель переносит четыре пункта при ширине 280-300 dp или увеличенном шрифте. Герой не показывает спойлеры о будущих состояниях невстреченных NPC; технический role ID скрыт в диагностику. Портрет уникального известного NPC привязывается к actor ID с чтением legacy локального ключа имени. Одинаковые имена не разрешают подмену. Предметы и журнал поясняют реальные ограничения.

Свободный ввод с ИИ остаётся строго подбором уже разрешённого choice_id, не динамическим AI game master. Показана Stop-кнопка для новых запросов, отправленный POST нельзя отозвать. В библиотеке главный путь назван «Создать RPG», расширенный редактор отделён.

В тесты добавлены регрессии 0 NPC, 280 dp / 200% и отсутствия спойлеров. Exact-head CI нового кода ещё НЕ принят. Предыдущий b337b3a CI #42466457691: Android FAILURE только при загрузке Gradle 9.3.1 (HTTP 504), остальные задачи SUCCESS; Android job 128688440171 перезапущен. M0 #42466457759 SUCCESS. Не переносить в main и не считать закрытым P0/#118 без полного green CI, двух RU FB2/live GLM, физического UI QA.

Следующее: завершить общий мастер с Resume, 0/1/2 NPC end-to-end, сохранить функциональность core и parity UI, расширить игровую информационную проекцию/портретные speaker IDs, исправить настройки и удаление приватных черновиков. Затем доказать CANON и ALTER_FATE на реальных книгах. Не трогать E6d, main; не делать микро-PR.


## Проверенное много-NPC авторство поверх полной книги v4 (код b337b3a)

[**Точный отчёт, тесты, архитектура и оставшиеся интерфейсные задачи**](P0_BOOKWIDE_V4_REVIEWED_NPC_AND_CI_RU_2026-11-08.md). Исправлен пропуск `expanded:true` через `BookwideActPlanner`, `CrossAct`, `MultiAct`; `WholeBookNpcSourcePlan` и `ReviewedNpcCampaignBookworldWriter` работают с независимо проверенной богатой v4 и сохраняют свои v3 контракты. Actor-specific knowledge, social memories и NPC replies доступны только через реальные `StoryWorld.apply` решения, redaction проверен. Новый полный регрессионный сценарий: 18 актов/144 событий/3 NPC/161 шаг/SQLite restart; старый без-NPC 18 актов/216 событий/233 действия сохранён. Исправлен CI 504 при загрузке Ink с SHA-256 check. Код `b337b3a6d46f7ee675b2b4fc3b63485f675160b9`; [CI #42466457691](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42466457691), M0 #42466457759: точный финальный результат ПЕРЕПРОВЕРИТЬ, не считать pending PASS. **main/E6d не трогать, один Draft PR #133, не мельчить.** Следующий крупный пакет — единый UI-мастер и игровые экраны после реальной source/literary приёмки.


## Поактовая проверка причинности без потери постоянной памяти (d87587d)

[**Подробный отчёт: что реализовано, как доказана безопасность, CI и остаток**](P0_LONG_BOOK_FUTURE_FLAG_CAUSAL_PROOF_RU_2026-11-08.md). Новая `FutureFlagLiveness` использует backward fixed point, чтобы при v4 схлопывать лишь *поведенчески равнозначные* прошедшие флаги при проверке, но НЕ удаляет outcome flags, `WorldEvents`, knowledge NPC, social memory, inventory, SQLite или сохранения. Реальный `story_core`, rich-v4 importer, `StoryPlan`, M2c, causal/invariant, cross-act и ownership-аудиты используют один контракт; v3 без изменений. Регрессии: 20 актов/40 флагов с поздней отрицательной проверкой, 18 актов/216 событий/17 мостов/233 SQLite действий. **Кодовый SHA `d87587db24682754814fdeebea120d2dd8238f00`**, [CI #42463600007](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42463600007), M0 #42463600025 — фактический итог перепроверить (на момент записи M1.7 и Flutter ещё выполнялись). Не считать CANON/AI_FREEFORM по любой книге готовыми. E6d/main не менялись, один Draft PR #133, **не дробить**.


## Последняя работа: прямой source-reviewed multi-act → v4 (код 350502d)

[**Факты, тесты, архитектура и следующий шаг**](P0_BOOKWIDE_EXTENDED_V4_AUTHORING_INTEGRATION_RU_2026-11-08.md). Одна связка в существующем Draft PR #133: `StoryPlan`/M2c/preflight/translator поддерживают opt-in v4 без обходного v2; `build-draft-extended` компилирует из source/editorial checkpoints независимо от Flutter/сети; MultiAct проверяет все event ID и главы, все causal/NPC/role gates. Синтетические испытания: 203 сцены/201 ход с replay; 72 source events/60 интерактивных наблюдений в 6 актах. Кодовый SHA `350502df7ed09812e9ce9a750d9b3843a1708c33`: [CI #42461603117](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42461603117) — Python, Dart, M1.7 и Flutter analyze SUCCESS, окончательный Flutter widget-run перепроверить; M0 #42461603120 SUCCESS. E6d отдельно FAIL. **Не заявлять готовой полного CANON RPG из любой книги:** 30 актов — номинальный предел, causal cap 8000 может блокировать сложные схемы; генератор полного лора/свободного ИИ и игровой UI ещё не приняты. Главный следующий блок — поактовые доказательства и долговременная память, НЕ простое увеличение лимитов. main/E6d не трогать и не делать микро-PR.


## Новый код: расширенный приватный BookWorld v4 (f30e590)

[**Подробный отчёт по версии, тестам и оставшимся блокерам**](P0_VERSIONED_EXTENDED_BOOKWORLD_V4_RU_2026-11-08.md). v4: 1024 сцен, 64 флага, 96 предметов, 128 фактов; изначально подтверждённый инвентарь, actor-specific знания, tick/time; отдельный opt-in `build-extended`, v3 не изменяется. Это **формат/runtime/CLI**, а не завершённый FB2→CANON RPG: генератор `StoryPlan` и промежуточные компиляторы пока в 192/32/12, нужен единый v4 authoring с семантической приёмкой. Код `f30e59007a913724f6466f3e70b27b926025bceb`; [CI #42458636957](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42458636957), M0 #42458636967 — читать окончательные выводы перед решением. E6d/main не трогать, один Draft PR #133, **не мельчить**.


## Новый единый перенос multi-act/whole-book model port (код 3c1a7aa)

[**Полный статус, файлы и gate**](P0_STANDALONE_MULTIACT_AND_BOOKWIDE_MODEL_PORT_RU_2026-11-08.md). `story_authoring` теперь содержит общий multi-act/NPC компилятор, reviewed hero, литературные и prose типы, source/chronology/causal gate и `PortableWholeBookAnalyzer` (точные окна, source hashes, consent, Resume, cancellation, provider callback). Flutter использует те же типы через export и остаётся только адаптером Z.ai/OS. **Это ещё не автоматический CANON FB2→RPG**, лимиты богатого формата и game UI остаются. Код `3c1a7aa19853d5ea13a031db4dc2ad06b80b2b96`. [CI #42455037055](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42455037055) — точный итог перепроверить; [M0 #42455036949](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42455036949) SUCCESS. E6d/main не менять. Один Draft PR #133, никаких микро-PR.


## Автономная подготовка, source-locked ИИ и перенос компилятора (код df592c9)

[**Отчёт по новому функциональному пакету**](P0_AUTONOMOUS_COMPILER_AI_PROPOSALS_RU_2026-11-08.md). В `story_authoring` теперь исходные редакторские NPC/knowledge/item bridges, native v2/v3 compiler на `Isolate.run`, `PortableReviewedDraftCompiler` и pure `StoryProposalValidator` для Z.ai и CLI. Добавлены `review-plan` и `build-draft`: из проверенных source/editorial/scene checkpoints получается частный rich-v3 без Flutter/сети; НЕ автоматически доказанный CANON. Точный кодовый HEAD `df592c97599b9d977e4f8aaf5deac913c024533b`; [CI #42452212594](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42452212594): Python/Dart и автономные Dart+Python проверки прошли, полный UI/Windows/Android до окончательного результата не считать PASS; [M0 #42452212571](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42452212571) SUCCESS. Один Draft PR #133; E6d/main не трогать. Следующий блок — самостоятельный весь `multi_act_trial_compiler` + `whole_book_npc_campaign` + hero/prose/reviewer + model port и масштабирование >48/192, затем единый GUI по заранее детальному проекту.


## Автономное авторство: начат кодовый пакет

[Фактический ход автономизации и блокеры](docs/P0_AUTONOMOUS_AUTHORING_PROGRESS_RU_2026-11-08.md). В коде `0ce8ea2` перенесены 25 модулей источника/событий/семантики/StoryPlan в `packages/story_authoring`; Flutter re-export вместо дублирования. CLI: `inspect-source`, `scan-source` с Resume, `build-reviewed`, `verify-world`. Источник, книги, причинность и импорт проверяются автономно, но **полный литературный FB2→RPG и модельное авторство пока не независимы**; не выдавать за готовое. Приёмка нового кода: [CI](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42448890904), M0 #42448890906 SUCCESS; точный статус CI перепроверять. Сначала закончить pure-Dart authoring слой, затем GUI по утверждённой схеме; никаких микро-PR, main/E6d не трогать.

## Сквозной аудит движка и GUI (8 ноября 2026)

[Отчёт](ENGINE_FORMAT_UI_GAP_AUDIT_RU_2026-11-08.md): найдены ограничения rich-v3 по role/knowledge/time/scene count, потенциальный спойлер lifeStates будущих NPC на экране «Герой», неполная игровая проекция карточек/сцен/вещей/журнала/условий, границы Z.ai free text (разрешённые choice only, <=32 из 100, без явной отмены, disclosure labels). Внести внутрь уже 2 крупных пакетов, не делать отдельные PR; это документы, не код.

## Сверка Hero/Inventory/Journal и FreeText AI с core — 8 ноября 2026

[Дополнение к плану](PLAN_TWO_UX_AUDITS_ONE_PR_RU_2026-11-08.md): 3 панели получают реальное signed/SQLite состояние, но пока выводят упрощённые списки; журнал показывает choice/event, не ввод игрока. Offline/AI FreeText лишь предлагает существующий enabled choice; AI с per-turn consent передаёт только текст игрока и имена допустимых choices, не выдумывает новый ход, не пишет SQLite без второго подтверждения. UI показывает общие причины для особых NPC gates. Всё отнесено к первому большому UX-пакету; реализовать динамический ИИ-мастер путём одной экранной правки нельзя. Исходники/CI, без live GLM/device; только docs, код не менялся.

## Игровые экраны и портреты: уточнение UX-аудита 8 ноября 2026

[Подробная проверка в общем плане](PLAN_TWO_UX_AUDITS_ONE_PR_RU_2026-11-08.md): WorldPlayPage/DialogueStage/GameQuickBar/gateway по исходникам и тестам. Чередование speaker turns, portrait placeholder (Material icons) или локальный PNG, реальные SQLite-гейты выбора работают по коду. **Не подтверждён physical rendering**, в репозитории нет screenshots/golden. UI пока показывает меньше возможностей NPC, чем core; портрет привязан к имени, монологи без двух названных собеседников не дают диалоговой карточки; есть риски 312dp bar, contrast, FAB. Добавить вместе в UI пакет 1, не делать новые PR. Автономен игровой runtime, но не весь Flutter-зависимый конвейер FB2→RPG. Исправления не выполнялись.

## Единый план исправлений по двум аудитам (8 ноября 2026)

[План двух крупных пакетов и одной общей приёмки](docs/PLAN_TWO_UX_AUDITS_ONE_PR_RU_2026-11-08.md). Пакет 1: единый путь, 0/1/2 NPC и надёжные UI/настройки/данные. Пакет 2: масштабируемая литературно связная игра, CANON/ALTER_FATE и отделяемый pure-Dart authoring. Затем общий exact-head CI и реальные RU FB2/GLM/физический UX. Код не менялся, PR #133 Draft, E6d и main не затрагивать.

## Полный UI/UX-аудит приложения — 8 ноября 2026

[Отчёт и реестр всех экранов](AI_STORY_RPG_FULL_APPLICATION_UX_AUDIT_RU_2026-11-08.md): проверены разделы приложения, все настройки и функции по исходникам, существующим тестам и CI; визуальный физический QA НЕ проведён. Автономный story_core + отдельные пакеты и standalone CLI подтверждены кодом 6c3750ba / CI #987 SUCCESS, M0 #1072 SUCCESS. Авторская подготовка книги пока частично живёт в Flutter-приложении (некоторые компиляторы импортируют Flutter) — сохранить отдельную переносимую архитектуру при будущих исправлениях.

Новые риски вне генератора: тема/читательские prefs без полной ошибки-обработки/rollback, остаточные checkpoints после удаления книги, смешение theme/app reading палитр для FreeText/Dialogue controls, 4 NPC нижних кнопки min width 312dp, устаревшие AI settings, файловые backup/device и TalkBack не проверены. Старые исправленные части (семантическая позиция чтения, отдельные BookWorld-сейвы, строгие backup/SQLite, охранные AI-согласия) НЕ переделывать. Общий book→game ещё имеет P0: NPC и лимиты, CANON, полное литературное E2E. Текущий результат — зарегистрированный аудит, код не менялся, новая CI не требуется для docs-only коммита.


8 ноября 2026. PR #133 OPEN / DRAFT; ветка `feature/p0-bookwide-gameplay-readiness-20261107`. Main, E6d, pinned contracts и завершённая очистка не затрагивались.

## Последняя полностью принятая база

`4cbca1a54621ee0958c3fffbf62d6ed2be0cbbed` — [CI #986](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773798) COMPLETED / SUCCESS, включая Windows/Android; [M0 #1071](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773686) SUCCESS. Общий сюжет и привязанные мотивы интегрированы в NPC-подготовку. Старые ошибки #985 устранены. Внешний [E6d #275](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773698) FAILURE отдельно.

## Новый код: 6c3750ba

Полный SHA: `6c3750bae27c30c5fdb67f17a055e6563e8081b0`. Основной [CI #987](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42439491413).

| Проверка на последнем просмотре | Состояние |
| --- | --- |
| Python reference | SUCCESS |
| Dart engine/scenario | SUCCESS |
| M1.7: схемы, импорты, SQLite, standalone | SUCCESS |
| Flutter static analysis | SUCCESS |
| M0 #1072 | SUCCESS |
| Полный Flutter-прогон | IN_PROGRESS |
| Windows/Android нового кода | Итог ещё не подтверждён |

[M0 #1072](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42439491496). M1.7 job **128605462864** теперь полностью SUCCESS, в том числе независимая Python/Dart-проверка прежних форматных fixtures и автономный smoke. Flutter job **128605463113** ещё выполнялся. Это не доказательство успешности новых 11 тестов: их итог нужно получить из того же job. Отдельный [External #276](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42439491416) не является основной приёмкой и не согласовывался.

Docs-only `33c61840` и последующее обновление статуса `[skip ci]` не меняют проверяемый код 6c3750ba. Не выводить статус CI из SHA документации.

## Реализованный результат

Один завершающий этап в прежнем процессе: финальный сюжет/герой/предметы/NPC → текст всех сцен и двух развязок → новое полное одобрение → прежняя установка автономной игры. Можно оставить прежний текст без облачных запросов. Готовые и ручные сцены сохраняются; запрос охватывает лишь отсутствующие; каждый пакет записывается до следующего. Старая редакция, ручная правка, отмена и ошибка записи останавливают дальнейшую работу.

В exact shown payload включены финальный маршрутный инвентарь, цель сцены/акта и общий авторский замысел. Подписанная скрытая речь и NPC-секреты не включаются. Модель не подаёт игровые правила. При применении один narrator paragraph добавляется перед исходным телом сцены; source words и NPC dialogue остаются дословно. Knowledge guards получают только проверенный сдвиг позиции реплики. Механика сравнивается целиком; независимый v3 importer и полный runtime causal audit обязательны. Новая версия не переписывает старые сейвы.

## Приёмка и ограничения

11 новых тестов охватывают полный fake-API/durable storage/restart/strict ZIP/два финала/SQLite путь с ключом и двумя NPC, сравнение механик, скрытие неразрешённой реплики, 429/отмену/resume, ручной текст, подделки/failed-write и телефон 360dp. Локальный Dart/Flutter отсутствует, живой GLM и физические устройства не запускались. Эти тесты не заменяют литературную приёмку на двух разных настоящих русских FB2.

Новый абзац не удаляет старые технические пометки и не доказывает художественное качество. CANON, произвольный роман, смысловая проверка реальной книги и устройства остаются открытыми. #118 и Draft PR не закрываются.

[Передача](../START_NEW_CHAT_RU.md) · [Контракт и тесты](P0_COMPLETE_CAMPAIGN_PROSE_RU.md)


## Проверка готовности UX (8 ноября 2026)

[Полный маршрутный UX-аудит движка и подготовки книги](P0_FULL_ENGINE_UX_AND_BOOK_CREATION_READINESS_AUDIT_RU_2026-11-08.md): **кодовая база 6c3750ba / CI #987 полностью SUCCESS** (в том числе Flutter, Android, Windows), но **путь «книга → полноценная RPG» не принят**. Проверены исходники главного маршрута и релевантные тесты; реальный визуальный/device/accessibility QA не выполнялся. Выявлены P0: невозможность пройти единую сборку без подходящего NPC, неготовность произвольной большой книги (2–12 актов, без source gaps, ≤15 ролей, ≤160 KiB карты, до 192 сцен), отсутствие полноценного CANON/source-verified literary causality и реального русского FB2→live GLM→проверенная игра. P1: скрытая навигация из BookActDraft через иконку, конкурирующие «Играть/Подготовить», поздний выбор героя, нет общего readiness/budget, возможны технические строки в игровом тексте, нет device/TalkBack проверки. **Следующий пакет — единый мастер + опциональные NPC + ранний preflight**, без E6d и без дробления PR. Main не менялся; docs-only SHA не меняет CI-базу.
