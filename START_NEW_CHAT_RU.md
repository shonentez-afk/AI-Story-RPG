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
