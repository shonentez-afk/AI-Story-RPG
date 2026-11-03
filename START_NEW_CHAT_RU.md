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


## M1.7.4c1 — окончательная автоматическая приёмка (2026-11-02)
- PR [#1](https://github.com/shonentez-afk/AI-Story-RPG/pull/1) merged в `main` как `a37eb21afe82e8e93dfc43fcb2caabe580153c6b` (squash), проверенный PR HEAD `13239eb843d99787ce50b5d97e71695be54dca85`.
- GitHub Actions [#150, run 41374846035](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41374846035) — **completed/success, 6/6 PASS**: Python, Dart, story_core/BookWorld, Flutter analyze и **80/80 tests**, Windows portable release bundle, Android debug APK. M0 SDK checks также PASS (run `41374846010`).
- Первый PR CI `41374617867` завершился Flutter **79 PASS / 1 FAIL** из-за `pumpAndSettle timed out` в `world_integration_test.dart` при подтверждении удаления: фоновый indeterminate progress indicator продолжает анимацию. Тест исправлен ожиданием конкретного кадра перехода диалога (300 ms), **не отключением проверки SQLite**. Повторный Flutter 80/80 PASS.
- Функции: обязательный системный backup перед удалением `.bwsave v2` или пустого `.bworld`, RESTRICT против удаления мира с кампаниями, проверка expectedRevision в SQLite, полный replay, сохранение дочерних fork. Старые M1.6 SharedPreferences/книги TXT/FB2 не затронуты.
- **SKIP:** реальный запуск на физических Android/Windows устройствах, восстановление из системного FilePicker после копирования файла, внезапная потеря питания, старые M1.6 migration, Book Compiler/AI. Результаты CI относятся к PR SHA; если после squash запущен отдельный main CI — его статус проверять по факту, не додумывать.
- Дальше **M1.7.4c2**: унификация ReaderChromeMode normal/reading/fullscreen в новом BookWorld UI, доступность 320dp/200%, Windows keyboard, затем Android↔Windows device E2E и backup restore QA. Не создавать вторую библиотеку и вторую CTA импорта книг.

## HANDOFF — M1.7.4c2 BookWorld ReaderChrome (2026-11-02)
- Последний принятый M1.7.4c1: `a37eb21`, PR #1 CI #150 `41374846035` (6/6 PASS, Flutter 80/80, Android/Windows). Документальный HEAD `8a9be28`; проверить также main CI #151 `41375458813` по факту.
- Новая работа: `feat/m174c2-bookworld-reader-chrome` (не начинать заново). В `world_play_page.dart` добавлены shared `ReaderChromeMode` normal/reading/fullscreen, `ReaderChromeButton`, `ReadingSettingsStore/Sheet`, F11 и Esc; в `world_integration_test.dart` три новых сценария включая SQLite и 320dp/200%. Подробно в `docs/M174C2_READER_CHROME_RU.md`.
- **ПЕРЕД ПРИЁМКОЙ проверить actual GitHub Actions для нового SHA**, Flutter analyze/widget, Dart/story_core, Android APK, Windows portable; при FAIL читать логи и исправлять до merge. Добавить точный SHA, PASS/FAIL/SKIP после результатов.
- Сохранять старые M1.6 SharedPreferences/SaveStore/GameProgress/.bwsave v1, новую SQLite v2 и независимые fork, единый Home/Library, одну CTA «Добавить книгу» для TXT/FB2/.bworld. Смена chrome/параметров чтения не должна записывать игровой ход.
- После зелёного CI перейти к физическим Android↔Windows E2E/backup+restore и policy legacy migration, затем подготовка M2 Book Compiler, но не объявлять обычные TXT/FB2 готовой RPG.


## M1.7.4c2 — автоматическая приёмка ЗАКРЫТА (2026-11-02)

- PR [#2](https://github.com/shonentez-afk/AI-Story-RPG/pull/2) merged/squash в `main`: **кодовый SHA `db7ec972a8fbbcb391a3d5cbd710154250eebe94`**; проверенный PR HEAD `b2e7f2fbf41574d511646b486d8afe14da34e5bd`.
- GitHub Actions [#155 (run `41376306932`)](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41376306932): **completed/success, 6/6 jobs PASS**. Python PASS, Dart PASS, story_core/schema/BookWorld PASS, Flutter analyze PASS, **Flutter 83/83 tests PASS**, Android debug APK PASS, Windows portable release + полный bundle PASS. Присутствуют артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable` и `AI-Story-RPG-BookWorld-demo` (проверять время хранения в Actions).
- В промежуточном CI #152 Flutter analyze FAIL: лишний `dart:typed_data` import после `flutter/services.dart`, удалён. CI #153 Flutter widget FAIL 4: после прокрутки новая сцена оставляла бейдж хода вне видимой области и при 200% кнопка была частично за пределами viewport. **Исправлено в реализации**: `WorldPlayPage` прокручивает к началу сцены после попытки выбора (успешной либо отказанной), но переключение chrome не сбрасывает позицию; тест 200% дополнительно прокручивает кнопку целиком в экран. Проверки не отключались. #154 cancelled при более новом коммите.
- Итог: общие `ReaderChromeMode` normal/reading/fullscreen, ReaderChromeButton, ReadingSettingsStore/Sheet, меню в AppBar, F11/Esc, доступные кнопки выбора/показа Hero/Items/Journal и общий офлайн palette/font/spacing. **Не изменён** `BookworldCampaignStore`, `StoryRuntimeAdapter`, журнал SQLite, TXT/FB2, M1.6 `CampaignStore/SaveStore/GameProgress` и .bwsave v1/v2.
- **SKIP:** физический Android/Windows UI и реальный F11/Esc/Tab/Enter на ПК, TalkBack/Narrator, native window fullscreen, межплатформенный импорт/экспорт на устройствах, power-failure, миграция legacy M1.6, Book Compiler/AI. CI-сборка ≠ проверка аппаратных устройств.
- **СЛЕДУЮЩИЙ ШАГ M1.7.4c3:** физическая Android↔Windows E2E-матрица (открыть .bworld, сделать 20+ ходов, резервная копия .bwsave v2, восстановление с exact world sha, перезапуск, forks, отмена удаления, keyboard/TalkBack/Narrator), затем политика безопасной миграции M1.6. Для автоматических тестов можно дополнительно построить cross-platform fixture-экспорт; не объявлять физические тесты PASS без пользователя/оборудования. После M1 acceptance — M2 Book Compiler.


## M1.7.4c3 — переносимый recovery и preflight без записей (2026-11-02)
- Ветка `feat/m174c3-portable-save-preflight`. Для `.bwsave v2` введена **читающая** `BookworldCampaignStore.previewPortable`: до подтверждения проверяет 2MiB, schema/ID, SHA-256 envelope, точный установленный `.bworld` и полный replay/checkpoint, возвращает source ID, SHA мира, revision, SHA состояния, terminal. `importPortable` повторно проверяет файл перед SQLite INSERT и создаёт **новый**, независимый слот. UI показывает проверенный прогресс до кнопки «Импортировать»; при cancel не пишет.
- Gateway `previewSave` применяет exact world SHA и `Isolate.run`. Новые тесты: preflight без записи, подделка checksum с невалидным checkpoint, 2 независимые SQLite базы с 24+fork+25 ходами, передача двух файлов UTF-8, перезапуск принимающей базы, 26-й ход только на получателе и отсутствие изменений источника; Flutter gateway + worker isolate preflight.
- Документ [M174C3_PORTABILITY_RECOVERY_RU.md](docs/M174C3_PORTABILITY_RECOVERY_RU.md) — пошаговый Android↔Windows E2E, меры перед удалением и **политика legacy M1.6**: не переводить старые rulesVersion=0/1 snapshots в новую схему без доказанной эквивалентности; старые слоты остаются доступны. Физическое тестирование устройств **SKIP**.
- **Новый CI нужно проверить по actual SHA/Actions:** Python, Dart/stories, BookWorld, Flutter analyze/tests, Android debug APK и Windows portable. Статус нового CI до результатов НЕ PASS. Исторический M1.7.4c2 — PR #2, CI #155, 83/83 Flutter, 6/6 PASS.
- После QA: физические Android/Windows перенос/отказ повреждённых файлов/Tab/Enter/Escape/TalkBack/Narrator, затем M2 Book Compiler. Не создавать вторую библиотеку или вторую CTA импорта; не трогать M1.6 SharedPreferences, `.bwsave v1`, TXT/FB2.


## M1.7.4c3 — принята автоматическая проверка (2026-11-02)
- PR [#3](https://github.com/shonentez-afk/AI-Story-RPG/pull/3) merged/squash в `main`: **кодовый SHA `48d5659c85ed6c42c05053f28ac88544827cda91`**; HEAD проверенного PR `b3ad242e149e2934cd11f793f8983ece2c6389b1`.
- GitHub Actions [#157 — run `41377701471`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41377701471): **completed/success, 6/6 PASS**. Python, Dart, core/format/SQLite-campaign-manager, Flutter analyze + **84/84 Flutter tests**, Windows portable release и Android debug APK — PASS. Артефакты: `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-Android-debug`, `AI-Story-RPG-BookWorld-demo` (срок хранения задаёт GitHub).
- Новые тесты `campaign_manager_test.dart`: read-only portable preflight с подделанным checksum/неверной ревизией; симуляция Android→Windows посредством **двух независимых SQLite каталогов и двух реальных файлов**, перенос 24+fork+25 ходов, повторное открытие, ход 26 только у получателя. Flutter: gateway preflight без записи и в рабочем `Isolate.run`; до импорта видны проверенные progress/terminal/sha. `importPortable` повторяет валидацию и создаёт новый ID.
- Старые SharedPreferences M1.6, TXT/FB2 и .bwsave v1 не менялись; автоматической миграции в BookWorld **нет** по обоснованной политике совместимости `docs/M174C3_PORTABILITY_RECOVERY_RU.md`. Одна библиотека, одна CTA импорта книг.
- **SKIP/НЕ ПРОВЕДЕНО:** файловый менеджер Android/Windows на реальном устройстве, настоящий двусторонний перенос .bworld/.bwsave v2 между платформами, запуск полученного APK/EXE на устройствах, ручная accessibility/keyboard матрица, power-loss и recovery при внезапном выключении. Зелёный CI не доказывает эти действия.
- Следующий этап: физический E2E по `docs/M174C3_PORTABILITY_RECOVERY_RU.md` для M1 acceptance (или явный deferral). Функциональная ветка **M2 Book Compiler** должна начинаться с фактического свежего `main`: конвейер TXT/FB2→исходные сегменты с provenance/coverage→проверяемый промежуточный blueprint→готовый .bworld, с честной маркировкой неполной компиляции и без обещания AI-игры до реализации. После каждого этапа обновлять этот handoff.


## UX/UI M1.7 — CODE BASELINE принят, M2 разблокирован (2026-11-02)

- Сквозной UX/UI-аудит текущего Flutter-приложения (Windows/Android) оформлен в [docs/UI_UX_FINAL_AUDIT_M174C3_RU.md](docs/UI_UX_FINAL_AUDIT_M174C3_RU.md): все 12 основных пользовательских маршрутов, 17 устранённых замечаний, проверка старой M1.6 и новой BookWorld архитектуры, доступность, навигация, сохранения и ошибки.
- PR [#4](https://github.com/shonentez-afk/AI-Story-RPG/pull/4) **merged/squash** в `main`: **кодовый SHA `88a7c42091888bb81a62c68db49b7cd26f60f5e3`**. Проверенный HEAD PR: `92acae96aa016fb8638dc7dd6c6f77afe1216977`.
- GitHub Actions [#170 — run 41380322453](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41380322453): **completed/success, все 6/6 jobs PASS**, Flutter analyze **PASS**, Flutter widget/unit **92/92 PASS**, core/SQLite/BookWorld, Dart, Python **PASS**, Android debug APK **PASS**, Windows portable release **PASS**. Артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo` присутствовали в run #170.
- В одном «Мои прохождения» доступен **один импорт .bwsave** (v1 пилот или v2 BookWorld по `format`); v2 проходит read-only preview + повторную native валидацию и добавляет только новый слот. Отсутствующий exact BookWorld объясняется без записи. Главное «Продолжить» ориентируется на фактический свежий timestamp двух сто́ров. Одна библиотека и одна CTA «Добавить книгу» (TXT/FB2/.bworld), исправлены общая сортировка/поиск/empty states, отзывчивость загрузки и ошибок, русские характеристики, reader chrome F11/Esc для книги/пилота/BookWorld, WCAG >=7:1 для четырёх основных читательских палитр.
- Старые `CampaignStore`, `SaveStore`, `GameProgress`, `.bwsave v1`, `.bwsave v2`, SQLite schema и исходные TXT/FB2 не конвертировались и не перезаписывались. **Не внедрять** вторую библиотеку, альтернативный импорт книг, новый пилотный storage, автоматическую legacy миграцию или другое несогласованное главное меню.
- **Ручные QA gates / SKIP:** настоящий Android/Windows FilePicker, запись и повторное открытие резервного файла после экспорта, двусторонний перенос по отдельным устройствам, отсутствие переполнения/артефактов на физическом телефоне и Windows, Tab/Shift+Tab/Enter/F11/Esc с настоящей клавиатурой, TalkBack/Narrator, rotation/200%, power-loss recovery. Перечень и критерии: `docs/M174C3_PORTABILITY_RECOVERY_RU.md` и полный аудит. Статус физического QA не повышать на основании CI.
- Известный старый читательский долг: сохранение позиции в длинном TXT/FB2 после смены шрифта/ориентации использует pixel offset; source-paragraph anchor остаётся отдельным улучшением при расширении читалки, не условием возврата к общему редизайну. Новый M2 Book Compiler/AI пока не реализован и должен добавлять функции в **существующий** единый импорт/Library и отдельный мастер конверсии, не выдавая TXT/FB2 за готовую RPG.
- **Следующий функциональный этап M2:** сначала прочитать `docs/TZ_RU.md`, `docs/ROADMAP_RU.md`, `docs/UI_UX_FINAL_AUDIT_M174C3_RU.md`, `docs/M174C3_PORTABILITY_RECOVERY_RU.md`; начинать с настоящего HEAD `main`. Построить Book Compiler (TXT/FB2 → source chunks/anchors/provenance → coverage → blueprint → проверенный .bworld) по принципу fail-closed; сохранять все существующие функции и обновлять этот handoff.


## M1 финальная читательская доработка / переход M2 (2026-11-02)
- Пользователь подтвердил, что реальных старых игр/прохождений M1.6 не было. **Не тратить работу на миграцию/дополнительный backup демо-сейвов M1.6**, не удалять автоматически прежние файлы/ключи; рабочий формат новых игр — BookWorld SQLite и `.bwsave v2`.
- PR [#5](https://github.com/shonentez-afk/AI-Story-RPG/pull/5), ветка `feat/m1-reader-anchor-and-m2-foundation-20261102`: `BookReadingState.anchorBlock/anchorFraction`, lazy `CustomScrollView.center`, восстановление позиции по абзацу после font/line/width/rotation, fallback pixel-only и тесты. Отчёт [M1_READER_SOURCE_ANCHOR_RU.md](docs/M1_READER_SOURCE_ANCHOR_RU.md).
- **Приёмка:** проверить последний Github Actions run PR #5: анализатор, Flutter widget, native/story_core, Android APK, Windows portable. Предыдущий PR тест первого патча ошибочно сбрасывал старый offset; проблема исправлена, и тест сохранён. Не объявлять весь этап PASS до окончательной проверки.
- Следующий M2a уже выполняется в отдельном [PR #6](https://github.com/shonentez-afk/AI-Story-RPG/pull/6) (`feat/m2a-offline-source-index-20261102`). Offline Dart chunks для TXT/FB2, Unicode UTF-16 source spans, sha256 и честное покрытие текста при `gameplay_coverage=0`; первый экран подготовки в единой библиотеке. Это **не генерация BookWorld**, не ИИ. См. `docs/M2A_SOURCE_INDEX_RU.md` в PR #6.
- M2 не должен создавать второе меню/библиотеку/дублирующую CTA импорта, не должен ломать принятую M1 UX и не должен обходить `rights_status`/проверку источников ради публикации пользовательских произведений.


## Зафиксировано: M1 reader исправлен, M2a принят; следующий этап M2b (2026-11-02)

**Это актуальное состояние, более позднее, чем старые заметки M1/PR #5, которые выше могли иметь статус «в работе».**
- PR [#5](https://github.com/shonentez-afk/AI-Story-RPG/pull/5) **MERGED** в `main` (squash `a1f0124fffa2817ba8c6f5b6d8d8a45bd3445413`). Проверенный source HEAD `af2932a64455bdc78fc8edb23df34b604d75a1d6`; [GitHub Actions #211](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41388339089): **6/6 PASS** (Flutter analyze, **103/103 Flutter widget tests**, Dart, Python, story-core/SQLite, Android debug APK, Windows portable).
- Исправлена реальная Flutter-регрессия `semantic source paragraph survives font and width reflow`: после `CustomScrollView.center` прежние глобальные ключи lazy-sliver сохраняли старые сведения о смещениях и `RenderViewport.correctBy` добавлял высоту абзаца (например +822 px). Для reflow, смены главы и initial restore теперь пересоздаются ключи `RenderSliverList` и ключ `CustomScrollView`, корректный порядок pre-center (обратная `GrowthDirection`). **Не возвращать** прежние циклы align/scrollOffsetCorrection, диагностические `AR-DBG`/`AR-POS`, eager-window эксперименты и скрытие следующих абзацев — этих элементов в принятом коде нет.
- Сохранение позиции: `anchorBlock`/`anchorFraction`, совместимый fallback `scrollOffset` для старых книг; закладки сохраняются. Коды/слоты демонстрационного M1.6 **не мигрировать**, не тратить M2 на backup демо, но и не удалять автоматически пользовательские файлы.
- PR [#6](https://github.com/shonentez-afk/AI-Story-RPG/pull/6) M2a **MERGED**, squash `61de63fb3688421d5ff2d76762fd8c5096e4ee95`, [CI #187](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41383438946) **6/6 PASS**. Уже есть offline TXT/FB2 `BookSourceIndexer`, exact parsed UTF-16 spans, SHA-256, индекс/coverage и экран подготовки книги **в существующей библиотеке**. Исходный индекс **не является** готовой игровой историей: `SOURCE_INDEX_ONLY`, `gameplay_coverage=0`, `can_publish_bookworld=false`.
- **Следующее M2b:** продолжать **с нового фактического `main`**, реализация очереди `SourceChunk` (PENDING/RUNNING/DONE/FAILED/REVIEW, resume), извлечение сущностей, имён и вариантов, фактов, мест, событий, их источников и тайны/спойлеров, cross-chapter сопоставление и human review. Никакой ложной 100% RPG-готовности; позже — проверяемый intermediate blueprint → `.bworld`. Сохранить единую библиотеку, **одну кнопку «Добавить книгу»**, настройки, читалку, M1 SQLite/v2. Физические Windows/Android E2E, FilePicker, OS accessibility/rotation на устройствах остаются **не проведены** (CI ≠ аппаратное тестирование).


## M2b1 — offline extraction queue, рабочая ветка (2026-11-02)
- Начало **после принятого M2a** от фактического main `a5fa542b183226b89bacaf198e404e17531019d9`. Ветка `feat/m2b1-resumable-provenance-20261102`. Не откатывать M1 reader anchors и единую библиотеку.
- `apps/story_reader/lib/book_source_analysis.dart`: immutable `SourceAnalysisSession`, состояния PENDING/RUNNING/DONE/FAILED/REVIEW, обработка ограниченными батчами, retry failed, безопасное восстановление RUNNING→PENDING из checkpoint, SHA-256 и строгая проверка fingerprint, точных источников и доказательств. `CHARACTER_NAME`/`LOCATION_NAME` — **только regex-кандидаты**, требуют REVIEW; подтверждение человеком не равно каноническому факту.
- Тесты `apps/story_reader/test/book_source_analysis_test.dart`; отчёт `docs/M2B1_SOURCE_ANALYSIS_RU.md`. **Не заявлять PASS до CI в PR**.
- Пока НЕТ UI-интеграции, durable storage, полноценного извлечения фактов/событий/alias, cross-chapter resolution, BookWorld из книги, AI или gameplay. `gameplay_coverage=0`, `can_publish_bookworld=false`.
- Продолжение: сначала проверить CI/исправить FAIL для этой ветки; затем M2b2 — приватные сохраняемые checkpoint+UI progress/review в существующем экране «Подготовка книги» без второй библиотеки и без второго импорта. Обязательно поддерживать START_NEW_CHAT_RU.md и STATUS_RU.md после приёмки.


## M2b2 — приватные checkpoints и review UI (2026-11-02)
- Ветка `feat/m2b2-private-checkpoints-review-20261102` построена поверх M2b1 PR #7 (НЕ ПУТАТЬ с main, если ещё не merged). Файлы: `apps/story_reader/lib/source_analysis_checkpoint_repository.dart`, `source_index_preview_page.dart`, улучшенный `book_source_analysis.dart`, `test/source_analysis_checkpoint_test.dart`, документ `docs/M2B2_CHECKPOINT_REVIEW_RU.md`.
- После индексации единственный экран подготовки TXT/FB2 загружает checkpoint из приватной папки ApplicationSupport по SHA нормализованной редакции; рабочая очередь возобновляется без raw text в checkpoint. Порции анализируются в `Isolate.run`, checkpoint сохраняется через flushed-temp + same-directory rename до показа нового прогресса. При сбое записи старый прогресс не заменяется.
- Кандидаты CHARACTER_NAME/LOCATION_NAME показываются по явному запросу (предупреждение о спойлерах), принимается/отклоняется только **упоминание**, не канон/сюжет. Есть ошибки, повтор failed и подтверждённый сброс анализа. Второй библиотеки/импорта нет; BookWorld, SQLite/legacy сейвы, TXT/FB2 чтение не переписаны.
- Требуется **проверить CI точного HEAD M2b2**, Android/Windows builds и негативные тесты, исправить FAIL прежде чем объединять. На данном этапе M2b2 CODE ADDED, CI NOT VERIFIED; физические устройства SKIP.
- Следующий шаг после автоматической приёмки: M2b3 факты/события/алиасы/cross-chapter, достоверные evidence, spoiler policies; затем проверяемый промежуточный blueprint. `gameplay_coverage=0`, `can_publish_bookworld=false`; regex-находки не превращать в игровые факты.


## Подтверждённая приёмка M2b1 / актуальная база M2b2 (2026-11-02)
- M2b1 PR #7 **MERGED** в main (squash SHA `91c6ede82f1615a6f5e96c2a4be816354252b6fc`). Подтверждённый HEAD до squash `22cd1a071b81bcf7784cf16f8778ad180a6d9504`: GitHub Actions `41399856182` **6/6 PASS**, Flutter analyze+tests, core/Dart/Python, Android APK, Windows portable. Первый CI FAIL синтаксиса processBatch был исправлен перед приёмкой.
- M2b2 PR #8 [https://github.com/shonentez-afk/AI-Story-RPG/pull/8](https://github.com/shonentez-afk/AI-Story-RPG/pull/8) перенесён на squash main без потери восьми изменённых файлов; после rebase mergeable=true. Первый CI M2b2 `41400545444` Flutter analyze PASS, 4 widget FAIL из-за offscreen taps/lazy section expectations, исправления уже в ветке; это НЕ итоговый PASS.
- **Обязательно проверить последний CI PR #8 точного HEAD и при FAIL чинить по логам**, затем merge; физические Android/Windows проверки не выдумывать. Далее M2b3 с фактами/событиями/alias/provenance/review, без ложной готовности .bworld.


## M2b2 — ПРИНЯТ И ОБЪЕДИНЁН, следующий M2b3 (2026-11-02)
- PR [#8](https://github.com/shonentez-afk/AI-Story-RPG/pull/8) **MERGED/squash в main**: итоговый кодовый SHA `e704cdf47d1b30816c65ac68a6ab49315597aa4e`; исходный проверенный PR HEAD `b4d5958fa19d2224f3fffd1ef5800a56db312cee`.
- Подтверждён [GitHub Actions 41401389861](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41401389861): **completed/success, 6/6 jobs PASS**. Python PASS, Dart PASS, story_core/BookWorld/SQLite PASS, Flutter analyze PASS, **112/112 Flutter widget/unit PASS**, Android debug APK PASS, Windows portable release PASS. В Actions присутствовали артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo`.
- M2b2 добавил приватные ApplicationSupport checkpoints для M2b1 с flush+same-directory rename, восстановление анализируемых source chunks, локальную порционную обработку в isolate, прогресс и ручное принятие/отклонение **только текстовых упоминаний** в существующем едином экране «Подготовка книги». Спойлеры скрыты до явного запроса, есть retry и подтверждённый reset анализа. Подробности `docs/M2B2_CHECKPOINT_REVIEW_RU.md`.
- Старые TXT/FB2, reader anchors, единая библиотека/одна кнопка импорта, настройки, BookWorld SQLite, `.bwsave v1/v2`, демо-сохранения **не переписывались и не удалялись**. Никакой новой библиотеки/дублирующей CTA. Не мигрировать лишний раз старые демо-слоты M1.6.
- **Не реализовано:** факты/события/родственные связи, cross-chapter alias resolution, spoiler-safe canon graph, AI Book Compiler, произвольный `.bworld` из книги; `gameplay_coverage=0`, `can_publish_bookworld=false`. **Ручные QA SKIP:** реальные Android/Windows устройства, FilePicker E2E, TalkBack/Narrator/клавиатура, power loss, долгие книги 20 МиБ / 30 000 чанков. CI не подтверждает эти тесты.
- **Следующий этап M2b3:** структурированный evidence-backed extraction (персонажи/алиасы/места/факты/события), явный статус CONFIRMED/INFERRED/CONFLICTED/INVENTED, provenance и temporal/spoiler gates, cross-chapter reconciliation/human review; сначала схема + тестовые оригинальные истории, затем интеграция в существующую подготовку книги. Нельзя объявлять извлечение готовым сюжетом или публиковать BookWorld до валидатора intermediate blueprint.
- Если документальный HEAD после этого отличается от кодового SHA из-за `[skip ci]`, принимать за кодовую контрольную точку `e704cdf4`/PR HEAD `b4d5958` и CI 41401389861; новые функциональные изменения должны получать собственную CI.


## M2b3a — evidence/provenance/spoiler contract, новая рабочая ветка (2026-11-02)
- Сначала увидеть окончательное принятие M2b2: PR #8 merged squash `e704cdf47d1b30816c65ac68a6ab49315597aa4e`, проверенный кодовый PR HEAD `b4d5958fa19d2224f3fffd1ef5800a56db312cee`, [Actions `41401389861`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41401389861) **6/6 PASS**, Flutter **112/112**, Android + Windows PASS. Извлечение игровых фактов из книги ещё не реализовано.
- Новая ветка `feat/m2b3a-provenance-evidence-20261102` от свежего `main`. `apps/story_reader/lib/source_evidence_graph.dart` и `test/source_evidence_graph_test.dart`; отчёт `docs/M2B3A_EVIDENCE_GRAPH_RU.md`. SOURCE-ONLY candidates CHARACTER/LOCATION/FACT/EVENT, exact UTF-16 spans/SHA/fingerprint, отдельное подтверждение источника человеком, статусы INFERRED/CONFIRMED/CONFLICTED/REJECTED, spoiler policy CHAPTER/AFTER_EVENT/HIDDEN, возможное совпадение имён между главами только как UNRESOLVED match. **Нет автоматического LLM/extractor FACT/EVENT**, новый модуль НЕ включён в Flutter UI/BookWorld/gameplay. Нельзя использовать его для объявления книги играбельной.
- По ветке M2b3a сначала проверить CI и исправить FAIL. `gameplay_coverage=0`, `can_publish_bookworld=false`; physical device QA SKIP. Следующее M2b3b — извлечение подтверждаемых фактов/событий, cross-chapter review и UI внутри существующего экрана, до intermediate blueprint.


## АКТУАЛЬНО: M2b3a принят; M2b3b в работе (2026-11-02)

- **M2b3a PR #9 MERGED/squash** в `main` как `f8fe317510e42290e544003a2cea0c8f97c30a92`. Проверенный PR SHA `da935fa1acb21834ac51646955b9c2918f8e209d`, [CI 41402784782](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41402784782): **6/6 PASS**, Flutter **117/117**, Python, Dart, world contracts, Windows portable и Android debug все PASS. M2b3a evidence graph — исключительно source citations и spoiler gates, без вывода игрового мира.
- **Новая ветка M2b3b** `feat/m2b3b-extraction-review-20261102` на этом `main`; `source_narrative_extractor.dart`, `story_evidence_review_session.dart`, `source_narrative_review_panel.dart`, отдельный `SourceCheckpointScope.narrativeEvidence` в прежнем repository, интеграция в **тот же экран** `source_index_preview_page.dart`; тесты `source_narrative_review_test.dart`, `source_narrative_review_panel_test.dart`. Пояснения и точные границы `docs/M2B3B_SOURCE_NARRATIVE_REVIEW_RU.md`.
- Только осторожные **локальные шаблоны** русской речи: имена с глаголами событий, состояния двери/окна/ворот и явные прозвища; все выводы **INFERRED**. Отличие состояний между главами = возможный сюжетный переход, **не** доказанная ошибка. Совпадения имён/псевдонимов не объединяются автоматически. Вывод цитат/связей только после предупреждения о спойлерах.
- Новый review checkpoint хранится **отдельно** от M2b1 и SQLite/старых save. Анализ порциями через isolate, checkpoint после каждой порции, пауза/возобновление; подтверждение цитаты человеком не равно подтверждению канонического факта. `gameplay_coverage=0`, `can_publish_bookworld=false`. Новых импортов/библиотек нет.
- **Приёмка M2b3b пока НЕ подтверждена:** проверить PR CI на ТОЧНОМ HEAD, при FAIL исправить код или тесты, повторить Flutter analyze+widgets и Android/Windows до 6/6 PASS, затем squash merge и ДОПИСАТЬ в `START_NEW_CHAT_RU.md`/STATUS/ROADMAP факт приёмки. Физические E2E SKIP. Следующий этап — M2b3c semantic/alias relations, chronology, затем blueprint; не выдумывать готовую RPG.


## АКТУАЛЬНАЯ ПРИЁМКА M2b3b И ПЕРЕХОД НА M2b3c — 2026-11-02

**M2b3b полностью принят, новые чаты ОБЯЗАТЕЛЬНО начинают с актуального `main` — не возвращаться к M2b3a/M2b2 или повторному UI/UX редизайну.**

- PR [#10](https://github.com/shonentez-afk/AI-Story-RPG/pull/10) **MERGED/squash**, итоговый кодовый SHA `b071188f7efdaddbeec865fb94dc7203833fedbb`. Проверенный PR HEAD `423f38963810fdfbbd4ca2eec836895913f635ee`.
- [GitHub Actions `41405360992`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41405360992): **completed/success, 6/6 jobs PASS**; Flutter analyze PASS, **126/126 Flutter widget/unit PASS**, Python PASS, Dart PASS, world/SQLite/contracts PASS, **Windows portable PASS**, **Android debug APK PASS**. Артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo` успешно созданы в этом run. Это CI, **не** физический QA.
- Новые файлы M2b3b: `apps/story_reader/lib/source_narrative_extractor.dart`, `story_evidence_review_session.dart`, `source_narrative_review_panel.dart`, тесты `source_narrative_review_test.dart` и `source_narrative_review_panel_test.dart`; существующий `source_index_preview_page.dart` показывает новую **сворачиваемую панель в том же экране**, без дополнительных библиотек и импортов. `source_analysis_checkpoint_repository.dart` получил отдельный `SourceCheckpointScope.narrativeEvidence`, физически другую папку `ai_story_evidence_review_v1`; прежний каталог M2b1 неизменён.
- Реально работает **локальный ограниченный deterministic extractor**: узкие русские обороты для явно названных событий, простых состояний двери/окна/ворот, «X по прозвищу Y» и «X также известный как Y»; точные текстовые evidence spans и SHA. Возможные расхождения между главами считаются **сюжетным изменением или гипотезой о противоречии**, но не подтверждённым противоречием; пары имён не объединены в NPC. Все новые записи INFERRED; только ручная проверка цитаты меняет статус, не истину канона. Отдельное открытие панели, отдельное раскрытие потенциальных спойлеров, пауза, возобновление, атомарные checkpoint после каждой порции и подтверждённый reset.
- Принятое приложение M1/M2a/M2b1/M2b2, одна библиотека/одна CTA «Добавить книгу», исходные TXT/FB2, reader semantic anchors, `BookStorage`, SQLite, `.bwsave v1/v2`, `CampaignStore`, game engine, настройки и главный экран **не менялись**. User previously approved existing UX. Не удалять/мигрировать демонстрационные или пользовательские слоты повторно.
- **ЧЕСТНАЯ ГОТОВНОСТЬ:** `gameplay_coverage=0`, `can_publish_bookworld=false`; произвольная пользовательская книга ещё НЕ превращается в играбельный BookWorld, автоматическое смысловое понимание глав/хронологии/персонажей, AI-провайдеры и сюжетный компилятор НЕ реализованы. Физические E2E Android/Windows, FilePicker/backup, accessibility, power-loss, большой роман 20 MiB/30k source chunks — SKIP.
- Отчёт: `docs/M2B3B_SOURCE_NARRATIVE_REVIEW_RU.md`. **Следующее — M2b3c:** типизированный граф предложенных relations/aliases, проверяемые source citations и human decisions SAME/DIFFERENT/UNRESOLVED, контекст высказывания vs знание рассказчика, временная последовательность и возможное изменение состояний, отрицания и атрибуция; отдельный валидатор, persistence в приватном store, регрессионный корпус оригинальных историй. Затем M2b4 — provider-interface для локального/облачного семантического извлечения при ЯВНОМ согласии на передачу текста, coverage по фактам/событиям; после — проверяемый intermediate blueprint и только потом playable `.bworld` с rights_status. Не заявлять PASS на новые этапы без точного CI.
- Если `main` HEAD после документационных `[skip ci]` отличается от squash, исходная принятая **кодовая** контрольная точка `b071188f7efdaddbeec865fb94dc7203833fedbb`; новые функциональные изменения требуют новых проверок.


## M2b3c — текущая ветка (2026-11-02, CI НЕ ПРИНЯТ)

- M2b3b **принят и находится в main**, PR #10 squash `b071188f7efdaddbeec865fb94dc7203833fedbb`, CI `41405360992` 6/6 PASS, Flutter 126/126 PASS. Активный документальный main `8e75d373b0f540dcb6f9b68663967880cfb6d2e6`.
- Начат этап **M2b3c** в `feat/m2b3c-identity-chronology-20261102`. Новые файлы: `apps/story_reader/lib/source_relation_review.dart`, `source_narrative_chronology.dart`, `source_relations_review_panel.dart`; тесты `source_relation_review_test.dart`, `source_relations_review_panel_test.dart`, `source_relation_storage_test.dart`; отчёт `docs/M2B3C_IDENTITY_CHRONOLOGY_RU.md`. В существующем `source_narrative_review_panel.dart` добавлена вложенная панель после ранее принятого spoiler gate.
- Только source-backed кандидаты `explicitAlias`/повтор имён по главам, решение человека `UNRESOLVED/SAME/DIFFERENT` после подтверждения обеих цитат, запрет логических цепочек A=B, B=C, A≠C. **Никакого автоматического слияния персонажей в BookWorld.** Границы глав: UNKNOWN/FORWARD/FLASHBACK/PARALLEL — *ручные*, не реальная модель времени. Отрицания и пересказанная речь извлекаются только по ограниченным локальным шаблонам и всегда остаются предположениями. Новая приватная папка checkpoint `ai_story_relation_review_v1` отделена от двух старых.
- Одна библиотека и один импорт остаются, читалка/SQLite/.bwsave/gameplay не затрагиваются; `gameplay_coverage=0` и `can_publish_bookworld=false`.
- **Проверка пока не объявлена успешной**: открыть PR M2b3c, проверить CI по точному HEAD и все 6 jobs/Flutter-тесты; исправлять ошибки, не делать merge при FAIL. Физическое Windows/Android E2E, доступность и большие романы 20 MiB: SKIP. После принятия M2b3c следующий **M2b4** — локальный/облачный semantic provider через явное согласие на сетевую передачу текста, source-cited структурированные сведения, затем intermediate blueprint и .bworld после валидации прав.


## ПРИНЯТО: M2b3c — проверяемые связи и текстовая хронология (2026-11-02)

**Продолжать только с актуального `main`! M2b3c принят, PR #11 закрыт merge. Старые разделы выше со словами «pending» — исторические и не являются актуальным состоянием.**

- PR [#11](https://github.com/shonentez-afk/AI-Story-RPG/pull/11) **MERGED/squash**; принятый кодовый SHA `4cad81c990d816cda6b316506ac47ce3fdee2967`; исходный тестированный head `c676fa86c692115b87e7901aa17985fbe7e4aa42`.
- [Actions `41408023445`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41408023445): **completed/success, все 6/6 jobs PASS**, Flutter analyze PASS, **137/137 Flutter tests PASS**, Python PASS, Dart PASS, world/SQLite/contracts PASS, Windows portable release PASS, Android debug APK PASS. Артефакты: `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-Android-debug`, `AI-Story-RPG-BookWorld-demo`. Отдельный M0 SDK/reference run `41408023664` PASS. Физический Windows/Android manual QA не проводился.
- `source_relation_review.dart`: source-backed `explicitAlias`/межглавное совпадение имени, решения человека `UNRESOLVED/SAME/DIFFERENT` только после подтверждения **обеих цитат**, валидация цепочек и запрет A=B, B=C, A≠C; не объединяет персонажей в игровом мире. `source_narrative_chronology.dart`: отличает отрицательные выражения, слова свидетеля, неопределённые высказывания; порядок только по источнику, не каноническое время. `source_relations_review_panel.dart`: вложен в уже существующий spoiler-gated раздел `source_narrative_review_panel.dart`, с явным открытием и ручными UNKNOWN/FORWARD/FLASHBACK/PARALLEL по границам глав. Отдельный приватный checkpoint `ai_story_relation_review_v1`; предыдущие `ai_story_evidence_review_v1` и `ai_story_source_analysis_v1` не переписываются. Подробный отчёт `docs/M2B3C_IDENTITY_CHRONOLOGY_RU.md`.
- **Не переписывать** принятую единую библиотеку, единственный импорт, reader anchors, TXT/FB2, `BookStorage`, `CampaignStore`, SQLite, `.bwsave v1/v2`, главный экран и настройки. Данные реальных старых игр не предполагать и не мигрировать ради M2.
- **Граница готовности:** `gameplay_coverage=0`, `can_publish_bookworld=false`, source quote/relationship hypothesis != true canon; пока нет AI semantic extractor, causal world model, verified scene/branch blueprint, компиляции пользовательской книги в playable `.bworld`. Ручные E2E телефонов/ПК, доступность OS, power-loss и масштаб 20 MiB/30k chunks — SKIP. UI по умолчанию ограничивает список первыми 4 парами/3 переходами/6 цитат; для длинных книг нужна последовательное раскрытие находок.
- **Далее M2b4a:** создать отдельный абстрактный источник семантического анализа (локальная реализация по умолчанию, облачная только после отдельного явного согласия на отправку исходного текста), типизированные source-backed candidate схемы и fail-closed проверку provenance/spoiler/rights_status; блокировать публикацию до полного validator+intermediate blueprint. Сначала unit/integration mocks/тесты негативных ответов, затем UI в **той же** подготовке книги. Не обещать произвольную книгу как готовую RPG без этого. План и критерии приёмки — `docs/M2B4_SEMANTIC_PROVIDER_PLAN_RU.md`.


## Повторный аудит UX/UI, настроек и открытия книги — 2026-11-02 (рабочая ветка)

- База принятого M2b3c `main` `4eff8fceba2df65db39dabc886353202b9de3857` (код M2b3c `4cad81c990d816cda6b316506ac47ce3fdee2967`). **Новая ветка `audit/ux-ui-book-open-settings-20261102`** с исправлениями UX (ещё не объявлять принятыми без CI).
- Отчёт `docs/UX_UI_FULL_AUDIT_BOOK_SETTINGS_2026-11-02_RU.md`. Ключевые исправления: отдельная тема приложения (системная/светлая/тёмная) без сброса OCR/сепия/OLED чтения, расширенная понятная вкладка настроек (параметры чтения, безопасный reset, приватность, одна библиотека/прохождения), сериализованные SharedPreferences write/read по настройкам и каждой книге, fail-closed повтор открытия книги при ошибке загрузки progress без записи поверх старого.
- Книги: UTF‑8/Windows‑1251/BOM UTF‑16, `BookStorage.scan` в isolate, новые книги .json атомарным temp+rename, нечитаемые файлы не удаляются и отображаются предупреждением. В библиотеке рядом с книгой видимые **«Читать» и «Подготовить к RPG»**, меню ⋮ оставлено для удаления — одна библиотека и одна CTA импорта сохранены. Исторические reader semantic anchors, BookWorld SQLite и игровые сохранения не переписывались.
- Тесты `book_open_encoding_audit_test.dart`, `book_open_library_audit_test.dart`, `settings_library_responsive_audit_test.dart`; обновлены `app_theme_test.dart`, `reading_preferences_test.dart`, `book_reading_state_test.dart`. По-прежнему нужно проверить **полный CI по последнему SHA**, при FAIL исправить и повторить Flutter analyze/widget, Python/Dart/story-core, Android APK + Windows portable. Не делать merge без 6/6 PASS.
- Аппаратный UI QA, скриншотная проверка, реальные системные диалоги, файловые переносы, OS accessibility, power-loss, 20 MiB stress — **не проведены**. M2b4 semantic providers остаётся отдельным следующим этапом. `gameplayCoverage=0`/`canPublishBookworld=false` для пользовательских книг.

## Hotfix: Illegal argument in isolate message при открытии книги — 2026-11-02
- Пользователь прислал реальную ошибку с Flutter _firstFrameCompleter/RenderParagraph/StatefulElement: фоновый Isolate.run пытался получить несериализуемый объект UI. Это НЕ считалось исправленным прежним аудитом.
- Рабочая ветка: fix/unsendable-isolate-book-opening-20261102. До приёмки status=CODE, CI PENDING; full report docs/BOOK_ISOLATE_UNSENDABLE_HOTFIX_RU.md.
- В book_isolate_workers.dart создан top-level compute API без захвата Flutter State: парсинг TXT/FB2, индекс, M2b1 checkpoints, M2b3b extraction, M2b3c relation/chronology. Исправлены вызовы home_page.dart, book_storage.dart, source_index_preview_page.dart, source_narrative_review_panel.dart, source_relations_review_panel.dart.
- Добавлен book_isolate_workers_test.dart с реальным StatefulWidget-пробником и data-only background regression. До CI зелёный статус НЕ заявлять; проверить GitHub Actions 6/6 + Android/Windows. Физическое воспроизведение на устройстве без исходного файла и runtime log пока не подтверждено.
- Принятый PR #12 UX/UI не откатывать, PR #13 закрыт дублирующим. Независимый PR #14 про кнопку Готово не перезаписывать. M2b4 только после исправления этого crash.
## 2026-11-02 — ПРОВЕРЕНО И ПРИНЯТО: hotfix открытия книги / Illegal argument in isolate message
- Реальный скриншот пользователя: Invalid argument(s): Illegal argument in isolate message: object is unsendable; в trace WidgetsBinding._firstFrameCompleter / RenderParagraph / StatefulElement. Предыдущий UX/UI аудит не исправлял именно этот класс crash.
- PR #15 https://github.com/shonentez-afk/AI-Story-RPG/pull/15 MERGED (squash code SHA a03d2a522b78bbd1a6d30c8bcae6a9733fd4688a); точный протестированный HEAD e26224f570e314fcbae4dbb868503ccf307ab96a.
- GitHub Actions https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41417818152 completed/success, 6/6 jobs PASS, Flutter analyze PASS, 155/155 Flutter tests PASS, Python PASS, Dart PASS, world/SQLite contracts PASS, Windows portable PASS, Android debug APK PASS. M0 run 41417818123 PASS. Артефакты AI-Story-RPG-Windows-portable и AI-Story-RPG-Android-debug подтверждены на этом run.
- Исправление: book_isolate_workers.dart с top-level typed compute worker entrypoints. home_page.dart импорт TXT/FB2; book_storage.dart JSON library scan; source_index_preview_page.dart индексация/checkpoints; source_narrative_review_panel.dart evidence; source_relations_review_panel.dart chronology/relations. Не передавать State, BuildContext, RenderObject, plugin/method closures в workers; не возвращаться к Isolate.run closure, объявленному внутри StatefulWidget State.
- Регрессия book_isolate_workers_test.dart: реальные compute операции для парсинга, индексирования, mentions/evidence/relations/chronology, сканирование библиотеки. Existing book_open_library_audit_test.dart: UI путь Подготовить → назад → Читать. WidgetTester FakeAsync не предназначен для ожидания настоящего isolate с pumpAndSettle; тесты используют корректные async зоны/ограниченные navigation frames.
- Сохраняется существующая одна библиотека, импорт, тексты, книга, игровые SQLite/.bwsave, три независимых checkpoints. Нет миграции и удаления данных.
- Физический запуск на ТОМ ЖЕ файле пользователя под Windows и Android НЕ проводился; CI не доказывает устранение всех возможных device-dependent багов. Для проверки нужна НОВАЯ сборка из Actions 41417818152; ранее установленный exe не меняется автоматически. Если ошибка повторится — получить полную трассировку, формат/размер файла, путь Читать или Подготовить к RPG.
- Отчёт docs/BOOK_ISOLATE_UNSENDABLE_HOTFIX_RU.md.

## 2026-11-02 — UX/UI PR #14 также принят
- PR #14 https://github.com/shonentez-afk/AI-Story-RPG/pull/14 MERGED squash SHA 97d82e4f4eeaaa91ad34f44d412c5eed779dc87e, проверенный HEAD b9a96fa41fc48d1d8e179d60581c393c2ada7d50, Actions 41414920106 6/6 PASS и 153/153 Flutter tests. Явная кнопка «Готово» в настройках чтения добавлена. PR #12 full UX/UI audit ранее принят, #13 закрыт дубликатом.
- Последний main после двух кодовых PR и этих документационных [skip ci] может отличаться от кодовой точки 97d82e4; следующий функциональный этап M2b4 semantic-provider требует собственного CI и ручного QA.

## 2026-11-02 — Реальный файл FB2 с иллюстрациями / новый общий Release
- Пользователь передал `Andersen Gans. Samye krasivye skazki (s illyustraciyami) - BooksCafe.Net.fb2` (SHA256 `6713c5ab79bd68e30b647177a9ac951c73d72b36b6942f2195f247221763148a`, 7 441 257 bytes). Локально проверены оригинальные байты: UTF-8 FB2, 6 глав-сказок в `body`, 3 сноски в `body name="notes"`, 67/67 JPEG валидны, 66/66 ссылок на текстовые изображения найдены. Оригинальный текст и картинки **не выгружались** в публичный GitHub.
- Старый импортёр представлял 3 сноски дополнительными главами. Ветка `fix/illustrated-fb2-and-unified-release-20261102` группирует их в один финальный раздел «Примечания», сохраняя содержание; ожидаем 6 сказок + 1 примечания. Ранее импортированные книги в JSON не мигрируются — для новой структуры нужно повторно импортировать FB2. Интерактивный переход по сноске НЕ реализован.
- `apps/story_reader/test/illustrated_fb2_collection_test.dart`: оригинальный синтетический FB2 (6 + 3; 67 JPEG) проверяет импорт, картинки, индекс, файловое сохранение и повторное открытие без копирования авторского произведения. Полный отчёт `docs/ILLUSTRATED_FB2_REAL_FILE_TEST_20261102_RU.md`.
- В `.github/workflows/android-ci.yml` Windows ZIP и Android APK должны публиковаться в **одном тестовом GitHub Release** `test-build-N` после успешных обеих платформенных сборок; `SHA256SUMS.txt` прилагается. Ранее релиз `android-build-247` был устаревшим и Android-only. Не утверждать, что новый Release опубликован, пока не увидим реальную запись/активы GitHub.
- Статус этой ветки: CODE / CI PENDING; необходимо 6/6 PASS на точном PR HEAD, merge, затем 6/6 push(main) и фактический новый GitHub Release. Нет Dart/Flutter SDK локально: оригинальную книгу проверяли локально XML/Pillow и имитировали алгоритм Dart; реальное открытие в конкретном EXE/на телефоне остаётся ручным QA.


## 2026-11-02 — FB2 с иллюстрациями принят, общий Windows+Android Release опубликован

**Актуально: PR #16 MERGED, тестовый GitHub Release `test-build-258` ОПУБЛИКОВАН. Предыдущие фразы «CI pending» в старых разделах — исторические.**

- Кодовый squash merge: `7532667f8497b001a65ee01c108d1e6811b2b158`. PR [#16](https://github.com/shonentez-afk/AI-Story-RPG/pull/16); точный тестированный PR head `2e6656dddbf9e9464d749f6bf252bf565651d1e4`. PR run `41420714946` — 6/6 PASS, Flutter analyze и **159/159 Flutter tests PASS**, Windows portable и Android debug PASS. M0 `41420714994` PASS.
- Push(main) Actions [`41421831068`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41421831068) — **7/7 PASS**: 6 CI jobs + unified Release job. GitHub Release [`test-build-258`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-258), published 2026-11-02T09:42:02Z, target **exact code merge SHA** above.
- Реальные активы релиза (отдельные файлы, НЕ только Actions artifacts):
  - [Windows portable ZIP](https://github.com/shonentez-afk/AI-Story-RPG/releases/download/test-build-258/AI-Story-RPG-Windows-portable.zip): 13 238 315 bytes, SHA256 `586358fbf61f0b645e69c2043450f2a466eb98f8abb552d215a64e192e8acf6a`; распаковывать **всю** папку `AI-Story-RPG-Windows` с exe, DLL, `data`.
  - [Android APK debug](https://github.com/shonentez-afk/AI-Story-RPG/releases/download/test-build-258/AI-Story-RPG-Android-debug.apk): 167 209 608 bytes, SHA256 `465998db35f8672b0a47d32552b66766aab558f07b572a0fc634716159297d39`.
  - [SHA256SUMS.txt](https://github.com/shonentez-afk/AI-Story-RPG/releases/download/test-build-258/SHA256SUMS.txt): 197 bytes. Актуальная GitHub Releases entry подтверждена через API, все assets в статусе `uploaded`.
- Пользовательский FB2 **не публиковался**: 7 441 257 bytes, SHA256 `6713c5ab79bd68e30b647177a9ac951c73d72b36b6942f2195f247221763148a`; локальный XML/Pillow: 6 основных сказок, 3 notes sections в отдельном body, 67/67 valid JPEG и 66/66 image refs, обложка. Исправленный импортёр объединяет notes в одну финальную главу «Примечания», всего **7** вместо **9**; все примечания сохраняются. Синтетический Dart регрессионный корпус на аналогичной структуре (не реальный текст книги) PASS.
- **ОГРАНИЧЕНИЕ:** Нет локального Dart/Flutter SDK, поэтому оригинальный файл не был открыт непосредственно в установленном EXE; подтверждены файловая целостность/декодирование Python, синтетический импорт Flutter и платформенные сборки. Ручной E2E на пользователевом Windows/Android остаётся SKIP. При повторной установке нужно повторно импортировать исходную FB2 (старые JSON-записи не мигрируют, не удалять их автоматически). Нажатие на номер сноски пока не выполняет переход к тексту (отдельный UX долг).
- Сохраняются M2b3c, PR #15 crash hotfix, PR #14 settings, SQLite/.bwsave и библиотека, без потерь данных. Дальше — M2b4 semantic-provider по ранее принятому плану, после проверки нового сборочного теста на устройстве.

## 2026-11-02 — UX карточки книги: прямая корзина вместо «⋮»
- После установки `test-build-258` пользователь показал скриншот библиотеки: меню «⋮» книги содержит ровно один пункт «Удалить книгу». Это неоправданный дополнительный переход; карточка уже имеет отдельные действия «Читать» и «Подготовить к RPG».
- Ветка `fix/library-visible-delete-action-20261102`: `apps/story_reader/lib/home_page.dart` заменяет `PopupMenuButton` на явно видимую кнопку `Icons.delete_outline` с tooltip «Удалить книгу» и семантическим ключом `library-delete-<id>`. Сохранено обязательное подтверждение удаления с именем книги и предупреждением о необратимости, а также обработка ошибки/блокировка `_working`.
- Проверки: `apps/story_reader/test/library_delete_button_test.dart` — наличие корзины, отсутствие однопунктного overflow, «Отмена» без удаления, подтверждение и фактическое удаление, ошибка диска без потери книги; `settings_library_responsive_audit_test.dart` — доступная кнопка на 320dp при 200% масштабе текста. Существующие кнопки чтения и подготовки не изменены.
- Статус до завершения CI: **PENDING**. Для приёмки нужен exact SHA PR Flutter analyze + full tests + 6/6 jobs (Android/Windows), затем squash merge, push(main) полный CI и проверенный новый Release с двумя платформами. Нельзя считать прежний `test-build-258` содержащим корзину: он предшествует этой правке.

## ПРИНЯТО 2026-11-02 — видимая корзина в библиотеке и test-build-260
- По скриншоту пользователя убрано избыточное меню «⋮», содержавшее единственный пункт удаления. В карточке импортированной книги теперь отдельная кнопка-корзина `Icons.delete_outline`, tooltip «Удалить книгу», key `library-delete-<id>` и цвет предупреждения. Касание вызывает прежний диалог подтверждения; кнопки «Читать»/«Подготовить к RPG», файлы книг, игровые сейвы, сохранения позиции не менялись.
- PR [#17](https://github.com/shonentez-afk/AI-Story-RPG/pull/17) **MERGED**, кодовый squash `180e32995e71e609fe303cad6db927f0420ed239`; протестированный HEAD `a33ea3f5c436622774cfc8e9aa07bb18edc9e10f`. PR CI `41424400911`: 6/6 PASS, **161/161 Flutter-тестов PASS**, Windows portable и Android debug APK PASS, M0 SDK `41424401023` PASS. Дополнительно проверены отмена, подтверждение, ошибка хранения без удаления и 320dp при масштабе текста 200%.
- Push(main) [CI `41425466744`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41425466744) **7/7 PASS**, включая Windows, Android и отдельную публикацию релиза.
- Новый [GitHub Release `test-build-260`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-260) опубликован `2026-11-02T10:08:56Z`, target **кодовый commit `180e32995e71e609fe303cad6db927f0420ed239`**:
  - [Windows ZIP](https://github.com/shonentez-afk/AI-Story-RPG/releases/download/test-build-260/AI-Story-RPG-Windows-portable.zip), 13 238 463 bytes, SHA256 `fcadfe2c264e907a82b6553795da50d0394e0c6dc7ae6c134203b7ec84ead713`.
  - [Android APK](https://github.com/shonentez-afk/AI-Story-RPG/releases/download/test-build-260/AI-Story-RPG-Android-debug.apk), 167 209 424 bytes, SHA256 `b832b719b1612b1b0980ad281536632973b0101ecfb3d4442457eabaf041c610`.
  - `SHA256SUMS.txt` присутствует. Все три актива GitHub Release проверены, state=uploaded.
- Старые test-build-258/256 **не содержат новую корзину**. Для проверки новой версии нужно переустановить/распаковать test-build-260. Ручной E2E на реальном устройстве остаётся SKIP; не путать CI PASS с проверкой всех физических устройств. Следующий функциональный план M2b4 semantic provider, но текущая UX-корзина уже завершена.


## M2b4a — provider boundary, PR #18 (2026-11-02)
- Начат с последнего принятого `main` `2c9f3f7d2fd8a95f385e2ec98c2ebd0b61465dc6`; последний опубликованный релиз пока `test-build-260` (Windows/Android), 7/7 push(main) CI для code SHA `180e32995e71e609fe303cad6db927f0420ed239`.
- Ветка `feature/m2b4a-semantic-provider-boundary-20261102`, PR https://github.com/shonentez-afk/AI-Story-RPG/pull/18, документ `docs/M2B4A_SEMANTIC_BOUNDARY_PROGRESS_RU.md`.
- Добавлены сменяемые типизированные semantic request/candidates, `OfflineRuleProvider`, `SemanticProviderGate`, fail-closed validator и негативные Flutter tests; локальная модель не настроена, cloud gate всегда закрыт. `SourceAnalysisSession.scanChunk` только read-only обёртка старого M2b1 сканера.
- **Статус CODE ONLY / CI PENDING**: проверить PR #18 точный HEAD Flutter analyze/test, Python/world, Windows+Android. Важно: текущий код ещё не добавлен в UI и не имеет semantic checkpoints. Не заявлять готовым весь M2b4a и не объединять без CI.
- Далее безопасные приватные semantic checkpoint/возобновление и UI строго внутри существующей страницы подготовки, после отдельного code/CI QA. Не трогать старую библиотеку, сохранения, M2b1/M2b3b/M2b3c, не отправлять книгу по сети и не объявлять playable BookWorld.


## 2026-11-02 — Продолжение M2b4a после зелёного PR #18

- Проверен actual PR #18 head `05a399c241670cda5d05e2bdda0d60cbe163812f`, CI `41427964306` completed/success: Flutter analyze/widget, Dart, Python/world, Windows portable и Android APK PASS; M0 `41427964385` PASS. PR #18 merged squash `13e9c0ebf4ab6e2cfbbcf306ad221b78cbcc7266`. Исторический статус «CI PENDING» для M2b4a1 закрыт.
- Начата отдельная ветка `feature/m2b4a-semantic-checkpoints-ui-20261102`. Реализованы `source_semantic_review.dart` (проверяемые checkpoint/resume), scope `semanticProposals` в собственной приватной папке, top-level compute workers, `source_semantic_review_panel.dart` и подключение в существующей `source_index_preview_page.dart`. Тесты `source_semantic_review_test.dart`, `source_semantic_review_panel_test.dart`. Документ `docs/M2B4A2_SEMANTIC_CHECKPOINT_UI_RU.md`.
- **M2b4a2 пока не принят: CODE / CI PENDING**. Сначала проверить точный SHA PR и Flutter analyze/test, Dart/Python/world, Windows+Android, исправить FAIL; только затем merge и main publish Release с точной кодовой ревизией. Пользователь просил продолжать строго по плану и обновлять этот handoff.
- Не переписывать старые M2b1/M2b3b/M2b3c checkpoint, сохранения, настройки/ридер. В модели пока только offline-rule предложения, неизвестный canonical статус и запрещённый cloud. Нет реального AI, blueprint и готовой RPG для пользовательской книги.


## ПРИНЯТО: M2b4a2 — 2026-11-02, полный CI и Release

- PR #19 https://github.com/shonentez-afk/AI-Story-RPG/pull/19 **MERGED**, кодовый squash `5c8eeb63a8aff47649107fe35a6cbfb6df729c14`; проверенный PR head `d163bf68b49436e62b381316fa9cc96377f780f9`.
- PR Actions `41430335297` **6/6 PASS**: Python, Dart, BookWorld, Flutter analyze, **176/176 Flutter tests**, Android debug APK, Windows portable. M0 `41430335058` PASS.
- Push(main) Actions `41431317114` **7/7 PASS**, включая публикацию GitHub Release; дополнительный M0 `41431317020` PASS.
- Проверенный выпуск: https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-266, опубликован 2026-11-02T10:52:37Z, target exact code SHA `5c8eeb63a8aff47649107fe35a6cbfb6df729c14`. Три актива имеют состояние `uploaded`:
  - Windows portable ZIP 13 264 516 bytes, SHA256 `6ddf5318eb95e915eb9e44db264f45b107a1345f14dac702a88106d7d6a234c8` (распаковывать полную папку exe+DLL+data).
  - Android debug APK 167 253 204 bytes, SHA256 `3e2de1b4a217b7a4d3d15ae21877bb5f2754bceca000e55d55d05d2c0af49b66`.
  - `SHA256SUMS.txt` присутствует.
- В интерфейсе: Библиотека → книга → «Подготовить к RPG» → «Семантические предложения · M2b4a» → «Открыть локальный анализ». Старая библиотека/настройки/книги/читательские позиции и M2b1/M2b3b/M2b3c и SQLite игровые сохранения не мигрировали и не удалялись.
- Это **локальный regexp-provider**, а не полноценный AI Book Compiler. Нет живой модели, облачных запросов, `IntermediateStoryBlueprint` или playable BookWorld из пользовательской книги; `gameplayCoverage=0`, `canPublishBookworld=false`. Ручной Windows/Android E2E на физическом устройстве, долгие книги 20 MiB/30k, экранный диктор, power-loss остаются **SKIP**.
- Следующая разработка: M2b4b источник проверяемых смысловых фактов/событий и отдельная интеграция модели с приватностью/правами, затем M2c causal blueprint/validator.


## 2026-11-02 — UX-коррекция «Подготовить к RPG» после тестирования пользователем

- Пользователь подтвердил, что `test-build-266` запускается, но смысл кнопки «Подготовить к RPG» и действий на следующем экране непонятен. Не принимать это за дефект парсера: проблема в модели взаимодействия и необоснованном ожидании готовой игры.
- Ветка `ux/preparation-guided-flow-20261102`. Полный отчёт `docs/UX_PREPARATION_GUIDED_FLOW_2026-11-02_RU.md`. Реализованы читабельная карта реальных шагов, граница «создать RPG пока недоступно», понятные действия локального поиска, счётчики проверенных упоминаний, скрытие спойлеров, последовательное раскрытие дополнительных находок, отдельный необязательный экспериментальный повторный поиск, свернутая диагностика и главы. Исторические M2b1/M2b3b/M2b3c/M2b4a2 и игровые сохранения не переписывались.
- Обновлён `source_analysis_checkpoint_test.dart`, добавлен `preparation_guided_ux_test.dart`. **Статус пока CODE / CI PENDING**, не переносить оценку CI `test-build-266` на новый UX код. Требуется Flutter analyze/widget, Dart/Python/world и обе платформенные сборки по SHA PR, затем merge, push(main) полный CI и новый проверенный Release. Ручной UX Windows/Android отдельно SKIP.
- Для уже установленного `test-build-266`: нажатие «Подготовить к RPG» создаёт индекс; «Обработать порцию» ищет упоминания по шаблонам; отдельные панели проверяют цитаты/связи; `OfflineRuleProvider` повторяет часть поиска. Ни один инструмент ещё не создаёт готовую RPG из загруженной книги.

**Уточнение UX PR #20:** первые CI находили неверные offscreen tap и устаревшие ожидания в тестах. В ответ вводная карточка компактная, кнопка поиска выше, вывод находок через «Показать ещё» без скачка списка; тесты адаптированы к реальной прокрутке. Не объявлять PASS до нового exact-head CI, merge и проверки нового Windows+Android Release.


## 2026-11-02 — пользователь потребовал закончить всю подготовку до ИИ

1. PR #20 UX merged `cdf64ff3c5da7cf52acaf9ee9767145a16d3d7d9` после PR run `41438307133` gates PASS и M0 `41438307091` PASS; не путать с прежними CI FAIL по старому SHA.
2. Открыта `feature/m2b4b-m2c-pre-ai-validation-20261102`. Прочитать `docs/M2_PRE_AI_READINESS_AUDIT_RU.md`, `apps/story_reader/lib/source_semantic_catalog.dart`, `apps/story_reader/lib/intermediate_story_blueprint.dart`, `apps/story_reader/test/pre_ai_semantic_blueprint_test.dart`. Новые source-cited assertions и причинный preflight не меняют старые checkpoints/saves, не имеют сети, не умеют экспортировать готовую книгу в игру.
3. Важно: `packages/bookworld_format/lib/bookworld_format.dart` и `tools/bookworld/bookworld.py` жёстко принимают лишь original-demo world. Нужно M2d для пользовательских адаптаций с полным validator, rights/source provenance; это отдельный обязательный пункт **перед** настоящим AI.
4. Статус: CODE / отдельный PR CI PENDING. Продолжать создание тестов и закрытие M2b4b/M2c/M2d; не обещать, что arbitrary FB2 уже playable. Обязательно проверять actual exact SHA CI + Windows/Android, фиксировать release. Предыдущие навыки чтения/сохранения/цифровых прав не сбрасывать.


## 2026-11-02 — M2b4b/M2c validated scaffold accepted, M2c editorial continuation

- PR #21 merged squash `a8b016e3bd4ebf6855fe7b81cc861b566b078a3b`; exact test head `69fc30289f0131b130bd448d56374b2ffc907fd8`. GitHub Actions `41447576581` 6/6 PASS, Flutter **187/187**, Windows portable and Android debug PASS. M0 `41447576604` PASS. Semantics remain INFERRED, draft can't publish.
- Следующая ветка `feature/m2c-editorial-checkpoints-readiness-20261102`: `source_semantic_editorial_review.dart`, read-only `preparation_readiness_report.dart`, 3 приватных checkpoint scopes, regression `pre_ai_editorial_readiness_test.dart`, `docs/M2C_EDITORIAL_CHECKPOINTS_RU.md`. **Её CI ещё НЕ принят.**
- Before AI important M2d separate: current Python+Dart `.bworld` allow only `original_demo`. Production personal adaptation must get separate package/rights/provenance validator, don't weaken old demo by just changing a string. Need usable one-button preparation flow and actual short-story E2E; no false "ready".


## 2026-11-02 — PR #22 accepted; M2 offline one-click pipeline

- PR #22 exact tested head `6144bc96520bf5b49577f5dab6000d7fda53609c`, core CI `41449001964` 6/6 PASS + M0 `41449001948` PASS, merge code SHA `95c99fb796f4f36dedc514958101bea98adb6684`. Editorial checkpoint, readiness report, new private scopes landed.
- Ветка `feature/m2-preparation-one-click-offline-20261102` содержит **ещё не принятый** one-click offline local-preparation coordinator (mentions M2b1 → M2b3b events → source-cited M2b4b catalog), сохранение каждой порции, pause/resume, worker isolates, UI `prepare-offline-all`. Добавлены отдельные тесты и документ `docs/M2_OFFLINE_PREPARATION_PIPELINE_RU.md`. Персонажи, локации, alias hints, встречи, события и состояния — только INFERRED, не канон.
- M2d компилятор пользовательского `.bworld` на короткой книге, типизированный перевод intermediate scene → StoryBlueprint, права/верификация источников и полноценный ИИ **ещё не завершены**. Ни один кодовый путь не помечает произвольную книгу готовой.
- Не мержить этот следующий этап без exact-head Flutter analyze/test, Python/Dart/world, Windows/Android; не удалять старые сохранения, приватные checkpoints, отдельный импорт.

## 2026-11-02 — M2d private adaptation preflight before AI

- M2b4b/M2c semantic and causal scaffold merged PR #21 `a8b016e3`, M2c editorial/status gate merged PR #22 `95c99fb7`, Windows/Android and 187+ Flutter regression CI passed on their exact branches.
- Ветка `feature/m2d-private-source-preflight-20261102`: `apps/story_reader/lib/private_adaptation_preflight.dart`, `test/private_adaptation_preflight_test.dart`, `docs/M2D_PRIVATE_ADAPTATION_PREFLIGHT_RU.md`. Новый preflight требует ручной canonCandidate, confirmed exact source passage, права, подтверждённые переходы/альтернативы; явные blockers при пропусках. **CODE / CI PENDING**, не компилятор ZIP, `canCompilePlayableBookworld=false`.
- PR #23 принят в `main` кодом `a22eaf291ffa11e847d4b542eab3b8e1a4920646` после 6/6 CI `41451512164`, M0 `41451512064`; реализует единый локальный one-click pipeline с checkpoint/resume, но ещё не превращает inference в канон.
- Для полноценного M2d нужно новый безопасный production-format/provenance, Python/Dart importer parity, playable author-owned short story Windows/Android и сохранения; затем явный API consent, модельный benchmark и без скрытого fallback.


**Текущая M2d граница:** preflight PR #24 требует собственного CI. Пакетный compiler и playable .bworld реальной книги не реализованы; следующий этап требует независимых production validator/компиляции и E2E.


## 2026-11-02 — M2d приватный v2 BookWorld: действующая рабочая ветка

- Preflight PR #24 **MERGED** squash `5b71951361623fcb54a29c21b44fc80ba565e117`. Exact PR SHA `1d428e67c228d08379af4951d6a3f24052c0bf8b` принят GitHub Actions `41458429744` core 6/6 PASS (Flutter, Dart/Python, Windows, Android) + M0 `41458429984` PASS. Push(main) `41459581044` не завершил Android: скачивание Google NDK 28.2 оборвалось с ошибкой ZIP/sdmanager — это **сбой окружения**, не успех релизной сборки; Windows + Flutter/Python/Dart PASS. Последний реально опубликованный релиз прежний `test-build-289` (из PR #23); проверяйте новый релиз отдельно.
- Ветка `feature/m2d-private-classic-scenario-translator-20261102` добавляет `private_classic_scenario_translator.dart`, `packages/bookworld_format/lib/private_bookworld.dart`, Python `tools/bookworld/private_bookworld.py`, строгое чтение ZIP v2 (четыре файла), source UTF-16 quote SHA от локального индекса, без публикации, с `private_use_only`. Допущен только `PROTAGONIST/ALTER_FATE/CLASSIC`. Исторический v1 `original_demo` остаётся строгим.
- `packages/campaign_manager` учится принимать v2 **только через отдельный полный валидатор**, сохраняет старую SQLite-библиотеку/сейвы, в тесте 20 ходов, два финала, восстановление и экспорт/импорт. Добавлены оригинальные фикстуры, отрицательные тесты ZIP/rights/provenance/cycles, новый CI шаг Python→Dart.
- Подробности `docs/M2D_PRIVATE_BOOKWORLD_V2_RU.md`. Статус **CODE / CI PENDING**, нельзя выдавать пакет v2 за установленную готовую RPG без exact-head CI и устройства. Последующий обязательный шаг: встроенный пользовательский M2d writer в Flutter для Windows+Android, редактор проверенного сценария, кнопка «Начать игру» только после успешного импорта; E2E на авторской книге. Реальная LLM не подключена, источник не отправляется в сеть.

## 2026-11-03 — M2e/native private BookWorld writer (продолжение после test-build-297)

- Актуальная принятая база: PR #25 MERGED code 73e57017bdf28855b7539fdf7d8bcbaf76adabb4; push(main) CI 41464407747 full success 7/7 и M0 41464407736 PASS; релиз test-build-297 https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-297 содержит Windows/Android. Старые записи о CI PENDING для PR #24/#25 являются историческими, не текущими.
- Новая ветка feature/m2e-native-bookworld-writer-20261103: встроенный Dart SQLite+ZIP writer формата private v2 без Python/HTTP, обязательный локальный SHA/UTF-16 source-proof, повторный импорт и тесты cross-check Python. Технический отчёт docs/M2E_NATIVE_PRIVATE_COMPILER_RU.md. **Статус M2e CODE / CI PENDING**, не переносить успех test-build-297 на новый код.
- Это ещё не «загрузил любую книгу → готова RPG»: в UI отсутствует полнофункциональный редактор проверенного M2c-сценария и автоматическая цепочка его сборки. Проверка канона необходима, недостаточно 100% текстового охвата.
- Следующий путь: native adapter BookSourceIndex в изоляторе → редактор персонажей/сцен/вариантов → единый отчёт фактов/готовности → кнопка создания/старта только для валидированного пакета → 20+ ходов и реальный Windows/Android E2E → настройки API/согласие/безопасность → подключение модели.

## 2026-11-03 — M2e2 short-story editor / roadmap continuation

- PR #26 exact head cca1f829bbbf6ce614c6aded652e00c5e3b5d15a, CI 41490060651 6/6 PASS (including Dart→Python ZIP/SQLite parity, Flutter, Windows/Android) and M0 41490060549 PASS; MERGED squash code 47a9d89e671eda6a758bbb30981cdbb7d7788824. Latest published release may still be test-build-297 until push(main) 41491441574 completes; verify exact release target before linking.
- Новая ветка feature/m2e2-reviewed-story-composer-20261103, документ docs/M2E2_REVIEWED_STORY_EDITOR_RU.md. Реализован отдельный ручной редактор короткой личной адаптации внутри существующей подготовки: точные подтверждённые цитаты, явные решения канона, 2 source scenes + 1 authored alternate, отдельный draft checkpoint, согласие privateUse, native compiler, установка в BookWorld library и открытие кампаний.
- Статус M2e2 **CODE / CI PENDING**. Нельзя утверждать, что любая книга автоматически компилируется или что новая UI-функция уже попала в выпуск. Не делать silent promotion из INFERRED; не удалять старые книги/сохранения.
- После M2e2: полный редактор identities/aliases/chronology/scenes; итоговый readiness report с тремя шкалами; Windows+Android physical E2E и stress; затем BYOK/cloud consent/token budget/model QA.


## 2026-11-03 — M2e3 проверяемая готовность установленной личной RPG

- Проверенная база `main` `867b5816`, CI `41506056713` 7/7 PASS, M0 `41506056826` success, релиз `test-build-310` содержит Windows portable и Android debug APK. Это успех **прошлого** M2e2, а не нового этапа.
- Новая ветка `feature/m2e3-verified-private-game-gate-20261103` добавляет `private_game_readiness.dart`, `private_game_readiness_panel.dart`, тесты и интеграцию в единую страницу подготовки. `PrivateBookworldImporter` независимо проверяет ZIP/SQLite/source SHA ранее установленной личной адаптации; кнопка открытия видна только для проверенного совпадающего мира. Старые книги и прохождения не меняются.
- Документ: `docs/M2E3_PRIVATE_GAME_READINESS_RU.md`. Текущий статус **CODE / CI PENDING**, нужен exact-head CI и затем принятие PR. Полная сюжетная модель романа, physical E2E, настройки BYOK/cloud согласия — впереди.


## 2026-11-03 — M2e4a: расширенный редактор источников (первая часть)

- Ветка `feature/m2e4-expanded-source-editor-20261103` создана поверх M2e3, пока PR #28 проходит отдельную CI-приёмку. Добавлена ссылка «Редактор персонажей, событий и хронологии» на единой странице подготовки.
- Новый `source_editorial_review_page.dart` открывает все source-backed утверждения с поиском, разделами, страницами по 12, явным spoiler-gate и сохранением ручных вердиктов в отдельном checkpoint. Не повышает inferred до канона самостоятельно. Проверяет источник, quote status, fingerprint и не переписывает книгу/сейвы.
- `source_relations_review_panel.dart` теперь может показывать все пары имён, переходы глав и цитаты порциями, вместо прежних 4/3/6. Добавлены Flutter widget-тесты для UI, invalid sources, записи и отказа.
- Подробно: `docs/M2E4A_SOURCE_EDITORIAL_REVIEW_RU.md`. Статус **CODE / CI PENDING**. Не выдавать это за готовый многосценный игровой конструктор, автоматическую адаптацию книги или подключённый ИИ. Дальше — пройти exact-head CI (Dart/Flutter/Python/Windows/Android) и принять PR, затем строить полноценный многосценный редактор и physical QA.


## 2026-11-03 — M2e5a: многосценный редактор на существующем причинном движке

- База `main` M2e4a `5d5560e8cc7946fa65c8881fccc4ad7cf3441dab`, PR #29 MERGED; CI `41560992466` (core Python/Dart/Flutter/schema/Windows/Android success) и M0 `41560992271` SUCCESS. Релиз M2e5a ещё не опубликован.
- Ветка `feature/m2e5a-multiscene-authoring-20261103`: новый `multi_scene_editor_page.dart` + `multi_scene_draft_workbench.dart`; точка входа из существующей «Подготовки книги». Проверенную короткую адаптацию можно **копировать** в отдельный многосценный черновик: добавлять подтверждённые события, вручную писать альтернативы, редактировать переходы, флаги, условия/последствия, сохранять незавершённую работу и снова открывать её.
- Новая `SourceCheckpointScope.multiSceneDraft` сохраняется независимо от `intermediateDraft`; книги/сейвы не мигрируют. Итоговая проверка использует старые `PrivateAdaptationPreflight` + `IntermediateStoryBlueprint.validate`, включая полный обход игровых состояний и ≥2 финала. Сборка — прежним native worker + строгим ZIP/SQLite importer и `WorldLibraryGateway.install`, только с отдельным согласием privateUse.
- Тесты `multi_scene_draft_workbench_test.dart` и `multi_scene_editor_page_test.dart`, включая 5-сценную playable-проверку, проверку ложного канона, ошибок записи и локальной изоляции. Подробности `docs/M2E5A_MULTISCENE_EDITOR_RU.md`.
- Статус **CODE / CI PENDING** до exact-head CI и Windows/Android artifact: не заявлять готовой автоматическую адаптацию всей книги или live ИИ. После приёмки продолжить удобный редактор ролей/NPC/сюжетной схемы, device QA и M2f consent/BYOK.


## 2026-11-03 — M2e5b1: проверяемые карточки персонажей (кодовый этап)

- M2e5a уже **MERGED в main**: PR #30, commit `75626fe4`, CI `41562881526` — Python, Dart, schema, Flutter, Windows portable и Android APK PASS; M0 `41562881525` success. Физические проверки по-прежнему SKIP.
- Новая ветка `feature/m2e5b1-character-dossiers-20261103`. Добавлены `source_character_dossiers.dart` и `source_character_dossier_panel.dart`: карточки из exact-span цитат, поиск/страницы, помеченные гипотезы псевдонимов/отношений, сохранённые SAME/DIFFERENT без автоматического слияния одинаковых имён. Решения сохраняет только существующая `SourceRelationsReviewPanel`, после записи она сообщает карточкам об обновлении.
- Отозванные цитаты, чужая редакция и повреждённый checkpoint блокируют отображение идентичности. Нет новых сохранённых NPC/игровых данных и нет изменений книг, миров и `.bwsave`.
- Тесты `source_character_dossiers_test.dart`, `source_character_dossier_panel_test.dart`. Подробный документ `docs/M2E5B1_CHARACTER_DOSSIERS_RU.md`. **CODE / CI PENDING**, не сливать без exact-head Flutter/Dart/Python/schema/Windows/Android.
- Далее M2e5b2: полноценный ручной authoring персонажей и связей, реестр знаний/мотиваций/NPC, согласование сюжета, затем device QA и настройки ИИ с приватностью/лимитами; live ИИ ещё не подключён.


## 2026-11-03 — M2e5b1 ПРИНЯТ (точная CI-приёмка)

- PR #31 **MERGED** в `main`: `fb76e6ac8c86fdcc682325f4f79df5f360cff222`; проверяемый head PR: `9d1605f0fee636332b02d9374ff009e6bf39fd5b`.
- GitHub Actions `41564955358` **completed/success, 6/6 обязательных jobs PASS**: Python, Dart, контракты/BookWorld, Flutter analyze + widget, Windows portable, Android debug APK. M0 `41564955391` **completed/success**. Первое падение на двух неполных тестовых фикстурах устранено до приёмки; итоговый green run относится только к `9d1605f0`.
- Проверяемые карточки персонажей, псевдонимов и возможных отношений на существующей странице подготовки. Слияние имён только по подтверждённому SAME из `SourceRelationReviewSession`, никакого автоматического NPC-канона. Отзыв цитаты и повреждённый checkpoint — fail-closed; исходные книги/BookWorld/SQLite/`.bwsave` не мигрировались.
- Документ `docs/M2E5B1_CHARACTER_DOSSIERS_RU.md`. Физические Windows/Android/E2E, полный роман, авторская модель знаний/мотиваций и автоматическая адаптация — **SKIP / PENDING**, не приравнивать к автоматическим CI.
- **СЛЕДУЮЩИЙ ЭТАП M2e5b2:** безопасный редактируемый NPC-staging (имя/роль/мотивация/отношения/знания) на подтверждённых источниках; затем UX- и сквозной QA, после него — consent/BYOK/лимиты ИИ. Ни облачного API, ни модели пока нет.


## 2026-11-03 — M2e5b2: авторский редактор NPC перед подключением ИИ

- Последняя принятая база M2e5b1: PR #31 merged, `main` `fb76e6ac` + handoff `76f10718`; CI `41564955358` и M0 `41564955391` — PASS; `test-build-325` опубликован для Windows/Android.
- Рабочая ветка `feature/m2e5b2-npc-editorial-20261103`: `npc_editorial_notebook.dart`, `npc_editorial_page.dart`, точка входа из существующего редактора персонажей, событий и хронологии. Поддержаны имя адаптации, роль, мотивация, знание, секрет, связь с другим подтверждённым досье. Все записи явно авторские или снабжены подтверждённым цитатным `canonCandidate`; это не игровой канон и не скрытое объединение имён.
- Новый отдельный `SourceCheckpointScope.npcEditorial` хранит локальные заметки независимо от идентичностей/короткой/многосценной адаптации, книг и кампаний. Проверка точного набора цитат, источников, группы получателя связи, отпечатка редакции и SHA256 целостности. При отозванном доказательстве — явный блокер без потери данных, сброс только по подтверждению.
- Автотесты `npc_editorial_notebook_test.dart`, `npc_editorial_page_test.dart` + документ `docs/M2E5B2_NPC_EDITORIAL_RU.md`.
- **CODE / QA PENDING**: не мержить до exact-head CI (Python/Dart/BookWorld/Flutter/Windows/Android + M0). Физическое тестирование Windows/Android по-прежнему SKIP. Следующий блок — M2e5b3 (проверяемый игровой Actor adapter, знания, карта отношений, UX/длинные сценарии), затем отдельный M2f consent/BYOK/ключи/лимиты; live ИИ ещё нет.
