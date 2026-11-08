# AI Story RPG — статус полного сценарного потока

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
