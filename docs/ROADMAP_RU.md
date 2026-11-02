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

- Сквозной UX/UI-аудит текущего Flutter-приложения (Windows/Android) оформлен в [docs/UI_UX_FINAL_AUDIT_M174C3_RU.md](docs/UI_UX_FINAL_AUDIT_M174C3_RU.md): все 12 основных пользовательских маршрутов, 17 устранённых замечаний, проверка старой M1.6 и новой BookWorld архитектуры, доступность, навигация, сохранения и ошибки.
- PR [#4](https://github.com/shonentez-afk/AI-Story-RPG/pull/4) **merged/squash** в `main`: **кодовый SHA `88a7c42091888bb81a62c68db49b7cd26f60f5e3`**. Проверенный HEAD PR: `92acae96aa016fb8638dc7dd6c6f77afe1216977`.
- GitHub Actions [#170 — run 41380322453](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41380322453): **completed/success, все 6/6 jobs PASS**, Flutter analyze **PASS**, Flutter widget/unit **92/92 PASS**, core/SQLite/BookWorld, Dart, Python **PASS**, Android debug APK **PASS**, Windows portable release **PASS**. Артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo` присутствовали в run #170.
- В одном «Мои прохождения» доступен **один импорт .bwsave** (v1 пилот или v2 BookWorld по `format`); v2 проходит read-only preview + повторную native валидацию и добавляет только новый слот. Отсутствующий exact BookWorld объясняется без записи. Главное «Продолжить» ориентируется на фактический свежий timestamp двух сто́ров. Одна библиотека и одна CTA «Добавить книгу» (TXT/FB2/.bworld), исправлены общая сортировка/поиск/empty states, отзывчивость загрузки и ошибок, русские характеристики, reader chrome F11/Esc для книги/пилота/BookWorld, WCAG >=7:1 для четырёх основных читательских палитр.
- Старые `CampaignStore`, `SaveStore`, `GameProgress`, `.bwsave v1`, `.bwsave v2`, SQLite schema и исходные TXT/FB2 не конвертировались и не перезаписывались. **Не внедрять** вторую библиотеку, альтернативный импорт книг, новый пилотный storage, автоматическую legacy миграцию или другое несогласованное главное меню.
- **Ручные QA gates / SKIP:** настоящий Android/Windows FilePicker, запись и повторное открытие резервного файла после экспорта, двусторонний перенос по отдельным устройствам, отсутствие переполнения/артефактов на физическом телефоне и Windows, Tab/Shift+Tab/Enter/F11/Esc с настоящей клавиатурой, TalkBack/Narrator, rotation/200%, power-loss recovery. Перечень и критерии: `docs/M174C3_PORTABILITY_RECOVERY_RU.md` и полный аудит. Статус физического QA не повышать на основании CI.
- Известный старый читательский долг: сохранение позиции в длинном TXT/FB2 после смены шрифта/ориентации использует pixel offset; source-paragraph anchor остаётся отдельным улучшением при расширении читалки, не условием возврата к общему редизайну. Новый M2 Book Compiler/AI пока не реализован и должен добавлять функции в **существующий** единый импорт/Library и отдельный мастер конверсии, не выдавая TXT/FB2 за готовую RPG.
- **Следующий функциональный этап M2:** сначала прочитать `docs/TZ_RU.md`, `docs/ROADMAP_RU.md`, `docs/UI_UX_FINAL_AUDIT_M174C3_RU.md`, `docs/M174C3_PORTABILITY_RECOVERY_RU.md`; начинать с настоящего HEAD `main`. Построить Book Compiler (TXT/FB2 → source chunks/anchors/provenance → coverage → blueprint → проверенный .bworld) по принципу fail-closed; сохранять все существующие функции и обновлять этот handoff.

### Freeze существующего UX/UI перед M2
Для M2 запрещено воссоздавать второе главное меню, вторую библиотеку или второй импорт TXT/FB2. Конверсия текста в игровой мир должна быть новой функцией **той же библиотеки**, с отдельными состояниями `not compiled / processing / verified / failed` и честными отчётами coverage. Любые новые экраны компилятора принимаются адресным UX-тестом, а не повтором полного аудита M1. Схема и сохранения M1 сохраняются.
