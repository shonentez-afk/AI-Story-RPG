> **АКТУАЛЬНАЯ ПРИЁМКА 9 ноября 2026:** в одном Draft PR #133 **завершён source-reviewed старт BOOK_CHARACTER** на существующем v4: selected source actor → идентичность первой главы → одобренные вещи/факты → исполнимые game choice gates → replay/SQLite → JSON API/Flutter. Код `46308802b15be6ed6afc2c191ae902ba24322aa5`, [полный CI #1090 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42562198099) и M0 #1175 SUCCESS. **Не повторять** предшествующие пакеты автономного runtime, Python HTTP, save transfer, NPC и журнал. Все три прямые import-checks Flutter NPC-мастера заменены публичным RpgAuthoringApi. **Оставшийся P0 одним следующим крупным блоком:** настоящий многоглавный литературный CANON (без ложных финалов), долгосрочный source-authentic BOOK_CHARACTER, typed AI-GM с новыми проверяемыми replay-переходами, production cross-language authoring, генератор a18 parity, независимые реальные FB2/устройства. [Описание принятого пакета](RPG_BOOK_CHARACTER_START_INTEGRATION_RU_2026-11-09.md).

> **Приёмка 9 ноября 2026:** новый private cross-client game transfer + consent-based free text + stateHash + journal paging принят: code SHA `071ed2b07bec9cc863aa22583288688337ed9eae`, [CI #1087 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128159) (включая M1.7, Python/Dart, v3/v4, Windows+Android), [M0 #1172 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128175). Больше не считать отсутствие переносимого save/подключаемого Python клиента пробелом. **Осталось:** канонические BOOK_CHARACTER/CANON/динамические AI-ходы, полная без-UI authoring передача внешнему клиенту, media, Browser/FFI и семантическая E6m parity. Аудит также выявил два прямых read-only импортёрных вызова внутри Flutter мастера NPC, заменить через `RpgAuthoringApi.inspectPrivateWorld` в следующем крупном authoring/gameplay пакете. [Полный аудит](RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md). Текущий генератор **E6m/0.3.0a16**.

> **Актуализация клиентской автономности 9 ноября 2026:** первый и второй пакеты прошли полный native CI #1083/#1084 на точных SHA `31372b0`/`4393024`. Следующий связанный крупный пакет (ожидает отдельный exact-head CI): самостоятельное `RpgCampaignTransfer` с приватным self-contained .bworld+.bwsave bundle, подтверждённый `confirm_suggestion`, верифицированный `state_hash` и `journal_page`, независимые SQLite и Python-другой-процесс тесты. [Аудит реализации, безопасности и того, что ещё НЕ сделано](RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md). Generator уже **E6m/0.3.0a16**, [CI #420 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42556984326), но совместная проверка native PR legacy generator всё ещё FAIL. Не подменять автономный сценарный runtime локальным JSON bridge: книжный CANON/BOOK_CHARACTER/freeform AI и внешний authoring workflow остаются отдельной незавершённой работой.

> **Текущая реализация поверх исходного плана:** первый крупный пакет код `31372b0b657fb0d0fa37476c1fcbc9fe614be525` прошёл [полный CI #1083 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554271712) (Python, Dart/M1.7, Flutter, Windows, Android и настоящий Python→HTTP→Dart→SQLite). [M0 #1168 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554271699). Поэтому пункты плана ниже «нет HTTP-адаптера», «нет третьего клиента» **уже не актуальны для локального token-auth loopback**: `RpgClientProtocol` v1 и реальный Python-клиент существуют. **НЕ готов** публичный cloud API/gRPC/Web runtime, расширенный store lifecycle и полные книжные режимы. Второй связанный пакет расширяет `inspect_world/audit_world/suggest_action` и Python v3/v4 E2E; его отдельный exact-head CI обязателен. Генератор **0.3.0a13** [CI #414 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554315131), совместный native PR author CI #413 **FAIL** из-за pin drift и старой Dart parity. Не выдавать независимую приёмку генератора за общую.

# AI Story RPG — автономный движок и подключаемые клиенты

**Обязательный план на 9 ноября 2026.** Исходная кодовая база: Draft PR #133, HEAD 8ba62b197d2b61f3f17a83f4da95ba80072a002a. Документ отличает проверенный код от требуемого результата. Его следует читать первым после START_NEW_CHAT_RU.md. Исторические аудиты 7–8 ноября не заменяют этот статус.

## 0. Неизменяемое требование

Нужен **полностью самостоятельный RPG-движок**, к которому подключаются Flutter, CLI и любые будущие клиенты. Игровые правила — только в самостоятельных пакетах. Клиенту принадлежат интерфейс, пути и жизненный цикл локального хранилища, выбор файлов, экран согласия, сетевой транспорт и секреты, но **не** механика NPC, выборов, инвентаря, сюжета, последствий, журнала, сохранений и проверки литературы. Не создавать второй движок внутри Python, Flutter или HTTP-адаптера.

Текущая схема:

- story_core — состояния, условия и атомарные переходы;
- story_runtime_adapter — единая связь с runtime;
- campaign_manager — SQLite, replay и переносимые сохранения;
- rpg_gameplay — игровой сервис и безопасные снимки героя, NPC, предметов и журнала;
- bookworld_format — строго проверенный формат частного мира, v3/v4, диалоги;
- story_authoring — импорт книг, source evidence, акты, NPC, сценарная проверка и компиляция;
- rpg_api — **публичная клиентская граница** ко всему перечисленному.

Это 7 независимых от Flutter Dart-пакетов. **Независимость от Flutter не означает, что уже готов Web/HTTP или поддержка другого языка.** Сейчас rpg_api — локальный Dart SDK 0.1.0. Чужой языковой стек должен использовать один официальный adapter/host, а не повторять правила.

## 1. Что действительно реализовано

| Подсистема | Факт на native HEAD | Ограничение |
|---|---|---|
| Headless игровой runtime | StoryWorld, NPC-знания и память, отношения/доверие, владелец предмета, разрешённые выборы, журнал, SQLite/replay, stale-revision, .bwsave | Это исполняет уже собранный мир; не пишет любой роман |
| Dart API | RpgGameApi, RpgAuthoringApi, RpgProposalReviewApi, RpgCampaignProseApi, RpgCampaignWorkflowApi, RpgMultiActTrialApi, RpgCreationApi; отдельно RpgWorldIntakeApi и RpgBookGameplayAuditApi | SDK 0.1.0, нет официального HTTP/gRPC/FFI и web runtime |
| Flutter и CLI | Flutter играет через API; apps/rpg_cli независимо устанавливает миры, делает ходы и импорт/экспорт save с настоящей SQLite | Нет принятой сквозной приёмки третьего типа клиента |
| Авторство без Flutter | FB2/TXT импорт и индекс, source lock, офлайн-анализ/Resume, редакторские проверки NPC, предметов, прозы, v3/v4 компилятор | Нет доказанного полного literary book-to-RPG для произвольного романа |
| BookWorld v4 | Есть тест native 203 сцен, initial inventory/knowledge и времени | Старый предел 192 сцены относится к v3, не ко всему v4; большие книги всё ещё требуют E2E |
| Приём мира | read-only preflight v1–v4, SHA/fingerprint/coverage; origin только достигнутой сцены; отдельный causal audit со статусами playable/blocked/inconclusive | Отчёт автора не подтверждает канон, лицензию или реальное прохождение пользователем |

## 2. Незакрытые проблемы — приоритетная матрица

### P0-A. API для разных клиентов

**Не реализовано:** готовый официальный HTTP/gRPC/FFI adapter для клиентов вне Dart; готовый Web/JS runtime (есть зависимости dart:io/SQLite); достаточная сквозная приёмка одинаковой игровой семантики через другой транспорт.

**Нужно:** завершить стабильный контракт capabilities/versions, типизированные DTO всех сущностей и ошибок, lifecycle private store, идемпотентность и expectedRevision, операции backup/restore, прогресс/отмена длительных запросов, пагинация журнала, допустимые scene/NPC/media presentations и fail-closed visibility. Названия будущих интерфейсов не считать уже существующими. Затем один реальный host adapter над **теми же** RpgGameApi и RpgAuthoringApi, без самостоятельной реализации правил. Встроенные Dart/Flutter клиенты должны работать офлайн без обязательного сервера.

**Приёмка:** один и тот же v3/v4 мир через Flutter, CLI и новый тип клиента даёт идентичные sceneId, choiceId, lock reasons, hero/item/NPC state, journal, revision, state-hash и переносимые .bwsave при тех же действиях; отдельные отрицательные тесты на spoiler leaks, stale revisions, порчу ZIP/SQLite и отсутствие секретов.

### P0-B. Неполная RPG-механика

**Факт:** RpgApiContract.arbitraryBookCanon=false и dynamicAiGameMaster=false. RpgCreationPolicy отклоняет CANON, FREE_WORLD и AI_FREEFORM. Включены короткий офлайн-режим и проверенная поактная ALTER_FATE. Проверенный character_id героя пока не равен полному BOOK_CHARACTER.

**Нужно:** настоящая семантика выбранного героя (его знания, стартовые предметы и допустимые действия по подтверждённой редакции, без переноса секретов других NPC); CANON с настоящей причинностью и **без выдуманного второго канонического финала**; ALTER_FATE с реальными альтернативными последствиями; корректное игровое время, хронология, ветвления, NPC и ownership.

**Свободный ИИ:** сейчас произвольный текст сопоставляется только существующему разрешённому choiceId. AI-GM не умеет безопасно создавать новый игровой факт/действие. Требуется схема «недоверенное предложение -> типизированный contract -> проверка мира/знаний/источника -> явное принятие -> подписанный переход -> replay». Никакого model-output -> прямой SQLite write. Офлайн fallback сохранять.

**Масштаб:** native v4 тест на 203 сцены уже есть, но нет доказательства обработки любой длинной книги. Audit ограничен бюджетом поиска (в том числе до 512 ходов в проверяемых маршрутах). Inconclusive нельзя превращать в playable; нужны поактовая проверка, Resume, счётчики охвата и причинной достижимости.

### P0-C. Автономное создание проверенной книги-игры

**Есть:** независимые source-locked анализ/редакторские компиляторы, ReviewedCampaignWorkflow, NPC/item/prose validators и v4 writer, сценарные и причинные проверки.

**Не доказано:** единый headless управляющий API «книга -> подтверждённый полный сюжет и роль -> NPC/предметы/диалоги -> все важные игровые события -> причинный аудит -> готовая многоактная RPG» без Flutter, без ручной сборки отдельных внутренних моделей клиентом. Не заявлять завершённый CANON из покрытия цитат.

**Граница генератора:** внешний ChatGPT Skill — литературный автор; локальная Python-программа — индексатор, диспетчер приватных JSON-заданий и строгий проверяющий компилятор; Dart native — единственная авторитетная игровая реализация. Не возвращать обязательный Z.ai/GLM API в генератор. Модель для свободного runtime-AI — отдельная будущая возможность.

**Текущий генератор: E6k+ / версия 0.3.0a12**, функциональный commit 44521f48250b804ce95eb4d79085c51e819b46f5, документационный HEAD 6c0eb8cacf1459a4ef8d3137b417f609cb25b9ad. Ветка исторически называется feature/external-rpg-author-e6g-pr133-compat-20261108, но **этап E6g давно пройден**. Автор работает через приватные задания analysis/story/enrichment/extension/literary_review; отсутствие ответа выдаёт needs_skill_response, неверный ответ skill_revision_required. [Отдельный CI #409 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42551908380) на точном functional SHA: синтетический source-locked Python/Dart native v4, NPC, items, 203 сцены, 2 финала и SQLite. Это НЕ литературная проверка двух реальных русских FB2. Установленный ChatGPT Skill может всё ещё быть на историческом E6d и требует отдельно проверенного обновления.

**Совместимость E6k+ / native:** не менять чужой tools/rpg_author и pinned compatibility SHA без изучения изменения exact blobs и нового Python/Dart parity. Старые private checkpoints не переписывать вручную. Нужен версионированный interchange и договор приёма по native API, а не обход contract_drift.

### P0-D. Единое безопасное представление для GUI

**Есть:** WorldGameView с текущей сценой и origin, герой, предметы, NPC, журнал, доступные решения, проверки spoiler/portrait ID. Остальное нужно заканчивать в движковых projection/DTO, **не** во Flutter: стабильные character_id/portrait reference и условные эмоции; только открытые биографии; item custody/история передачи/доступное применение; объяснимые блокировки без раскрытия секретов; хронологический журнал по подтверждённым SQLite-событиям; диалоги, включая монологи и ответы героя. UI-локальные PNG не гарантированно входят в portable .bwsave. Нужно отдельно определить media manifest и переносимость.

### P0-E. Общая приёмка не завершена

Не подтверждены две разные реальные русские FB2 с литературной проверкой всех актов и значимых событий; полноценный live-author Skill проход на реальной книге; окончательный Windows/Android физический UX; перенос сохранений между устройствами; cross-language adapter; CANON/BOOK_CHARACTER/dynamic-AI playtests. Синтетический тест не заменяет это.

## 3. Точный CI и открытые блокеры на момент аудита

**Native PR #133 код 8ba62b197d2b61f3f17a83f4da95ba80072a002a:**

- [AI Story RPG CI #1082](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42550384516) **FAIL**. Python reference PASS, Dart engine/scenario PASS, M1.7/SQLite PASS; Flutter widget FAIL: четыре теста ищут старую подпись «Добавить книгу», текущая кнопка «Добавить книгу или RPG». Файлы: home_test.dart, ui_ux_audit_test.dart и два теста world_integration_test.dart. Исправить ожидания без отката согласованного UX.
- Android и Windows jobs для этого HEAD **SKIPPED**, не объявлять сборку PASS.
- [M0 #1167](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42550384628) **SUCCESS**.
- [External author tests #407 на native PR](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42550384545) **FAIL**: pinned contract_drift и ошибка resolve package:story_authoring в старом Dart parity пути. Это не провал core, но совместная приёмка native+author **не** пройдена.
- [Отдельный E6k+ author CI #409](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42551908380) **SUCCESS** на 44521f4. Не подменять независимой зелёной проверкой требуемую совместную.
- После документационного commit [skip ci] точный code CI остаётся на 8ba62b. Каждый **новый кодовый** HEAD требует собственного полного CI.

## 4. Единый маршрут реализации — не дробить на микро-PR

**Все native изменения — в прежнем Draft PR #133**; generator-owned ветку и main не трогать, пока большая приёмка не готова.

**Большой пакет I — полностью подключаемый игровой API.** Восстановить текущий CI; закончить client-neutral lifecycle, version/capability/error/DTO/projection contract, store/backup ports, один настоящий внешний adapter без второго движка, golden replay v3/v4 Flutter/CLI/adapter с NPC/items/hero/journal, CAS, 0/1/2 NPC, 203 сценами, spoiler-negative.

**Большой пакет II — законченная RPG-семантика.** Реальные CANON/ALTER_FATE/BOOK_CHARACTER и проверяемые initial-state/time; безопасный typed AI-freeform с явным согласием и replay; причинная проверка всех существенных событий и выходов длинных кампаний, без «inconclusive = success». Не ставить флаг поддержки, пока путь не исполним.

**Большой пакет III — полный авторский контракт и единая E2E.** Один headless authoring workflow, подключённый внешним Skill-first E6k+ через совместимый versioned source-locked contract. Две настоящие русские FB2, проверенная литературная логика/роль/NPC/предметы/финалы, настоящий игровой импорт/replay/save в Flutter/CLI/adapter и Windows/Android, затем полный exact-head Python/Dart/schema/SQLite/Flutter/Android/Windows/M0 + author parity, и только потом merge PR #133.

### Что означает DONE

- [ ] Внешний клиент, не импортирующий Flutter, пользуется официальным публичным контрактом без копии RPG-правил.
- [ ] Одинаковые игровые state/journal/NPC/choice/save результаты на одном мире в нескольких независимых клиентах.
- [ ] Нет скрытых преждевременных персонажей/реплик/владельцев или неоткрытых фактов.
- [ ] Все обещанные CANON/ALTER_FATE/BOOK_CHARACTER/AI_FREEFORM действительно проходят проверки; неподдерживаемые режимы честно отклоняются.
- [ ] Book-to-RPG и генератор можно использовать без Flutter и обязательного стороннего модельного API; source/rights/consent/role/causal gates сохраняются.
- [ ] Совместимость E6k+ по точному pin, два реальных FB2, Win/Android E2E и переносимые saves — PASS на проверенном SHA; приватные файлы не публикуются.

## 5. Инструкция новому чату

1. Прочитать START_NEW_CHAT_RU.md, этот план, docs/CURRENT_STATUS_RU.md и docs/RPG_API_CLIENT_BOUNDARY_RU_2026-11-08.md; затем текущее состояние PR #133 и exact GitHub Actions.
2. Внешнего автора проверить по tools/rpg_author/START_NEW_CHAT_RU.md **на его собственной ветке**; реальный этап E6k+, версия 0.3.0a12. Не повторять старое обозначение E6g как текущую версию. Не изменять generator-owned код.
3. Не повторять уже сделанное отделение story_core, rpg_gameplay и story_authoring от Flutter. Завершать недостающие публичные порты и реальные RPG-правила **крупными функциональными блоками** в PR #133.
4. Не создавать микро-PR на отдельные поля и экраны. Обновлять handoff после значимых приёмок, отличать «код написан», «CI точно PASS», «проверено на устройстве» и «литературно подтверждено».
5. Не изменять main и не делать force push. Не перепаковывать старые .bworld/.bwsave, не терять private SQLite, книги и checkpoints; никакого ослабления проверки ради успеха CI.
