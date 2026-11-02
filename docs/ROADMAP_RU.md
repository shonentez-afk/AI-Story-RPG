# Дорожная карта AI Story RPG — «Живая книга»
**Дата базового плана:** 2026-11-01. **Статус:** план, ни один этап не объявлен завершённым без тестов.

## M0. Фиксация архитектуры и контрактов
- **Дополнительный обязательный spike (2026-11-01):** сравнить `story_engine` и `ink_dart+flutter_ink` на одном BookWorld-демо и общих Windows/Android тестах из [аудита движков](TEXT_RPG_ENGINES_GITHUB_AUDIT_RU.md); выбрать один runtime, не смешивать их состояния.
- ТЗ, ADR, соглашения по лицензиям и статусу; создать каркас Flutter monorepo (Android/Windows).
- Определить версии `.bworld` и `.bwsave`, JSON Schema, демонстрационную книгу без юридических ограничений и golden fixtures.
- Заложить CI: format/analyze/test для Dart и Python, проверка файлов и исключение секретов.
- **Готово, если:** минимальный Flutter app собирается на Windows и Android; тесты форматов проходят. Написанная документация — только часть M0.

## M1. Минимальный полезный офлайн-продукт (P0)
- Общий движок Dart: детерминированные условия/эффекты, действия, NPC, инвентарь, время, семантика выбора; локальная SQLite.
- Чтение .bworld и отдельные кампании .bwsave; автоматическое сохранение, история текста; импорт/экспорт через системный выбор файлов.
- 3 роли, 3 режима сюжета, 3 режима взаимодействия представлены в мастере; реально доступные комбинации определяются manifest.supported_modes. ИИ в M1 не включён; недоступные опции объясняются.
- Одна авторская демонстрационная история с >= 6 сценами, >= 2 концовками и >= 2 изменяемыми состояниями; Windows и Android должны дать идентичный результат при одинаковой последовательности.
- Русский UI: светлая/тёмная/сепия, размер шрифта, сенсорные элементы, сохранения.
- **Готово, если:** офлайн 20 ходов, перезапуск, экспорт/импорт сохранения, согласованные результаты обеих платформ, реальная сборка .exe и .apk.

## M2. Book Compiler / «Импорт книги» (P1)
- Python-модуль (отдельный инструмент/служба) + импорт на Android: TXT/FB2/EPUB сначала, затем PDF/DOCX.
- Полный проход по главам, контроль coverage, provenance, обнаружение персонажей/алиасов/мест/тайн/хронологии.
- Поэтапная обработка с checkpoint/retry, структурированные LLM-ответы, QA фактов и проверка достижимости.
- Генерация полностью офлайн-проходимых подготовленных сцен и проверка импорта в оба приложения.
- **Готово, если:** одно произведение из общественного достояния полностью обрабатывается и готовый пакет можно передать на Android для игры без сети. Никаких ложных «100% охвата» при пропущенных главах.

## M3. Живая история с ИИ (P1/P2)
- Абстрактный LLM-провайдер; стартовый Z.ai glm-4.7-flash BYOK, переключение на совместимые провайдеры.
- Нормализатор свободного действия -> проверка -> атомарная транзакция -> текст; гибридный ввод.
- NPC знания/убеждения/видимость секретов, альтернативные ветки, отмена и возврат к последней совместимой классической сцене без реткона.
- 100+ ходов воспроизводимого тестирования: исчезнувшие предметы, ожившие NPC, спойлеры, самовольные решения игрока.
- **Готово, если:** классическая игра остаётся работоспособной при выключенном ИИ; свободный ввод работает с заданной моделью и записывает проверяемые последствия.

## M4. Reader + polish + доставка (P2)
- Полноценный режим обычного чтения и переход от главы к игровой сцене при наличии подготовленного соответствия.
- Качество русских диалогов; доступность; опциональная TTS; иллюстрации только с учётом источников/лицензий.
- Изолированный инструмент ручного исправления BookWorld; библиотека адаптаций по разрешённым лицензиям; портирование iOS.
- Опциональная синхронизация без обязательной учётной записи; разрешение конфликтов через новые ветки.

## Очерёдность разработки
1. Схема форматов и демонстрационный пакет -> работающий общий runtime.
2. Кроссплатформенные тесты -> сборки Windows+Android.
3. Полная компиляция книги -> контроль причинности и сохранения.
4. Только затем свободная генерация с ИИ и адаптивная история.

## Реестр качества
На каждом этапе вести: commit SHA, фактически выполненные команды, число PASS/FAIL/SKIP, известные ограничения, список неизменённых/новых зависимостей. Не публиковать тесты как PASS по одному только чтению кода.

## Ближайшие подэтапы после M1.6.5
- **M1.6.5:** несколько локальных пилотных кампаний, автосохранение ходов, безопасная совместимость старого слота и UI выбора прохождения. Код и тесты добавлены; окончательная приёмка только после зелёного CI и проверки на устройствах.
- **M1.6.6:** переносимый `.bwsave` с проверяемыми версиями, book_id, campaign_id, проверкой содержимого, импортом/экспортом через системный диалог и отрицательными тестами. Утверждать совместимость Windows/Android только после двух сборок.
- **M1.7:** отдельный `story_core`, BookWorld fixture и schema-first контракты, тестовые 20+ ходов в UI, SQLite/Drift и миграция локальных слотов с реальным recovery. Не связывать с книгой в читалке без подготовленного BookWorld.
- **M1 QA gate:** Windows EXE и APK, автоматическая сверка сценариев/сейвов, формат/analyze/test, регрессия чтения и журнал QA с SHA.

## Статус M1.6.6 и критические оставшиеся работы
- **M1.6.6 исходники:** пилотный `.bwsave` (UTF-8 JSON) с хешированием, проверкой совместимости и импортом в новый слот. Готовность фиксировать только после Flutter/Dart/Python CI и Android APK. Не считать формат engine-neutral или пригодным для разных BookWorld.
- **M1.7:** формальные BookWorld schema + fixtures, независимый `story_core`, движок через `StoryRuntimeAdapter`, структурированный machine-readable event log, полнофункциональный `.bwsave` и миграции, SQLite/Drift, мастер режимов. Приоритет — воспроизводимое восстановление без привязки к внутреннему snapshot движка.
- **M1.8 / acceptance:** Windows EXE, Android APK, реальные импорт/экспорт и cross-platform 20+ ходов, точная позиция, UI/UX на устройствах, проверки отказа/повреждения и документы по PASS/FAIL/SKIP.

## Порог качества перед M1.7 (2026-11-02)
Приоритет восстановить PASS Flutter widget suite после рефакторинга очереди `CampaignStore` (кэш-специфичная очередь вместо глобального Future), затем Android/Windows артефакты. Вывод об исправлении и готовности `.bwsave` делать только по фактически завершённым GitHub Actions. Тесты должны охватывать восстановление legacy, быстрый выход из игры, несколько кампаний, импорт/экспорт и удаление без возрождения.

## UI/UX checkpoint перед следующим функциональным этапом (2026-11-02)
Кодовый аудит и UX hotfix M1.6.6: `docs/UI_UX_AUDIT_2026-11-02_RU.md`. Изменения старого интерфейса изолированы от `BookWorld`, `.bwsave` и сохраняемых данных. Следующая функциональная стадия M1.7 начинается после PASS Flutter analyze/widget + Android APK + Windows portable для нового HEAD; физическая Android/Windows/a11y проверка помечается SKIP, а не подменяется CI.

## UI/UX checkpoint: принят по автоматическому CI (2026-11-02)
Коммит исходников `8ca82afd0a71079cde9e08bdc28f17819ce6b436`, GitHub Actions `41332717865`: Python, Dart, Flutter analyze, 71/71 widget tests, Windows portable и Android APK **PASS**. Физические UI/a11y проверки Windows и Android **SKIP**. Полный отчёт `docs/UI_UX_AUDIT_2026-11-02_RU.md`. По просьбе пользователя переход к M1.7 оставлен до следующего отдельного шага.

## Начало M1.7 (2026-11-02)
- **M1.7.1:** первый реальный чистый Dart `story_core` и схема промежуточного original-demo blueprint: правила, факты, предметы, транзакционная проверка в памяти, replay по хешированному event log, 35-step test, отдельный blocking CI job. Подробности `M17_STORY_CORE_RU.md`. **Не** готовый .bworld и **не** UI интеграция.
- **M1.7.2:** StoryRuntimeAdapter и единый coordinator `story_engine` / `story_core`, без двух источников истины; миграционные тесты legacy M1.6.
- **M1.7.3:** BookWorld ZIP/SQLite/manifest/rights/checksums/import; не путать с JSON blueprint.
- **M1.7.4:** полноценный SQLite/Drift campaign, portable .bwsave, восстановление, UI 20+ ходов Android+Windows и QA.

## M1.7.2 — проверяемый runtime adapter (2026-11-02)
Новый изолированный Dart `packages/story_runtime_adapter` объединяет `story_engine` с `story_core` через candidate-commit, idempotent action, проверку выбора и верифицированный replay. Реализация и отрицательные тесты: `docs/M17_STORY_RUNTIME_ADAPTER_RU.md`. **Нет** SQLite, связи со старым `GameProgress` и `.bwsave`/читалкой; не выдавать этот этап за полную миграцию. Следующий M1.7.3 — BookWorld ZIP с manifest/world.sqlite; M1.7.4 — durable transactions и безопасная migration UI.

## Контрольная точка M1.7.2 — принят (2026-11-02)
`8fef11521c9f702414a6364c04b2350d30713b0d`, Actions `41337108811` SUCCESS. Прошли 10 unit тестов story_core, 9 bridge тестов, 6 schema тестов, 71 Flutter widget, Python/Dart, Android APK и Windows bundle. Следующий M1.7.3: контракт и проверяемый `.bworld` ZIP/SQLite (без нарушения существующей библиотеки), затем M1.7.4 durable SQLite/Drift, migration и UI 20+ turns. Подробности: `M17_STORY_RUNTIME_ADAPTER_RU.md`.

## M1.7.3 — реализация формата BookWorld (2026-11-02)
Кодовый этап: `docs/M17_BOOKWORLD_FORMAT_RU.md`. Есть пакет `packages/bookworld_format` (Dart) и Python builder, реальная ZIP/SQLite структура, versioned manifest, точные SHA/CRC, read-only проверка, оригинальный demo .bworld и security/unit contracts. **Не** подключён Flutter импорт, нет произвольных assets/source/ZIP compression, сохранений SQLite/Drift. Следующий M1.7.4 — приватная библиотека миров и кампаний, миграция `M1.6`, реальное Android↔Windows QA.

## M1.7.3 — принята контрольная точка (2026-11-02)
Код `7c3923492118a7aef9c9ecda3e0c319a2961499f`, Actions `41338634157` #143 `completed/success` (Python ZIP/SQLite 12, manifest+blueprint schema 9, core 10, adapter 9, BookWorld Dart 5, Flutter widget 71, Android и Windows PASS). Demo `.bworld` опубликован как artifact того же запуска. Далее M1.7.4 — подключить приватное SQLite/Drift хранилище, миграцию, UI-import и фактические E2E на обоих устройствах, без второй библиотеки.

## M1.7.4a — новый durable SQLite-слой без миграции legacy
Изолированная `packages/campaign_manager`: SHA-verified BookWorld catalog, SQLite WAL+FULL, атомарный journal+head, replay core+engine, portable `ai_story_bwsave_v2`, десять regression/security тестов. Документ `docs/M17_CAMPAIGN_SQLITE_RU.md`. **Следом M1.7.4b:** привязать к приложению через приватный путь, UI import/play/save, фоновый isolate, бэкап и legacy migration policy; потом Android+Windows E2E. Не путать наличие пакета с работающим пользовательским импортом.

## M1.7.4a — автоматическая контрольная точка принята
`cc69778586b45c3e82c4f1dc415ce2dc545b043e`, GitHub Actions `41340309393` (#145 SUCCESS 6/6). Чистый Dart SQLite `campaign_manager` 10/10 тестов, Python+Dart M0, core 10, adapter 9, BookWorld 5, schema 9, Flutter 71, Android+Windows PASS. Реальные UI-импорт/кампании в Flutter, legacy миграция и физические E2E остаются M1.7.4b. Подробности `M17_CAMPAIGN_SQLITE_RU.md`.

## M1.7.4b1 — новый игровой мир в единой библиотеке (2026-11-02)
Постоянный SQLite `campaign_manager` подключён к Flutter через isolate gateway и `path_provider`. Один старый импорт TXT/FB2 расширен на проверенный .bworld, отдельный мир появляется рядом с книгами, открывает реальные SQLite-кампании и настоящие Hero/Items/Journal, импорт/экспорт BookWorld .bwsave v2. Сквозные Linux Flutter widget/SQLite 35-turn проверки: `world_integration_test.dart`. **Дальше M1.7.4b2:** единый список кампаний (включая пилотные), безопасное удаление/backup и явная migration policy, читательский chrome для новых сцен, физические Android↔Windows/a11y тесты. Подробности `M174B_FLUTTER_BOOKWORLD_RU.md`.

## M1.7.4b2 — сведение новых/legacy кампаний в одном UX
Один общий экран `Мои прохождения` и один главный «Продолжить»: приоритет существующего пилотного слота, при его отсутствии новый BookWorld, данные хранятся и проверяются раздельно. Нет разрушительной миграции, новой библиотеки или дополнительной CTA импорта книг. Новые тесты для обеих навигаций; следующий этап backup/delete/reader chrome и физический Android/Windows acceptance. См. `M174B_FLUTTER_BOOKWORLD_RU.md`.

## M1.7.4b — завершение кодового UI QA
Исправленный `f4bf62c` (GitHub Actions #148) прошёл 78 Flutter tests, включая 35 реальных UI ходов через SQLite, native isolate, объединение сохранений и 320dp/200%; Android APK и Windows portable **PASS**, GitHub Actions #148 `41372851607` **completed/success (6/6)**. Дальнейшие задачи после платформенного PASS: безопасное удаление/backup, читательские режимы для новых сцен, сценарный план миграции legacy M1.6, реальный device E2E. `docs/M174B_FLUTTER_BOOKWORLD_RU.md`.

## M1.7.4c1 — резервирование и удаление BookWorld (2026-11-02)
Новая отдельная ветка `feat/m174c1-safe-backup-delete`: безопасный экспорт исходного .bworld; запрет удаления мира с кампаниями; SQLite транзакционное удаление кампании после replay и проверки ревизии; независимость форков; подтверждение и системный экспорт .bwsave v2 перед удалением. Тесты добавлены. Подробности в `docs/M174C_SAFE_BACKUP_DELETE_RU.md`. **CI ещё не подтверждён**, предыдущий PASS #148 только для M1.7.4b. Legacy сохранения M1.6 и TXT/FB2 не затрагивать.


## M1.7.4c1 — окончательная автоматическая приёмка (2026-11-02)
- PR [#1](https://github.com/shonentez-afk/AI-Story-RPG/pull/1) merged в `main` как `a37eb21afe82e8e93dfc43fcb2caabe580153c6b` (squash), проверенный PR HEAD `13239eb843d99787ce50b5d97e71695be54dca85`.
- GitHub Actions [#150, run 41374846035](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41374846035) — **completed/success, 6/6 PASS**: Python, Dart, story_core/BookWorld, Flutter analyze и **80/80 tests**, Windows portable release bundle, Android debug APK. M0 SDK checks также PASS (run `41374846010`).
- Первый PR CI `41374617867` завершился Flutter **79 PASS / 1 FAIL** из-за `pumpAndSettle timed out` в `world_integration_test.dart` при подтверждении удаления: фоновый indeterminate progress indicator продолжает анимацию. Тест исправлен ожиданием конкретного кадра перехода диалога (300 ms), **не отключением проверки SQLite**. Повторный Flutter 80/80 PASS.
- Функции: обязательный системный backup перед удалением `.bwsave v2` или пустого `.bworld`, RESTRICT против удаления мира с кампаниями, проверка expectedRevision в SQLite, полный replay, сохранение дочерних fork. Старые M1.6 SharedPreferences/книги TXT/FB2 не затронуты.
- **SKIP:** реальный запуск на физических Android/Windows устройствах, восстановление из системного FilePicker после копирования файла, внезапная потеря питания, старые M1.6 migration, Book Compiler/AI. Результаты CI относятся к PR SHA; если после squash запущен отдельный main CI — его статус проверять по факту, не додумывать.
- Дальше **M1.7.4c2**: унификация ReaderChromeMode normal/reading/fullscreen в новом BookWorld UI, доступность 320dp/200%, Windows keyboard, затем Android↔Windows device E2E и backup restore QA. Не создавать вторую библиотеку и вторую CTA импорта книг.

## M1.7.4c2 — общий BookWorld reader chrome (2026-11-02)
Реализован код UI режимов normal/reading/fullscreen и shared typography, F11/Esc для Windows, три новых Flutter/SQLite проверки. После подтверждения GitHub CI перейти к физическим Android+Windows E2E (импорт/экспорт .bworld/.bwsave v2, legacy migration policy) и лишь затем M2 Book Compiler. Матрица и ограничения: [M174C2_READER_CHROME_RU.md](M174C2_READER_CHROME_RU.md). Статус кода до CI — непроверенный.


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
- Документ [M174C3_PORTABILITY_RECOVERY_RU.md](M174C3_PORTABILITY_RECOVERY_RU.md) — пошаговый Android↔Windows E2E, меры перед удалением и **политика legacy M1.6**: не переводить старые rulesVersion=0/1 snapshots в новую схему без доказанной эквивалентности; старые слоты остаются доступны. Физическое тестирование устройств **SKIP**.
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

- Сквозной UX/UI-аудит текущего Flutter-приложения (Windows/Android) оформлен в [docs/UI_UX_FINAL_AUDIT_M174C3_RU.md](UI_UX_FINAL_AUDIT_M174C3_RU.md): все 12 основных пользовательских маршрутов, 17 устранённых замечаний, проверка старой M1.6 и новой BookWorld архитектуры, доступность, навигация, сохранения и ошибки.
- PR [#4](https://github.com/shonentez-afk/AI-Story-RPG/pull/4) **merged/squash** в `main`: **кодовый SHA `88a7c42091888bb81a62c68db49b7cd26f60f5e3`**. Проверенный HEAD PR: `92acae96aa016fb8638dc7dd6c6f77afe1216977`.
- GitHub Actions [#170 — run 41380322453](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41380322453): **completed/success, все 6/6 jobs PASS**, Flutter analyze **PASS**, Flutter widget/unit **92/92 PASS**, core/SQLite/BookWorld, Dart, Python **PASS**, Android debug APK **PASS**, Windows portable release **PASS**. Артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo` присутствовали в run #170.
- В одном «Мои прохождения» доступен **один импорт .bwsave** (v1 пилот или v2 BookWorld по `format`); v2 проходит read-only preview + повторную native валидацию и добавляет только новый слот. Отсутствующий exact BookWorld объясняется без записи. Главное «Продолжить» ориентируется на фактический свежий timestamp двух сто́ров. Одна библиотека и одна CTA «Добавить книгу» (TXT/FB2/.bworld), исправлены общая сортировка/поиск/empty states, отзывчивость загрузки и ошибок, русские характеристики, reader chrome F11/Esc для книги/пилота/BookWorld, WCAG >=7:1 для четырёх основных читательских палитр.
- Старые `CampaignStore`, `SaveStore`, `GameProgress`, `.bwsave v1`, `.bwsave v2`, SQLite schema и исходные TXT/FB2 не конвертировались и не перезаписывались. **Не внедрять** вторую библиотеку, альтернативный импорт книг, новый пилотный storage, автоматическую legacy миграцию или другое несогласованное главное меню.
- **Ручные QA gates / SKIP:** настоящий Android/Windows FilePicker, запись и повторное открытие резервного файла после экспорта, двусторонний перенос по отдельным устройствам, отсутствие переполнения/артефактов на физическом телефоне и Windows, Tab/Shift+Tab/Enter/F11/Esc с настоящей клавиатурой, TalkBack/Narrator, rotation/200%, power-loss recovery. Перечень и критерии: `docs/M174C3_PORTABILITY_RECOVERY_RU.md` и полный аудит. Статус физического QA не повышать на основании CI.
- Известный старый читательский долг: сохранение позиции в длинном TXT/FB2 после смены шрифта/ориентации использует pixel offset; source-paragraph anchor остаётся отдельным улучшением при расширении читалки, не условием возврата к общему редизайну. Новый M2 Book Compiler/AI пока не реализован и должен добавлять функции в **существующий** единый импорт/Library и отдельный мастер конверсии, не выдавая TXT/FB2 за готовую RPG.
- **Следующий функциональный этап M2:** сначала прочитать `docs/TZ_RU.md`, `docs/ROADMAP_RU.md`, `docs/UI_UX_FINAL_AUDIT_M174C3_RU.md`, `docs/M174C3_PORTABILITY_RECOVERY_RU.md`; начинать с настоящего HEAD `main`. Построить Book Compiler (TXT/FB2 → source chunks/anchors/provenance → coverage → blueprint → проверенный .bworld) по принципу fail-closed; сохранять все существующие функции и обновлять этот handoff.

### Freeze существующего UX/UI перед M2
Для M2 запрещено воссоздавать второе главное меню, вторую библиотеку или второй импорт TXT/FB2. Конверсия текста в игровой мир должна быть новой функцией **той же библиотеки**, с отдельными состояниями `not compiled / processing / verified / failed` и честными отчётами coverage. Любые новые экраны компилятора принимаются адресным UX-тестом, а не повтором полного аудита M1. Схема и сохранения M1 сохраняются.


## M1 финальная читательская доработка / переход M2 (2026-11-02)
- Пользователь подтвердил, что реальных старых игр/прохождений M1.6 не было. **Не тратить работу на миграцию/дополнительный backup демо-сейвов M1.6**, не удалять автоматически прежние файлы/ключи; рабочий формат новых игр — BookWorld SQLite и `.bwsave v2`.
- PR [#5](https://github.com/shonentez-afk/AI-Story-RPG/pull/5), ветка `feat/m1-reader-anchor-and-m2-foundation-20261102`: `BookReadingState.anchorBlock/anchorFraction`, lazy `CustomScrollView.center`, восстановление позиции по абзацу после font/line/width/rotation, fallback pixel-only и тесты. Отчёт [M1_READER_SOURCE_ANCHOR_RU.md](M1_READER_SOURCE_ANCHOR_RU.md).
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


## M2b2 — ПРИНЯТ И ОБЪЕДИНЁН, следующий M2b3 (2026-11-02)
- PR [#8](https://github.com/shonentez-afk/AI-Story-RPG/pull/8) **MERGED/squash в main**: итоговый кодовый SHA `e704cdf47d1b30816c65ac68a6ab49315597aa4e`; исходный проверенный PR HEAD `b4d5958fa19d2224f3fffd1ef5800a56db312cee`.
- Подтверждён [GitHub Actions 41401389861](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41401389861): **completed/success, 6/6 jobs PASS**. Python PASS, Dart PASS, story_core/BookWorld/SQLite PASS, Flutter analyze PASS, **112/112 Flutter widget/unit PASS**, Android debug APK PASS, Windows portable release PASS. В Actions присутствовали артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo`.
- M2b2 добавил приватные ApplicationSupport checkpoints для M2b1 с flush+same-directory rename, восстановление анализируемых source chunks, локальную порционную обработку в isolate, прогресс и ручное принятие/отклонение **только текстовых упоминаний** в существующем едином экране «Подготовка книги». Спойлеры скрыты до явного запроса, есть retry и подтверждённый reset анализа. Подробности `docs/M2B2_CHECKPOINT_REVIEW_RU.md`.
- Старые TXT/FB2, reader anchors, единая библиотека/одна кнопка импорта, настройки, BookWorld SQLite, `.bwsave v1/v2`, демо-сохранения **не переписывались и не удалялись**. Никакой новой библиотеки/дублирующей CTA. Не мигрировать лишний раз старые демо-слоты M1.6.
- **Не реализовано:** факты/события/родственные связи, cross-chapter alias resolution, spoiler-safe canon graph, AI Book Compiler, произвольный `.bworld` из книги; `gameplay_coverage=0`, `can_publish_bookworld=false`. **Ручные QA SKIP:** реальные Android/Windows устройства, FilePicker E2E, TalkBack/Narrator/клавиатура, power loss, долгие книги 20 МиБ / 30 000 чанков. CI не подтверждает эти тесты.
- **Следующий этап M2b3:** структурированный evidence-backed extraction (персонажи/алиасы/места/факты/события), явный статус CONFIRMED/INFERRED/CONFLICTED/INVENTED, provenance и temporal/spoiler gates, cross-chapter reconciliation/human review; сначала схема + тестовые оригинальные истории, затем интеграция в существующую подготовку книги. Нельзя объявлять извлечение готовым сюжетом или публиковать BookWorld до валидатора intermediate blueprint.
- Если документальный HEAD после этого отличается от кодового SHA из-за `[skip ci]`, принимать за кодовую контрольную точку `e704cdf4`/PR HEAD `b4d5958` и CI 41401389861; новые функциональные изменения должны получать собственную CI.


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

## ПРИНЯТО 2026-11-02 — видимая корзина в библиотеке и test-build-260
- По скриншоту пользователя убрано избыточное меню «⋮», содержавшее единственный пункт удаления. В карточке импортированной книги теперь отдельная кнопка-корзина `Icons.delete_outline`, tooltip «Удалить книгу», key `library-delete-<id>` и цвет предупреждения. Касание вызывает прежний диалог подтверждения; кнопки «Читать»/«Подготовить к RPG», файлы книг, игровые сейвы, сохранения позиции не менялись.
- PR [#17](https://github.com/shonentez-afk/AI-Story-RPG/pull/17) **MERGED**, кодовый squash `180e32995e71e609fe303cad6db927f0420ed239`; протестированный HEAD `a33ea3f5c436622774cfc8e9aa07bb18edc9e10f`. PR CI `41424400911`: 6/6 PASS, **161/161 Flutter-тестов PASS**, Windows portable и Android debug APK PASS, M0 SDK `41424401023` PASS. Дополнительно проверены отмена, подтверждение, ошибка хранения без удаления и 320dp при масштабе текста 200%.
- Push(main) [CI `41425466744`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41425466744) **7/7 PASS**, включая Windows, Android и отдельную публикацию релиза.
- Новый [GitHub Release `test-build-260`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-260) опубликован `2026-11-02T10:08:56Z`, target **кодовый commit `180e32995e71e609fe303cad6db927f0420ed239`**:
  - [Windows ZIP](https://github.com/shonentez-afk/AI-Story-RPG/releases/download/test-build-260/AI-Story-RPG-Windows-portable.zip), 13 238 463 bytes, SHA256 `fcadfe2c264e907a82b6553795da50d0394e0c6dc7ae6c134203b7ec84ead713`.
  - [Android APK](https://github.com/shonentez-afk/AI-Story-RPG/releases/download/test-build-260/AI-Story-RPG-Android-debug.apk), 167 209 424 bytes, SHA256 `b832b719b1612b1b0980ad281536632973b0101ecfb3d4442457eabaf041c610`.
  - `SHA256SUMS.txt` присутствует. Все три актива GitHub Release проверены, state=uploaded.
- Старые test-build-258/256 **не содержат новую корзину**. Для проверки новой версии нужно переустановить/распаковать test-build-260. Ручной E2E на реальном устройстве остаётся SKIP; не путать CI PASS с проверкой всех физических устройств. Следующий функциональный план M2b4 semantic provider, но текущая UX-корзина уже завершена.


## Обновление 2026-11-02 — следующий кусок M2b4

M2b4a1 provider boundary: **ACCEPTED** (PR #18, exact head `05a399c2`, CI `41427964306` PASS, M0 `41427964385` PASS, merge `13e9c0eb`). M2b4a2 semantic checkpoint+возобновление+UI: **CODE / отдельный CI PENDING**. Затем M2b4b source-backed semantic extraction (с реальной проверенной моделью, только после настройки/согласия для облака); M2c validator+intermediate blueprint; исключительно после этого playable BookWorld для пользовательской книги. Пока никаких ложных «AI RPG готово».


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


## 2026-11-02 — уточнена последовательность до интеграции ИИ

Сначала завершить M2b4b модельно-независимую семантическую схему и проверку первоисточника, M2c intermediate blueprint + причинный симулятор, затем M2d accepted book-derived `.bworld` builder/importer (не подменять `original_demo`), проверку приватности/прав и единый UI-оркестратор. Только ПОСЛЕ безопасного API/JSON/rights gate можно активировать настоящую модель; полная автоматическая смысловая экстракция до этого невозможна. Ветка `feature/m2b4b-m2c-pre-ai-validation-20261102`, аудит `docs/M2_PRE_AI_READINESS_AUDIT_RU.md`. Статус кодовой ветки CI PENDING.


## 2026-11-02 — M2b4b/M2c validated scaffold accepted, M2c editorial continuation

- PR #21 merged squash `a8b016e3bd4ebf6855fe7b81cc861b566b078a3b`; exact test head `69fc30289f0131b130bd448d56374b2ffc907fd8`. GitHub Actions `41447576581` 6/6 PASS, Flutter **187/187**, Windows portable and Android debug PASS. M0 `41447576604` PASS. Semantics remain INFERRED, draft can't publish.
- Следующая ветка `feature/m2c-editorial-checkpoints-readiness-20261102`: `source_semantic_editorial_review.dart`, read-only `preparation_readiness_report.dart`, 3 приватных checkpoint scopes, regression `pre_ai_editorial_readiness_test.dart`, `docs/M2C_EDITORIAL_CHECKPOINTS_RU.md`. **Её CI ещё НЕ принят.**
- Before AI important M2d separate: current Python+Dart `.bworld` allow only `original_demo`. Production personal adaptation must get separate package/rights/provenance validator, don't weaken old demo by just changing a string. Need usable one-button preparation flow and actual short-story E2E; no false "ready".


## 2026-11-02 — PR #22 accepted; M2 offline one-click pipeline

- PR #22 exact tested head `6144bc96520bf5b49577f5dab6000d7fda53609c`, core CI `41449001964` 6/6 PASS + M0 `41449001948` PASS, merge code SHA `95c99fb796f4f36dedc514958101bea98adb6684`. Editorial checkpoint, readiness report, new private scopes landed.
- Ветка `feature/m2-preparation-one-click-offline-20261102` содержит **ещё не принятый** one-click offline local-preparation coordinator (mentions M2b1 → M2b3b events → source-cited M2b4b catalog), сохранение каждой порции, pause/resume, worker isolates, UI `prepare-offline-all`. Добавлены отдельные тесты и документ `docs/M2_OFFLINE_PREPARATION_PIPELINE_RU.md`. Персонажи, локации, alias hints, встречи, события и состояния — только INFERRED, не канон.
- M2d компилятор пользовательского `.bworld` на короткой книге, типизированный перевод intermediate scene → StoryBlueprint, права/верификация источников и полноценный ИИ **ещё не завершены**. Ни один кодовый путь не помечает произвольную книгу готовой.
- Не мержить этот следующий этап без exact-head Flutter analyze/test, Python/Dart/world, Windows/Android; не удалять старые сохранения, приватные checkpoints, отдельный импорт.
