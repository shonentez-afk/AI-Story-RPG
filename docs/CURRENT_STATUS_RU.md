# AI Story RPG — актуальный статус 2026-11-07

## 2026-11-07 — ОДИН ФУНКЦИОНАЛЬНЫЙ ПАКЕТ P0 (не дробить дальше)

**Разработка в PR #133 Draft.** Новый пакет пока НЕ ПРИНЯТ: после push обязательно проверить основной CI на точном новом кодовом SHA. Базовая приёмка до пакета: [CI #958 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372605037) на `d5d83ce299b4c0bd28bda6e95027d944a850138a` (6 актов / 72 source events / 60 интерактивных выборов / 77 SQLite ходов, Windows + Android PASS). `main`/E6d НЕ трогать.

**Готовится единый P0-блок «вся исполнимая многоактная кампания»:**
- `BookwideCampaignContract` формально связывает КАЖДОЕ из двух опорных событий любого акта с его исходной сценой и конкретным выбором, все дополнительно подтверждённые source encounters, а также ОБА перехода (original/alternate) из каждого промежуточного акта. Перед записью/установкой `.bworld` проверяются авторские source IDs, границы актов и отсутствие подмены. После строгого rich-v3 импорта **ОДИН** проход `CompiledCampaignCausalGate.verify` требует исполнимые hash-chained `WorldEvent` witnesses для всех этих действий, отсутствие тупиков/ловушек и полный обход (бюджет -> fail closed). Число реально доказанных source choices и bridges выводится в `StoryPlanTrialCompilation`, а в UI явно указан план проверок до запуска.
- Для превышения шести актов компоновщик **НЕ меняет rich-v3 контракт 32 флага**: 2 долговечных outcome-флага каждого акта сохраняются для причинных зависимостей, а 3 временных флага принятия/отказа/открытия переиспользуются ТОЛЬКО после явно проверяемого сброса на обеих ветвях межактового моста. История решений сохраняется в `WorldEvent`/SQLite; переходные флаги не выдаются за доказанный литературный смысл. Для старого режима 2–6 актов старые имена флагов сохраняются. Планировщик допускает максимум 12 актов при **неизменных** ограничениях 192 сцен, 32 флага, 2500/8192 причинных состояний; если реально сложная кампания превышает бюджет, сборка должна прерваться, а не принять её вслепую.
- Приёмка включает уже зелёный шестактовый стресс >48 событий и новый сквозной тест **8 актов / 96 подтверждаемых source proposals / 16 опорных + 8 дополнительных исходных решений / 14 переходов / 31 SQLite ход**; он проверяет подмену опорной цитаты, неверную границу акта, фактический rich-v3 импорт, все source/bridge witnesses, автономную игру и перезапуск SQLite ровно между актами 4→5. Никаких сетевых запросов и приватных FB2 в CI.

**Что считать готовым ТОЛЬКО после нового SUCCESS CI:** исходное событие -> проверенный исполнимый выбор -> причинное последствие -> переход в следующий акт -> восстановленное состояние в производственном движке. Это не является полным литературным сценарием и не подтверждает CANON/ALTER_FATE, авторскую хронологию или знания NPC. **После приёмки не открывать микрозадачи/PR:** следующий функциональный пакет должен объединять автоматическое построение книги, NPC и проверку причинной непрерывности с единым E2E на двух реальных RU FB2/GLM/устройствах; Issue #118 ещё OPEN.


## 2026-11-07 — ПРИНЯТО: 72 события / 60 игровых решений, CI #958 SUCCESS

**Точный проверенный КОД:** [`d5d83ce299b4c0bd28bda6e95027d944a850138a`](https://github.com/shonentez-afk/AI-Story-RPG/commit/d5d83ce299b4c0bd28bda6e95027d944a850138a). [AI Story RPG CI #958](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372605037) завершён **SUCCESS** для Python reference, Dart engine/story_core, M1.7/ZIP/SQLite, Flutter analyze, **661 Flutter PASS / 2 SKIP** (закрытые FB2 отсутствуют в публичном CI), Windows portable **SUCCESS**, Android debug APK **SUCCESS**. [M0 #1043](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372605258) **SUCCESS**. Публичные артефакты CI: [Windows portable](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372605037/artifacts/13574587018), [Android debug APK (в GitHub Actions ZIP)](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372605037/artifacts/13574034673). Следующие документальные коммиты используют `[skip ci]` и НЕ являются новыми протестированными кодовыми SHA.

**Реальная нагрузочная приёмка:** `bookwide_large_event_campaign_test.dart` действительно выполнялся в #958 (лог: `60 reviewed interactive events across six acts compile, each choice is playable, and a 77-step SQLite campaign survives reopening`, затем `All tests passed!`). Синтетическая книга с 6 главами, 18 окнами Z.ai-анализа через OFFLINE callback, 72 source-verified предложения события, 6 актов по 12 событий, из них 60 дополнительно подтверждённых интерактивных действий. Все 60 имеют воспроизводимые `StoryWorld.apply` choice witnesses после строгого rich-v3 импорта; последовательность из 77 ходов фиксируется через production SQLite, достигает финала и сохраняется после reopen. Это подтверждает снятие общего потолка 48 в нынешнем многоактовом *пробном* компиляторе, но не снимает другие границы: 6 актов, 24 дополнительных событий на акт (планировщик ограничивает акт 24 событиями, включая 2 якоря), 192 сцены, бюджет причинного обхода и ручная семантическая проверка.

**Уже исправлено в том же пакете:** `StoryCampaignCausalAudit` обнаруживает непроходимые циклические SCC и не запрещает повторные действия с выходом; `CompiledCampaignCausalGate` требует исполнимых `source_examine` решений; ролевые `hero_observe` не считаются повторной привязкой. Тесты этого пакета прошли на #958.

**Следующее P0:** подтвердить `CampaignCausalReport.choiceWitnesses` также для двух SOURCE-backed исходных (якорных) решений каждого акта; затем доказать безопасность композиции больше 6 актов через отдельные проверенные boundary contracts, не увеличивая бесконтрольно число состояний в одном BFS. Остальные блокеры релиза 1.0: семантическое соответствие книге, полноценные CANON/ALTER_FATE, две разные реальные приватные FB2 + GLM, ручной QA Windows/Android. [Issue #118](https://github.com/shonentez-afk/AI-Story-RPG/issues/118) OPEN. [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) **Draft**; `main` и внешний E6d не трогать. External RPG author tests #247 по отложенному `contract_drift` остаётся FAIL, это не регрессия основного CI.


## 2026-11-07 — P0 нагрузка 72 исходных события / 60 решений / 6 актов

**Последний кодовый SHA:** [`d5d83ce`](https://github.com/shonentez-afk/AI-Story-RPG/commit/d5d83ce299b4c0bd28bda6e95027d944a850138a) в [PR #133 Draft](https://github.com/shonentez-afk/AI-Story-RPG/pull/133). [Основной CI #958](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372605037) — **в процессе на момент записи**; Python, Dart и M1.7 PASS, Flutter analyze PASS, длительные widget tests ещё проверяются. [M0 #1043](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372605258) — **SUCCESS** на том же коде. Не утверждать SUCCESS всей сборки до фактического завершения #958. Внешний author-tests #247 по отложенной E6d совместимости FAIL; не трогать по договорённости.

**Новый интеграционный тест** [`bookwide_large_event_campaign_test.dart`](../apps/story_reader/test/bookwide_large_event_campaign_test.dart) создаёт полностью синтетическую шестиглавную книгу: 18 source windows, 4 источник-проверяемых event proposal на окно, итого **72 отдельных source events** (без приватного текста и сетевого API). `BookwideActPlanner.build` разбивает их на 6 актов по 12 событий; 2 якоря и 10 дополнительных решений на акт, всего **60 дополнительных интерактивных событий (>48)**. Проверяет source-to-choice привязку, причинное свидетельство `StoryCampaignCausalAudit` для каждого решения, строгую компиляцию/импорт rich-v3, затем **77 последовательных SQLite WorldEvents** по действительному маршруту, достижение финала и восстановление после закрытия/повторного открытия хранилища. Только когда CI пройдёт можно считать нагрузочный контракт протестированным, а не просто написанным.

**Совместимость с ролевыми действиями:** [`d5d83ce`](https://github.com/shonentez-afk/AI-Story-RPG/commit/d5d83ce299b4c0bd28bda6e95027d944a850138a) исправил `BookwideSourceEncounters.executableChoicesForReviewedEvents`: обязательным остаётся именно базовое `..._examine_source` для подтверждённого события, а дополнительное `..._hero_observe` не считается дублированием и не препятствует уже принятому ролевому режиму. Новый негативный случай добавлен к существующему Flutter-интеграционному тесту героя.

**Граница этого этапа:** даже 100% source-event coverage здесь остаётся проверкой механики, **не** доказательством литературного смысла/канона, согласованности полной книги, CANON/ALTER_FATE или готового релиза 1.0. `BookwideStoryPlanComposer.maxDraftActs = 6`, `StoryPlan/IntermediateStoryBlueprint.maxScenes = 192` и бюджет обхода 8192/256 пока действуют; для длинных романов потребуется композиционное доказательство между актами. Следующее после точного PASS #958: доказывать исполнимость не только дополнительных `source_examine`, но и подтверждённых **якорных** `source-backed` решений актов; затем стресс-тест граничных случаев (превышение вместимости, обрыв на границе, `inconclusive`), две реальные FB2 с GLM. PR #133 оставить Draft, `main` и E6d не изменять.


## 2026-11-07 — продолжение P0: замкнутые циклы, source-action witnesses, поактные границы

**Последний КОДОВЫЙ коммит:** [`8ac68af`](https://github.com/shonentez-afk/AI-Story-RPG/commit/8ac68af0970b37378bc51ab344ee0ac57e70637b) в прежнем [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133) (Draft). **M0 #1039 SUCCESS**; [основной CI #954](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42371993459) запущен, результат нужно проверить по exact SHA. До его SUCCESS НЕ объявлять пакет принятым. Старый подтверждённый код `2c6560bd`, CI #951 SUCCESS. `main`/E6d не трогать.

**Что изменилось одним функциональным направлением (три кодовых коммита):**
1. [`83d7c1e`](https://github.com/shonentez-afk/AI-Story-RPG/commit/83d7c1edbe94b7d357c77a01f08bfaf03e9e4637): `StoryCampaignCausalAudit` сохраняет реальные переходы `StoryWorld.apply`, выполняет итеративный SCC-анализ и обратную достижимость от реальных финалов. При полном обходе сообщает `CampaignCausalCycle` (короткий вход, последовательность повторяемых действий, воспроизводимые `WorldEvent`), если компонент цикличен и из него нет пути к финалу. Добровольный цикл с исполнимым выходом не блокирует. При превышении бюджета — `inconclusive`, а не ложный отказ. Предустановочный gate запрещает доказанный замкнутый цикл. Новые engine/Flutter тесты.
2. [`8aa7dd3`](https://github.com/shonentez-afk/AI-Story-RPG/commit/8aa7dd302607b599c2904710f40b84105af9f451): `BookwideSourceEncounters.executableChoicesForReviewedEvents` проверяет однозначную связь каждого пользовательски подтверждённого интерактивного исходного события с `sourceEventId` реального `StoryDecision`. После строгого импорта rich-v3 `CompiledCampaignCausalGate.verify(requiredChoiceIds: ...)` требует реальный исполнимый путь к КАЖДОМУ такому действию (не просто текст цитаты). Тест проверяет `choiceWitnesses` на двух актах и четырёх событиях.
3. [`8ac68af`](https://github.com/shonentez-afk/AI-Story-RPG/commit/8ac68af0970b37378bc51ab344ee0ac57e70637b): убран отдельный глобальный лимит 48 интерактивных событий. Теперь до 24 дополнительных source-encounters на акт, при обязательной проверке цепи каждого акта до его исходной входной сцены. Общий предел остаётся по `StoryPlan` / `IntermediateStoryBlueprint`: 192 сцены, проверки размера и состояния, а также по реальному причинному обходу. UI перестал обещать потолок 48. Не объявлять это безлимитным романным компилятором: `BookwideStoryPlanComposer.maxDraftActs=6`, лимиты 192 сцен/2500 плановых состояний и семантическая проверка канона остаются.

**Дополнение по приёмке:** кодовый HEAD [`cc9a4fe`](https://github.com/shonentez-afk/AI-Story-RPG/commit/cc9a4fe2cb264415764874b931b3982018f7648f) исправляет отсутствовавший `story_core` import в тесте, обнаруженный [CI #954](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42371993459) (Flutter static analysis FAIL; Python и Dart PASS, M0 #1039 SUCCESS). Новый [CI #955](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42372138149) и M0 #1040 должны быть проверены по коду `cc9a4fe`. До результата #955 не объявлять пакет принятым. Пакет ещё не проходил нагрузочный QA на реально более 48 событиях; это остаётся отдельным блокером масштабирования. Внешний E6d не трогать.

**Следующая приёмка:** проверить завершение #954 и M0 #1039 на `8ac68af`; если есть FAIL — исправить конкретные причины, не отключая тесты. Затем нагрузочный сценарий с более чем 48 разными событиями по нескольким актам, контроль безопасного восстановления и границ размера/состояний. Только после этого расширять масштаб за шесть актов с композицией boundary contracts, не увеличивая глобальный BFS без доказательств. Нужны две реальные разные русские FB2 и GLM 4.7 Flash; художественная и каноническая семантика не доказана. PR #133 Draft, Issue #118 OPEN, `main` и внешний E6d не трогать.


## 2026-11-07 — P0 приёмка проверки игровой кампании

**Подтверждённый кодовый HEAD:** `2c6560bd13b10cd644033950c26c6439ba9ed68f` ([commit](https://github.com/shonentez-afk/AI-Story-RPG/commit/2c6560bd13b10cd644033950c26c6439ba9ed68f)), [основной CI #951](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42364986753) **SUCCESS**: Python PASS, Dart PASS, M1.7 + строгий импорт .bworld + SQLite PASS, Flutter analyze PASS, **658 Flutter PASS / 2 SKIP** (отсутствующие приватные FB2 в публичном CI), [Windows portable](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42364986753/artifacts/13571179356) SUCCESS, [Android debug APK](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42364986753/artifacts/13571840021) SUCCESS. [M0 #1036](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42364986992) **SUCCESS**. Эти результаты относятся к **кодовой** версии `2c6560bd`, а следующие документационные коммиты используют `[skip ci]`; не путать.

**Принятый функциональный пакет:** `StoryCampaignCausalAudit.inspect` обходит реальные `StoryWorld.apply` состояния всех доступных ветвей, подтверждает исполнимые маршруты к финалам и выбору, выдаёт replayable hash-chained события и находит короткие контрмаршруты к неоконечным сценам **без доступного действия**, с фактическими причинами блокировок. Статусы `playable/blocked/inconclusive` не смешиваются. Общий `CausalStateSignature` применяется и к предыдущей проверке причинных реплик NPC. `CompiledCampaignCausalGate.verify` после независимого импорта rich-v3 вызывается в обоих существующих компиляторах коротких и многоактных пробных RPG, до установки. Старые легальные игры прошли Flutter-регрессию, намеренно неиграбельные отклоняются. Никаких изменений rich-v3/Python/SQLite runtime и E6d.

**Известные границы, не выдавать за закрытые:**
- Текущий `trap` — сцена без *единого разрешённого* хода. **Замкнутый цикл с разрешёнными ходами, но вообще без пути к финалу** пока отдельно не классифицируется — нужен анализ SCC/обратной достижимости по уже исследованному графу состояний.
- `choiceWitnesses` содержит доказательства доступных решений, а `requiredChoiceIds` умеет задавать обязательные конкретные решения. Но текущий рабочий компилятор **по умолчанию** требует все концовки и отсутствие безвыходных состояний; обязательность *каждого* source-backed решения из текста пока не подключена. Не объявлять полный coverage книги готовым.
- Поиск ограничен по состояниям/ходам (стандартно 8192/256); неполная проверка возвращает `inconclusive` и не разрешает автоматически устанавливать игру. Для романов потребуется поактное композиционное доказательство, а не бесконечное расширение поиска.
- Остался предел `BookwideSourceEncounters.maxReviewedEvents = 48`, не реализован автоматически связанный сценарий **всей книги**, семантическая оценка соответствия канону, две реальные приватные русские FB2 с GLM и ручной запуск на устройствах. Issue #118 OPEN. PR #133 Draft, `main` не менять.

**Следующий связанный функциональный пакет:** (1) устранить недоказанные тупики-циклы через SCC/liveness, не ломая добровольные повторяемые действия с выходом; (2) связать `BookwideActPlanner.compareWithStoryPlan`, `BookwideSourceEncounters` и `CampaignCausalReport.choiceWitnesses` для доказанного покрытия подтверждённых событий/решений, снять лимит 48 через актные boundary contracts; (3) реальные 2 FB2 + GLM, затем финальная приёмка сценария и UX. Внешний E6d другой чат — не редактировать. Документ: [P0 WHOLE CAMPAIGN](docs/P0_WHOLE_CAMPAIGN_EXECUTABLE_ROUTES_RU_2026-11-07.md).



## 2026-11-07 — проверка *всей игры* на достижимость финалов и тупики

**Историческая запись до CI #951. Результаты приёмки указаны выше.** Последний принятый код `5011b3515334a051b17feabce2067a92a217f85e`: [CI #950](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42363370976) **SUCCESS** (Python, Dart, M1.7, 654 Flutter PASS / 2 SKIP, Windows и Android), [M0 #1035](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42363370979) **SUCCESS**.

**Новая задача реализована в коде, но ещё не принята CI:** `StoryCampaignCausalAudit.inspect` в чистом `story_core` обходит *реальные* `StoryWorld.apply` состояния всех игровых развилок, доказывает достижимые финалы и исполнимые выборы, находит nonterminal softlock с коротким хэшированным маршрутом и причинами заблокированных кнопок, различает `playable / blocked / inconclusive`. Старый NPC-поиск использует **тот же** ключ причинного состояния из `causal_state_signature.dart`. `CompiledCampaignCausalGate.verify` после строгого импорта rich-v3 подключён в короткий `StoryPlanTrialCompiler` и `MultiActTrialCompiler` **перед установкой**: неисполнимую или непроверенную игру нельзя объявить готовой. Новые engine и Flutter-тесты написаны. Только структура и правила, никакой оценки художественной истины и никаких изменений ZIP/schema/Python/E6d.

Подробный контракт, испытания и ограничения: [docs/P0_WHOLE_CAMPAIGN_EXECUTABLE_ROUTES_RU_2026-11-07.md](docs/P0_WHOLE_CAMPAIGN_EXECUTABLE_ROUTES_RU_2026-11-07.md). **Дальше:** проверка source-event coverage и неразрывных сюжетных переходов всей книги, затем реальный end-to-end с двумя приватными русскими FB2 и GLM. Приёмка 1.0 issue #118 остаётся OPEN, PR #133 Draft, `main` не трогать.



## 2026-11-07 — P0 двигатель: реальные причинные маршруты NPC

**Новый связанный пакет в PR #133 ожидает exact-HEAD CI; не объявлять PASS заранее.** Последний подтверждённый кодовый baseline `a45fa886`, [CI #949](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42361497532) SUCCESS (654 Flutter PASS/2 SKIP, Python/Dart/M1.7/SQLite, Windows portable, Android APK), [M0 #1034](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42361497406) SUCCESS.

**Исправленный пробел движка:** структурная связь source scene → dialogue scene ещё не гарантирует, что NPC может на реальной ветке узнать факт, вспомнить событие или заслужить доверие. Добавлен чистый `StoryCausalRouteAudit.find` в `packages/story_core`: детерминированно перебирает только реально принятые `StoryWorld.apply` ветки, различает факты по постоянному actor ID, социальную память и отношения, предметы, флаги, время и жизненные состояния; отдаёт подтверждённые события и воспроизводимую последовательность выбора. У результата три статуса: proven/unreachable/inconclusive (лимит, **не** ложный отказ). Предусмотрен режим `forbiddenChoiceId` для контрмаршрута.

**Применение:** `RichNpcDialogueKnowledge.auditExecutableRoutes` проверяет knowledge/memory/trust/causal prerequisites NPC-turn до авторского подтверждения; `RichNpcDialogueAuthoring.propose` и `NpcKnowledgeRichWorldBridge.prepare` вызывают его до компиляции. Исходные source-lock и runtime-redaction не меняются; готовые игры совместимы, **rich-v3 формат и Python importer не изменены**. Написаны новые engine + authoring regression tests включая невозможный путь, альтернативу, replay, social memory и предел бюджета.

Точный контракт, границы и список проверок: [docs/P0_NPC_EXECUTABLE_CAUSAL_ROUTES_RU_2026-11-07.md](docs/P0_NPC_EXECUTABLE_CAUSAL_ROUTES_RU_2026-11-07.md).

**Затем по плану:** на базе контрпримеров `StoryCausalRouteAudit` расширять валидатор многоактного сценария для полной книги: авторские цели и причинные переходы `source event → choice → consequence → dialogue`, отдельная смысловая проверка на реальных 2 русских FB2 и GLM. Не переключаться на дизайн, E6d, веб-платформу, пиксельную графику. PR #133 Draft, `main` не менять.



## Контрольный пункт 2026-11-07: интерфейс NPC синхронизирован с движком

**Подтверждённый кодовый SHA:** `a45fa8869ba064d6129ced346f6fadab639a1dac` ([commit](https://github.com/shonentez-afk/AI-Story-RPG/commit/a45fa8869ba064d6129ced346f6fadab639a1dac)); [CI #949](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42361497532) — Python SUCCESS, Dart SUCCESS, M1.7/SQLite/standalone SUCCESS, Flutter analyze SUCCESS, **654 PASS / 2 SKIP** (приватные FB2 отсутствуют в публичном CI), Windows portable **SUCCESS**, **Android APK: SUCCESS**. [M0 #1034](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42361497406) **SUCCESS**. **Полный основной CI #949: SUCCESS.** Артефакты: [Windows portable](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42361497532/artifacts/13569893314), [Android debug APK (в ZIP-артефакте)](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42361497532/artifacts/13569694203).

**Что вошло одним функциональным пакетом (PR #133 Draft):** после строгой базовой сборки .bworld открыт факультативный экран `NpcDialogueResponsesReviewPage` для source-reviewed NPC-разговоров: выбор нескольких сцен, постоянного `character_id`, источниковой цитаты и текста **всех** игровых ответов героя. Для каждого варианта показаны реальные typed/world-event последствия. Принятие — только через `RichNpcDialogueResponses.propose/accept` и **повторную строгую сборку/импорт** того же формата. Отдельный Skip ставит неизменённый базовый мир; системный Back отменяет сборку. Z.ai не вызывается и сохранения не мутируются.

В `WorldPlayPage` теперь есть четвёртая вкладка **NPC** для персонажей с подтверждённой встречей: направленное отношение NPC→герой, количество и типы event-memory, lifeState если подписан; всё получено из SQLite replay, не из текстовых реплик ИИ. Для неизвестных будущих NPC вкладка не раскрывает имена; старый пилот сохраняет три кнопки.

**UI дефект CI #948 закрыт** в тестовом коммите `a45fa88`: две ошибки теста были в off-screen нажатиях `skip` и первом переключателе на 320dp, т.к. Flutter ListView создаёт элементы лениво. Новые тесты действительно скроллят страницу и нажимают реальные controls; Flutter #949 654 PASS / 2 SKIP. Не отключали тесты, не изменяли двигательные проверки и формат.

**Что НЕ сделано:** визуальный QA живого Windows/Android на физическом устройстве и анализ скриншотов (только исходники + widget tests), пошаговая форма первоначальных знаний/предметов/диалогов NPC с черновиками (текущий большой AlertDialog неудобен), понятный переход «Играть по книге» vs «Подготовить к RPG», полноценная автоматическая мотивационно-каузальная адаптация всей книги и CANON/ALTER_FATE, две реальные частные FB2 и выпуск 1.0 (#118). Внешняя E6d ветка по договорённости не меняется; её отдельный `contract_drift` не блокирует этот main-app функциональный пакет. `main` не изменять; PR #133 оставить Draft. Документационный коммит — `[skip ci]`, точный проверенный кодовый SHA остаётся `a45fa8869ba064d6129ced346f6fadab639a1dac`.



## 2026-11-07 — функциональная синхронизация интерфейса с NPC-движком

**Историческая запись до проверки #949; подтверждённые результаты указаны в контрольном пункте выше.** Последний проверенный baseline: `d7d7539464a6702997c03db9fdbf5012036a5fbf`, [CI #947](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42359369386) SUCCESS (647 Flutter PASS, 2 SKIP; M1.7, Python/Dart, Windows/Android), [M0 #1032](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42359369396) SUCCESS.

**Аудит интерфейса выявил отставание:** NPC directed trust/memory было не видно отдельной карточкой, выборы ответов героя уже существовали в signed rich-v3, но не имели пользовательской формы подготовки. Исходный ручной NPC build находится в очень длинном AlertDialog (>1700 строк исходника экрана); проход готовых диалогов и кнопки выбора уже были.

**Исправления данного пакета:**

- `NpcDialogueResponsesReviewPage` — новый шаг *в том же авторском мастере*, после успешной строгой первой сборки/импорта rich-v3, но **до установки игры**. Отбирает только допустимые source-reviewed многовариантные NPC-сцены; позволяет выбрать одну/несколько сцен, permanent `character_id` собеседника, точный подтверждённый source quote и собственный текст каждого существующего `choice_id`; показывает проверяемый игровой исход (ветку, вещь/факт/флаг, event-derived memory/trust). Требует весь набор вариантов и отдельное подтверждение. `RichNpcDialogueResponses.propose` выдаёт привязанный к SHA blueprint/social digest; штатный worker компилирует и повторно импортирует точный новый rich-v3. Явная кнопка Skip собирает базовый world, системный Back отменяет сборку.
- `WorldPlayPage` и `GameQuickBar`: четвёртая вкладка **NPC** доступна только если встречены NPC; показывает **только** replay-derived отношения NPC→player, число/вид памяти, подтверждённый lifeState. Не раскрывает будущих имён и скрытые знания; pilot game сохраняет старую тройку вкладок. Никаких model/story state writes из UI.
- UI тесты `npc_dialogue_responses_review_page_test.dart` (сцены/собеседники/цитаты/полные ответы/согласие, skip и узкий Android), `world_npc_relationship_panel_test.dart` (показ подтверждённого отношения, no NPC before encounter, 320px). Исторический event-replay, независимый ZIP parser Dart/Python и все движковые эффекты без изменений.

Актуальный аудит с честными ограничениями: [docs/P0_ENGINE_UI_GAP_AUDIT_RU_2026-11-07.md](docs/P0_ENGINE_UI_GAP_AUDIT_RU_2026-11-07.md). **Не сделано:** полный визуальный аудит живого APK/Windows (не видели фактический рендер на устройстве), удобные отдельные шаги для остальных частей гигантского NPC-диалога, автоплан всех причинных NPC-сцен полной книги, CANON/ALTER_FATE, 2 реальных FB2 и финальная приёмка #118. PR #133 остаётся Draft, main/E6d не менять.



## 2026-11-07 — P0 NPC: ответы игрока внутри разговора и реальные последствия (PR #133)

**Реализация нового функционального пакета, ожидает exact-HEAD CI.** До изменения проверенная база: `a1be713`, [CI #945](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42356760768) SUCCESS, M0 #1030 SUCCESS, Flutter 643 PASS/2 SKIP, Android/Windows PASS. Последний `489a413` — только документация, [skip ci].

В `packages/bookworld_format/lib/npc_dialogue_responses.dart` добавлен **один source-reviewed контракт выбора реплик**: для каждой подписанной диалоговой сцены с 2+ настоящими `BlueprintChoice` все `choice_id` связываются с проверенным `interlocutor_id` (постоянный NPC), точным текстом ответа игрока `player_line` и локальной цитатой `source_quote_sha256`. Автор подтверждает **весь** набор вариантов; `RichNpcDialogueResponses.propose/accept` требует ещё отдельный SHA-256 `approvalDigest` точного blueprint и social rulebook. Никакие незаявленные говорящие, будущее знание, недостающий вариант или поддельное source evidence не принимаются. Выборы обязаны приводить хотя бы к двум *разным* зарегистрированным исходам (сцена/эффекты/memory). Формат — **дополнительное подписанное поле** `presentation.scene_dialogue_responses` внутри прежнего rich-v3 ZIP; старые миры не мигрируют и сохраняют поведение.

`RichPrivateBookworldImporter` и `tools/bookworld/private_rich_bookworld.py` **независимо** проверяют каждое поле нового контракта, включая присутствие NPC через подписанный witness и обязательный engine-choice-gate для NPC, который может уйти/погибнуть; presentation не может выдать доступность игрового выбора, это делает `story_core` по своим typed effects/conditions. `NpcKnowledgeRichWorldBridge.prepare` и `compileReviewedNpcRichPrivateBookworldInWorker` принимают **опциональный** `reviewedResponseProposal` и `approvedResponseDigest`; принятие происходит только после проверенной редакторской подготовки.

`DeviceWorldLibraryGateway` отображает выбранную подписанную реплику как `Игрок: «...»` в действующих кнопках и журнале, **полностью скрывает** текст при любой заблокированности исходного игрового выбора, записывает только штатное `StoryWorld.apply` действие в SQLite, а в журнал дополнительно выводит реальные дельты NPC memory/trust из replay `NpcSocialLedger`. Нет новых операций и второго dialogue engine, ни UI, ни Z.ai не мутируют состояние непосредственно. Совместимость старых `.bworld` сохраняется.

Тесты `private_rich_bookworld_writer_test.dart` выполняют две разные ветки: ожидание/помощь → +20 доверия и знание у NPC, отказ → −10 доверия без знания; сравнивают replay stateHash/social snapshotHash. Отрицательные случаи: подмена `choice_id`, NPC, цитаты, согласия, текста, пропущенная реплика. Flutter unit проверяет отображение доступного/закрытого ответа; независимый Python — metadata и реальные байты `book_private_rich_npc_responses_dart.bworld` из Dart CI.

**Ограничение:** этот этап оформляет **принятые автором** ответы и реальные последствия уже смоделированных игровых действий. Он НЕ создаёт автоматически сюжетные выбора и последствия из художественного текста, НЕ является полным CANON/ALTER_FATE и пока не имеет отдельного текстового UI-редактора ответов. Следующая задача — встроить авторский UI для массовой разметки нескольких разговоров, затем развить source-book event/motive→scenario генератор для всей книги (не E6d), по 2 реальным FB2 и автономной Win/Android приёмке. `main` не менять, PR #133 Draft, Issue #118 остаётся открытым, E6d вести отдельно.



## КОНТРОЛЬНЫЙ ПУНКТ 2026-11-07 — NPC Z.ai + autonomous core: exact-head PASS

**Подтверждённый код:** `a1be713fde6bb4f3ba905180a109e825da8be09f`. [AI Story RPG CI #945](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42356760768) — **SUCCESS** на точно этом SHA: Python, Dart, M1.7/SQLite, standalone engine, Flutter analyze + **643 PASS / 2 SKIP** (приватные FB2 недоступны публичному CI), Windows portable и Android debug APK. [M0 #1030](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42356760749) — **SUCCESS**. Публикация релиза в Draft PR ожидаемо SKIPPED. Первое падение CI #944 было **только UI-тестом**: ListView лениво создавал кнопку, найдено `StateError: No element`; коммит `a1be713` исправил прокрутку и получил green exact-head CI #945.

**Подтверждённые артефакты #945:** Windows portable `13568395844` (~15 MB), Android debug `13567794310` (~88 MB ZIP с APK внутри), demo .bworld `13567623707`, benchmark Grimm Frog Prince FB2 `13567462394` — все не истекли при проверке.

**Что добавлено и как открыть:** после создания частного rich-v3 мира в существующем `NpcKnowledgeRulesPage` вернитесь из экрана кампаний в редактор правил — появится кнопка «Предложить реплики NPC через Z.ai (черновик)» только при наличии точного source-verified разговора. `NpcDialogueDraftPage` показывает полный payload, требует отдельное согласие на возможный платный запрос, строго контролирует состав/порядок/speaker_id ответа и позволяет скопировать текст **без установки** в игру. Для включения текста в RPG потребуется редакторская приёмка/перекомпиляция; автоматического одобрения литературного смысла нет. `story_core`, SQLite и автономный runtime НЕ вызывают ИИ и не зависят от Flutter/UI. Подтверждён отдельно mock-test 429 → тот же запрос, без отправки до согласия.

**Честно не закрыто:** это именно авторский черновик уже существующей диалоговой сцены, не автоматическая полно-книжная генерация; нужны многовариантные NPC-разговоры с причинными последствиями каждого ответа, проверка мотиваций/хронологии по полному источнику, CANON/ALTER_FATE, единый FB2→RPG мастер, две реальные русские FB2 и ручные Win/Android проверки. PR #133 **DRAFT**, Issue #118 не закрывать, `main` не изменять. `External RPG author tests #234` отдельно FAIL с прежним `contract_drift`, **E6d сейчас не трогать** (параллельный чат). Документальный коммит после этого контрольного пункта — только docs `[skip ci]`; проверенный кодовый SHA остаётся `a1be713`.



## 2026-11-07 — P0: Z.ai NPC-диалоги как отдельный черновик автора (PR #133)

**Подтверждённая база перед этапом:** HEAD `187166db326adbf5c576328cc89dc06dbf1cd6a8`, [CI #943](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42355345649) **SUCCESS** (637 Flutter tests PASS + 2 SKIP private FB2; Python/Dart/M1.7, Windows portable, Android debug), [M0 #1028](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42355345791) **SUCCESS**. [External RPG author tests #232](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42355345634) отдельно FAIL по прежнему `contract_drift`; E6d ведётся другим чатом и не меняется.

**Новая разработка (ОЖИДАЕТ exact-head CI, пока не писать PASS):** модуль `apps/story_reader/lib/zai_npc_dialogue_draft.dart` принимает ТОЛЬКО импортированный и подтверждённый rich-v3 `.bworld` и `scene_origins`: отдельно перепроверяет `RichNpcDialogueKnowledge.validate`, source-locked происхождение сцены, всех говорящих/факты. Контекст содержит только показанный пользователю текст одной сцены, выбранные постоянные `character_id`, уже подтверждённые причинные условия реплик, игровые варианты и **необязательные** явно одобренные мотивы; не отправляет всю книгу, fingerprint/hash из локального approval digest, сохранения и API-ключ. Сервер — существующий Z.ai GLM 4.7 Flash с теми же vault/preferences/transport, без фоновых запросов и без отправки без отдельного согласия. До 3 ограниченных повторов только идентичного payload на 429/5xx/обрыв.

Парсер принимает JSON **ровно** одной сцены с тем же числом, порядком и именами говорящих; не может изменить нарративные строки, выборы/эффекты `story_core`, `npc_knowledge`, архив или SQLite. Ответ всегда `NpcDialogueCloudDraft`: `canInstallDirectly=false`, `isHumanReviewed=false`, `isLiteraryCanon=false`. Не доказывает смысл/канон нового текста. Для реального включения автор должен проверить его, перенести в уже существующую редакцию сцены и заново собрать и проверить мир. Данные из книги и слова NPC — недоверенные инструкции для модели.

**UI:** `NpcKnowledgeRulesPage` после успешно установленного `.bworld`, содержащего source-reviewed NPC-диалог, показывает кнопку «Предложить реплики NPC через Z.ai (черновик)». Она открывает `NpcDialogueDraftPage` со всем точным payload, предупреждением о платности и трёх повторах, отдельным флажком согласия, результатом и копированием. Облачная кнопка никогда не появляется в автономном `WorldPlayPage`. При редактировании NPC-правил предыдущий контекст сбрасывается. Это авторская вспомогательная функция — **не автономная генерация готовой сцены из всей книги**.

**Тесты:** `apps/story_reader/test/zai_npc_dialogue_draft_test.dart` с подлинным rich-v3 ZIP, импортёром, source-origin, permanent actor, источниковым `learn_fact`, mock Z.ai, UI consent; атаки с чужими говорящими, переставленными ходами, кавычками/переводами строк, лишними полями, неизвестной сценой; retry 429 точно тем же телом, no-send без согласия, отключённого ИИ/ключа. Запустить Flutter CI #next, M1.7, M0 и Windows/Android на новом SHA.

**Открытые блоки:** полноценный мотивированный source-locked сценарий NPC со многими выборами и последствиями на каждой ветви, истинная автоматическая адаптация всех событий книги без лимита, CANON/ALTER_FATE, полный FB2→RPG мастер, 2 реальные русские FB2 и физический Win/Android QA. PR #133 остаётся Draft; main и E6d не трогать.


## 2026-11-07 — P0 NPC: offline-планировщик диалогов, часть единого PR #133

**Стабильная подтверждённая база до этого этапа:** `fc2d213fdcd9838567fbaefc3c8c157d4adb557b`; [CI #942](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42351970248) **SUCCESS** (M1.7, Python, Dart, Flutter, Android APK, Windows portable), [M0 #1027](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42351970302) **SUCCESS**. Separate [External RPG author tests #231](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42351970215) FAIL из-за старого `contract_drift`; отложенную E6d не затрагивать.

**Новый пакет к проверке exact-head CI:**
- `packages/bookworld_format/lib/npc_dialogue_authoring.dart` (pure Dart, **без Flutter, LLM, Python и сети**) добавляет `RichNpcDialogueAuthoring.propose/accept`: из уже принятого подписанного текста сцены, явного назначения говорящих → постоянным `character_id`, проверенных `npc_knowledge.grants` с точными цитатами и отдельно просмотренных семантических привязок строит все `scene_dialogue_knowledge` записи для существующего rich-v3. Никаких новых флагов, событий, предметов, канонических утверждений или реплик не выдумывает.
- Каждый голос NPC строго классифицируется автором: либо реплика после **конкретного исходного игрового `learn_fact`**, либо отдельно разрешённая бытовая `GAME_FICTION` без знаний. Отсутствующие/двусмысленные привязки, неверная цитата, чужой актёр, осиротевшая разметка или конфликт классификаций — отказ; нет auto-guess личности по имени.
- Сам план **не устанавливает** игру и не меняет кампания; второй шаг `accept` требует точный SHA-256 digest, привязанный к версии всего `StoryBlueprint`, профилям говорящих и условиям, и явное подтверждение. После этого `NpcKnowledgeRichWorldBridge.prepare` (и `compileReviewedNpcRichPrivateBookworldInWorker`) принимают `reviewedDialogueProposal`/`approvedDialogueDigest`; конфликт с ручной подменой `reviewedDialogueTurns` запрещён.
- Контракт проверяется существующим `RichNpcDialogueKnowledge.validate` и импортёром; во время игры реплики всё ещё раскрываются только после SQLite replay через `RichNpcDialogueKnowledge.redact`. **Автономный движок не менялся**, новых save-схем и второго рантайма нет.
- E2E тесты для двух маршрутов (знающий NPC / ещё не знающий), отказ без согласия, неоднозначный grant, неверный `character_id`, смена digest, импорт rich-v3, replay. CI независимо проверяет ZIP, собранный Dart, с Python.

**Честная граница:** автоматизируем **сборку игрового контракта для готового проверенного диалогового текста**, пока ещё **не создаём автоматически художественные слова NPC из полного графа книги**, не доказываем мотивы/канон и не решаем большие CANON/ALTER_FATE. Дальше — полно-книжный NPC/event/motive graph, GLM draft с согласием, литературная проверка каждой реплики, последствия ответов и развилки, две реальные FB2 Win/Android. Не закрывать Issue #118, PR #133 оставить Draft, E6d не изменять.



## 2026-11-07 — P0 NPC: причинные условия на проверенных репликах (часть PR #133)

**Новая реализация — awaiting exact-HEAD CI (не объявлять PASS заранее).** В `packages/bookworld_format/lib/npc_dialogue_knowledge.dart` добавлен совместимый с rich-v3 необязательный набор для одобренной частной реплики: `required_prior_choice_id`, `source_quote_sha256`, `private_fiction_confirmed: true`. Все три обязательны вместе. Строгий импортёр сопоставляет предыдущее решение с source-locked исходной цитатой, маршрутной достижимостью до текущей сцены и, для требуемых `required_fact_ids`, точным `learn_fact` этому постоянному `character_id`. Из одного порядка глав знание и право на слова не появляются. Это явно **GAME_FICTION**, а не литературный CANON или доказательство произнесённой NPC реплики.

Во время исполнения `WorldLibraryGateway` получает только journal из проверенной SQLite replay-кампании и передаёт его в `RichNpcDialogueKnowledge.redact`. Без предшествующего committed выбора слова недоступны даже при наличии иных знаний; они не попадают в Flutter, историю и локальный курсор. Поведение детерминированное, офлайн, без дублирования `story_core` и без изменений `.bworld` ZIP/SQLite/механики игровых эффектов. Старые rich-v3 записи без этих полей сохраняют прежнее поведение. `NpcKnowledgeRichWorldBridge.prepare` проверяет тот же набор при авторской подготовке.

Добавлена проверка **двух маршрутов** и replay в `packages/bookworld_format/test/private_rich_bookworld_writer_test.dart` с негативными случаями: ложный SHA источника, недостижимое решение, решение без `learn_fact`, снятое согласие. Независимый `tools/bookworld/private_rich_bookworld.py` проверяет точно ту же тройку; `tests/test_rich_scene_dialogue_projection.py` покрывает Python-контракт; CI `.github/workflows/android-ci.yml` валидирует **те же Dart-созданные байты** `book_private_rich_dialogue_causal_dart.bworld` в Python. 

**Далее:** дождаться exact-HEAD CI/M0 и при необходимости поправить ошибки, затем развить автоматический source-reviewed NPC dialogue authoring по фактам, участникам, мотивам, последовательности событий и разным игровым маршрутам, а после — полно-книжную адаптацию. Текущий пакет — работающая проверка для *подготовленных* диалогов, НЕ автоматическое создание всех литературно достоверных разговоров. PR #133 оставить Draft до полной приёмки Issue #118. E6d не трогать, main не менять. Исторический стабильный SHA до этих изменений: `4bb128e`, CI #939 и M0 #1024 SUCCESS.


## 2026-11-07 — Защита закрытых реплик героя (единый PR #133)

**Подтверждённая база:** [AI Story RPG CI #938](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42345757647) и [M0 #1023](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42345757634) на коде `b5b7f1ae03600cd19bc61fcc3e9a8d105844bd97` — SUCCESS, включая 635 Flutter tests (2 SKIP), Android APK, Windows portable, Dart/Python/M1.7. PR #133 по-прежнему DRAFT, `main` не трогать, E6d отложен.

**Продолжение того же функционального пакета (точный новый CI после коммита проверить):**
- В `WorldLibraryGateway._view` добавлена `WorldChoiceView.fromVerifiedRules`. Каждый вариант ответа с типизированным условием `knows_fact` сверяется с **replay-verified** `state.knowledge[actor]` и `current.choices` из подписанного сценария. Пока ответ закрыт (из-за неизвестного факта, роли или другого условия), **на UI не передаётся текст секретной реплики**, только нейтральная заглушка. Это защищает и экранные кнопки, и accessibility label.
- Когда **все** условия выполнены и движок реально разрешил выбор, отображается полный исходный текст. Если adapter вдруг пометил ответ доступным, хотя игрок/говорящий не знает факт, выдаётся `FormatException` вместо разглашения текста. Старые обычные выборы без `knows_fact` сохраняют прежнее поведение.
- Отрицательные тесты: неизвестный факт, чужая роль при известном факте, неучтённый `knows_fact`, обычный выбор по предмету и состояние после действительного приобретения знания. Условия и эффекты остаются в единственном `story_core`; формат rich-v3/SQLite и старые .bworld не меняются.
- **Граница готовности:** это защита и работа УЖЕ СУЩЕСТВУЮЩИХ knowledge-gated ответов, а НЕ ещё генерация полноценных литературно подтверждённых NPC разговоров. Дальше нужен явный author review: источник говорящего, `character_id`, факт, момент получения, мотивация и влияние ответа на последствия. Только после этого полный CANON/ALTER_FATE и автоматический путь FB2 → playable RPG.

**Открытые большие блоки 1.0:** (1) все существенные события книги без временных лимитов 8/акт, 48 всего; (2) подтверждённая хронология/знания/состояния/отношения NPC в каждой ветви; (3) реальные многовариантные диалоги и последствия без спойлеров; (4) настоящий CANON и причинный ALTER_FATE; (5) один мастер с приватным GLM, согласием, лимитами и восстановлением; (6) две разные русские FB2, реальный GLM, мобильные/Windows ручные испытания; (7) финальная приёмка PR #133 → main CI → release SHA256. **Не делать микропиары.**



## 2026-11-07 — новое целевое P0: достоверная запись прочитанного героем (локально, без ИИ)

**База PR #133 до этого изменения:** код `fb15a1ee7ce3bfbbe8aaa2a15273be812a5bcf87`: [CI #937](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42343416675) **SUCCESS** (Flutter 635 PASS / 2 SKIP, Dart/Python/M1.7, Windows/Android), M0 #1022 SUCCESS. Текущий HEAD `13789101407f4d66eda443b4f0ab6386d6dcbf84` — только docs [skip ci]. `main` = `81fb75b`, PR #133 DRAFT, E6d не трогать.

**Новый связанный функциональный шаг внутри того же PR #133:**
- `ReviewedHeroReadingCandidate` без запроса к ИИ строит ровно один возможный `learn_fact` **из дословного verified source span**, только когда в реально проверенном `StoryPlan` существует действие `_hero_observe` для выбранного героя по постоянному `character_id`. Предложение *не* является проверенной литературной истиной: это текст, который **игрок прочитал**; никакого исходного знания или тайны NPC не придумываем. Fact ID детерминирован от source edition/event/choice/exact quote и не публикует текст/ключи.
- На существующем `SourceLockedGameplayReviewPage` добавлена кнопка **«Предложить знание из цитаты без ИИ»**. Она только показывает локального кандидата, не вызывает Z.ai и ничего не устанавливает: нужны ручной выбор, редакторское объяснение (18–350 символов), согласие на частную игровую интерпретацию, финальный exact-digest preview и подтверждение перед сборкой. Это **тот же `ReviewedGameplayCompiler`**, который проверяет source SHA, typed `learn_fact`, игровую достижимость и rich-v3 writer/importer.
- `MultiActTrialPage._chooseGameplay` при включённом ролевом действии гарантирует, что нужная verified-цитата попадает в лимит 6 выбранных фрагментов, даже когда она находится позже первых шести главных событий. Сортировка по книге сохранена. Старые планы и выборы без роли ведут себя по-прежнему.
- E2E расширен реальным `MultiActTrialCompiler` → exact quote/context → локальный кандидат → review preview → confirmed rich-v3 `.bworld` → 2 кампании SQLite. Путь `_hero_observe` выдаёт игроку **только память о собственном чтении**, пропуск не выдаёт её, после close/reopen известный факт остаётся у первого игрока и отсутствует у второго; NPC knowledge изначально пустая. Отказ финального согласия блокирует запись.
- Это **НЕ** полный первичный набор знаний книжного персонажа, **НЕ** генератор NPC-диалогов и **НЕ** готовый CANON. Следующее — отдельно проверенные role-linked сведения/разговоры и полноценная причинность всей книги.

**Приёмка:** после коммита проверить EXACT HEAD CI/M0, Flutter widget, Python/Dart, M1.7, Android/Windows; не объявлять новый пакет PASS раньше подтверждения. Держать PR #133 единым Draft до общей приёмки #118. E6d не изменять.



## ПОДТВЕРЖДЁННЫЙ КОНТРОЛЬНЫЙ ПУНКТ — 2026-11-07

**Последний проверенный КОД:** `fb15a1ee7ce3bfbbe8aaa2a15273be812a5bcf87` в [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133). [AI Story RPG CI #937](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42343416675) — **SUCCESS** на ТОЧНОМ кодовом SHA: Flutter analyze, **635 widget тестов PASS, 2 SKIP**, Python, Dart, M1.7, Windows portable, Android APK. [M0 #1022](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42343416691) — **SUCCESS** на том же SHA. Публикация тестового GitHub release в PR ожидаемо SKIPPED; это НЕ ошибка сборки.

**Доступные артефакты CI #937:** `AI-Story-RPG-Windows-portable` (artifact ID `13562822537`, не истёк); `AI-Story-RPG-Android-debug` (artifact ID `13562299704`, не истёк); `AI-Story-RPG-BookWorld-demo` и `AI-Story-RPG-Grimm-Frog-Prince-FB2` (публичный QA-пример). Для Android артефакт Actions является ZIP-обёрткой для собранного APK; не путать с готовым APK-файлом напрямую.

**Что реально работает в том же движке:** выбранный герой по постоянному source-reviewed `character_id` → игровой identity flag `player_is_npc_<id>` → при отдельном ручном согласии и наличии двух последовательных source-encounter с точным цитатным упоминанием доступна `_hero_observe`, а затем `_hero_recall` только после `hero_source_observed`. Смена героя/отрывка снимает прежние подтверждения; нейтральные выборы работают независимо; нет придуманного канона, секретов NPC или выдуманного владения вещами. Действия, журнал и state replay проверены из SQLite после закрытия/повторного открытия.

**НЕ путать с закрытием проекта:** PR #133 остаётся **Draft**, в `main` не переносить до общего функционального пакета и приёмки #118. Дальше — проверяемые начальные знания героя, роль-зависимые реплики и диалоги, причинная адаптация всей книги, реальные CANON/ALTER_FATE, полный FB2/GLM и Win/Android E2E. E6d ведёт другой чат, **не трогать**. Не делать отдельный PR на мелкие поля/экраны; соблюдать единый функциональный пакет. Если следующий коммит меняет ТОЛЬКО эти документы с `[skip ci]`, проверенный кодовый SHA по-прежнему `fb15a1e`, а новый документальный HEAD сам по себе НЕ имеет нового CI.



## P0 — ролевые игровые действия по подтверждённым цитатам (2026-11-07)

**Проверенная база:** [CI #936](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341576311) на `abfb5a509beb5d45aacc13ce80b29fee36f86ef8` — **SUCCESS** во ВСЕХ задачах: Flutter analyze/widget, Dart core, Python, M1.7, Windows portable, Android debug; [M0 #1021](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341576327) — SUCCESS. PR #133 **Draft**, не сливать до полного функционального пакета.

**Новое расширение этого же PR, результаты exact-head CI ещё не получены:**
- `ReviewedHeroRole.confirmedMentions` сохраняет только проверенные `EvidenceKind.character` ссылки из существующего NPC-досье. Не копирует в мир книжные цитаты/биографии/секреты.
- `ReviewedHeroSourceAction.find` независимо перепроверяет оригинальные UTF-16 offsets цитаты и упоминания героя, одинаковый `chunkId`, точное пересечение диапазонов, статус `confirmed` и `sourceFingerprint`. Требует **два последовательных добровольно выбранных source-encounter**, где первое событие явно упоминает выбранную подтверждённую личность. Совпадение имени где-то в книге не даёт права.
- Только после **отдельного явного** согласия в существующем `MultiActTrialPage` overlay добавляет к исходному `StoryPlan` ровно две типизированные **GAME_FICTION** опции: `..._hero_observe` требует `player_is_npc_<permanent-id>` и устанавливает `hero_source_observed` как факт выполненного **игроком** действия, а `..._hero_recall` в следующей сцене требует оба флага. Обычные `pass_source`/`examine_source` остаются свободными и сохраняют все старые исходы. Знания NPC, тайны, время/присутствие, литературный канон не выводятся из текста и не выдаются игроку.
- Путь **один**: существующий typed `StoryPlan` → source-locked `MultiActTrialCompiler` → private rich-v3 `.bworld` → `story_core` → SQLite `campaign_manager`, включая reopen. Без нового механизма действий, save format, формата книги, миграции, API или дополнительных экранов. Смена героя/цитаты/решения сбрасывает старые AI/литературные/gameplay approvals; отказ чтения NPC checkpoint снимает прежнюю личность.
- Добавлен E2E-тест двух выбранных цитат с реальными точными упоминаниями героя, неизменности нейтрального пути, запрета на действие без проверенной личности, lock/unlock по `hero_source_observed` и сохранения условий после SQLite reopen.
- Остаётся важно: это **только ограниченный, честно обозначенный частный игровой механизм**, НЕ универсальные role-specific диалоги/знания и НЕ полный литературный CANON. Дальше по #118: отдельные факты игрока только из явно одобренного источника, правила доступности диалогов и последовательная причинность от начала до конца книги, реальные FB2/GLM Windows+Android.

**Следующему чату:** сначала проверить точный HEAD PR #133 и завершённый exact-head CI/M0 для этого изменения, устранить FAIL до любых следующих функций. Не создавать микропиары, не трогать ветку внешнего генератора E6d, не сливать Draft преждевременно.



## CI #935: исправление исходного состояния длинного Flutter-редактора

[CI #935](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341114807) завершился **FAILURE** только из-за двух Flutter widget-тестов. Python reference, Dart engine, M1.7 contracts/SQLite и M0 #1020 SUCCESS. Отчёт `multi_act_trial_compiler_test.dart`: (1) `scrollUntilVisible` вызывается на ещё НЕ СОЗДАННОМ элементе длинного `ListView` (StateError No element); (2) `ExpansionTile` списка дополнительных событий терял собственное состояние после выгрузки из ленивой области, так что `multiact-select-all-encounters` отсутствовал при возвращении пользователя.

**Изменено по реальной причине, без отключения проверок:** `MultiActTrialPage` теперь использует `PageStorageKey<String>('multiact-source-encounters')` — состояние открытого списка сохраняется при прокрутке к цитатам и назад. E2E widget-тесты используют физическую прокрутку основного `Scrollable` до появления нужного `Finder`, затем `ensureVisible` и проверку фактического клика. Они продолжают проверять два source-event выбора, массовое выделение, сброс согласия на цитаты, включённость кандидатов игрового предмета после согласия. В результате исправляется реальный UX, а не маскируется тест.

Дополнительно выбор персонажа соответствует существующему `NpcEditorialPage`: отсутствие НИКОГДА не сохранявшейся `identityRelations` допускает штатную пустую сессию связей, если остальные подтверждённые source/editorial/NPC checkpoint правильные. Присутствующий повреждённый файл **не** сбрасывается и отклоняется. Тест проверяет оба случая.

**Этот новый SHA нужно проверить по новому CI, включая Windows/Android; PR #133 остаётся Draft, E6d не трогать.** Уровень role `character_id` + источник предметов не доказывает готовый литературный CANON/полную RPG.



## Исправление совместимости с фактическим NPC-редактором

Проверка обнаружила безопасный особый случай: существующий `NpcEditorialPage` может создать подтверждённую карточку `npc_<character_id>` **до** сохранения необязательного checkpoint `identityRelations`. В `ReviewedHeroRoleCatalog` отсутствие именно этого файла соответствует проверенной пустой `SourceRelationReviewSession.create(index, graph)` — точно как у существующего NPC редактора. Но если файл существует и повреждён или относится к иной редакции, декодер по-прежнему бросает `FormatException`. Нельзя заменять повреждённый файл пустым и тем самым подменять source grouping. Дополнительный тест проверяет отсутствие/повреждение/восстановление checkpoint без выдачи несуществующих персонажей.

**Состояние непосредственно до добавления:** PR #133 HEAD `3188f87a138edd12a2480e693024a1ea0a01d9cd`, [CI #935](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341114807), [M0 #1020](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341114777). Python, Dart и M1.7, M0 PASS, Flutter widget job на момент подготовки ещё выполняется. Новое изменение требует отдельной exact-head проверки; не считать готовым по результатам предыдущего SHA. PR остаётся Draft; E6d не трогать.



**CI #934 — FAILED (3 isolated Flutter tests; Python/Dart/M1.7 PASS; M0 #1019 PASS).** Причины: (a) тест героя использовал неподдержанный локальным extractor шаблон упоминания «Артем» и не создал подтверждённый dossier; теперь используется **тот же проверенный литеральный шаблон** «Артем по прозвищу Волк», что и в существующем `npc_editorial_notebook_test`, без изменения extractor или подмены identity. (b) старый source/gameplay widget-тест нажимал чекбокс на y=608 при viewport 600, потому разрешение цитат не включилось; теперь нажатие выполняется с видимой прокруткой и проверкой значения сразу после клика. (c) другой widget-тест искал чекбокс цитат ВЫШЕ раскрываемого блока, хотя он расположен НИЖЕ списка событий, так что прокрутка шла в противоположную сторону; направление исправлено. Без отключения проверки и без фальшивой успешной приёмки.

**Дополнение к UI в этом же функциональном PR:** существующая вкладка `Герой` показывает валидный `player_is_npc_<128-bit>` как «Постоянный ID», только из реально сохранённого игрового состояния, без нового экрана/схемы. Поддельный флаг либо свободный герой не превращаются в подтверждённого NPC. Текущий новый exact-head CI после коммита проверить перед merge. PR #133 Draft; E6d отложен.



## 2026-11-07 — постоянная роль в существующей вкладке «Герой»

**Следующее дополнение к функциональному PR #133 (точный CI нового коммита ещё необходим):** `world_play_page.dart` отображает уже сохранённый в штатном `WorldGameView.flags` `player_is_npc_<character_id>` как «Роль: проверенная карточка персонажа» и краткий ID в **существующей** вкладке «Герой». Достоверным источником служит только один true flag, строго подходящий `npc_` + 32 hex; имя/текст диалога не служат заменой. У игрока по-прежнему нет автоматически выданных секретов NPC или выдуманных знаний. Старые миры без роли не меняют вид; новых полей в .bworld/SQLite не требуется. Отдельный виджет-тест проверяет реальный UI и не требует сети.

**Состояние кода до этого дополнения:** `bf881b2` — ввёл source-validated protagonist IDs и тесты, но CI #933 остановился на предупреждении об устаревшем параметре Flutter `DropdownButtonFormField.value`. Коммит `f76cadc6089d11b3a662bbb99da1915f9323c793` заменил на `initialValue`, M0 #1019 — SUCCESS, [CI #934](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42340656714) — Python/Dart/M1.7 SUCCESS, Flutter analyze прошёл, Flutter widget на момент записи ещё выполняется. Не объявлять полный CI SUCCESS и не сливать PR #133 до подтверждения всех задач/Android/Windows. E6d не трогать.

**Что не выполнено:** герой-специфические сюжетные действия/разрешения, законные начальные знания из источника, полный граф событий и настоящий CANON с исходной причинностью, ручной GLM+FB2/Android/Windows E2E. Не считать флаг `character_id` всей игровой механикой героя.



## Новое в PR #133 — выбор проверенной личности героя

**Готов первый сквозной функциональный путь, техническая приёмка exact-head CI ещё впереди.** `ReviewedHeroRoleCatalog` по отдельному нажатию «Выбрать героя по проверенной карточке NPC» читает ровно существующие приватные checkpoint: `narrativeEvidence`, `semanticCatalog`, `semanticEditorial`, `identityRelations`, `npcEditorial`. Каждая запись снова проверяется `SourceCharacterDossierIndex`/`NpcEditorialNotebook.validate`; никакого ИИ, отправки текста и создания `character_id` по имени. Устаревшая/неподтверждённая карточка не показывается. Используются существующие случайные стабильные `npc_<128-bit>` IDs, не идентификаторы цитат.

Выбранный профиль становится **реальным сохранённым состоянием** текущего `story_core`: `player_is_npc_<character_id>` присутствует в `flags` и `initialFlags` единственного `StoryPlan`, затем в rich-v3 `.bworld` / SQLite. Авторские секреты NPC, прежние факты и знания автоматически в `player` НЕ копируются. Игровой actor по-прежнему называется `player` ради совместимости старых rich-v3. `hero.name` закрепляется за `displayName` выбранной сохранённой карточки; изменение героя сбрасывает предыдущие source/AI/gameplay approvals. Перед компиляцией карточки перечитываются и проверяются на изменение ID, source group и названия — stale identity блокируется. Старый режим с вручную введённым именем остался.

**Важное ограничение:** это **первый реальный выбор персонажа на уровне игрового состояния**, но ещё не полный литературный protagonist playthrough. Не выдавать статический флаг за доказанные знания/мотивации или автоматические герой-специфические ветви. Следующие этапы: source-locked role-based доступность реплик/действий, начальные знания с явным источником и владельцем, затем полноценные CANON/ALTER_FATE. Не добавлять второй движок, второй пользовательский экран или микропиар.

Тесты: восстановление редактируемых NPC из существующего личного чекпойнта, неизменный `character_id` после переименования, повреждённая карточка/чужая редакция заблокированы, сохранённый player identity flag и пустые NPC знания после SQLite reopen. Параллельно исправлен widget-тест больших `ExpansionTile`: дети `ListView` строятся лениво; теперь тест реально прокручивает до создания элемента, а не вызывает `scrollUntilVisible` на ещё не существующем виджете. Предыдущий CI #932 FAILED только на этом тесте, Python/Dart/M1.7 были SUCCESS. Полный следующий CI и Android/Windows пока **не объявлять PASS**.



## Текущий P0: цепочки source encounters, единый PR #133

Следующая версия `BookwideSourceEncounters.attach` поддерживает до 8 **последовательных** дополнительных игровых событий на акт и до 48 суммарно. Новые сцены с ID `source_encounter_2`, `_3` и т.д. используют существующий `StoryPlan`/`story_core`; первый ID остаётся обратно совместимым. UI может выбрать все доступные события одним нажатием (строго в рамках лимита), но каждое добавление сбрасывает устаревшие consent и model/GLM approvals. `SourceLockedGameplayContext` не даёт выдавать item/fact за пропуск сцены. Flutter widget проверяет 600px экран и массовый выбор; интеграционный тест — два акта по две дополнительные сцены, реальный optional `grant_item`, обход без награды, SQLite replay.
**CI #930 FAILED** из-за scrollUntilVisible с delta 100: чекбокс был в y=620 за root height 600. Dart/Python/M1.7 SUCCESS. Новый код исправляет прокрутку на 250; до результатов exact-head CI **не объявлять функциональный пакет полностью принятым**. `main` не менялся, PR #133 Draft. E6d отложен.



**NEW #133: реальные дополнительные события книги в игровом маршруте.** Новый `bookwide_source_encounters.dart` добавляет в обычный `StoryPlan` source-locked `act_N_source_encounter` на выбранный дополнительный event этого акта. Имеются 2 действия: изучить/пройти мимо; выбранный choice реально коммитится в `WorldEvent` и живёт в SQLite. Встроенный экран показывает и даёт отдельно подтвердить точную цитату, меняя план/историю только после consent, сбрасывая прошлые model approvals при новой выборке. Единственное `MultiActTrialCompiler`/ rich v3/Python/Dart importer, условия межактовой связи и типизированные предметы/знания могут сосуществовать, т.к. план вычисляется один раз из текущих ревизий. Добавлены отрицательные тесты на чужой/повторный event и согласие, E2E с двумя актами/двумя дополнительными событиями и SQLite close/reopen, UI widget. **Новый предел: до 8 дополнительных событий на акт и 48 суммарно. Это ограниченный playable слой наблюдений, НЕ полный событийный сценарий романа.** На текущем кодовом коммите точный CI ещё не объявлять успешным. E6d отложен.



**Интеграция контракта предметов и межактовых последствий в #133 (ещё проверить точный CI):** UI теперь может предложить source-locked item/fact candidates для точно того же `continuity.plan`, который будет скомпилирован; старые одобрения от базового плана не допускаются. Оба согласия локальные/явные, GLM сам не вызывается от открытия. Кандидаты вносятся после независимого route auditor и дополнительного approval digest, `.bworld` и SQLite не подменяются. Сквозной тест с кольцом и сохранением двух вариантов добавлен. Литературная проверка старой редакции при включённой причинности не переиспользуется.



**Новый функциональный инкремент PR #133:** `CrossActConsequenceGate.applyReviewedActChain` обеспечивает реальную причинную связку ВСЕХ соседних актов. От принятого либо отвергнутого решения зависит доступность предложения следующей части; меняются именно `StoryPlan` conditions и `StoryWorld` choices, а не UI-надпись. Источник проверяется, фиктивная причинность явно подтверждается пользователем; совместимость существующих без галочки не меняется. E2E для 4 актов с двумя маршрутами и реальным SQLite добавлен, результат нового exact-head CI ещё проверить. Это не готовый CANON и не автоматическая целая книга. E6d отложен.



## Подтверждено

- **PR #132 MERGED**, [merge SHA `81fb75b`](https://github.com/shonentez-afk/AI-Story-RPG/commit/81fb75b77f11b8f82cafa1e7604afa9fe9bbb678). Уже в `main`: независимое ядро NPC memories/trust/choices, предметы, event-sourced статус (present/absent/dead), проверяемые source citations, private rich-v3 `npc_social` v1–v5, replay/SQLite и интерфейс.
- Exact pre-merge [CI #920](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42331504767) **SUCCESS**: Python, Dart, M1.7, Flutter/widget, Windows portable, Android APK; [M0 #1005](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42331505079) **SUCCESS**.
- Post-merge main [CI](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42333580182) и [M0](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42333580205) запущены; их финальное состояние **проверить живым инструментом**. Публикация тестовых артефактов не равна ручному QA.
- Внешняя E6d имеет отдельный `contract_drift`; **отложена** до конца основного приложения по распоряжению пользователя. Не менять `tools/rpg_author`, pin или её PR.

## Следующий P0

[PR #133 DRAFT](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), рабочая ветка `feature/p0-bookwide-gameplay-readiness-20261107`: единый путь **полная книга → связный сценарий → выбор настоящего героя/реального режима → приватный playable BookWorld**. [План и критерии](P0_BOOKWIDE_AUTHOR_PATH_RU_2026-11-07.md).

- Уже существует short/multi-act пробный ALTER_FATE с source-locked цитатами, игровыми выборами, SQLite, GLM proposals после согласия и ограниченной редакторской проверкой.
- Первый инкремент следующего пакета вводит source coverage без доверия к AI-оценке, выбранную пользователем **подпись** героя в `presentation.hero.name`, честный UI «только пробный ALTER_FATE». Подпись — не подлинный выбор литературного NPC. Это не готовый CANON/1.0.
- Требуется не только обнаружить события всего произведения, но и **включить** их в причинные игровые маршруты, сохранить знания/предметы NPC при вариантах, полную хронику и концовки; затем 2 реальные FB2, реальный GLM, устройства Windows/Android.

## Принципы и приёмка

Никаких микропиар по полям, никакого второго движка. Всё через `story_core`, существующий формат rich-v3, проверяемые offline game/save/replay. Каждый функциональный пакет — точный HEAD CI Dart/Python/schema/Flutter + Windows/Android + M0, затем merge и CI main. История прежних стадий доступна по git; [полные критерии 1.0](PROJECT_COMPLETION_GATE_RU_2026-11-06.md), [Issue #118](https://github.com/shonentez-afk/AI-Story-RPG/issues/118).
