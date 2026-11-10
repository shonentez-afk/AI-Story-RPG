# 10.11.2026 — P0 UI ↔ RPG ENGINE: ПРИНЯТО ПО ПОЛНОМУ CI #1131

**АКТУАЛЬНЫЙ КОД:** `2b3c36868426aa6147763bdda9b3957174621b19`, единый [Draft PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133). [Основной CI #1131](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42736654180) **COMPLETED SUCCESS на точном SHA**: Python reference, Dart engine, M1.7 SQLite/BookWorld contracts, Flutter static analyze и **весь набор Flutter widget-тестов**, Windows portable и Android debug APK — все SUCCESS. [M0 #1216](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42736654155) SUCCESS. [External RPG author #492](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42736654696) SUCCESS. Старый CI #1130 FAIL имел **ровно два** неуспешных Flutter-теста; исправлены одним кодовым коммитом выше, после чего полная регрессия зелёная.

**АРТЕФАКТЫ #1131:** `AI-Story-RPG-Windows-portable` (15 380 490 байт), `AI-Story-RPG-Android-debug` (88 992 709 байт), оба опубликованы внутри Actions и на момент проверки **not expired**. Отдельный job `Publish Windows + Android test release` **SKIPPED**; не объявлять созданным GitHub Release. Бинарные файлы не тестировались физически на личном устройстве, CI сборка не равна ручной UX-проверке.

**UI PARITY: ТЕХНИЧЕСКИЙ ПАКЕТ ПРИНЯТ В CI.** Flutter показывает только нативно подтверждённые world capabilities, роли и смысловой статус v5; принимает из E6q.1 source-reviewed `.bworld` только при совпадении exact source fingerprint + consent; различает literal-only vs full causal-reviewed. Карточки Герой/Предметы/Журнал/NPC получили replay-verified знания, инвентарь, цели, открытые обещания, отложенные решения и альтернативные обязательства. Preview свободного ИИ-действия показывает типизированные последствия **до** подтверждения, а изменения мира фиксируются **только** автономным core. В CI прошли кейсы CANON→ALTER_FATE на настоящем SQLite-backed v5, импорт/отказ иной редакции, защита от future NPC spoilers, узкий экран 320dp/увеличение текста и прокрутка длинного журнала.

**Последние точечные исправления #1131:** при открытом диалоге согласия на импорт спрятана бесконечно анимируемая полоса прогресса за диалогом (при этом блокировка повторных действий сохраняется), а Flutter-тест длинного журнала прокручивает реальный lazy `ListView.builder`, вместо ожидания заранее созданных вне экрана строк.

**ЧЕСТНАЯ ГРАНИЦА ПРИЁМКИ:** проверена реализация UI/API и автоматическая регрессия, НЕ физический рендер Windows/Android на реальном устройстве, НЕ содержательная литературная правдивость двух различных реальных русских книг, НЕ устойчивость реальных ответов GLM в долгом прохождении. Это следующие продуктовые испытания. Генератор E6q.1 проверен отдельно, main не менять, PR #133 остаётся Draft до общей продуктовой приёмки; не заводить микро-PR и не переделывать уже принятый core/UI без обнаруженного дефекта. Сведения в документации ниже этой записи — исторические статусы; **не путать** прежнее «CI in progress» с актуальным SUCCESS.

---

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

# АКТУАЛЬНЫЙ HANDOFF — 9 НОЯБРЯ 2026: CAUSAL GRAPH V2 + NPC РЕАКЦИИ ПРИНЯТЫ

**Проверенный КОД:** `f368f8c068a39592464c66fd518d155b705d596f` в **едином Draft PR #133**. [Native CI #1111](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42584271223) — **COMPLETED SUCCESS на этом SHA**, включая Python, Dart, M1.7 (новые v2 source-wide/NPC/SQLite/API), Flutter (757 PASS, 2 SKIP), Windows portable и Android debug APK. [M0 #1196](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42584271237) — SUCCESS; [External author #460](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42584271206) — SUCCESS на том же коде с обязательными source-pin и Dart parity. Артефакты опубликованы в #1111. Новый docs-only [skip ci] commit не меняет принятого кода.

**УЖЕ СДЕЛАНО, НЕ ПОВТОРЯТЬ:** native BookWorld v5 source-causal review v2 — `BookCausalGraph` для КАЖДОЙ original scene, source quote SHA, только предшествующие зависимости, исполнимые факты/предметы/память/доверие/цели/жизненный статус/флаги; approved source effects и автоматическое CANON→ALTER_FATE при противоречии. Проверяемые динамические передачи уже известного игроку факта или принадлежащего предмета NPC, и утверждённая `NpcAutomaticReaction`, которая без дополнительного ИИ-запроса при достаточном доверии меняет цель NPC и пересылает факт второму присутствующему NPC. Долгосрочные последствия воспроизводятся через общий event-chain/SQLite/.bwsave. Тесты с Анной/Борисом, JSON API, Flutter и переносами прошли. Формат v1/старые saves сохранены. [Отчёт пакета](docs/RPG_WHOLE_BOOK_CAUSAL_NPC_DYNAMIC_RU_2026-11-09.md).

**НЕ СЧИТАТЬ ПОЛНОЙ ЛИТЕРАТУРНОЙ RPG ИЗ ЛЮБОЙ КНИГИ:** граф действительно исполним и покрывает исходные сцены, но его смысл, причинные правила и автоматические NPC-реакции ещё требуют литературного авторского review. Независимый ChatGPT Skill E6p/0.3.0a19 (отдельная ветка) пока не создаёт/не утверждает для любой книги весь новый v2 causal graph. Не выдавать проверку цитат за доказательство мотивов/всех сюжетных обязательств; `arbitraryBookCanon=false` оставить. Настоящие две разные RU FB2, литературные свободные игровые прохождения и ручной/физический Android+Windows QA ещё не приняты. Это отдельный незакрытый продуктовый критерий, а не непрошедшие автоматические CI этого нативного пакета.

**ДИСЦИПЛИНА:** единый Draft PR #133, main не трогать и не merge до продуктовой приёмки. Чужую ветку E6p без отдельного согласования не изменять. Никаких микро-PR; подробные архивные статусы ниже считать историческими.

---

# АКТУАЛЬНАЯ РАБОЧАЯ ПЕРЕДАЧА — 9 НОЯБРЯ 2026: CAUSAL GRAPH + NPC DYNAMIC

**Новый связанный пакет в Draft PR #133:** source-wide review v2 для BookWorld v5, `BookCausalGraph` с явным source quote SHA для КАЖДОЙ канонической сцены, зависимостями (только прошлые), проверенными условиями фактов/памяти/доверия/целей/владения предметом/состояния NPC/флагов, source-reviewed typed эффекты по выходу из сцены. Движок автоматически выбирает ALTER_FATE при нарушении проверенного будущего causal event вследствие динамического NPC-действия, не возвращая игрока в исходный текст. Добавлены согласованные прямые передачи предметов игрок↔NPC и подтверждённая передача знания от героя NPC в том же едином journal/SQLite replay, через существующий API и Flutter. Формат v1 и старые save не получают новых обязательных полей.

**Требование приёмки:** на финальном HEAD должны быть SUCCESS основной CI (Python, Dart, Flutter, Win/Android), M0, External author source pin + native Dart parity. Наличие коммитов, проход отдельных tests или синтетического one-NPC E2E **не** доказывают автоматически литературу всей книги. Исторические утверждения ниже о полном отсутствии причинности/динамических NPC устарели. Генератор E6p 0.3.0a19 в другой ветке; его расширение для автоматического литературного authoring v2, реальный FB2 QA и физические устройства остаются отдельными непроверенными критериями. Не трогать main, без микро-PR.

---

# АКТУАЛЬНЫЙ HANDOFF — 9 НОЯБРЯ 2026: КРУПНЫЙ ИГРОВОЙ ПАКЕТ BOOK_CHARACTER ПРИНЯТ

**Проверенный code HEAD** `46308802b15be6ed6afc2c191ae902ba24322aa5` в **едином Draft PR #133**, [основной CI #1090](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42562198099) **COMPLETED SUCCESS на этом SHA**: Python, Dart, M1.7, Native BookWorld/SQLite, реальный Python→HTTP→Dart, Flutter analyze/widget, Windows portable и Android APK. [M0 #1175](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42562198620) **SUCCESS**. Артефакты Windows и Android опубликованы в #1090. Следующий документационный SHA с [skip ci] НЕ является новым кодом.

**ЧТО НОВОГО И НЕ НУЖНО ПЕРЕДЕЛЫВАТЬ:** `ReviewedBookCharacterStartWriter` + `LocalRpgBookCharacterStartApi` создают **новый**, source-reviewed private BookWorld v4 с постоянным `character_id` ранее выбранного книжного героя, утверждённым буквальным UTF-16-упоминанием из первой главы, подтверждёнными стартовыми предметами и фактами и исполнимыми условиями существующих решений `has_item`/`knows_fact`. Подтверждение/цитаты/digest обязателены, точная исходная редакция и SHA base проверяются; поддельное знание, поздние спойлеры или чужой герой отклоняются. Работает через **существующий story_core**, новый .bworld имеет другой ID, прежние saves/кампании не изменяются. Тесты проверили реальный игровой ход, SQLite/.bwsave replay, JSON SDK и отрицательные случаи. `RpgClientProtocol` предоставляет `inspect_character_start`/`compile_character_start`; `WorldGameView` владеет `heroSourceCharacterId`/`sourceReviewedHeroStart`, Flutter их отображает без второго regex/игровых правил. **Все ТРИ прямых вызова RichPrivateBookworldImporter в Flutter NPC-мастере удалены** в пользу `RpgAuthoringApi.inspectPrivateWorld`. [Описание пакета](docs/RPG_BOOK_CHARACTER_START_INTEGRATION_RU_2026-11-09.md).

**ЭТО НЕ ПОЛНАЯ BOOK_CHARACTER/КАНОН:** редакционно проверен именно начальный набор вещь/знание и условия выбора, а не все будущие литературные знания/мотивации персонажа. Полная буквальная CANON, свободный динамический ИИ-мастер, произвольные причинные действия и source-wide истинность всей книги **ещё не готовы и честно запрещены** (`arbitraryBookCanon=false`, `dynamicAiGameMaster=false`). Не открывать эти флаги до настоящего source-wide и persisted replay-механизма.

**НЕ ПОВТОРЯТЬ:** независимый Dart RPG runtime, Python HTTP bridge, v3/v4, перенос .bworld+.bwsave, NPC, память/доверие, журнал, causality, signed free-text choice и SQLite — уже реализованы и прошли свои CI #1087/#1090. Следующий ОДИН крупный функциональный пакет должен реализовывать **настоящий whole-book CANON + проверяемые новые AI-GM действия и достоверную долгосрочную роль героя**, а также единый внешний authoring контракт, не переписывать API/импорт.

**Генератор отдельно:** в исторически названной E6g-ветке уже **0.3.0a18**; [собственный author CI #429](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42561455316) **SUCCESS**. На нативном PR [author CI #430](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42562198063) **FAIL** по старому source-pin contract_drift и legacy Dart parity `story_authoring` probe. Это **открытый блокер общей интеграции**: не отключать fail-closed и не редактировать чужую ветку генератора из этого чата. Ручные литературные тесты на двух настоящих RU FB2 и реальные устройства Win/Android ещё НЕ проведены.

**ЗАПРЕТЫ:** никаких микро-PR; работа только в Draft PR #133; main не изменять, E6m/E6n чужие generator-owned tools не трогать. Актуальные документы: [пакет](docs/RPG_BOOK_CHARACTER_START_INTEGRATION_RU_2026-11-09.md), [полный аудит](docs/RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md), [план](docs/RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md).

---

# НОВЫЙ КРУПНЫЙ ИГРОВОЙ ПАКЕТ — книжный герой с реальными исходными фактами и предметами, 9 ноября 2026

**Не повторять уже принятый перенос состояний/JSON/SQLite.** Проверенный baseline native PR #133: code `071ed2b07bec9cc863aa22583288688337ed9eae`, [CI #1087 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128159). Сейчас реализуется НОВЫЙ gaming/authoring пакет, который должен пройти отдельный exact-head CI: единый ReviewedBookCharacterStartWriter для source-reviewed initial inventory, player knowledge и исполнимых has_item/knows_fact условий реальных решений существующего v4; без подмены исходной книги и без нового игрового движка. Обязательны human reviewed chapter-0 quote + буквальное role mention/UTF-16 + parent-archive SHA + approved digest + user consent. Новый приватный .bworld, старые кампании не изменять. RpgBookCharacterStartApi + JSON inspect_character_start/compile_character_start; source role и начальный review теперь принадлежат WorldGameView, не regex Flutter. NPC-мастер Flutter проверяет .bworld через публичный RpgAuthoringApi.

**Обязательная приёмка:** настоящий native v4, item+knowledge+causal gate, SQLite/.bwsave replay, Python JSON, отрицательные test cases, полные M1.7, Flutter/Windows/Android. [Описание реализации](docs/RPG_BOOK_CHARACTER_START_INTEGRATION_RU_2026-11-09.md). **Не выдавать CANON/динамический AI-GM за готовые**: формат по-прежнему частный ALTER_FATE, эти два направления принципиально не закрывает инвентарь героя. Генератор развивается независимо, на момент прошлой проверки уже E6m/0.3.0a16+; проверить новую версию отдельной ветки перед интеграцией. НЕ создавать микро-PR, main/E6m не изменять.

---

# ОБЯЗАТЕЛЬНЫЙ HANDOFF — 9 НОЯБРЯ 2026: АВТОНОМНОСТЬ КЛИЕНТОВ ПРИНЯТА, КНИЖНЫЕ МЕХАНИКИ ЕЩЁ НЕ ПОЛНЫЕ

**Проверенный code HEAD:** `071ed2b07bec9cc863aa22583288688337ed9eae` в Draft PR #133. [AI Story RPG CI #1087](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128159) **COMPLETED SUCCESS на точном SHA**: Python, Dart/M1.7, настоящий Python→Dart HTTP→SQLite, v3/v4 перенос private `.bworld + .bwsave` в ПУСТУЮ библиотеку, replay/verified stateHash/journal/NPC/предметы, Flutter widget/analyze, Windows portable, Android debug APK. [M0 #1172](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128175) **SUCCESS**. **Сборки — не физические пользовательские испытания.**

**Реализовано в одном крупном пакете:** `RpgCampaignTransfer`, `export_bundle/inspect_bundle/import_bundle` с частным переносимым архивом (не generator snapshot), подтверждение импорта + checksum + оригинальный native ZIP и строгий replay; `WorldGameView.stateHash`, `journal_page` (CAS и пагинация), `confirm_suggestion` (согласие, повторная проверка fingerprint, actionId и допустимости); Python loopback не использует системный HTTP_PROXY. **Тот же механизм исполняет Flutter, CLI и Python-клиент; второго rule engine нет.**

**Проверка полной автономности НЕ закрыта целиком.** [Независимый аудит](docs/RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md): игра на проверенном BookWorld автономна, но произвольный полный литературный CANON, действительная BOOK_CHARACTER с начальными знаниями/предметами, динамический AI-GM с подписанным story_core-переходом, все editor/authoring API для внешних языков, media/портреты в пакете и отдельный Browser/FFI/cloud adapter ещё не готовы. Найдены **две прямые ссылки на RichPrivateBookworldImporter в Flutter NPC-мастере** `whole_book_npc_campaign_page.dart` (~625 и ~682); заменить публичным `RpgAuthoringApi.inspectPrivateWorld` в **следующем одном крупном игровом/авторском пакете**, не отдельным микро-PR. `world_library_gateway.dart` напрямую открывает SQLite **только как платформенный storage adapter**, игровых правил там нет.

**Генератор:** уже **E6m/0.3.0a16** (историческая ветка ещё содержит e6g в имени). [Авторский CI #420 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42556984326), code SHA `ce221f0454a5be61de6bc39297e11cc070342680`. ChatGPT Skill-first, его `snapshot-private` содержит приватную книгу и авторские ответы, и не является `.bwsave` игрока. **Native External RPG author tests #423 FAIL** (старый `contract_drift`/Dart probe), отдельная зелёная ветка ≠ единая совместимость. Не отключать doctor и не менять generator-owned файлы в нативной ветке.

**СЛЕДУЮЩИЙ ПРИОРИТЕТ — ОДИН КРУПНЫЙ БЛОК:** source-reviewed CANON + BOOK_CHARACTER + typed dynamic AI freeform в движке, единый причинно проверенный whole-book authoring workflow, выравнивание Flutter и стороннего JSON API, затем семантическая E6m↔native parity и 2 реальные RU FB2/физический Win+Android. Никаких микро-PR; один Draft PR #133, `main` не трогать. [Полный план](docs/RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md).

---

# ПЕРЕДАЧА — 9 НОЯБРЯ 2026: ПОЛНАЯ КЛИЕНТСКАЯ ПЕРЕНОСИМОСТЬ RPG, НОВЫЙ КРУПНЫЙ ПАКЕТ

**Цель без изменения:** один полностью самостоятельный RPG runtime/API, Flutter/CLI/Python и любые новые клиенты без копии правил. **Проверенный baseline:** native SHA `43930247ef0d2b3e67de7d05ac629fe5a9dd45a4`, [CI #1084](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42555732659) SUCCESS: Python, Dart, M1.7, Flutter, Windows + Android.

**Новый функциональный пакет на приёмке (НЕ считать PASS до exact-code CI):** `WorldGameView.stateHash` из проверенного replay, `journal_page` (пагинация + CAS), `confirm_suggestion` (обязательное согласие, fingerprint+revision и повторная проверка правил), приватный self-contained `RpgCampaignTransfer` — `.bworld + .bwsave` в одном `export_bundle/inspect_bundle/import_bundle`, проверка SHA и rollback невалидного импорта. Чужой клиент может принять кампанию в **пустую** SQLite-библиотеку, а не только открыть save после ручной установки мира. Python-host теперь принудительно обходит `HTTP_PROXY` для приватного loopback. Добавлены Dart- и Python-E2E (раздельные базы, v3/v4, повторное открытие). Один связанный коммит в **Draft PR #133**; никаких микро-PR. [Подробный аудит автономности](docs/RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md).

**Генератор:** уже **E6m / 0.3.0a16**, не E6k/E6g. [Собственный CI #420 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42556984326) SHA `ce221f0454a5be61de6bc39297e11cc070342680`. ChatGPT Skill-first, полный приватный `snapshot-private/restore-private` сохраняет АВТОРСКУЮ сессию (исходную книгу и ответы), **не** заменяет игровой transferable bundle; установленный старый Skill не обновляется автоматически. Старый External author check **на native PR** FAIL (`contract_drift` + legacy Dart parity `story_authoring`), не отключать; согласовать отдельной точной E6m/native приёмкой без переписывания generator-owned кода.

**Недоделано несмотря на полноценное локальное multi-client исполнение:** настоящий literary CANON, достоверная BOOK_CHARACTER (начальное знание/вещи), динамические свободные AI действия с проверенными переходами, полный whole-book authoring для произвольной книги, portable NPC media/портреты, HTTP для удалённых клиентов/Browser/FFI, 2 реальные RU FB2 literary-QA и физические Android/Windows проверки. **Следующий крупный блок:** книжные роли + CANON + typed AI game master внутри `story_core/story_authoring/rpg_api`, не в Flutter/Python. [Полный план](docs/RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md). Main не менять.

---

# АКТУАЛЬНЫЙ HANDOFF — 9 НОЯБРЯ 2026: ПЕРВЫЙ КРУПНЫЙ API-ПАКЕТ ПРИНЯТ, ВТОРОЙ — НА ПРИЁМКЕ

**Проверенное:** код `31372b0b657fb0d0fa37476c1fcbc9fe614be525`, [основной CI #1083](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554271712) **COMPLETED SUCCESS** на ТОЧНО этом SHA (Python, Dart, M1.7, отдельный Python → HTTP → Dart → SQLite, Flutter, Windows portable, Android debug). [M0 #1168](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554271699) **SUCCESS**. Это первая официально проверенная клиентонезависимая RPG API-граница: `RpgClientProtocol` v1 в чистом `rpg_api`, auth loopback HTTP в `apps/rpg_cli`, Python-клиент без RPG-правил, единая безопасная projection. Приёмка CI **не** подтверждает физический UX Android/Windows и литературный CANON.

**Новый второй связанный кодовый пакет в том же Draft PR #133 — ДО НОВОГО EXACT-HEAD CI НЕ ПРИНИМАТЬ:** API `inspect_world` (настоящий read-only native BookWorld v1–v4 intake), `audit_world` (bounded `StoryWorld` causal playable/blocked/inconclusive, без ложного доказательства канона), `suggest_action` (только проверенные существующие выборы), и Python/Dart E2E v3/v4/replay. **Ни Flutter, ни Python не получили копию игровых правил.** Проверить точный новый SHA и новые Actions после git push.

**Внешний автор:** уже **0.3.0a13**, несмотря на историческое название ветки `feature/external-rpg-author-e6g-pr133-compat-20261108`; [author CI #414](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42554315131) **SUCCESS** на `1f154a0eda9d046b7f355d4399f2b79cb2a3e2d3`. ChatGPT Skill пишет литературные данные; Python — приватные задания/проверка, Dart — единственный runtime. **Отдельный native branch External RPG author tests #413 FAIL**: pinned `contract_drift` шести source files + старое `tests/rpg_author/dart` не разрешает `package:story_authoring`. НЕ отключать проверку и НЕ обновлять чужой `compatibility.json` без точного аудита и повторного parity.

**Главный незакрытый маршрут (одним PR, не микро-PR):** полностью source-reviewed CANON и BOOK_CHARACTER, действительно проверенный freeform AI GM, единый large-book/story authoring + native/E6k+ exact interchange, 2 реальные RU FB2 с истинной литературной проверкой, перенос saves, физические Windows/Android устройства, миграция/порты для новых клиентов. [План](docs/RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md), [протокол](docs/RPG_CLIENT_PROTOCOL_V1_RU_2026-11-09.md). `main` и генераторную ветку из native-чата не трогать.

---

# АКТУАЛЬНАЯ ПЕРЕДАЧА — 9 ноября 2026: автономный RPG-движок для любых клиентов

> **Приоритет над всеми историческими записями ниже.** Новый обязательный план: [RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md](docs/RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md). Старые названия генератора E6d/E6g и промежуточные статусы CI ниже являются архивом, не текущим состоянием.

**Требование пользователя:** полностью самостоятельный RPG-движок с одним источником правил, подключаемый к Flutter, CLI и любым будущим клиентам. Все сцены, герой, NPC, знания, память, отношения, предметы, владельцы, реплики, проверка действий, журнал, причинность, сохранения и сценарное авторство принадлежат движковым пакетам и публичному `rpg_api`. Flutter отвечает за UI, платформенный ввод/вывод, ключи, сеть и пользовательские согласия — не за механики. Нужен реальный версионированный контракт и официальный adapter для других языков/HTTP, без копирования ядра. Сейчас есть **локальный Dart API 0.1.0, НЕ HTTP/Web-сервер**.

**Native PR #133:** Draft, последний проверенный code HEAD `8ba62b197d2b61f3f17a83f4da95ba80072a002a`. [CI #1082](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42550384516) **FAIL**: Python, Dart и M1.7/SQLite PASS; Flutter виджет-тесты FAIL (четыре проверки всё ещё ожидают «Добавить книгу», тогда как UI содержит «Добавить книгу или RPG»), Windows/Android SKIPPED. [M0 #1167](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42550384628) PASS. Документальные commits с `[skip ci]` не заменяют exact-code CI.

**Генератор уже E6k+ / версия 0.3.0a12 — НЕ E6g.** Имя отдельной GitHub-ветки `feature/external-rpg-author-e6g-pr133-compat-20261108` — историческое. Последний проверенный функциональный SHA `44521f48250b804ce95eb4d79085c51e819b46f5`; документационный SHA `6c0eb8cacf1459a4ef8d3137b417f609cb25b9ad`. [External author CI #409](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42551908380) PASS (Python+Dart на синтетической книге). Актуальная архитектура: **ChatGPT Skill — литературный автор**, Python — локальная приватная очередь/валидатор, Dart native — проверяющий компилятор и единственный RPG runtime. **Не возвращать обязательный GLM/Z.ai API для генератора.** Установленный Skill ещё может быть старым E6d. На native PR external-author test FAIL (`contract_drift` плюс разрешение пакета `story_authoring` в старом Dart parity). Не отключать проверку pin.

**Готово в native:** семь независимых Dart-пакетов и один `rpg_api`, Flutter + CLI, replay SQLite/.bwsave, NPC/предметы/журнал, verified BookWorld v3/v4, native тест 203 сцен, безопасное происхождение текущей сцены, intake и causal audit `playable/blocked/inconclusive`. **Не готово:** официальный cross-language / HTTP / web adapter, полный стабильный клиентский DTO/capabilities/storage lifecycle, настоящий CANON, полноценный BOOK_CHARACTER с исходными знаниями/вещами, динамический AI_FREEFORM, завершённый автоматически проверенный whole-book authoring workflow и две реальные RU FB2 с Windows/Android E2E.

**Работа в следующем чате, единым PR #133, не микро-PR:** (1) восстановить точный полный CI, (2) завершить полный многоклиентный API и настоящий adapter, (3) довести RPG режимы/героя/ИИ до проверяемых переходов, (4) согласовать native и E6k+ через versioned contract, (5) общая книжная, SQLite/backup и устройственная приёмка. **Не затрагивать main и generator-owned tools/rpg_author**, не дублировать игровой движок и не объявлять непроверенное DONE.

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

## 2026-11-09 — подтверждённая автономная CLI/API-приёмка (exact-code)

**Кодовый SHA:** `bce9becab8a88d57a01cc4a46c968aca1f1238f7`.
[Основной CI #42513354448](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42513354448) — задача
**M1.7 deterministic world and schema contracts: COMPLETED SUCCESS**,
включая `dart analyze`, `dart test` и запуск нового
`apps/rpg_cli` с offline FB2, реальным verified NPC/Item BookWorld,
SQLite reopen и portable save. Python reference и Dart engine/scenario
тоже SUCCESS; Flutter widget-suite на момент этой записи ещё
выполнялся, полное Windows/Android CI **не объявлять**.
[M0 #42513354382](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42513354382) — COMPLETED SUCCESS.

Отдельный `External RPG author tests` на PR #133 сохраняет старый
`compatibility` pin, работает в параллельном E6g; его FAIL
**не равен** провалу независимого игрового движка. Для PR #133 статус
Draft, `main` без изменений. Граница: 7 чистых Dart-пакетов
(включая `rpg_api`), два клиента Flutter/CLI; это локальный SDK,
не HTTP service и не гарантированная литературная RPG по любой книге.
Открыты: source-locked v4 >192, reviewed initial state/time,
CANON/ALTER_FATE/hero role, full AI workflow + consent, реальные
RU FB2 и Win/Android device QA. Следующий цельный пакет:
довести `BookToRpgWorkflow` до валидируемой компиляции полного
романа и согласовать внешнего автора E6g с актуальным native HEAD.

## 2026-11-09 — второй автономный клиент RPG API (приёмка в PR #133)

Добавлен `apps/rpg_cli`: настоящий клиент независимого `RpgGameApi` и
`RpgAuthoringApi`, без Flutter, второго движка и облачных вызовов.
Поддерживает `prepare`, `install`, `worlds`, `campaigns`, `start`, `view`,
`choose`, `export-save`, `import-save`. CI проверяет реальные replay и
save roundtrip (source-reviewed synthetic NPC+items), смену SQLite соединений,
FB2/выбор отдельной сказки, строгую ревизию и отказ от перезаписи.
`tools/ci_check_engine_boundaries.py` запрещает импорт внутренних движковых
пакетов из CLI; pinned SQLite hook расширен для нового Dart-клиента.

**CI нового коммита ещё не прошёл, не объявлять SUCCESS без exact SHA.**
Это доказывает самостоятельность игрового API, но НЕ полный автоматический
CANON, длинную книгу >192 сцен, свободный AI-GM или реальный device E2E.
Один Draft PR #133, `main` и параллельный E6g не трогать.

# AI Story RPG — продолжение полного сценарного потока

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

[**Точный отчёт, тесты, архитектура и оставшиеся интерфейсные задачи**](docs/P0_BOOKWIDE_V4_REVIEWED_NPC_AND_CI_RU_2026-11-08.md). Исправлен пропуск `expanded:true` через `BookwideActPlanner`, `CrossAct`, `MultiAct`; `WholeBookNpcSourcePlan` и `ReviewedNpcCampaignBookworldWriter` работают с независимо проверенной богатой v4 и сохраняют свои v3 контракты. Actor-specific knowledge, social memories и NPC replies доступны только через реальные `StoryWorld.apply` решения, redaction проверен. Новый полный регрессионный сценарий: 18 актов/144 событий/3 NPC/161 шаг/SQLite restart; старый без-NPC 18 актов/216 событий/233 действия сохранён. Исправлен CI 504 при загрузке Ink с SHA-256 check. Код `b337b3a6d46f7ee675b2b4fc3b63485f675160b9`; [CI #42466457691](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42466457691), M0 #42466457759: точный финальный результат ПЕРЕПРОВЕРИТЬ, не считать pending PASS. **main/E6d не трогать, один Draft PR #133, не мельчить.** Следующий крупный пакет — единый UI-мастер и игровые экраны после реальной source/literary приёмки.


## Поактовая проверка причинности без потери постоянной памяти (d87587d)

[**Подробный отчёт: что реализовано, как доказана безопасность, CI и остаток**](docs/P0_LONG_BOOK_FUTURE_FLAG_CAUSAL_PROOF_RU_2026-11-08.md). Новая `FutureFlagLiveness` использует backward fixed point, чтобы при v4 схлопывать лишь *поведенчески равнозначные* прошедшие флаги при проверке, но НЕ удаляет outcome flags, `WorldEvents`, knowledge NPC, social memory, inventory, SQLite или сохранения. Реальный `story_core`, rich-v4 importer, `StoryPlan`, M2c, causal/invariant, cross-act и ownership-аудиты используют один контракт; v3 без изменений. Регрессии: 20 актов/40 флагов с поздней отрицательной проверкой, 18 актов/216 событий/17 мостов/233 SQLite действий. **Кодовый SHA `d87587db24682754814fdeebea120d2dd8238f00`**, [CI #42463600007](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42463600007), M0 #42463600025 — фактический итог перепроверить (на момент записи M1.7 и Flutter ещё выполнялись). Не считать CANON/AI_FREEFORM по любой книге готовыми. E6d/main не менялись, один Draft PR #133, **не дробить**.


## Последняя работа: прямой source-reviewed multi-act → v4 (код 350502d)

[**Факты, тесты, архитектура и следующий шаг**](docs/P0_BOOKWIDE_EXTENDED_V4_AUTHORING_INTEGRATION_RU_2026-11-08.md). Одна связка в существующем Draft PR #133: `StoryPlan`/M2c/preflight/translator поддерживают opt-in v4 без обходного v2; `build-draft-extended` компилирует из source/editorial checkpoints независимо от Flutter/сети; MultiAct проверяет все event ID и главы, все causal/NPC/role gates. Синтетические испытания: 203 сцены/201 ход с replay; 72 source events/60 интерактивных наблюдений в 6 актах. Кодовый SHA `350502df7ed09812e9ce9a750d9b3843a1708c33`: [CI #42461603117](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42461603117) — Python, Dart, M1.7 и Flutter analyze SUCCESS, окончательный Flutter widget-run перепроверить; M0 #42461603120 SUCCESS. E6d отдельно FAIL. **Не заявлять готовой полного CANON RPG из любой книги:** 30 актов — номинальный предел, causal cap 8000 может блокировать сложные схемы; генератор полного лора/свободного ИИ и игровой UI ещё не приняты. Главный следующий блок — поактовые доказательства и долговременная память, НЕ простое увеличение лимитов. main/E6d не трогать и не делать микро-PR.


## Новый код: расширенный приватный BookWorld v4 (f30e590)

[**Подробный отчёт по версии, тестам и оставшимся блокерам**](docs/P0_VERSIONED_EXTENDED_BOOKWORLD_V4_RU_2026-11-08.md). v4: 1024 сцен, 64 флага, 96 предметов, 128 фактов; изначально подтверждённый инвентарь, actor-specific знания, tick/time; отдельный opt-in `build-extended`, v3 не изменяется. Это **формат/runtime/CLI**, а не завершённый FB2→CANON RPG: генератор `StoryPlan` и промежуточные компиляторы пока в 192/32/12, нужен единый v4 authoring с семантической приёмкой. Код `f30e59007a913724f6466f3e70b27b926025bceb`; [CI #42458636957](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42458636957), M0 #42458636967 — читать окончательные выводы перед решением. E6d/main не трогать, один Draft PR #133, **не мельчить**.


## Новый единый перенос multi-act/whole-book model port (код 3c1a7aa)

[**Полный статус, файлы и gate**](docs/P0_STANDALONE_MULTIACT_AND_BOOKWIDE_MODEL_PORT_RU_2026-11-08.md). `story_authoring` теперь содержит общий multi-act/NPC компилятор, reviewed hero, литературные и prose типы, source/chronology/causal gate и `PortableWholeBookAnalyzer` (точные окна, source hashes, consent, Resume, cancellation, provider callback). Flutter использует те же типы через export и остаётся только адаптером Z.ai/OS. **Это ещё не автоматический CANON FB2→RPG**, лимиты богатого формата и game UI остаются. Код `3c1a7aa19853d5ea13a031db4dc2ad06b80b2b96`. [CI #42455037055](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42455037055) — точный итог перепроверить; [M0 #42455036949](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42455036949) SUCCESS. E6d/main не менять. Один Draft PR #133, никаких микро-PR.


## Автономная подготовка, source-locked ИИ и перенос компилятора (код df592c9)

[**Отчёт по новому функциональному пакету**](docs/P0_AUTONOMOUS_COMPILER_AI_PROPOSALS_RU_2026-11-08.md). В `story_authoring` теперь исходные редакторские NPC/knowledge/item bridges, native v2/v3 compiler на `Isolate.run`, `PortableReviewedDraftCompiler` и pure `StoryProposalValidator` для Z.ai и CLI. Добавлены `review-plan` и `build-draft`: из проверенных source/editorial/scene checkpoints получается частный rich-v3 без Flutter/сети; НЕ автоматически доказанный CANON. Точный кодовый HEAD `df592c97599b9d977e4f8aaf5deac913c024533b`; [CI #42452212594](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42452212594): Python/Dart и автономные Dart+Python проверки прошли, полный UI/Windows/Android до окончательного результата не считать PASS; [M0 #42452212571](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42452212571) SUCCESS. Один Draft PR #133; E6d/main не трогать. Следующий блок — самостоятельный весь `multi_act_trial_compiler` + `whole_book_npc_campaign` + hero/prose/reviewer + model port и масштабирование >48/192, затем единый GUI по заранее детальному проекту.


## Автономное авторство: начат кодовый пакет

[Фактический ход автономизации и блокеры](docs/P0_AUTONOMOUS_AUTHORING_PROGRESS_RU_2026-11-08.md). В коде `0ce8ea2` перенесены 25 модулей источника/событий/семантики/StoryPlan в `packages/story_authoring`; Flutter re-export вместо дублирования. CLI: `inspect-source`, `scan-source` с Resume, `build-reviewed`, `verify-world`. Источник, книги, причинность и импорт проверяются автономно, но **полный литературный FB2→RPG и модельное авторство пока не независимы**; не выдавать за готовое. Приёмка нового кода: [CI](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42448890904), M0 #42448890906 SUCCESS; точный статус CI перепроверять. Сначала закончить pure-Dart authoring слой, затем GUI по утверждённой схеме; никаких микро-PR, main/E6d не трогать.

## Проект единого мастера и 100% автономности, до изменения экранов

[Документ обязательной архитектуры и приёмки](docs/DESIGN_UNIFIED_BOOK_TO_RPG_PATH_AND_AUTONOMOUS_AUTHORING_RU_2026-11-08.md): source→review→роль/режим→книга по актам→NPC/предметы→диалоги/проза→strict validated .bworld→реальный runtime/SQLite→импорт. Указать отличие проверенных функций от перечисленных режимов CANON/AI_FREEFORM; не упускать GPT/GLM consent и offline. Первый технический пакет — перенести импортёр/индекс/компиляцию source locked в pure Dart + CLI без дублирования, затем проектировать GUI. Один PR #133, два функциональных пакета, один gate. Начало реализации не означает «автономное авторство уже завершено».

## Расширенная проверка разрывов движок/формат/UI (8 ноября 2026)

[Матрица, источники и критерии приёмки](docs/ENGINE_FORMAT_UI_GAP_AUDIT_RU_2026-11-08.md). Внимание: B1 — `WorldGameView.npcLifeStates` может включать невстреченного NPC при future lifeTransitions, хотя NPC sheet фильтрует встречи; проверить privacy regression. A1–A4 — rich-v3 НЕ поддерживает часть core возможностей (стартовые знания/инвентарь, time effects, private CANON/AI_FREEFORM, большие книги); B2–B10 — UI-прослойка слабее NPC/диалогов/сцен; C1–C6 — ИИ только выбирает разрешённое действие, >32 вариантов запрещает, нет видимого Stop, возможны исходные цитаты в labels. Существующий план 2 больших пакета + одна приёмка; не мельчить, main и E6d не трогать. По GitHub Compare после кодового SHA `6c3750ba` все изменения — только Markdown. CI #987 и M0 #1072 SUCCESS для кода. Физические экраны и live GLM не проверены.

## Аудит игровых панелей и свободного ИИ-ввода (8 ноября 2026)

[Сверка «Герой/Предметы/Журнал» и свободного ввода с реальным `story_core`](docs/PLAN_TWO_UX_AUDITS_ONE_PR_RU_2026-11-08.md): данные основаны на SQLite replay, но UI показывает простые текстовые списки без полного контекста роли/предметов/событий. FreeText офлайн и Z.ai работают **только** через выбор подписанного enabled `choice_id`, AI не создаёт действий/сюжет/предметы; один consent на отправку, отдельное подтверждение хода. В журнале записывается исходное действие, а не дословная фраза свободного ввода. Особые причины npc_trust/memory/item_owner сейчас показываются общей фразой. Добавлено в **существующий пакет 1**, без нового PR/задач; настоящий динамический AI-game-master потребует расширения typed-контракта движка, это не UI switch. Только docs, код пока не изменён. Физический UI и live GLM не проверены.

## ВАЖНО: уточнение аудита игрового экрана (8 ноября 2026)

[В едином плане двух аудитов добавлен аудит экрана RPG, диалогов/иконок/портретов и архитектуры](docs/PLAN_TWO_UX_AUDITS_ONE_PR_RU_2026-11-08.md#уточнение-по-игровому-экрану-диалогам-и-соответствию-ядру--8-ноября-2026). По исходникам WorldPlayPage/DialogueStage/GameQuickBar/WorldLibraryGateway подтверждены: центральный scrollable reader, 86px круглый слот (иконка человека/книги, PNG вручную), последовательные подписанные реплики, защищённые knowledge-gated choices и честная projection из SQLite/story_core; портреты привязаны к `campaignId+speaker_name`, а не `character_id`; монологи без двух говорящих переходят в обычную прозу. UI **не раскрывает всех возможностей движка**: только счётчики NPC/score/state, технический ID героя, нет встроенной галереи/эмоций. Риски GameQuickBar <312dp, тёмная app theme × светлая reader palette, FAB/кнопки, physical screenshots. Не говорить, что UI визуально полностью проверен: нет screenshot/golden в репозитории и device QA. Включить в существующий **пакет 1**, не создавать микро-PR. Полный игровой runtime автономен (4 pure-Dart пакета + CLI/SQLite), но полный FB2→сценарий пока частично импортирует Flutter и live GLM нужен для облачного authoring. Код этим документальным уточнением не меняется.

## Единый план по двум аудитам — 8 ноября 2026

[**ПЛАН ИСПРАВЛЕНИЙ: 2 крупных пакета + общая приёмка**](docs/PLAN_TWO_UX_AUDITS_ONE_PR_RU_2026-11-08.md) составлен по полному UI/UX-аудиту и аудиту пути «книга → игра». **Пакет 1** — один видимый мастер, early readiness/Resume, опциональные 0/1/2 NPC, настройки/prefs/fault recovery, privacy-удаление черновиков, темы/контраст/адаптивность, backup. **Пакет 2** — полноценная масштабируемая карта книги, причинные знания/предметы/NPC, настоящий CANON и ALTER_FATE, литературный presentation, чистый автономный Dart authoring слой без второго runtime. **Общая приёмка** — CI exact SHA + реальные 2 RU FB2/live GLM + физические Win/Android. Только один Draft PR #133, без микро-PR; main, E6d, issue #118 без изменений. Это **план, код ещё не исправлен**.

## ВАЖНО: полный UI/UX-аудит ВСЕГО приложения — 8 ноября 2026

[Главный отчёт](docs/AI_STORY_RPG_FULL_APPLICATION_UX_AUDIT_RU_2026-11-08.md) — инвентаризация 171 Dart-файла приложения, 132 Flutter-тестов и более 50 UI-модулей (исходники и CI; НЕ реальные скриншоты/физические устройства). Аудит охватывает главный экран, библиотеку/кодировки/удаление, читалку/оглавление/иллюстрации/позицию/закладки, демо, BookWorld/блокировку выбора, диалоги, портреты, свободное действие, Герой/Предметы/Журнал/NPC, кампании, .bworld/.bwsave, **ВСЕ НАСТРОЙКИ**, Z.ai/приватность, source/editorial, подготовку сценария/героя/NPC/предметов и prose, Android/Windows/адаптивность и границы движка.

**ОБЯЗАТЕЛЬНО СОХРАНИТЬ НЕЗАВИСИМОСТЬ ДВИЖКА ОТ ПРИЛОЖЕНИЯ:** story_core + story_runtime_adapter + bookworld_format + campaign_manager — 4 отдельные pure-Dart пакета, boundary CI и standalone CLI прошли на коде 6c3750ba ([CI #987](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42439491413) SUCCESS / M0 #1072 SUCCESS); Flutter, SQLite, сеть и UI не нужны для исполнения core. Но подготовка FB2→сценарий находится преимущественно в apps/story_reader/lib, часть компиляторов напрямую импортирует Flutter compute. Не называть ПОЛНЫЙ авторский конвейер независимым; при реализации вынести чистую логику в отдельный reusable Dart слой, не создавать второй игровой исполнитель. Внешний E6d по-прежнему отложен пользователем.

**Новые ПОЛНОПРИЛОЖЕНЧЕСКИЕ P1 сверх прошлых UX-аудитов:** смена темы optimistic/unawaited без rollback/error и сериализации; ошибки сохранения читательской темы местами скрываются, false из SharedPreferences setters не проверяется; удаление книги удаляет только библиотечный файл, но оставляет scoped authoring checkpoints без понятного очистного UI; смешанные AppTheme dark/light и независимые палитры ReadingPreferences могут дать невидимый текст контролов свободного действия/диалоговых кнопок; нижняя GameQuickBar с NPC требует не менее 312 logical pixels (не протестирована ширина <312); устаревшие описания возможностей ИИ; реальные backup roundtrip/system picker, TalkBack/desktop keyboard и фон Android не проверены.

**Сохранять исправленное:** BookReader уже использует semantic paragraph anchor при изменении ширины/шрифта — старый баг «только пиксели» закрыт; BookWorld удаляется с подтверждённым backup/revision check; автономная игра и SQLite replay работают. Не проводить общий редизайн ради уже решённых проблем. Остаются критические book→game P0 (NPC обязателен, 2–12 актов/≤15 ролей/до 192 сцен, отсутствие полного CANON, нет двух RU FB2/live GLM/device E2E). Сначала единый согласованный функциональный пакет UX пути и настроек с fault-injection и 0/1/2 NPC, после — масштабирование и отдельно авторский слой, затем реальные книги/физическая приёмка. Никакого микро-PR на каждую функцию.

Это **аудит без исправлений в коде**; docs-only [skip ci] не является новым протестированным кодом, PR #133 оставлять Draft, main/E6d не менять, #118 не закрывать.


8 ноября 2026. Ветка `feature/p0-bookwide-gameplay-readiness-20261107`; существующий [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) OPEN / DRAFT. Не дробить на микро-PR, не сливать в main и не создавать второй runtime. E6d / tools/rpg_author / pinned contracts отложены пользователем. Очистка репозитория завершена, повторять не надо. Игра автономна: story_core / rich-v3 / SQLite.

## Начать с проверки exact-head CI

Новый код **`6c3750bae27c30c5fdb67f17a055e6563e8081b0`**, [CI #987](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42439491413). На последнем просмотре **Python, Dart, весь M1.7 (схемы/независимые импорты/SQLite/standalone), Flutter static analysis и [M0 #1072](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42439491496) — SUCCESS**. M1.7 job 128605462864 завершён. Полный Flutter job **128605463113** ещё выполнялся; новые 11 тестов и Windows/Android пока не объявлены PASS. Проверить эти run/job IDs, не внедрять всё заново.

Предыдущая полная принятая база **4cbca1a54621ee0958c3fffbf62d6ed2be0cbbed** — [CI #986](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773798) COMPLETED / SUCCESS с Windows/Android, [M0 #1071](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773686) SUCCESS. Прежние ошибки #985 исправлены. [External E6d #275](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42437773698) FAILURE отдельно; [External #276](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42439491416) требует своего результата. Не ослаблять внешний контракт и не объявлять все workflows зелёными.

Документация `33c61840` и следующее docs-only обновление `[skip ci]` поверх него не меняют код 6c3750ba. [Комментарий пакета](https://github.com/shonentez-afk/AI-Story-RPG/pull/133#issuecomment-6716283575). [Подробный актуальный статус](docs/CURRENT_STATUS_RU.md).

## Что написано единым пакетом

Прежний `_start` компилирует окончательный сюжет/героя/предметы/NPC, затем открывает **«Текст всего прохождения»**. Пользователь оставляет прежний текст без ИИ либо пишет/запрашивает/редактирует повествование всех сцен, включая обе развязки. Отмена не устанавливает неполный вариант. Окончательное применение требует нового прочтения всего текста и подтверждения частной адаптации, затем возвращает архив в прежнюю установку.

`CampaignProseManifest` вычисляет contexts из exact final .bworld: общий замысел, цель сцены/акта, допустимые цитаты, цели будущих решений и фактический all-route инвентарь с NPC socialRulebook. Скрытые NPC-реплики, секреты карточек и сейвы не пересылаются. Модель не создаёт правила. Изменение авторской редакции проверяется до POST/повтора/сохранения и до/после текстовой компиляции.

`CampaignProseStore/Request` сохраняют каждую успешную часть по точному архиву/сюжету. Готовые и ручные сцены не пересылаются; согласия не восстанавливаются. Есть ограниченные identical retries 429/обрыва, отмена и exact-record compare; старый ответ не должен заменять новую ручную правку. Многофайловая/межпроцессная атомарная транзакция не заявлена.

`ReviewedCampaignProseWriter` принимает полный набор русских narrator paragraphs 80–1800 символов, без прямой речи. Абзац добавляется ПЕРЕД всем прежним телом. Цитаты, технические пометки и NPC-диалоги сохраняются дословно: это не замена всех технических формулировок гладким романом. Для подписанного диалога сравниваются все прежние turns, knowledge review сдвигаются только по turn_index. Механические поля blueprint сравниваются полностью, прежний v3 writer/importer заново проверяет источник/архив/SQLite, runtime causal audit подтверждает старые действия и развязки. Новый bookworld_id не переписывает прежнюю кампанию.

Файлы: campaign_prose_authoring.dart, campaign_prose_page.dart, reviewed_campaign_prose_writer.dart, связанная вставка в whole_book_npc_campaign_page.dart (30 добавленных / 2 заменённых строки), 11 тестов campaign_prose_flow_test.dart. [Контракт и тестовая приёмка](docs/P0_COMPLETE_CAMPAIGN_PROSE_RU.md). Пакет ещё нужно принять по полному CI, а не по наличию тестов.

## Открытые границы

Источник/API в новых тестах synthetic, не живой GLM. Локальный Dart/Flutter отсутствует. Поиск прежних приватных FB2 среди доступных Project/Library файлов не вернул их байты. Две разные настоящие русские FB2, живое подключение, литературная проверка мотивов/хронологии/всех сцен и физический Windows/Android QA ещё предстоят. CANON и произвольная структура за пределами прежних дилемм не объявлены готовыми.

После приёмки этого пакета следующий полезный результат — содержательное прохождение настоящей книги и устранение найденных смысловых проблем. Не продолжать бесконечное наращивание мелких инфраструктурных слоёв. #118 и Draft PR не закрывать по синтетическим PASS.


## UX-аудит перед испытанием реальной книги (8 ноября 2026)

Подробный [сквозной аудит движка и готовности книга→игра](docs/P0_FULL_ENGINE_UX_AND_BOOK_CREATION_READINESS_AUDIT_RU_2026-11-08.md) завершён **по исходникам и exact CI**, но не на физическом GUI. CI #987 / 6c3750ba **SUCCESS** во всех основных jobs, в том числе Flutter, Windows и Android. PR #133 остаётся Draft. **Вердикт: автономный движок готов к ограниченной частной тестовой игре, UX «передал произвольную книгу→полная RPG» — НЕ ГОТОВ**. Не начинать реальный книжный приёмочный прогон, выдавая его за release, пока не закрыты критические UX-гейты.

Главные находки: общий сюжет скрыт за AppBar-иконкой после другого многошагового экрана; два CTA библиотеки ведут в конкурирующие пути, статус героя пояснён противоречиво. `WholeBookNpcCampaignPage` не разрешает единый путь при нуле подходящих NPC, хотя runtime допускает отсутствие NPC. Сценарный запрос имеет жесткие ограничения 2–12 актов, без пропущенных глав, ≤15 ролей, ≤160 KiB карты, 24 дополнительных события на акт и 192 сцены без удобного preflight. CANON и литературная достоверность всё ещё не реализованы; `isFullBookRpg == false`. Новый narrator paragraph не очищает старый технический текст. Реальный Grimm CI — импорт и индексация, не полноценная игра; приватный RU FB2 smoke в публичном CI SKIP. Устройства/TalkBack и live GLM не проверены.

**Следующий один связанный функциональный блок:** единый видимый мастер с прогрессом/ранним readiness, опциональный NPC с 0/1/2-NPC E2E, понятные режимы и прямой доступ к common story. Не создавать отдельный PR на каждый пункт; затем проверить масштабирование и презентационный слой и только потом содержательный прогон реальной книги. Кодовый runtime не менялся этим docs-only аудитом, новый CI не требуется только для текста.
