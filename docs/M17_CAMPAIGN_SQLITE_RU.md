# M1.7.4a — транзакционный каталог BookWorld и независимые кампании SQLite

**База:** документационный HEAD `562a933e51f3e020889a8790d064fb46eb41a90d`. Проверенная исходная база M1.7.3: `7c3923492118a7aef9c9ecda3e0c319a2961499f`, GitHub Actions #143 `41338634157` SUCCESS, Flutter 71/71 и оба платформенных билда PASS.

## Реализация нового модуля

`packages/campaign_manager` — самостоятельный native Dart пакет, без Flutter и без `SharedPreferences`/старых слотов M1.6. Он использует `bookworld_format` только для проверки готового ZIP+SQLite мира и `StoryEngineCoordinator` для подтверждения игровых действий.

- `BookworldCampaignStore.openPrivateDirectory(path)` создаёт **отдельный** `bookworld_campaigns_v1.sqlite` в приватном каталоге, переданном вызывающим приложением. Schema v1 помечена `application_id=ASRP`, `user_version=1`; незнакомые версии отказываются открываться, автомиграций и перезаписи чужих схем нет.
- `PRAGMA foreign_keys=ON`, `trusted_schema=OFF`, `journal_mode=WAL`, `synchronous=FULL`, integrity/foreign key check. Ровно четыре таблицы: `meta`, `bookworlds` (проверенный .bworld blob + SHA-256), `campaigns` (идентификатор, BookWorld hash, parent ID, revision, state/head hash, дата), `events` (монотонный sequence, action_id, канонический JSON, event hash). Ограничение **2000 ходов** на новую кампанию.
- `installBookworld` полностью проверяет ZIP, hashes и сам SQLite **до** записи в каталог; одинаковый мир дедуплицируется по точному hash, другие редакции допускаются отдельным BookWorld.
- `createCampaign` создаёт независимую кампанию без изменения сохранений `ai_story_m1_intro`.
- `commitChoice`: `BEGIN IMMEDIATE`, загрузка и проверка полного сохранённого журнала, восстановление через `story_core`+ `story_engine`, `choose` в кандидатных состояниях, затем **атомарно в одной SQLite транзакции** `INSERT INTO events` + `UPDATE campaigns` на expected revision. Любой сбой хранилища делает ROLLBACK без наполовину сохранённого хода. Повтор action_id идемпотентен; старые revision и недопустимые choice не фиксируются.
- `loadCampaign` заново проверяет полный журнал, event hashes, точное соответствие blueprint SHA, head revision/state SHA и навигацию `story_engine`; не выдаёт повреждённое состояние как успешное восстановление.
- `exportPortable` / `importPortable`: собственный **`ai_story_bwsave_v2`**, только для new BookWorld, точный `world_sha256`, source campaign ID как метаданные, role=PROTAGONIST, plot=CANON, interaction=CLASSIC, проверяемый checkpoint и SHA-256 envelope. Импорт после replay создаёт **новый локальный campaign ID**, не затрагивает исходный и другие слоты. Лимит 2 МиБ. Для импорта требуется заранее установленная точная версия BookWorld: экспорт не содержит текст книги или внешний API-ключ.

## Тесты и CI

`packages/campaign_manager/test/campaign_manager_test.dart`:
1. Дедупликация проверенного ZIP и запрет повреждённого BookWorld.
2. **35 подтверждённых действий**, закрытие SQLite на 23-м ходе, открытие того же файла, доигрывание до финала с проверкой инвентаря/секретов/хеша.
3. Отклонённые, устаревшие и повторные action_id без дополнительного event.
4. Две кампании — независимый инвентарь, разные окончания.
5. Новый engine-neutral save v2 — export→import в другую кампанию, продолжение без влияния на оригинал.
6. Повреждённые/несовместимые save, включая подделанный внешний checksum при внутренне урезанном журнале.
7. Подмена события в SQLite — загрузка запрещена.
8. Искусственная ошибка SQLite при INSERT: полностью проверенный ROLLBACK; после снятия ошибки игра продолжается.
9. Неизвестная DB schema version и повреждённый BookWorld BLOB отвергаются.

GitHub Actions `story-core` теперь дополнительно запускает `dart pub get`, `dart analyze`, `dart test` для `packages/campaign_manager`. Он уже блокирует публикацию APK/Windows при FAIL. Ссылки на действительный run/commit и итог PASS вписать **только после выполнения CI**.

## Ограничения, которые нельзя выдавать за готовые

- **M1.7.4a не полный M1.7.4.** Старый Flutter UI всё ещё работает через `GameProgress`, `CampaignStore` и `SharedPreferences`. Новая база пока не подключена к интерфейсу, не вызывает `path_provider` и не перехватывает файл через `file_picker`. Обещать UI-кнопку .bworld или физический Android↔Windows runtime QA пока нельзя.
- **Legacy migration ещё отсутствует**: это намеренно, чтобы не потерять правила `rulesVersion=0/1`, старые `.bwsave` и сохранения `ai_story_m1_intro`. Понадобятся экспорт/бэкап, сравнение двух графов сценария и явная политика перевода либо параллельного хранения.
- **Сейв v2** — engine-neutral, но строго ограничен original-demo BookWorld/CLASSIC и не включает RNG, несколько ролей, живые NPC/ИИ, ссылки на реальную книгу. Это не готовый универсальный .bwsave из ТЗ.
- **Crash guarantee** относится к SQLite-транзакции подтверждённого хода (WAL+FULL) после возврата из COMMIT. Дисковая надёжность устройства, полный power-off и перенос файла БД между платформами в этом CI не проверены: SKIP.
- **SQLite вместо Drift:** сейчас чистый sqlite3 FFI с явными миграционными версиями; Drift может быть принят позже без изменения внутреннего формата. Не выдавать отсутствие Drift за реализацию заявленного UI persistence layer.
- **Синхронный native Dart API** необходимо вызывать из отдельного isolate при подключении Flutter, не блокировать UI. Нет защищённого от внешнего противника криптографического MAC/подписи, только SHA-256 целостности и replay.
- **UI/UX** не менялись, поэтому сохраняется одна библиотека и одна кнопка импорта книг TXT/FB2.

## Следующий подэтап M1.7.4b

Интеграция BookWorldStore с `path_provider`, file picker/изоляцией native работу в отдельном isolate, минимальная панель запуска подготовленного мира в существующем интерфейсе, сохранение после каждого хода и отображение отказов; совместимость M1.6 через неизменный старый стор и явную миграцию только при подтверждении. Затем реальные Android/Windows 20+ ходов, перенос .bwsave v2, отказ от подделанных ZIP и визуальный/a11y аудит.
