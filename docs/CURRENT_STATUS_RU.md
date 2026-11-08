# AI Story RPG — статус полного сценарного потока

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
