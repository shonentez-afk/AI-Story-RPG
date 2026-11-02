# Продолжение разработки AI Story RPG — «Живая книга»

**Репозиторий:** https://github.com/shonentez-afk/AI-Story-RPG
**Основная ветка:** main
**Язык переписки и документов:** русский.

## С чего начать
1. Получить содержимое репозитория из GitHub. Сначала проверить `README.md`, `docs/TZ_RU.md`, `docs/STATUS_RU.md`, `docs/ROADMAP_RU.md`, `docs/ARCHITECTURE_RU.md`, `docs/THIRD_PARTY_RU.md`.
2. Считать `docs/TZ_RU.md` главным источником требований; не заменять его догадками.
3. Продолжать строго с реального статуса, **не начинать заново** и не объявлять непротестированное реализованным.
4. Продукт — Flutter/Dart (Windows+Android), offline-first классическая RPG, независимо от ИИ; компилятор книг Python отдельно.
5. Три оси выбора: персонаж (свой/главный/другой), сюжет (канон/изменить судьбу/свободный), взаимодействие (классика/ИИ/гибрид).
6. Z.ai `glm-4.7-flash` — стартовый сменяемый провайдер через личный ключ; не считать бесплатность/лимиты гарантированными и не записывать секреты.
7. Первая техническая веха: общий детерминированный core и переносимый BookWorld с офлайн демо, затем Flutter сборки, затем компилятор, затем ИИ.
8. После каждого законченного шага сохранять исходники, тесты, документацию и актуальный статус в GitHub. Указывать SHA коммита, PASS/FAIL/SKIP и дальнейшие блокеры.

## Утверждённые ограничения
- Нельзя привязывать игровой runtime к серверу, Python или модели. 
- Нельзя самовольно менять канон или изменять действия игрока по требованию LLM.
- Нельзя воспроизводить тексты книг при публикации адаптаций без прав.
- Нельзя копировать код Mørkyn (PolyForm Noncommercial), Project Lunar/PlotTwist (не подтверждённые LICENSE) или GPL-проекта в независимый код продукта без отдельного разрешения.
- Любой отказ ИИ или сети не должен повреждать сохранение.
- При AI->CLASSIC допускаются только совместимые подготовленные ветви без реткона.

## Короткий мастер-промпт
«Продолжай `shonentez-afk/AI-Story-RPG` по `docs/TZ_RU.md` и `docs/STATUS_RU.md`. Сначала проверь реальное состояние репозитория. Реализуй ближайший незавершённый этап M0/M1. Соблюдай Flutter cross-platform offline-first, схемы BookWorld, журнал действий, тесты и лицензии. Сохраняй изменения на GitHub и обновляй STATUS и handoff. Не придумывай результаты проверок».

## Обязательное решение о готовых текстовых движках (2026-11-01)
Перед написанием собственного runtime: прочитать [аудит](docs/TEXT_RPG_ENGINES_GITHUB_AUDIT_RU.md) и раздел 6.1 [ТЗ](docs/TZ_RU.md). На этапе M0 сравнить на идентичной истории `ErikSchultheiss/story_engine` (BSD-3-Clause) и `dennerkrans/ink_dart + flutter_ink` (MIT), выполнить тесты 20+ ходов, saves, условий, автономности и на Android/Windows, затем зафиксировать выбор в ADR. Единственный источник истины по миру — `story_core`, внешний runtime через `StoryRuntimeAdapter`; `.bworld`/`.bwsave` независимы от его внутреннего формата. Не объявлять ни один движок выбранным, пока нет результатов пилота.

## Актуальное продолжение после M1.6.4
Проверь HEAD `main` и реальный GitHub Actions workflow. В M1.6.4 добавлены зависимости выбора от предметов, наглядные причины блокировок и `rulesVersion` в сохранении: новые сессии используют ограничения, старые остаются в режиме 0 без реткона. После зелёного CI следующий приоритет — переносимый `.bwsave`, безопасное автосохранение нескольких кампаний, затем BookWorld и Windows EXE. Не смешивать это с обычной читалкой.

## Передача после M1.6.5 — несколько кампаний и автосохранение (2026-11-01)
- Проверить HEAD `main` и workflow последнего коммита, а не ориентироваться только на этот текст.
- Добавлен `apps/story_reader/lib/campaign_store.dart`: уникальные локальные кампании, snapshot+journal+GameProgress+rulesVersion в одном значении; очередь запись-следом-за-записью в `StoryReaderPage`. Старый `SaveStore.key` остаётся отдельной видимой `legacy` кампанией — **не удалять, не перезаписывать новой игрой, не менять `rulesVersion=0`**.
- Добавлен экран `CampaignsPage` «Мои прохождения» с выбором и удалением по подтверждению; главный экран показывает последнюю активную игру. Кнопка «Новая история» и «Начать заново» создают новые кампании. Книга TXT/FB2 и её отдельные состояния не затронуты.
- Тесты: `campaign_store_test.dart`, `campaigns_page_test.dart`, актуализированный `game_panels_test.dart`; нужны реальный GitHub Actions Flutter analyze/test + APK, а Windows EXE остаётся SKIP до отдельного workflow.
- Важно: это всё ещё временное SharedPreferences-хранилище **не** полноценный `.bwsave`, SQLite, BookWorld, не автоматический компилятор и не облачный ИИ. Следующий этап — M1.6.6 portable `.bwsave` и дальнейший M1 acceptance из ROADMAP. Не смешивать чтение книг с игрой.

## Проверка и исправление QA M1.6.5
Первый CI `41326180614` по `2df691ac` выявил Flutter analyze FAIL из-за одного лишнего import в `campaigns_page_test.dart`; Android APK пропущен. Следующая правка убирает импорт, добавляет защиту повреждённого сохранения от перезаписи и отрицательный widget test. Перед продолжением **проверить зелёный CI актуального HEAD** и записать точный SHA/статусы. Не выдавать неработавший APK за успешный.

## Устранение гонки удаление/автосохранение
После M1.6.5 проверь `campaign_store_test.dart`: сценарий `deletion wins over in-flight and late autosaves`. Хранилище сериализует in-process write/delete и запрещает повторную запись под удалённым ID. Это не полноценная SQLite-транзакция.

## M1.6.6 — пилотные переносимые `.bwsave` (2026-11-01)
- Прочитать `docs/BWSAVE_PILOT_FORMAT_RU.md` и проверить точный HEAD `main`, GitHub Actions и новейший Android prerelease перед любыми заявлениями о PASS.
- `apps/story_reader/lib/pilot_save_codec.dart`: JSON v1 с SHA-256 от канонически отсортированного payload, встроенный `book_id=ai_story_m1_intro`, `bookworld_hash=null`, реальный `GameProgress`, журнал, snapshot и rulesVersion. Размер максимум 4 МиБ; импорту предшествует настоящая `StoryEngine.restore` без записи в хранилище.
- `CampaignsPage`: системные FilePicker export/import `.bwsave`, предпросмотр и подтверждение перед созданием **нового** слота через `CampaignStore.importNew`; нельзя перезаписывать исходную или legacy-кампанию. Доступность действий проверяют новые виджет-тесты.
- `apps/story_reader/test/pilot_save_codec_test.dart`: roundtrip, шах хеша, неверная версия/книга/UTF-8, невозможность испортить старые кампании, legacy rules. Добавлена зависимость `crypto ^3.0.6`; README, STATUS, ARCHITECTURE, ROADMAP обновлены.
- **Не выдавать за сделанное:** полноценный engine-neutral `.bwsave`, импорт произвольного BookWorld, структурированный event log, SQLite/Drift, реальные Windows EXE и физический Android ↔ Windows transfer, ИИ и автоматический Book Compiler. Продолжение: M1.7 `story_core`/BookWorld/migration и автоматическая + ручная QA.
- Сравнить с ТЗ; формат для встроенного пилота помечен как временный (оригинальный opaque `story_engine` snapshot).

## M1.6.7 — Windows CI build
В `.github/workflows/android-ci.yml` добавлен `windows-exe` (Windows runner, portable release directory + `SHA256SUMS.txt`, Actions artifact `AI-Story-RPG-Windows-portable`). Проверить в новом workflow реальный PASS/FAIL, не путать `flutter analyze` на Linux с Windows сборкой. Запуск Windows и перенос сохранения на реальные устройства ещё не проверены. Дистрибутив включает DLL+data; одиночный `.exe` не является работающей поставкой.

## Важное исправление M1.6.5/M1.6.6
По логам `41327708276` новые 6 тестов `pilot_save_codec_test.dart` PASS, но `game_panels_test.dart` имел две регрессии: отсутствие «Продолжить» и незагруженный список новых кампаний при быстром выходе. `CampaignStore.all()` и `read()` теперь ожидают `_writeFence` (очередь автосохранений). Проверить реальный CI по актуальному HEAD, затем именно widget сценарии возврата из игры; не выдавать за исправленное только по просмотру кода.

## Корневая поправка очереди
`StoryReaderPage._queueSave()` теперь вызывает `CampaignStore.write()` синхронно при подтверждении выбора, вместо отложенного вызова через `_pendingWrite.then`. Иначе `HomePage` мог прочитать `CampaignStore.all()` до регистрации записи в `_writeFence`. Дополнительный widget-тест проверяет немедленный выход без ручного Save. Проверить Flutter CI по актуальному HEAD.

## Блокирующий hotfix очереди сохранений после screenshot CI (2026-11-02)
Лог `41328244444` подтвердил FAIL/Timeout в `game_panels_test.dart` и `campaigns_page_test.dart` (10 мин ожидания), Android и Windows сборки SKIP. Корень — общая на isolate статическая `CampaignStore._writeFence` переживала `SharedPreferences.setMockInitialValues` в widget-тестах; устаревшее Future из FakeAsync блокировало чтение в новом тесте. Исправлено: `Expando<_CampaignQueue>` keyed by `SharedPreferences` object (per cache lifecycle) плюс тесты смены кэша. Проверить **актуальный HEAD и РЕАЛЬНЫЙ зелёный Flutter CI** перед продолжением M1.7; в частности «Продолжить», старый слот, несколько кампаний, экран .bwsave, удаление. Версии и source data не трогать. При CI ошибках исправлять по логам, без заглушек и без запросов на ручную установку.

## Critical follow-up: test fence ordering, CI run 41330543268
Run `41330543268`: Python PASS, Dart PASS, Flutter analyze PASS, основные widget-тесты UI и `.bwsave` PASS, но один `campaign_store_test` FAIL (read-before-write-registration), всего 62/63 PASS. Финальный hotfix использует `SharedPreferencesStorePlatform.instance` как синхронный ключ очереди, `Expando<_CampaignQueue>` и раннюю регистрацию `write/delete`, плюс `shared_preferences_platform_interface: ^2.4.2`. Не объявлять этап зелёным до подтверждения нового HEAD в Actions. `START_NEW_CHAT_RU.md` обязательно обновлять после будущих CI исправлений.

## 2026-11-02 — СТАБИЛИЗАЦИЯ UI/UX M1.6.6 (после запроса «полный аудит, исправь, потом продолжим»)
1. В первую очередь прочитать `docs/UI_UX_AUDIT_2026-11-02_RU.md` и фактический SHA HEAD `main`. Это **кодовый аудит всех экранов**, а не визуальные замеры на реальном телефоне/Windows.
2. Исправлены: ложная кнопка новой игры до проверки сохранений, пустой импорт книг/кампаний, стабильные названия сцен и компактное menu на 320dp, переход в прохождения из настроек и версия M1.6, scrollable dialogs, шесть разных финалов по стабильному ending choice ID, custom reading palette RPG, экран ошибок, ограничение большого журнала и дублирование первого FB2-heading. Общий ReaderChromeButton получил accessibility hint/secondary mouse click, прежний контракт normal/reading/fullscreen сохранён.
3. Новый `GameProgress.endingId` **необязательный** в сериализации (старые JSON без поля продолжают работать); bookId, campaign IDs, engine snapshot, формат пилотного `.bwsave` не менялись. `_choose` игнорирует stale/double taps.
4. Тест: `apps/story_reader/test/ui_ux_audit_test.dart`, существующий `campaigns_page_test.dart` обновлён под заголовок сцены. Обязательно проверить `flutter analyze/test`, Dart/Python и **реальные** Windows+Android workflow statuses, SHA последнего коммита. До успешной проверки не утверждать, что UI hotfix прошёл QA.
5. В `docs/UI_UX_AUDIT_2026-11-02_RU.md` перечислены неизменённые ограничения: pixel offset reader, SQLite/Drift, TalkBack, Windows keyboard/real devices, EPUB, производительность FB2, и отсутствие полноценной BookWorld AI RPG.
6. Пользователь хочет сначала закончить UI/UX и **только потом** продолжать M1.7. Не начинай M1.7 до принятия UI checkpoint.

## После UI/UX hotfix — исправление долгой загрузки библиотеки
По первому UX запуску `41332089654` (SHA `3560ba54`) Python/Dart/Flutter analyze PASS, widget FAIL из-за `pumpAndSettle` в библиотеке без platform storage и заблокированной Home навигации, Android+Windows SKIP. Следующая правка: `HomePage._open` снимает lock сразу после возврата, `_refresh` не блокирует переход к RPG, `BookStorage.all()` ограничен 8 секундами с явной ошибкой и кнопкой «Повторить загрузку». Уточнение в `docs/UI_UX_AUDIT_2026-11-02_RU.md`. Требуется повторный полный CI последнего SHA до передачи в следующий чат.

## UI/UX audit — QA hotfix lifecycle (после ef004a4)
Run `41332360623` (SHA `ef004a4`): Python/Dart/analyze PASS, Flutter FAIL из-за незакрытых 8s `Future.timeout` timers в `HomePage._refresh`; Android/Windows SKIP. Убираем фоновый timeout на главной, в `LibraryPage` ставим отменяемые в `dispose` deadline timers для `Future.any`, защищаем позднее обновление по поколению загрузки. При возобновлении — проверить последние HEAD, весь CI, обе сборки и не сообщать PASS без логов. Исходные RPG/book saves не мигрировать.

## QA маленькая правка после CI 41332615600
Предыдущий запуск Flutter analyze прерван одним `const_with_non_const` в `home_page.dart`; убрано `const` при создании `TimeoutException`. Проверь новый run по HEAD до приёмки UX, продолжать только после PASS widget + Android + Windows.

## ФИНАЛЬНЫЙ HANDOFF UX-АУДИТА — 2026-11-02
**Проверенный исходный SHA:** `8ca82afd0a71079cde9e08bdc28f17819ce6b436`. **CI:** [`41332717865`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41332717865) `completed/success`: Python PASS, Dart PASS, Flutter analyze PASS, **71/71 widget PASS**, Windows portable PASS, Android debug APK + prerelease [`android-build-138`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-138) PASS.

- **Последние исправления после отчёта:** для `HomePage` убран ненужный background Future.timeout при чтении книг; `LibraryPage` использует управляемый `Timer` с отменой в `dispose`, `Future.any` и 8-секундным дружественным fail/retry; исправлен `const_with_non_const`. Платформенная библиотека не должна блокировать RPG и кнопку «Продолжить».
- Полный реестр UX и открытых вопросов — `docs/UI_UX_AUDIT_2026-11-02_RU.md`; все изменения, включая шесть финалов, 320 dp/200% интерфейс, сохранения и темы, прошли CI. Не переписывать уже принятый дизайн и не откатывать недавние улучшения.
- **SKIP:** ручной визуальный осмотр/запуск на реальных Windows и Android, TalkBack/Narrator, системная high contrast, перенос `.bwsave` между устройствами.
- Открытые будущие задачи: относительный/абзацный якорь позиции чтения вместо scroll pixels; SQLite/Drift ACID; настоящий BookWorld/story_core, EPUB/AI/Compiler по ROADMAP. Не выдавать их за реализованные.
- **Просьба пользователя:** на этом этапе **остановиться после UI/UX-аудита и исправлений**. M1.7 только после следующего явного «продолжай».
- Этот handoff — только документационный commit поверх проверенного исходного SHA; если в HEAD дополнительный коммит [skip ci], он не меняет Flutter/Dart-код.

## UX: убрать дубли библиотеки и импорта после отзыва реального пользователя (2026-11-02)
Пользователь проверил успешный Android APK #138, сообщил что приложение работает, но обнаружил на Home два представления одной библиотеки и несколько одинаковых способов добавить книгу. Исправление: **на Home одна карточка «Библиотека»**, без прежней полки первых 8 книг, «Моя библиотека» и «Все книги». **В LibraryPage одна видимая кнопка «Добавить книгу»**, без дублирования в AppBar и пустых/error блоках; демо RPG, поиск, сортировка, удаление, импорт TXT/FB2, все сохранения и BookReaderPage остаются. Дополнены widget-тесты `home_test.dart` и `ui_ux_audit_test.dart` на отсутствие дублирования.
Последний проверенный перед этой правкой код: `8ca82afd`, Actions `41332717865` (71/71 PASS, Android/Windows PASS). Для текущего UX-исправления проверить свой HEAD и новую CI, не выдавать #138 за проверку нового интерфейса; обновить результаты.

## M1.7.1 — начало модели BookWorld / story_core после подтверждения пользователем «всё работает, продолжаем» (2026-11-02)
1. База перед новыми изменениями — `17d99e1a339e401d795f7db19e14613cad786753`; CI `41334189482` SUCCESS (Flutter 71/71, Android APK, Windows portable, M0). Не откатывать UX: **на Home один вход в библиотеку, внутри одна кнопка импорта**.
2. Добавлены новый pure Dart `packages/story_core` и `shared_schemas/v1/story_blueprint.schema.json` плюс `shared_schemas/fixtures/manor_world_m17.json` — original-demo blueprint с 8 сценами, 15 уникальными choice IDs, только PROTAGONIST/CANON/CLASSIC. JSON blueprint **НЕ** полноценный .bworld; source_fingerprint null честно объявлен.
3. Реальное ядро `StoryWorld` делает атомарную in-memory проверку условий+эффектов, сохраняет `WorldState`, actor-specific `knowledge`, snapshot hashes и hash-chained `WorldEvent`, требует idempotent action IDs, предоставляет `replay` с проверкой всех ходов. Тест на **35 действий** + негативные опции/подмена, schema test.
4. `.github/workflows/android-ci.yml` дополнен blocking job `story-core` с Dart analyze/test и Python jsonschema 2020-12; Android/Windows теперь зависят от него. **Проверить свежий HEAD + фактические run PASS/FAIL, затем исправить возникающие ошибки**.
5. По ТЗ/ADR-001 основной runtime остаётся `story_engine`. Новый core **ещё не интегрирован в UI**, нельзя параллельно менять GameProgress пользователя без StoryRuntimeAdapter и миграции. Старые slots/legacy, book storage, pilot .bwsave и режимы UI не изменялись.
6. Подробный отчёт `docs/M17_STORY_CORE_RU.md`. Следующий M1.7.2 — bridge StoryRuntimeAdapter с проверяемой атомарной транзакцией world+scenario, затем BookWorld ZIP, SQLite/Drift, полноценный .bwsave, реальный cross-platform 20+ UI ходов.

## M1.7.1 hardening: blueprint binding и incomplete log
`StoryBlueprint.blueprintHash` вводит hash точной редакции оригинального fixture; `WorldEvent.blueprint_sha256` связывает цепочку событий с этой редакцией. `StoryWorld.replay(...,expectedSequence,expectedStateHash)` проверяет ожидаемый head (без него обрезанный хвост не отличим от честной ранней точки). Все объявления modes строго ограничены `PROTAGONIST/CANON/CLASSIC`. Проверь по новейшему HEAD отдельный `story-core` CI и 71+ Flutter/widget regression, Android/Windows job status. Никакой миграции M1.6 сейвов в этом подэтапе нет.

## ПРОДОЛЖЕНИЕ M1.7.2 — связка story_engine с story_core (2026-11-02)
- Базовый перед изменениями `2d779839c26f91146bdad63f1b3afaf7b87b97a2`, успешный Actions `41336338177` (Python/Dart, 9 ядро + 6 schema, 71 Flutter, Windows и Android PASS).
- Новый `packages/story_runtime_adapter`, интерфейс `StoryRuntimeAdapter` и работающий `StoryEngineCoordinator`: компилирует оригинальный blueprint M1.7.1 в `StoryProject` для выбранного `story_engine:0.1.0-alpha.1`, сравнивает навигационные действия с `StoryWorld`, проверяет два кандидата (копию world + восстановленный из snapshot engine) и обновляет активную пару только после согласованного перехода. No network/LLM/Python/Flutter.
- Новый `StoryWorld.fork()`, `choiceLockReason`. `checkpoint()` (формат `ai_story_bridge_checkpoint_v1`, пока только в RAM) и `restore()`: строгий version/hash/revision/head, core replay, затем story_engine replay, отказ на повреждении, несовпадении версии или усечённом логе. Тестовые 35 ходов + 23-turn resume, atomic reject, double action, independent campaigns.
- CI: в `.github/workflows/android-ci.yml` к job `story-core` добавлены `dart pub get/analyze/test` пакета `packages/story_runtime_adapter`; обе платформенные сборки уже зависят от job. **ПЕРВЫМ ДЕЛОМ ПРОВЕРИТЬ РЕАЛЬНЫЙ ПОСЛЕДНИЙ CI** и исправить FAIL. В docs `M17_STORY_RUNTIME_ADAPTER_RU.md` полный реестр.
- Старый `StoryReaderPage` использует свой `GameProgress` и `CampaignStore` с `ai_story_m1_intro`, blueprint использует другой book_id. Ни один user save/legacy не перезаписан. **Не объявлять UI/SQLite/полный .bworld/.bwsave реализованными**. Переход к GUI только после полноценного моста сохранений и миграционного QA.
- UX: главная по-прежнему одна библиотека/одна кнопка «Добавить книгу»; повторные UI редизайны не нужны. Следующее техническое M1.7.3 — безопасный ZIP/SQLite BookWorld, далее M1.7.4 durable migration/UI 20+ actions.

## M1.7.2 — ЗАКРЫТ АВТОМАТИЧЕСКОЙ ПРИЁМКОЙ (2026-11-02)
- Основной проверенный SHA: `8fef11521c9f702414a6364c04b2350d30713b0d`. [GitHub Actions #142](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41337108811) `completed/success`: Python PASS; Dart M0/engine/stress PASS; story_core **10/10** PASS; StoryRuntimeAdapter **9/9** PASS; JSON Schema **6/6** PASS; Flutter analyze PASS; **71/71 widget** PASS; Android APK PASS; Windows portable PASS.
- Android prerelease: [`android-build-142`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-142), APK `AI-Story-RPG-M1-debug.apk`; Windows полный комплект в Actions artifact `AI-Story-RPG-Windows-portable`.
- Изменения M1.7.2 в `packages/story_runtime_adapter` и `packages/story_core`; GUI НЕ переключён на новый координатор, user saves/legacy/M1.6 `.bwsave` не мигрированы. В проекте по-прежнему ОДНА библиотека и ОДНА кнопка импорта. Ручное устройство/инструментальная доступность SKIP. Не выдавать новый модуль за импорт книги в игру.
- Документация `docs/M17_STORY_RUNTIME_ADAPTER_RU.md`. Следующий M1.7.3 — .bworld ZIP/SQLite с безопасным импортом, manifests/version/rights/hash/limits; M1.7.4 — SQLite/Drift, гарантия атомарного durable сохранения, migration старых save, испытания UI. Не делать массовых UI-переделок без необходимости.
- Этот документальный commit с `[skip ci]` поверх проверенного исходного SHA меняет только Markdown; не сравнивать его SHA с протестированным кодом без этой оговорки.

## M1.7.3 — ВОССТАНОВЛЕНИЕ НОВОГО ФОРМАТА BOOKWORLD (2026-11-02)
- Последний baseline M1.7.2: `8fef11521c9f702414a6364c04b2350d30713b0d`, CI `41337108811` SUCCESS (включая Android/Windows/71 Flutter). Документальный коммит `c89e230`.
- Новые исходники `7c3923492118a7aef9c9ecda3e0c319a2961499f`: Python `tools/bookworld/bookworld.py` компилирует original demo blueprint в настоящий `.bworld`; native Dart `packages/bookworld_format` проверяет ZIP/SQLite/schema/manifest/digests и отдаёт `StoryBlueprint` для существующего `StoryEngineCoordinator`. Нет вызовов Python во время игры.
- Дополнены `shared_schemas/v1/bookworld_manifest.schema.json`, `shared_schemas/tests/test_bookworld_manifest_schema.py`, Python security tests `tools/bookworld/tests/test_bookworld.py`, Dart tests `packages/bookworld_format/test/bookworld_import_test.dart`. CI в job `story-core` собирает `artifacts/bookworld/manor_m17_original_demo.bworld` + SHA256SUMS и при успехе загружает artifact `AI-Story-RPG-BookWorld-demo`, затем проверяет Python, Dart native и продолжает остальные Flutter/Android/Windows.
- Очень важная граница: НОВЫЙ `.bworld` ЕЩЁ НЕ ПОЯВЛЯЕТСЯ В UI; нет portable `.bwsave`, Drift SQLite кампаний, миграции старых пользовательских прохождений, импорт чужой книги, LLM/AI, поддержка assets/source. Никаких изменений старой единой библиотеки TXT/FB2, saved slots или интерфейса.
- Прочитать подробный документ `docs/M17_BOOKWORLD_FORMAT_RU.md`, сравнить с `docs/TZ_RU.md` §7.1/7.3. При следующем чате **сначала** получить свежий HEAD и CI `7c3923`, исправить FAIL, записать проверенный SHA/PASS/SKIP в `docs/STATUS_RU.md`. **Не** объявлять Android import готовым на основании одного Linux Dart пакета.
- Следующий M1.7.4: приватный BookworldStore, durable SQLite/Drift campaign+replay, legacy migration/backup, file picker, UI запуск игры, 20+ ходов и реальное cross-platform QA. Не возвращать вторую библиотеку и многократные кнопки импорта.

## M1.7.3 — ЗАКРЫТА АВТОМАТИЧЕСКОЙ ПРИЁМКОЙ (2026-11-02)
- **Проверенные исходники:** `7c3923492118a7aef9c9ecda3e0c319a2961499f`. [GitHub Actions #143](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41338634157) — **completed / success**, все шесть jobs PASS: Python ZIP/SQLite 12/12, JSON Schema 9/9, story_core 10/10, StoryRuntimeAdapter 9/9, новый Dart BookworldImport 5/5, Flutter 71/71, Windows portable и Android APK.
- Demo archive `AI-Story-RPG-BookWorld-demo` находится в artifacts run #143; `manor_m17_original_demo.bworld` имеет SHA256 `e150d4c4b004106d162ed323843cc78fdacf2eaa0316d3651ab447a7d45fa9a4`, внутри 8 сцен/15 choices, настоящий SQLite и canon JSON. Android prerelease [`android-build-143`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-143), Windows полный комплект в run artifacts.
- Обязательно сначала читать `docs/M17_BOOKWORLD_FORMAT_RU.md`. Принято **только** native Dart import+Python compiler, не переносить рабочий M1.6 Flutter UI/пользовательские кампании без реальной миграции. `rights_status` — заявленные метаданные, без подписи не подтверждают авторство; ZIP v1 поддерживает **ровно три** `ZIP_STORED` члена, не принимает assets/source/сжатие.
- **SKIP:** Flutter UI импорт `.bworld` на реальном Android/Windows, ACID SQLite/Drift кампании, восстановление после падения/backup и M1.6 save migration, AI/LLM, публичные книги. Следующий M1.7.4 — durable BookworldStore/campaigns, проверяемый file-picker import, migration и 20+ UI ходов.
- Этот handoff добавлен отдельным documentation-only commit `[skip ci]` поверх проверенных исходников; SHA docs HEAD может отличаться от проверенного SHA кода.

## M1.7.4a — новая SQLite persistence для настоящего BookWorld (2026-11-02)
- Последний подтверждённый кодовый baseline M1.7.3: `7c3923492118a7aef9c9ecda3e0c319a2961499f`, Actions `41338634157` #143 SUCCESS; document-only `562a933e`. **ПРОВЕРЬ HEAD и свежий CI** для нового M1.7.4a до заявления PASS.
- `packages/campaign_manager` — **реальная SQLite база** `bookworld_campaigns_v1.sqlite` для уже проверенных .bworld, отдельные `bookworlds`, `campaigns`, `events`, meta, WAL+FULL, foreign keys, revision и hash. Atomic BEGIN IMMEDIATE → verify/choose → INSERT event + UPDATE head → COMMIT, любой сбой ROLLBACK; при load повторный replay настоящих story_core+story_engine.
- Новый portable `ai_story_bwsave_v2` (original-demo/CANON/CLASSIC) не совместим с pilot v1, но **не перезаписывает** старые слоты, импорт форкает новое ID после проверки world+checksum+checkpoint. Требуется точный world_sha256 уже в библиотеке. 10 тестов в `packages/campaign_manager/test/campaign_manager_test.dart`, включая **35 turns, reopen after 23**, invalid choice, replay corruption, power-failure simulation at SQLite INSERT via trigger, schema mismatch, multiple campaigns.
- `.github/workflows/android-ci.yml` story-core job получил новый blocking `dart pub get`, `dart analyze`, `dart test` для `campaign_manager`. Полный документ `docs/M17_CAMPAIGN_SQLITE_RU.md`. По итогам CI добавить точный SHA, run id и PASS/FAIL/SKIP.
- **КРИТИЧЕСКИ НЕ СЛОМАТЬ:** M1.6 `CampaignStore` / `GameProgress` / `SaveStore` / `pilot_save_codec`, старый `.bwsave`, книги TXT/FB2, unified Home и одна import CTA. Новый pure Dart Store ещё не подключён к Flutter UI, path_provider/file_picker, Android/Windows физическим тестам; не говорить, что эти функции готовы.
- Продолжить M1.7.4b: безопасный путь `path_provider` + отдельный isolate, UI для настоящего .bworld без второй библиотеки, migration backup/legacy policy, 20+ реальных ходов Android+Windows, device a11y/QA.

### Корректировка fork-semantics до приёмки M1.7.4a
Флаг `parent_campaign_id` не должен означать пустую кампанию с чужим ID: `createCampaign(worldSha, parentCampaignId: id)` теперь проверяет полный replay родителя и переносит его event log + state/head в **одной транзакции**, после чего две кампании независимы. В `campaign_manager_test.dart` добавлен 10-й тест. При возобновлении проверить **последний HEAD**, а не только CI первого коммита `19e4345`.

## M1.7.4a — ЗАКРЫТ АВТОМАТИЧЕСКИМ QA (2026-11-02)
- **Последний проверенный кодовый SHA:** `cc69778586b45c3e82c4f1dc415ce2dc545b043e`. **Actions #145** [`41340309393`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41340309393): `completed/success`, **6/6 jobs PASS**. Python/Dart M0 PASS, story_core 10/10, story_runtime_adapter 9/9, JSON Schema 9/9, Python BookWorld security 12/12, `bookworld_format` 5/5, **новый campaign_manager 10/10**, Flutter widget **71/71** PASS, Android APK и Windows portable PASS. Старый run `41339885596` cancelled по concurrency после исправления fork, не использовать его как окончательный результат.
- Публикация [Android debug `android-build-145`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-145), полный Windows bundle, оба в artifacts [Actions #145](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41340309393). `AI-Story-RPG-BookWorld-demo` тоже опубликован.
- Что работает В КОДЕ: `packages/campaign_manager/lib/campaign_manager.dart` — новая отдельная SQLite v1 store: verified .bworld, WAL+FULL, event/head в одной транзакции, полный replay на load, 35 turns и reopen after 23, idempotency, fork с перенесённым head/journal, изоляция нескольких кампаний, portable `ai_story_bwsave_v2` с проверкой точного world hash и импортом в новую кампанию. Чистый Dart API, не Flutter GUI.
- ВАЖНО: **не трогать старые M1.6 user saves** `SharedPreferences`, `CampaignStore`, `GameProgress`, `SaveStore`, пилотный `.bwsave v1`; в новых коммитах исходники этих файлов не менялись. `campaign_manager` ещё НЕ входит в dependencies приложения и НЕ запускается на Android/Windows в UI; успешные сборки этих приложений не равны реальному тесту нового Store на устройствах.
- Полный отчёт `docs/M17_CAMPAIGN_SQLITE_RU.md`. Следующее M1.7.4b: интеграция private path (`path_provider`) + isolate + picker, показ .bworld в **существующей единой библиотеке**, runtime play 20+ ходов, миграционная политика/backup, .bwsave v2 import/export UI, Android↔Windows E2E и визуальный аудит. **Не добавляй второй «Библиотека» или множественные CTA «Добавить книгу».**
- Если HEAD теперь docs-only `[skip ci]`, он не меняет проверенный кодовый SHA `cc69778`; при продолжении брать фактический свежий HEAD.

## M1.7.4b1 — интеграция подготовленных BookWorld в Flutter (2026-11-02)
- Последний подтверждённый по CI SHA: `cc69778586b45c3e82c4f1dc415ce2dc545b043e`, [Actions #145](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41340309393) SUCCESS, Android/Windows и 71 Flutter, 10 SQLite PASS. Документальный HEAD `15e32e5`. **Для этого нового UI этапа СНАЧАЛА проверь свежий SHA и actual CI, исправь FAIL до продолжения.**
- В `apps/story_reader/lib/world_library_gateway.dart` сделан Dart bridge, вся работа `BookworldCampaignStore` идёт в `Isolate.run`, DB в private AppSupport/ai_story_bookworld, не рядом с TXT/FB2. Есть подтверждённый WorldGameView, WordChoice lockReason, import .bwsave v2 с точной проверкой world hash.
- `world_campaigns_page.dart`: новый/сохранённый/ответвлённый поход по миру, экспорт/импорт сохранения. `world_play_page.dart`: реальные сцены/варианты/условия, GameQuickBar «Герой», «Предметы», «Журнал», SQLite commit перед изменением UI. Старое `home_page.dart` сохраняет ОДНУ кнопку `library-import`, расширены расширения файла `['txt','fb2','bworld']`, проверенный .bworld показывается карточкой RPG в ТОМ ЖЕ LibraryPage. Обычная читалка не превращает книгу в RPG без компиляции.
- Flutter CI перед `flutter test` компилирует настоящий demo .bworld; `apps/story_reader/test/world_integration_test.dart` содержит **35 UI ходов** через native SQLite + reopen после 23, отдельные проверки failed write, legacy TXT/FB2 CTA, locked choice, панели и 320dp/200%. Проверь реальный CI, это новый тестовый контур.
- **Не ломать:** старые M1.6 `CampaignStore`/`SaveStore`/`GameProgress`, `.bwsave v1`, импорт TXT/FB2, главную с одной библиотекой, настройки и сохранения. `.bworld` v1 только original-demo/CLASSIC, v2-сейвы требуют точный BookWorld SHA.
- Подробное объяснение `docs/M174B_FLUTTER_BOOKWORLD_RU.md`. После PASS продолжить M1.7.4b2: объединить старые/новые кампании в «Мои прохождения» (не создавать второй library), безопасное удаление/backup, унифицировать reader chrome, Android/Windows device E2E и реальная миграционная политика без потери legacy.

### M1.7.4b2 — объединённые сохранения, не миграция (2026-11-02)
В `apps/story_reader/lib/campaigns_page.dart` добавлены записи BookWorld SQLite рядом с неизменёнными пилотными слотами; Home теперь учитывает обе системы и продолжает последний BookWorld, когда нет пилотного слота. Кнопок «Библиотека» не прибавилось. `world_integration_test.dart` вырос до 6 widget tests, включая общий список и Home Continue. **Взять новый HEAD и фактический GitHub Actions** перед PASS. Миграция legacy `rulesVersion=0/1`, безопасное удаление миров и физическое cross-platform тестирование ещё SKIP.

### Особенность Flutter CI M1.7.4b — итоговая архитектура
В рабочей сборке native `DeviceWorldLibraryGateway(background:true)` использует `Isolate.run`; старые тестовые хосты `AIStoryApp()` без явного gateway используют только прежние M1.6 данные. Новые `testWidgets` используют **настоящий sqlite3, движок и BookWorld** через `background:false` inline (без fakeAsync deadlock), а отдельный обычный Dart `test()` проверяет настоящий `Isolate.run` в асинхронной зоне. Тест с 35 UI ходами и возвратом после 23-го хода сохранён. Этот итоговый контракт заменяет ранний эксперимент с `WidgetTester.runAsync` из предыдущих записей.

### M1.7.4b CI correction, проверять
На `cca53c4` Flutter tests FAIL (21) из-за преждевременного запуска native SQLite в legacy widget host, ожидания isolate в fakeAsync и переполнения GameQuickBar на 320dp. Исправлено explicit production gateway injection через `AIStoryApp(worldGateway: DeviceWorldLibraryGateway())` в `main()`; старый `AIStoryApp()` не запускает неустановленный native сервис. Widget tests используют реальную SQLite через `DeviceWorldLibraryGateway(background:false)`, плюс отдельный normal `test` проверяет default `background:true` isolate. Патч GameQuickBar (Expanded + maxLines2). Старые user saves не менялись. **СНАЧАЛА проверить свежий HEAD/CI, не считать FAIL на cca53c4 положительным результатом.**

### M1.7.4b — кодовый UI QA зафиксирован (2026-11-02)
**Актуальный исходный SHA `f4bf62c156abb9cc0a1b4a4a4851cdb33312994a`**, [Actions #148 `41372851607`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41372851607). Python/Dart story-core PASS, Flutter **78/78 PASS** (71 старых, 6 новых UI widget с 35 реальными SQLite ходами/reopen после 23, 1 настоящий isolate), flutter/dart analyze PASS. Android debug APK PASS и Windows portable PASS — GitHub Actions #148 `41372851607` **completed/success, все 6/6 jobs PASS**. Android [`android-build-148`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-148), Windows и demo `.bworld` — artifacts этого run. Предыдущая cca53c4: Flutter FAIL, её не использовать. Не переписывать M1.6 SharedPreferences, пилотные .bwsave v1 и Library TXT/FB2; новые .bwsave v2 и World SQLite в отдельной БД. Консолидированные «Мои прохождения» и Home Continue реализованы. Следующие подэтапы: safe backup/delete, полноэкранный reader chrome в новом RPG и физический QA Android/Windows, затем Book Compiler (без выдачи TXT/FB2 за готовый сюжет).

## M1.7.4b — ЗАКРЫТ АВТОМАТИЧЕСКОЙ ПРИЁМКОЙ (2026-11-02)
- **Проверенный кодовый SHA `f4bf62c156abb9cc0a1b4a4a4851cdb33312994a`.** [GitHub Actions #148 `41372851607`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41372851607) **completed/success, 6/6 jobs PASS**. core 10, adapter 9, BookWorld schema 9, ZIP/SQLite Python 12, Dart format 5, campaign_manager 10; **Flutter 78/78 PASS**, Dart/Python M0 PASS, Android APK PASS, Windows portable PASS.
- Android [`android-build-148`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-148), Windows portable, BookWorld demo .bworld в artifacts run #148.
- Теперь Flutter app в production явно подключает `DeviceWorldLibraryGateway` в `main()`, native SQLite в `Isolate.run`, его новый BookWorld можно импортировать через единую библиотеку TXT/FB2/.bworld, играть 35+ подтверждённых ходов с реальным автосохранением, продолжать из Home и общего `Мои прохождения`, пользоваться Hero/Items/Journal, делать ответвления и импорт/экспорт v2. Старые M1.6 data/store/save не изменены.
- **SKIP/не реализовано:** физический Android/Windows тест SQLite на устройстве, реальный межплатформенный перенос .bwsave v2, power-loss, полноценный reader chrome normal/reading/fullscreen в новом RPG, безопасный BookWorld delete/backup, конверсия legacy M1.6, книга TXT/FB2→сюжет, AI/HYBRID.
- Следующий M1.7.4c: backup/restore и правила удаления/восстановления, reader chrome и UX-полировка; затем физическая Android/Windows приёмка. Перед дальнейшей работой всегда читать `docs/M174B_FLUTTER_BOOKWORLD_RU.md` и фактический HEAD. Этот docs-only commit `[skip ci]` не меняет проверенный SHA исходников.

## Handoff после M1.7.4c1 (2026-11-02)
Проверить ветку `feat/m174c1-safe-backup-delete`, её CI и принять через PR только после успешных тестов. В `BookworldCampaignStore` добавлены exportBookworld/deleteBookworld/deleteCampaign; во Flutter gateway и едином UX — backup-gated действия, два native и два Flutter теста. Исходные M1.6 saves, TXT/FB2 и .bwsave v1 не менялись. Следом M1.7.4c2: нормальный/читательский/полноэкранный chrome на игровых сценах, затем устройство Android/Windows и recovery. Нельзя выдавать CI #148 за проверку нового коммита.
