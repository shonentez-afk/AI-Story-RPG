# Текущий статус AI Story RPG
**Дата актуализации:** 2026-11-02. **Состояние:** M1.7.4c3 + UX/UI M1.7 baseline принят CI #170 (6/6, Flutter 92/92); аппаратный Android/Windows E2E — SKIP.

## Подтверждено
- Репозиторий `shonentez-afk/AI-Story-RPG` доступен для записи, создан начальный README.
- Единое ТЗ сохранено в `docs/TZ_RU.md`.
- Проанализированы источники NovelToGame, AnyWorld, Mørkyn, Project Lunar, PlotTwist и библиотеки для обработки документов.
- Выбрана проектная архитектура Android+Windows, Flutter/Dart, Python Book Compiler, `.bworld`, `.bwsave`, offline-first, Z.ai как первый опциональный LLM.

## НЕ подтверждено
- Нет работающих Flutter приложений, Android APK, Windows EXE, готовых игровых BookWorld или автоматического компилятора книг.
- Не выполнены интеграционные, функциональные и мобильные испытания.
- Не подтверждены числовые лимиты/качество API конкретного аккаунта Z.ai.
- Нет подключённых ключей или моделей; они не должны попадать в репозиторий.

## Следующая задача
Запустить M0: Flutter monorepo + проектные схемы BookWorld/Save + тестовая история + CI и фактическая сборка на Windows/Android. После реализации обновить статус со ссылками на коммит и реальными результатами тестов.

## Новое утверждённое решение (2026-11-01)
В нормативное ТЗ версии 0.2 внесён обязательный M0-пилот двух готовых Dart runtime: `story_engine` и `ink_dart + flutter_ink` на одной демонстрационной истории, с офлайн-проверками, сохранением/восстановлением, Android/Windows и выбором **одного** решения через ADR. Аудит зафиксирован в `docs/TEXT_RPG_ENGINES_GITHUB_AUDIT_RU.md`. **Фактически движки ещё не встроены, испытания не выполнены**.

## M0: практический старт 2026-11-01
- В `experiments/m0_engine_comparison/` добавлены единый `scenario.json` (11 сцен, 21 выбор, 3 концовки), Python-генератор Ink и 4 unit-теста.
- В локальной исполняемой среде выполнено `python3 pilot/compile_pilot.py` и `python3 -m unittest discover -s tests -v` на эквивалентном тестовом сценарии: **4 PASS, 0 FAIL**; код сценария и тестов перенесён в GitHub.
- **Не выполнено:** компиляция Ink (`inklecate` не установлен), тестирование с `ink_dart` и `story_engine` (нет Dart/Flutter), Windows/Android сборки, проверка сохранений через реальные движки.
- Следующий шаг: установить SDK на подходящей build-машине, создать Dart-адаптеры к обоим движкам, запустить одинаковый набор ходов, save/restore и принять ADR.

## M0 — продолжение: автономный reference runner
- В `experiments/m0_engine_comparison/pilot/reference_runtime.py` реализован независимый Python-эталон исполнения сценария: условия, эффекты, журнал событий, проверки повторного action_id, save/restore с перепроигрыванием и fingerprint исходного сценария. Это **тестовый oracle**, не будущий Flutter runtime.
- Добавлен `tests/test_reference_runtime.py` с проверками развилок, трёх концовок, 20+ ходов, tampered save, несовместимых сохранений, независимых веток.
- **Локальный запуск** эквивалентного пакета: `python3 -m unittest discover -s tests -v` → 17 PASS / 0 FAIL (4 старых + 13 новых тестов); код oracle и 10 переносимых тестов записаны в GitHub (размер и состав исходных тестов в GitHub и локальной копии отличаются, поэтому число 17 не считать GitHub CI результатом).
- **SKIP**: Dart и Flutter SDK отсутствуют; `story_engine`/`ink_dart` на устройствах не запущены, Windows/Android проверки не выполнены. Для честного решения о движке необходим действительный Dart/Flutter прогон.

## M0 — подготовка установки Dart/Flutter
- Проверено в текущем контейнере: Linux, установлен Git/Python, **нет `dart`/`flutter`**; прямой `git ls-remote` к GitHub завершился `Could not resolve host`. Установка SDK в этот контейнер не выполнена.
- Добавлены `docs/SETUP_FLUTTER_RU.md` (Windows, Android, Linux, PATH, SDK, Android Studio/Visual Studio) и `.github/workflows/m0-sdk-and-tests.yml` (GitHub Actions для установки Flutter stable на runner и Python unittest).
- В текущей смонтированной локальной копии `ai_story_m0` запущено `python3 -m unittest discover -s tests -v`: **25 PASS / 0 FAIL**; наличие дополнительных файлов локальной копии отличается от репозитория, поэтому результат **не считать проверкой GitHub CI**.
- **Не подтверждено:** успешное выполнение нового GitHub Actions workflow, наличие Flutter SDK на устройствах, Dart/Flutter сборки и прохождение игры через `story_engine`/`ink_dart`.

## CI: переход на CircleCI (2026-11-01)
- В репозитории создан `.circleci/config.yml` с заданиями `reference-tests` (Python сценарий и unittest) и `dart-sdk` (скачивание официального Dart Stable SDK на Linux runner, проверка версии и сохранение артефакта).
- GitHub Actions ранее завершался до выдачи runner, поэтому этот CI рассматривается как основной для M0.
- **Не подтверждено:** привязка репозитория к CircleCI, запуск pipeline, успешная загрузка Dart SDK или PASS тестов в CircleCI. Требуется подключить проект в CircleCI и проверить Pipelines.
- Среда CircleCI изолирована от текущего ChatGPT контейнера; SDK не устанавливается сюда автоматически.

## M0 — устранение совместимости SDK и API (2026-11-01)
- Пользователь сообщил об успешном зелёном CircleCI после первоначального подключения. Этот результат относится к указанному пользователем запуску; новые правки требуют отдельного прогона.
- Проверена публичная документация `story_engine`: вместо неверно указанного `StoryDirectTransition(targetEventId: ...)` в `story_engine_smoke/bin/smoke.dart` применён документированный `StoryEventTransition(destinationEventId: ...)`.
- Для `ink_dart_smoke` зависимость зафиксирована по Git commit `a87f2ee1c1fbfc80f9f22483567fce91f133a18a` и пути `packages/ink_dart` для воспроизводимого тестирования без догадок о доступности версии в pub.dev.
- В CircleCI запускаются проверки эталонного сценария, пять контрактных трасс, `story_engine` smoke, компиляция Ink и `ink_dart` smoke. **Их итог после последних коммитов пока не известен**; не считать `PASS` до проверки actual CircleCI logs.

## M0 — полный сравнительный тест Ink (2026-11-01)
- В `experiments/m0_engine_comparison/ink_dart_smoke/bin/full_scenario.dart` добавлено прохождение пяти эталонных маршрутов на настоящем API `ink_dart`, с проверкой финального текста, состояния игровых переменных, концовок и сериализации/восстановления Ink state.
- В `.circleci/config.yml` добавлен `dart run bin/full_scenario.dart ...` после компиляции `manor_mystery.ink` с помощью `inklecate`.
- Особенность сравнения: engine-neutral идентификаторы выборов сопоставляются с Ink по тексту внутри текущей сцены; при совпадающих текстах тест специально останавливается. Для промышленной версии нужен генератор устойчивых ID/tags.
- **Результат CI после коммита ещё не подтверждён**; нельзя объявлять `story_engine` или `ink_dart` успешно прошедшим пять маршрутов до изучения логов CircleCI. Сами адаптеры могут потребовать исправлений после первой реальной компиляции.

## M0 — нагрузочный тест 1000 сцен
- Добавлен `pilot/generate_stress.py`: воспроизводимая линейная история из 1000 сцен и 999 переходов.
- Добавлен `story_engine_smoke/bin/stress.dart`: проверка всех переходов, переменной `visited`, snapshot/restore и измерение времени.
- Тест генератора находится в `tests/test_stress_generator.py`; CircleCI запускает stress после проверки полного сценария.
- **Итоги CircleCI ещё не проверены**: benchmark создан и включён в pipeline, PASS и производительность пока неизвестны.

## M1 start — Flutter reader scaffold / ADR-001 (2026-11-01)
- Принято ADR-001: `story_engine 0.1.0-alpha.1` — основной runtime; `ink_dart` — необязательный адаптер Ink, авторитетное состояние BookWorld остаётся под нашим контролем.
- Созданы `apps/story_reader/pubspec.yaml`, `apps/story_reader/lib/main.dart`, `apps/story_reader/README_RU.md`: начальный Flutter host, текст, кнопки выборов, старт/повтор, внутрисессионный снимок состояния и восстановление.
- **Не подтверждено:** `flutter analyze`, Flutter widget tests, сборки Android/Windows; нет платформенных каталогов, файловых сохранений, загрузки книг и AI. M1 prototype — исходники, пока не выпускаемый APK/EXE.

## M1 — persistent saves and Flutter CI (2026-11-01)
- `apps/story_reader/lib/save_store.dart`: один локальный слот сохранения на основе shared_preferences; `main.dart` сохраняет snapshot при нажатии кнопки и восстанавливает его в другом запуске, обрабатывает ошибки. Это временный M1 формат, не `.bwsave`.
- Добавлен `apps/story_reader/test/reader_test.dart` — widget smoke сцены и перехода.
- В `.circleci/config.yml` добавлен отдельный job `flutter-reader`: загрузка Flutter stable, `flutter pub get`, `flutter analyze`, `flutter test`.
- **CI ещё не подтверждён:** проверка Flutter, сборка Android APK/Windows EXE и установка на устройство пока не выполнены. Реальный локальный persistent save требует проверки после сборки.

## M1.1 — Главное меню и оболочка (2026-11-01)
- Добавлен `apps/story_reader/lib/home_page.dart`: стартовое меню (Продолжить, Новая история, Библиотека, Настройки), библиотека с демо, информационный экран настроек.
- `main.dart` переключён на домашнюю страницу; `StoryReaderPage(resume: true)` загружает существующий единственный слот, новая история запускается независимо от сохранения.
- Добавлен `test/home_test.dart`; существующий `test/reader_test.dart` адаптирован к новому меню.
- Android APK генерируется существующим `android-apk` заданием. **CI после этих коммитов ещё не проверен**. Библиотека пока содержит только демо, импорта книг нет.

## M1.2 — начальный импорт TXT/FB2 и обложек (2026-11-01)
- Добавлены `book_import.dart`, `book_storage.dart`, `book_reader.dart`: UTF-8 TXT, XML FB2 (название, автор, разделы), разрешённое PNG/JPEG изображение обложки из FB2 `<coverpage><image href='#id'/></coverpage>` + `<binary id='id'>`.
- Обложка сохраняется локально вместе с книгой и показывается в библиотеке и читателе; при отсутствии/ошибке обложки — стандартная иконка.
- `home_page.dart`: кнопка импорта TXT/FB2, просмотр импортированных книг, постоянная локальная библиотека. Геймплей и сохранения M1.1 сохранены отдельно.
- Ограничения: пока только UTF-8, максимум 20 МБ входной книги и 8 МБ обложки, без FB2 ZIP, EPUB и превращения книги в RPG; большие FB2 и вложенные секции требуют дальнейшего расширения.
- **Важное:** CI Flutter/Android после новых коммитов ещё не проверен. Код может потребовать исправлений после `flutter analyze/test` и проверки на телефоне.

## UI research — reading + gameplay (2026-11-01)
- Создан `docs/READER_AND_GAME_UX_RU.md`: исследование GitHub референсов KOReader, Liseur, flutter_readium, Papyrus Reader, lumina, Atrament Web UI. Зафиксированы общий слой чтения, переключение контекстов чтение/игра, темы, типографика, управление на телефоне и Windows, размещение обложек, панель игрового состояния, приоритеты реализации и приёмка.
- Решение: UX проектировать сейчас, внедрять по шагам; пока **только спецификация**, изменение Flutter интерфейса по требованиям этого документа ещё не выполнено. Сторонний код не копировался.

## M1.2.x — настройки чтения (2026-11-01)
- Добавлен `apps/story_reader/lib/reading_preferences.dart`: темы Light, Sepia, Dark, OLED и постоянные настройки размера текста, межстрочного интервала, полей через shared_preferences.
- `book_reader.dart` применяет настройки на экране импортированной книги; кнопка в верхней панели открывает выбор темы и слайдеры. Обложка FB2 продолжает использоваться в библиотеке и карточке.
- `test/reading_preferences_test.dart`: проверки сохранения и ограничения некорректных значений. Блок тем адаптирован к узким экранам.
- **Новый Flutter CI и APK после этих изменений ещё не подтверждены**. Режим читалки оснащён настройками, игровой экран пока на стандартной теме; применение общего ReaderSurface и сохранение позиции книги — следующие задачи.

## M1.2.1 — FB2 inline illustrations (2026-11-01)
- Добавлены упорядоченные `BookBlock`/`BookChapter`/`BookImage` и будущий игровой контракт `SceneMediaBinding`.
- Импорт FB2 выделяет внутренние иллюстрации и сохраняет порядок с текстом, JSON schema 2; schema 1 по-прежнему читается.
- Читалка показывает изображения внутри книги и увеличивает по нажатию; добавлен тест вложенных секций/порядка иллюстраций.
- Файл `docs/MEDIA_IN_GAME_IMPLEMENTATION_PLAN_RU.md` фиксирует дорожную карту до игровых привязок и ограничений спойлеров.
- **CI и APK после этих изменений пока не проверены; игровые привязки только модель, ещё не подключены к движку.**

## Переход с CircleCI на GitHub Actions (2026-11-01)
- Создан `.github/workflows/android-ci.yml` (Python reference, Dart engine/probe/stress/Ink, Flutter analyze/test, Android debug APK).
- APK публикуется артефактом `AI-Story-RPG-Android-debug` с файлом SHA256SUMS.txt (после зелёного workflow).
- Удалён `.circleci/config.yml`, чтобы не запускались две CI-системы. Подключение CircleCI к GitHub и будущие уведомления могут отдельно отключаться пользователем в интерфейсе CircleCI.
- Ветка `main`, push / pull request / manual workflow_dispatch. Требуется подтвердить первый прогон GitHub Actions; успешную сборку пока не заявляем.

## M1.3 — навигация читалки и интерфейс (2026-11-01)
- `book_reading_state.dart`: независимое от игрового snapshot сохранение выбранной главы и закладок для каждого ID импортированной книги.
- `book_reader.dart`: адаптивная верхняя панель с оглавлением, закладкой, настройками шрифта; просмотр текущей главы и навигация «Назад/Далее», счётчик глав; иллюстрации по-прежнему в своих местах, обложка на первой главе.
- `home_page.dart`: передача стабильного ID импортированной книги в читалку, актуализирован текст главной страницы.
- `test/book_reading_state_test.dart`: сохранение и восстановление, изоляция от существующего игрового сохранения.
- Ограничения: сохранение **позиции по главе**, пока не до точного абзаца/места прокрутки; EPUB, поиск и постраничная разбивка остаются в плане. **CI после этих изменений не подтверждён**.

## M1.3 UI — единый стиль приложения (2026-11-01)
- `app_theme.dart`: светлая тёплая и тёмная оболочка приложения; persistent `AppAppearanceController` через shared_preferences, независимая от палитры книжной страницы.
- `main.dart`: MaterialApp подключён к общим темам; RPG использует типографику и фон из `ReadingPreferences` без изменений движка или snapshots.
- `home_page.dart`: переключатель светлой/тёмной темы в настройках, библиотека и главное меню наследуют общую тему.
- `book_reader.dart`: верхняя панель в цветах страницы; ручное скрытие/возврат верхней панели для чтения без отвлечений.
- `test/app_theme_test.dart`: проверка смены и сохранения темы.
- **CI и APK после этих изменений не подтверждены.** Следующий контроль: flutter analyze/test, Android Actions, реальная проверка удобства на телефоне. Визуальные доработки нижней панели и игровой инвентарь остаются будущими этапами.

## M1.4 — RPG UI shell (2026-11-01)
- `game_panels.dart`: новая компактная нижняя панель «Герой / Предметы / Журнал», открывающая информационные modal sheets. Поля честно показывают ограничения демо: никакого вымышленного инвентаря/статов.
- `main.dart`: игровой выбор теперь визуально выделен после текста сцены; нижняя панель не закрывает текст, `StoryEngine` и snapshots не менялись.
- `test/game_panels_test.dart`: widget-тест отображения действий и инвентаря.
- **CI после нового кода не подтверждён.** Настоящие атрибуты персонажа, инвентарь, журнал событий и медиа-привязки потребуют подключения отдельного deterministic world state.

## Прямой APK + согласование верхней и нижней панели (2026-11-01)
- В GitHub Actions при успешной Android-сборке на ветке `main` теперь дополнительно создаётся prerelease `android-build-<run_number>` с **отдельным APK-файлом** и SHA256; скачивание во вкладке Releases без ZIP. Стандартный Actions artifact ZIP остаётся как резервный вариант. Требуется право Actions на создание релизов (contents:write job) и успешный прогон.
- `main.dart`: игровая верхняя панель и нижняя панель Герой/Предметы/Журнал теперь используют активную палитру страницы, а не общую Material surface.
- `book_reader.dart`: явный фон экрана, кнопка показа панели и нижние кнопки листания согласованы с палитрой текста/фона книги; четыре темы сохранены.
- **Новые изменения не проверены на Android и CI; тест устройства необходим.** Debug APK только для личного тестирования.

## M1.4 UI unified reader & RPG controls (2026-11-01)
- `apps/story_reader/lib/reading_settings_sheet.dart`: один общий Flutter-компонент настроек чтения для книги и игры. Четыре темы, размер шрифта, межстрочный интервал, поля. Оба экрана используют один `ReadingSettingsStore`/SharedPreferences.
- `book_reader.dart`: использует общий компонент вместо своего дублирующего окна.
- `main.dart`: в RPG добавлена кнопка настроек чтения; кнопка immersive скрывает верхнюю панель и нижнюю навигацию «Герой/Предметы/Журнал», повторное нажатие их возвращает; действия по сюжету остаются доступны.
- `test/reading_shared_ui_test.dart`: тест игровых настроек и скрытия/возврата панели.
- GitHub main: коммиты `8d25c806`, `939bcbe6`, `251de8c9`, `89e82655`. CI/APK после изменений ещё не подтверждены.

## M1.4 Reader Chrome unified — 2026-11-01
- Общий `reader_chrome.dart` управляет normal/reading/fullscreen одинаково в `BookReaderPage` и `StoryReaderPage`; простое нажатие normal↔reading, длинное нажатие — выбор одного из трёх режимов; fullscreen по простому нажатию возвращается в normal.
- Игровая панель Герой/Предметы/Журнал остаётся в reading и скрывается только в fullscreen; сюжетообразующие варианты всегда в теле страницы. Книжная читалка не имеет RPG-панели, но пользуется тем же переключателем.
- Единые настройки `ReadingSettingsSheet` и палитры по-прежнему общие. `docs/READER_CHROME_CONTRACT_RU.md` описывает правила и матрицу регрессии обоих экранов.
- Добавлены тесты `test/reader_chrome_test.dart`, расширен `test/reading_shared_ui_test.dart`. **CI/APK нового коммита не проверены**, требуется зелёный Flutter analyze/test и Android APK.

## M1.6.4 — инвентарь влияет на выборы (2026-11-01)
- Новые игровые сеансы получают pilot rulesVersion=1, проверяемые условия для подвала, тайного прохода, встречи с тенью и концовок. Используются существующие ID и подлинный `GameProgress`, не текст меток.
- На RPG-экране отключённые решения объясняют требование; действие валидируется и при обработке нажатия.
- Для совместимости прежних `GameSaveRecord` и raw story_engine snapshots используются rulesVersion=0 без новых блокировок. Сохранения продолжают использовать исходный ключ `ai_story_m1_snapshot_v1`.
- Добавлены unit/widget регрессии двух достижимых концовок, восстановления версии правил, ключа и визуального объяснения заблокированного выбора.
- **QA на момент публикации исходников:** GitHub Actions нового коммита ещё не завершён; местный Flutter SDK отсутствует. Не считать нововведение подтверждённым до реальных CI логов.

## M1.6.5 — независимые локальные кампании и автосохранение (2026-11-01)
- В `apps/story_reader/lib/campaign_store.dart` создано постоянное хранилище нескольких независимых пилотных кампаний, каждая — **одна self-contained JSON запись** SharedPreferences (engine snapshot, журнал, характеристики, предметы, rulesVersion и метаданные сцены). Общего индекса, от которого зависит восстановление сохранений, нет.
- Подтверждённый игровой выбор ставит в упорядоченную очередь автосохранение неизменяемого снимка. Старт новой игры и «Начать заново» создают **новый** ID вместо перезаписи предыдущего прохождения. Ручная кнопка «Сохранить» оставлена.
- Главное меню показывает последнее выбранное прохождение и путь «Мои прохождения»: открыть нужную кампанию либо удалить **только её** после подтверждения. Повреждённая запись не скрывается и не заменяется пустым состоянием.
- Старый `ai_story_m1_snapshot_v1` НЕ удалён и НЕ мигрирует принудительно: доступен как отдельное «Старое прохождение» с прежним `rulesVersion`, старой историей и snapshot. Обновляется через старую обёртку только при продолжении этой кампании. Новые сейвы лежат в отдельных ключах. Изоляция импорта книг и настроек чтения сохранена.
- Добавлены unit/widget тесты нескольких слотов, автосохранения, выбора прохождения, удаления, опасных ID, повреждений, старого ключа. Старый widget-тест предупреждения о перезаписи переписан под безопасный сценарий независимых прохождений.
- **Ограничения:** SharedPreferences остаётся временным M1-хранилищем, оно не обеспечивает заявленную для готового BookWorld SQLite-транзакционность и crash-safe fsync. Экспорт/импорт `.bwsave`, SQLite/Drift, Windows EXE и Book Compiler ещё НЕ сделаны. Не приписывать их M1.6.5.
- **QA:** исходный commit до текущего шага `78c15ed31ca4147eb8b121e64b8a9f9d58f9e582`; результаты GitHub Actions для нового commit записать после выполнения, не отмечать PASS заранее.

## QA M1.6.5 — первый CI и дополнительная защита восстановления
- Коммит `2df691ac3a818357423ae9e274790ae200788370`, запуск Actions `41326180614`: Python PASS, Dart PASS, Flutter analyze **FAIL** (unused import `package:flutter/material.dart` в `test/campaigns_page_test.dart`); widget tests и APK SKIP, так как gate остановил job. Это зафиксированный сбой, а не приёмка этапа.
- Следующая правка удаляет unused import и предотвращает изменение повреждённого сохранения: при ошибке восстановления RPG показывает отдельный экран ошибки без кнопок выбора/записи, с возвратом и повторной попыткой. Главная кнопка «Продолжить» предпочитает неповреждённый слот.
- Добавлен widget-тест порченого engine snapshot, проверяющий отсутствие игровых действий и сохранность прежнего снимка.
- Следующий коммит требует повторного CI Flutter analyze/test и Android APK. Никакого утверждения PASS по этому тексту до результатов workflow.

## Защита от позднего автосохранения после удаления (M1.6.5)
- `CampaignStore` упорядочивает запись и удаление между экземплярами в одном процессе. При удалении сразу выставляется tombstone для данного ID; отложенный write не может восстановить уже удалённый слот. Добавлен unit-тест на конкурирующее удаление/автозапись.
- Это локальная защита M1; будущая SQLite-модель и атомарные .bwsave требуют собственной приёмки.

## M1.6.6 — пилотный импорт/экспорт `.bwsave` (2026-11-01)
- Добавлен `pilot_save_codec.dart`: автономный UTF-8 JSON-контейнер с `schema_version=1`, `book_id=ai_story_m1_intro`, версией `story_engine`, снимком, настоящим `GameProgress`, журналом решений и `rules_version`. SHA-256 от канонически отсортированного payload защищает от случайной порчи; ограничение файла 4 МиБ.
- Модель честно маркирует `bookworld_hash=null`, отсутствие ролей, сюжета и RNG. Формат строго привязан к встроенному пилоту и текущему `story_engine`; **не** объявляется готовым engine-neutral BookWorld .bwsave.
- В «Мои прохождения» добавлены импорт и экспорт через системный `FilePicker` Android/Windows. Импорт сначала проверяет схему/хеш и выполнение `StoryEngine.restore`, показывает подтверждение, затем создаёт **новый** ID; отмена/ошибка не затрагивает локальные слоты. Экспорт доступен включая старую legacy-кампанию при валидном snapshot.
- Убран повторный вызов `_restore()` в initState RPG (раньше при resume вызывался дважды, но второй возвращал из-за `_restoreBusy`).
- Новые тесты: `pilot_save_codec_test.dart` (roundtrip, стабильная контрольная сумма, подмена/неверная версия, UTF-8/размер, runtime snapshot, legacy rules, изоляция импорта), `campaigns_page_test.dart` (доступность действий). `crypto ^3.0.6` — **новая** зависимость. Граница чтения TXT/FB2 не менялась.
- Договорённости и ограничения: `docs/BWSAVE_PILOT_FORMAT_RU.md`. **QA**: исходники готовы, но PASS/FAIL по новому GitHub Actions нужно получить отдельно; Windows EXE/ручной перенос ещё SKIP.

## M1.6.7 — Windows Flutter release bundle (workflow added, QA pending)
- Для критерия M1 Windows добавлено отдельное задание `windows-exe` в `.github/workflows/android-ci.yml`: runner Windows + Flutter stable, генерация `windows/`, `flutter build windows --release`, проверка исполняемого файла и каталога `data`, выгрузка **полного** portable bundle через Actions artifact. Одного `.exe` без DLL/data недостаточно.
- CI зависим от Python/Dart/Flutter gates. Проверка реальной сборки, работа на Windows, наличие вложенных DLL и поведение `.bwsave` — отдельный PASS/FAIL, не объявлять без фактического job. Installer/подпись .exe пока отсутствуют.

## Исправление регрессии при возвращении к меню после автосохранения
- В отменённом запуске `41327708276` (коммит `860500eb`) шесть тестов `pilot_save_codec_test.dart` завершились PASS, но два прежних widget-сценария `game_panels_test.dart` дали FAIL: после быстрого выхода не находились «Продолжить» и два отдельных прохождения. Android этап отменён новой публикацией исходников.
- Корень проблемы: `CampaignStore.all/read` мог выполнять чтение раньше незавершённого `_writeFence` (переход из игры/кнопка «Главная» не ожидали очереди). Исправление: ждать in-process очередь записей перед перечислением и чтением. Добавлен юнит-тест `listing and reading wait for queued autosaves`.
- До повторных реальных логов Flutter widget tests и Windows/Android builds не ставить PASS.

## Уточнение корня гонки — синхронная постановка в очередь
- Помимо ожидания `CampaignStore._writeFence` при чтении, исправлена `StoryReaderPage._queueSave()`: раньше вызов `_campaigns.write` откладывался через `_pendingWrite.then(...)`, поэтому UI мог открыть `all()` **до** регистрации записи в store. Теперь запись ставится в `CampaignStore._serial` непосредственно при подтверждённом действии; дальнейшая последовательность и обработка ошибок остались на store.
- В `game_panels_test.dart` добавлен отрицательный сценарий **«выбор -> немедленный выход без Save -> Продолжить -> та же сцена»**. Результат фиксировать только после новых CI логов.

## QA hotfix — Widget tests зависали и не находили «Продолжить» (2026-11-02)
- По логу workflow `41328244444` для `0823fd80a0057d826def6f81917b1cdf1bc2c294`: Python PASS, Dart PASS, Flutter analyze PASS, но неуспешны 3 widget-сценария в `game_panels_test.dart`; `campaigns_page_test.dart` завис на `portable save actions are visible without mixing book import` и достиг `TimeoutException after 10 minutes`, затем `old single-slot save resumes` не увидел «Продолжить». Android APK и Windows bundle SKIP (не собраны).
- Причина выявлена в `CampaignStore`: статическая `_writeFence` и tombstone-набор действовали на весь Dart isolate. В последовательных widget-тестах с `SharedPreferences.setMockInitialValues` предыдущие операции могли оставить незавершённую очередь от уничтоженного FakeAsync test scope; новый тест ждал старую очередь при `all()/read()`. Ранее исправленная постановка записи при выборе не устраняла изоляцию этой очереди.
- Очередь и tombstones переведены на `Expando<_CampaignQueue>` по **экземпляру `SharedPreferences`**. В пределах работающего приложения очередь остаётся общей для всех `CampaignStore`, гарантирует последовательные операции и барьер чтения, но свежий тестовый кэш не наследует незавершённые Future/удалённые IDs.
- Добавлены unit-тесты повторного использования ID после смены тестового кэша и независимости очередей.
- **QA gate:** новый HEAD должен пройти полный Flutter widget suite, затем Android APK и Windows release bundle. До этого PASS не заявлять.

## QA корректировка очереди после run 41330543268
- По HEAD `26d737e4032225bbe0d9edd6a884481526e1ebe6`, `flutter analyze` PASS; прежние 5 проблемных widget-сценариев (три game panels, старый slot и экран portable) **PASS**, тайм-аут устранён. Полная Flutter job **FAIL**: единственный тест `campaign_store_test.dart: listing and reading wait for queued autosaves` показал пустой список при чтении одновременно с записью (всего 62 PASS / 1 FAIL).
- Корень второго бага: после перехода к scoped queue `write()` вызывал `await SharedPreferences.getInstance()` **до** помещения операции в очередь; `all()` мог захватить ещё пустую очередь.
- Исправление: очередь теперь привязана к `SharedPreferencesStorePlatform.instance`, доступному синхронно, а `write/delete` ставятся в неё до получения асинхронного `SharedPreferences.getInstance`. `read/all/markActive` захватывают барьер до await. `setMockInitialValues` меняет backend, сохраняя тестовую изоляцию.
- Явная зависимость `shared_preferences_platform_interface: ^2.4.2` (BSD-3-Clause) добавлена в pubspec; требуется повторный CI и APK/Windows сборки.

## UI/UX audit M1.6.6 (2026-11-02) — пакет исправлений
- Проведён сквозной статический аудит всех работающих экранов Flutter по коду/UX-контрактам и последнему зелёному baseline `d5f7056`. **Отчёт:** `docs/UI_UX_AUDIT_2026-11-02_RU.md`.
- Исправлены состояния загрузки и пустые каталоги, доступ к сохранениям из настроек, узкое меню действий, идентификация прохождения по сцене, scrollable подтверждения, корректный показ финалов, кнопки RPG для sepia/dark/OLED, scroll ограничение журнала, первый FB2-heading и видимость режима чтения с мыши.
- Дополнительное поле `GameProgress.endingId` необязательно, старая форма JSON не отвергается; все маршруты и существующие ID/книги/сейвы остаются без миграции.
- Добавлен `apps/story_reader/test/ui_ux_audit_test.dart` с проверками accessibility-layout 320 dp/2x, финалов и JSON, сохранений, библиотек, настроек, OLED и FB2. Обновлён тест списка прохождений под обозначения сцен.
- **QA после публикации нового HEAD:** PASS/FAIL/SKIP по полному GitHub Actions, включая Android и Windows. Ручные device screenshots / TalkBack / Windows keyboard остаются SKIP и перечислены в аудите.

## QA аудит M1.6 — исправление обнаруженной регрессии загрузки библиотеки
- `41332089654` (первый UI/UX пакет `3560ba54`) завершился Flutter widget FAIL (6 ошибок); Python, Dart и Flutter analyze PASS, Android и Windows SKIP.
- Выявлено: `LibraryPage._loadingBooks` держал бесконечный анимированный индикатор в среде без доступа к path_provider; `HomePage._opening` оставался заблокированным, пока `_refresh` ждал `BookStorage.all()`, что мешало «Продолжить». Данные сохранений не повреждались.
- Исправление: разблокировать навигацию сразу при `Navigator.pop`, обновлять Home независимо, ограничить операцию чтения книг 8 секундами, отображать ошибку + «Повторить загрузку», добавить регрессионное ожидание. Проверить следующий HEAD CI полностью.

## UX audit — устранение утечки таймеров загрузки книг
- CI `41332360623` по `ef004a4`: Python, Dart, Flutter analyze PASS; Flutter widget tests FAIL из-за незакрытых таймеров в `HomePage._refresh`; Android/Windows SKIP.
- Исправление: убрать background `Future.timeout` на главном экране, а в `LibraryPage` заменить его на явно управляемый `Timer` + `Future.any` и отменять каждый deadline в `dispose()` и при завершении операции; `_loadGeneration` не допускает запись устаревшего результата. Видимые состояния «Повторить загрузку» и данные книг сохраняются.
- Проверить полный CI нового SHA. `docs/UI_UX_AUDIT_2026-11-02_RU.md` дополнен.

## QA исправление компиляции (2026-11-02)
- CI `41332615600` по `5a696037`: Python/Dart PASS; Flutter analyze FAIL (один `const_with_non_const` при создании `TimeoutException` в `home_page.dart`), widget и Android/Windows SKIP. Удалён ошибочный `const` у конструктора, бизнес-логика и записи данных не менялись. Повторный полный CI обязателен.

## UI/UX M1.6.6 — успешная приёмка (2026-11-02)
- **Программный SHA:** `8ca82afd0a71079cde9e08bdc28f17819ce6b436`. **CI:** `41332717865` — `completed/success`. Python PASS, Dart/engine PASS, Flutter analyze PASS, **widget 71/71 PASS**, Android debug APK PASS, Windows portable bundle PASS.
- Подтверждено наличие GitHub artifact `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-Android-debug` и Android prerelease `android-build-138` с APK+SHA256SUMS. Реальное Windows/Android UI, keyboard navigation и TalkBack остаются SKIP.
- Ранее обнаруженные 6+ регрессий UX, затем незакрытые таймеры `Future.timeout` и ошибка `const TimeoutException` исправлены последовательными коммитами. Итоговый отчёт: `docs/UI_UX_AUDIT_2026-11-02_RU.md`.
- Принят кодовый UI/UX checkpoint; следующая функциональная разработка **не начиналась** по просьбе пользователя.

## UX correction: единая библиотека и один импорт (2026-11-02)
- По прямому отзыву пользователя после успешного APK #138 удалено дублирование «Библиотека» + «Моя библиотека»/«Все книги» на Home. Там теперь один вход в каталог, прежняя горизонтальная полка первых восьми книг удалена. На главной больше нет второго чтения `BookStorage().all()`.
- В самой библиотеке оставлено ровно одно `Добавить книгу` — явная текстовая кнопка; верхняя import-иконка и второй CTA пустого/ошибочного состояния удалены. Файлы TXT/FB2 по-прежнему импортируются тем же `BookImporter` и сохраняются в прежнюю папку; никаких миграций/удалений пользовательских книг и RPG не выполняется.
- Тесты `home_test.dart`, `ui_ux_audit_test.dart` адаптированы к новому контракту. **CI после фиксации**: заполнить реальными PASS/FAIL/commit; не путать старый зелёный APK #138 с новым.

## M1.7.1 — начало независимого ядра мира (2026-11-02)
- Начальная база: `17d99e1a339e401d795f7db19e14613cad786753` (Actions `41334189482` SUCCESS, Android/Windows artifacts).
- Новые файлы `packages/story_core`, `shared_schemas/v1/story_blueprint.schema.json`, `shared_schemas/fixtures/manor_world_m17.json`. Чистый Dart deterministic core, строгая схема оригинального blueprint, атомарная проверка эффектов **в памяти**, actor-specific knowledge, idempotent actions, hash-linked replay. Входные данные — только original demo, CLASSIC.
- Новый блокирующий CI job `story-core`: Dart analyze/test и Python JSON Schema Draft 2020-12. Тест: 35 действий, межпрогонный hash, replay и отрицательные случаи. Модуль пока не подключён к Flutter и не хранит пользовательские кампании.
- **Не реализовано:** настоящий ZIP `.bworld`, StoryRuntimeAdapter transaction, SQLite/Drift, сохранения M1.7, AI, Book Compiler; не считать M1.7 полностью завершённым. Подробности `docs/M17_STORY_CORE_RU.md`.
- **QA:** новый SHA и PASS/FAIL записать ПОСЛЕ GitHub Actions. Не выдавать существующие 71 Flutter тесты за тест ядра. Старые сохранения и UI не менялись.

## Уточнение M1.7.1 (без изменения старых сейвов)
- Новое событие `WorldEvent` содержит `blueprint_sha256` точной редакции тестового мира. Replay может проверять ожидаемые sequence + state hash, чтобы определить усечённый конец журнала при наличии подтверждённого checkpoint. Отвергаются неподготовленные CUSTOM/FREE_WORLD. Добавлены негативные Dart+Python тесты.
- Это контракт только нового M1.7-модуля, **не** изменение `ai_story_save_envelope_v1` и **не** миграция пользовательских данных.

## M1.7.2 — связка story_engine/story_core (2026-11-02)
- Исходная база `2d779839c26f91146bdad63f1b3afaf7b87b97a2` (Actions `41336338177` **SUCCESS**: Android+Windows, 71 Flutter widget PASS, story_core 9+6 PASS).
- Добавлен `packages/story_runtime_adapter` с интерфейсом `StoryRuntimeAdapter`, координатором `StoryEngineCoordinator`, `RuntimeChoice`, верифицированным in-memory checkpoint/replay и атомарным в пределах isolate выбором через две независимые кандидатные копии runtime+world.
- `StoryWorld.fork()` и `choiceLockReason`; доп. unit-тест. Проверка нового пакета в blocking `story-core` CI перед платформенными сборками. Пройдённость нового этапа определяется **только CI нового SHA**.
- **Никаких изменений старой Flutter-пилотной RPG и пользовательских сохранений**. `manor_m17_original_demo` отдельно от `ai_story_m1_intro`. SQLite/Drift, runtime migration, .bworld ZIP, полноценный .bwsave и GUI интеграция ещё не реализованы. Полный отчёт `docs/M17_STORY_RUNTIME_ADAPTER_RU.md`.

## M1.7.2 — итоговая приёмка
Исходный SHA `8fef11521c9f702414a6364c04b2350d30713b0d`, Actions `41337108811` **SUCCESS** (Python/Dart, story_core **10/10**, story_runtime_adapter **9/9**, JSON Schema **6/6**, Flutter analyze, widget **71/71**, Android APK и Windows portable PASS). Артефакты обеих платформ подтверждены, Android prerelease `android-build-142` содержит APK+SHA256SUMS. Физический device QA/M1.6 migration/SQLite/настоящий .bworld ZIP **SKIP, не реализовано**. Отчёт: `docs/M17_STORY_RUNTIME_ADAPTER_RU.md`.

## M1.7.3 — первый полноценный ZIP+SQLite BookWorld (2026-11-02)
- Рабочий коммит исходников `7c3923492118a7aef9c9ecda3e0c319a2961499f`. Python `tools/bookworld/bookworld.py` детерминированно компилирует оригинальный blueprint в реально проверяемый `.bworld` (ZIP, manifest.json, scenario/blueprint.json, world.sqlite). Dart `packages/bookworld_format` независимо импортирует, проверяет CRC, SHA-256, SQLite integrity + rows и возвращает `StoryBlueprint`, который в тесте запускает `StoryEngineCoordinator`.
- Новые unit/security тесты Python, Dart, JSON Schema. Blocking CI job `story-core` расширен; ожидаем конечные реальные PASS/FAIL по run нового SHA. Подробности `docs/M17_BOOKWORLD_FORMAT_RU.md`.
- GUI, пользовательские книги/сейвы, `CampaignStore` и дизайн главного меню НЕ МЕНЯЛИСЬ. Следующий этап M1.7.4 — SQLite/Drift, safe UI import, migration и 20+ E2E ходов.

## M1.7.3 — автоматическая приёмка завершена
Исходный SHA `7c3923492118a7aef9c9ecda3e0c319a2961499f`; GitHub Actions `41338634157` (**#143 SUCCESS 6/6**). Python BookWorld security **12/12 PASS**, JSON Schema **9/9 PASS**, story_core **10/10 PASS**, adapter **9/9 PASS**, Dart BookWorld importer **5/5 PASS**, Flutter analyze PASS и widget **71/71 PASS**, Windows portable PASS, Android APK PASS. Artifacts: `AI-Story-RPG-BookWorld-demo`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-Android-debug`, prerelease `android-build-143`. **SKIP:** реальный Android/Windows UI-импорт `.bworld`, SQLite/Drift сохранения, перенос M1.6; подробности `docs/M17_BOOKWORLD_FORMAT_RU.md`.

## M1.7.4a — реализован native SQLite store новых BookWorld-кампаний
- Создан независимый `packages/campaign_manager`: устанавливает только проверенный .bworld по SHA, хранит worlds/campaigns/events в новом SQLite с WAL+FULL, подтверждает game event+head строго одной транзакцией и проверяет replay при каждом открытии.
- `ai_story_bwsave_v2`: отдельный контракт для нового мира; импорт форкает ID и требует точный установленный BookWorld. Legacy M1.6 SharedPreferences и .bwsave v1 **не изменялись**.
- 10 новых автоматических сценариев: в том числе 35 ходов/перезапуск после 23, повреждение SQLite event, откат INSERT failure, независимые кампании, целостность portable export/import.
- `story-core` blocking job расширен `dart analyze/test` модуля. **Итоговый SHA и CI PASS вписать по результату**, старый #143 не является проверкой этого пакета. Подробности `docs/M17_CAMPAIGN_SQLITE_RU.md`.
- Flutter GUI и текущие кампании пока используют прежний код; UI-импорт и legacy migration остаются в M1.7.4b, новые UI функции не выдавать за готовые.

## M1.7.4a — итоговая приёмка PASS, 2026-11-02
- Проверенный кодовый SHA `cc69778586b45c3e82c4f1dc415ce2dc545b043e`, Actions [#145 / `41340309393`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41340309393) **completed/success, 6/6 jobs PASS**.
- Python/Dart M0 PASS; `story_core` 10/10, `StoryRuntimeAdapter` 9/9, JSON Schema 9/9, Python BookWorld 12/12, `bookworld_format` 5/5, новый `campaign_manager` 10/10, Flutter analyze и widget 71/71 **PASS**. Android APK/Windows portable PASS. GitHub [Android release `android-build-145`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-145) и артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo` опубликованы.
- В stage реализованы SQLite WAL+FULL confirmed turn/events/head, replay, restart after 23/35, настоящие дочерние ветки с переносом проверенного состояния, отдельный save v2 с импортом в новый ID. Прежняя Flutter UI и M1.6 сохранения НЕ МЕНЯЛИСЬ.
- **SKIP/не реализовано:** физический QA, UI-импорт .bworld, фактический запуск нового store в Android/Windows приложении, legacy migration/backup, force power loss. Подробный документ `docs/M17_CAMPAIGN_SQLITE_RU.md`. Общий M1.7.4 **не закрыт**.

## M1.7.4b1 — интеграция .bworld в существующую Flutter-библиотеку (2026-11-02)
- База `cc69778586b45c3e82c4f1dc415ce2dc545b043e`, Actions #145 SUCCESS; docs HEAD `15e32e5`. Созданы `world_library_gateway.dart` (SQLite через `Isolate.run`), `world_campaigns_page.dart`, `world_play_page.dart`. Старая CTA «Добавить книгу» одна, теперь принимает .bworld в дополнение к TXT/FB2, мир имеет отличимую RPG карточку в прежней библиотеке.
- Подготовлены четыре Flutter integration/widget проверки: реальный native sqlite3 gateway, 35 UI ходов с re-open после 23, отказ записи без ложного следующего кадра, интерфейс 320dp/200% текста. Flutter CI получает реальный собранный .bworld до тестов.
- Миграция M1.6 не производилась; существующие `CampaignStore`, `SaveStore`, `GameProgress`, `BookStorage` не изменены. Новый v2 сохраняется отдельно в SQLite. Работа новых экранов на Android/Windows устройствах пока не подтверждена. Полный отчёт `docs/M174B_FLUTTER_BOOKWORLD_RU.md`.
- **ВАЖНО:** QA нового SHA и итоговые PASS/FAIL/SKIP вписывать только после actual GitHub Actions; не считать наличие widget тестов доказательством PASS.

## M1.7.4b2 — объединение сохранений без миграции
- Общий экран `Мои прохождения` в `campaigns_page.dart` отображает вместе legacy M1.6 и native SQLite BookWorld-кампании, но каждую восстанавливает собственным runtime. HomePage теперь продолжает новый BookWorld, когда нет старого пилотного слота, и считает оба вида кампаний.
- Два новых Flutter UI-теста: совместный список/проверка сохранности пилота, и продолжение BookWorld из Home. Полная таблица изменений `docs/M174B_FLUTTER_BOOKWORLD_RU.md`; **QA только после нового GitHub Actions**.

## M1.7.4b QA исправления до приёмки
- CI `41372278079` по `cca53c4`: Python/Dart/BookWorld PASS, но Flutter widget **FAIL 21**, Android/Windows SKIP. Причины: legacy tests без native plugin зависали на Isolate.run, fakeAsync worker, 320dp overflow в GameQuickBar.
- Следующий hotfix: DI gateway в production main, nullable gateway в legacy Home/Library/Campaigns/Settings, реальный SQLite в widget test inline и отдельная проверка Isolate.run, равные ширины для GameQuickBar. Нужен повторный полный CI нового SHA. Подробности `docs/M174B_FLUTTER_BOOKWORLD_RU.md`.

## M1.7.4b — кодовый QA исправленного UI
`f4bf62c156abb9cc0a1b4a4a4851cdb33312994a`, Actions #148 `41372851607`: Python/Dart и story-core PASS; Flutter analyze PASS; **78/78 Flutter tests PASS** (71 старых + 6 новых widget + 1 isolate). Реальный SQLite/BookWorld 35 ходов с UI re-open на 23-м, единый список кампаний и Home Continue прошли; 320dp/200% и откат UI при ошибке записи также PASS. GitHub Actions #148 `41372851607` **completed/success (6/6 PASS)**, Android debug APK PASS, Windows portable PASS. Android prerelease `android-build-148`, отдельный artifact проверенного BookWorld. Физические Android/Windows E2E и legacy миграция всё ещё SKIP. Полный `docs/M174B_FLUTTER_BOOKWORLD_RU.md`.

## M1.7.4b — окончательная автоматическая приёмка
- **Исходный SHA `f4bf62c156abb9cc0a1b4a4a4851cdb33312994a`**, [GitHub Actions #148](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41372851607) `completed/success`, 6/6 jobs PASS.
- Python/Dart M0 PASS; story_core 10/10, adapter 9/9, JSON Schema 9/9, Python BookWorld 12/12, BookWorld Dart 5/5, campaign_manager 10/10, Flutter analyze PASS и **78/78 tests PASS** (в том числе 35 UI ходов, reopen на 23-м, native worker isolate, старые пилотные UI).
- Android APK PASS, Windows portable PASS, demo .bworld artifact PASS. [Android prerelease #148](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-148).
- SKIP: Android/Windows physical E2E, real cross-device .bwsave transfer, legacy migration, power-loss, safe delete/backup. Общая UI-интеграция M1.7.4b принята **только по автоматическим QA**, полный M1.7 acceptance ещё требует аппаратной проверки и остаточных функций. См. `docs/M174B_FLUTTER_BOOKWORLD_RU.md`.

## M1.7.4c1 — резервирование и удаление BookWorld (2026-11-02)
Новая отдельная ветка `feat/m174c1-safe-backup-delete`: безопасный экспорт исходного .bworld; запрет удаления мира с кампаниями; SQLite транзакционное удаление кампании после replay и проверки ревизии; независимость форков; подтверждение и системный экспорт .bwsave v2 перед удалением. Тесты добавлены. Подробности в `docs/M174C_SAFE_BACKUP_DELETE_RU.md`. **CI ещё не подтверждён**, предыдущий PASS #148 только для M1.7.4b. Legacy сохранения M1.6 и TXT/FB2 не затрагивать.


## M1.7.4c1 — окончательная автоматическая приёмка (2026-11-02)
- PR [#1](https://github.com/shonentez-afk/AI-Story-RPG/pull/1) merged в `main` как `a37eb21afe82e8e93dfc43fcb2caabe580153c6b` (squash), проверенный PR HEAD `13239eb843d99787ce50b5d97e71695be54dca85`.
- GitHub Actions [#150, run 41374846035](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41374846035) — **completed/success, 6/6 PASS**: Python, Dart, story_core/BookWorld, Flutter analyze и **80/80 tests**, Windows portable release bundle, Android debug APK. M0 SDK checks также PASS (run `41374846010`).
- Первый PR CI `41374617867` завершился Flutter **79 PASS / 1 FAIL** из-за `pumpAndSettle timed out` в `world_integration_test.dart` при подтверждении удаления: фоновый indeterminate progress indicator продолжает анимацию. Тест исправлен ожиданием конкретного кадра перехода диалога (300 ms), **не отключением проверки SQLite**. Повторный Flutter 80/80 PASS.
- Функции: обязательный системный backup перед удалением `.bwsave v2` или пустого `.bworld`, RESTRICT против удаления мира с кампаниями, проверка expectedRevision в SQLite, полный replay, сохранение дочерних fork. Старые M1.6 SharedPreferences/книги TXT/FB2 не затронуты.
- **SKIP:** реальный запуск на физических Android/Windows устройствах, восстановление из системного FilePicker после копирования файла, внезапная потеря питания, старые M1.6 migration, Book Compiler/AI. Результаты CI относятся к PR SHA; если после squash запущен отдельный main CI — его статус проверять по факту, не додумывать.
- Дальше **M1.7.4c2**: унификация ReaderChromeMode normal/reading/fullscreen в новом BookWorld UI, доступность 320dp/200%, Windows keyboard, затем Android↔Windows device E2E и backup restore QA. Не создавать вторую библиотеку и вторую CTA импорта книг.

## M1.7.4c2 — BookWorld reader chrome и визуальная совместимость (2026-11-02)
В ветке `feat/m174c2-bookworld-reader-chrome` добавлены три режима общего `ReaderChromeMode`, палитры/шрифт/поля `ReadingSettingsStore`, доступное меню режимов, F11/Esc и сохранение игровых панелей/choices в иммерсивном режиме. Добавлены 3 Flutter widget-теста на реальной SQLite (настройки, переключение+replay, 320dp/200%). Старые M1.6 данные, `.bwsave` и единая библиотека не изменены. **Нужен фактический CI нового SHA, PASS пока не заявлять.** Подробности: [M174C2_READER_CHROME_RU.md](M174C2_READER_CHROME_RU.md).


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


## 2026-11-02 — M2b1: рабочая ветка (НЕ ПРИНЯТО CI)
- PR #7 `feat/m2b1-resumable-provenance-20261102`: локальная очередь анализа SourceChunk с контрольными точками, SHA-256 provenance и проверяемыми упоминаниями имён и мест. Добавлен отдельный регрессионный тест. Это не извлечение канона и не готовая RPG.
- Статус: CODE ADDED, CI PENDING; Flutter/Android/Windows PASS не подтверждены. Интерфейс M1/M2a и сохранения не изменены. Следующий этап M2b2 — durable checkpoint, UI review в существующей библиотеке.


## 2026-11-02 — M2b2 implementation branch, CI pending
- На базе M2b1 сделаны private ApplicationSupport checkpoints с атомарной заменой и восстановлением, единый экран подготовки с порциями анализа, review только текстовых упоминаний, скрытие спойлеров, явная ошибка/сброс. M1 и M2a UX не переписаны.
- Тесты: `source_analysis_checkpoint_test.dart` + актуализация `book_source_index_test.dart`. **PASS не заявлен** до точного CI SHA. Android/Windows physical/manual QA: SKIP.
- Следующая цель M2b3: source-grounded facts/events/alias resolution; никакого `.bworld` из пользовательской книги до валидации.


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


## 2026-11-02 — M2b4a1 принят, M2b4a2 checkpoint/UI в отдельной ветке

- M2b4a1 PR #18 MERGED squash `13e9c0ebf4ab6e2cfbbcf306ad221b78cbcc7266`; exact tested head `05a399c241670cda5d05e2bdda0d60cbe163812f`, CI `41427964306` core PASS, `41427964385` M0 PASS. Offline semantic provider boundary и fail-closed source-backed validation приняты; **это не работающая LLM и не компиляция произвольной книги**.
- M2b4a2 branch `feature/m2b4a-semantic-checkpoints-ui-20261102`, новый приватный checkpoint+возобновление, top-level workers, панель в одной подготовке, ручные метки без canon, отдельный reset. Отчёт: `docs/M2B4A2_SEMANTIC_CHECKPOINT_UI_RU.md`.
- Статус M2b4a2 **CODE/CI PENDING**: до отдельного полного PR CI+Windows+Android+M0 не принимать. Исторические M2b1/M2b3b/M2b3c, SQLite/BookWorld/.bwsave, библиотека, настройки и ридер не мигрируются. `gameplayCoverage=0`, `canPublishBookworld=false`.


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


## 2026-11-02 — pre-AI аудит M2b4b/M2c

- Принят UX PR #20: code SHA `cdf64ff3c5da7cf52acaf9ee9767145a16d3d7d9`, exact head `f46d59a4798f158493e9d06d30e6fd753f2b2bcf`, Actions `41438307133` gated core/Windows/Android PASS, M0 `41438307091` PASS. Публикацию нового main release подтверждать отдельно.
- Новая ветка `feature/m2b4b-m2c-pre-ai-validation-20261102`: `source_semantic_catalog.dart` + `intermediate_story_blueprint.dart`, точная валидация source citations, typed voice/time/polarity, причинное исследование альтернатив, тесты `pre_ai_semantic_blueprint_test.dart`. **CODE / CI PENDING**, это подготовка под ИИ, не реальный AI-провайдер и не публичный пользовательский .bworld.
- Полный аудит незакрытых требований: `docs/M2_PRE_AI_READINESS_AUDIT_RU.md`; основной риск — импорт/построение .bworld принимает строго `original_demo` с null fingerprint, поэтому для произвольной книги M2d нужен отдельный безопасный production pipeline.


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


## 2026-11-03 — M2e5b2 ПРИНЯТ; перейти к M2e5b3

- PR **#32 MERGED**: `main` `84f26a6027d813fa20e15533678d88334d22bb57`; HEAD ветки при проверке `ab47e5db2e11b32f86575642afb801ba57c07f27`.
- GitHub Actions `41567959847` **COMPLETED/SUCCESS**: 6/6 — Python, Dart, строгий BookWorld/schema, Flutter static+widget, Windows portable, Android debug APK. M0 `41567959905` **COMPLETED/SUCCESS**; оба проверяют точный HEAD `ab47e5db`. Первоначальная ошибка жизненного цикла TextEditingController в диалогах исправлена до принятия; финальный прогон без ошибок.
- Редактируемые NPC: роль/мотивация/знания/секреты/отношения и цитатные кандидаты, локальный атомарный checkpoint `npcEditorial`, source fingerprint, защита от изменённой идентичности SAME/DIFFERENT и отозванных доказательств. Никакой автоматической публикации, gameplay NPC, экспорта книги или ИИ; `BookWorld`, книга, SQLite кампании, `.bwsave` не изменены.
- Технический отчёт: `docs/M2E5B2_NPC_EDITORIAL_RU.md`. Физические Windows/Android E2E, длинная реальная книга, стресс-прохождения — SKIP, не PASS. Новая release после слияния зависит от отдельного main CI; последний подтверждённый перед M2e5b2 релиз `test-build-325`.
- **Далее M2e5b3:** полноценный UX аудит M2e5a/b1/b2 при 320dp/200% текста, карта сцен/связей и редактор конфликтов, независимый и проверяемый адаптер для игровых Actor ID/знаний/секретов с ограничением спойлеров; затем физическая приёмка Windows/Android, большой роман, долгие игровые сохранения. Только после этих шагов — M2f безопасность подключения ИИ (согласие, BYOK, локальная модель, хранение ключей, квоты). Не объявлять весь путь до ИИ завершённым.


## 2026-11-03 — M2e5b3a: карта сцен и инспектор NPC, **CODE / CI PENDING**

- База `main` `d2f85a13`, M2e5b2 PR #32, CI `41567959847` и M0 `41567959905` success; последний подтверждённый релиз `test-build-329` (Windows + Android).
- Ветка `feature/m2e5b3a-continuity-preview-20261103`. В конструкторе многосценной RPG за spoiler gate добавлена **статическая карта переходов** со страницами, диагностикой пустых/недостижимых/некорректно связанных сцен и кнопками перехода к редактированию. Она **не заменяет** прежний причинный preflight флагов и финалов.
- В существующем авторском NPC-редакторе — **read-only инспектор согласованности**: предварительные стабильные `stage_npc_…` из точных цитат, проверки неоднозначного имени, ролей/мотивов, отсутствующих карточек целей, главы упоминания и возможных сцен; запрет автоматического раскрытия знаний/секретов и отправки в ИИ. Читает сценарий только отдельно; повреждённый черновик не стирает NPC.
- Тесты `draft_scene_graph_overview_test.dart` и `npc_continuity_audit_test.dart` (в т.ч. 320dp и 200% текста). Документ `docs/M2E5B3A_GRAPH_AND_NPC_AUDIT_RU.md`.
- **Текущий код не считать принятым без exact-head CI** (Python, Dart, BookWorld/schema, Flutter analyze/widget, Windows portable, Android APK, M0). Физические Windows/Android, реальная большая книга, многопроходные сейвы — SKIP. **Далее M2e5b3b:** проверка UX широкого и узкого интерфейса, правила знания/тайн/NPC в runtime, сцены/актёры/мотивы и 20–100+ ходов; после этого M2f consent, BYOK, лимиты/шифрование ключей, локальная и облачная ИИ-конфигурация. Live ИИ ещё не подключён.


## 2026-11-03 — M2e5b3a ПРИНЯТ; следующий этап M2e5b3b

- PR **#33 MERGED** в `main`: `1d35d82340bc808fbd10ca75a487dc541c9c8833`; exact-head PR `5accd5a56831d047cc20f82e59d5596247d28931`.
- CI **41573524717 completed/success**, все 6 обязательных jobs PASS: Python, Dart, строгий BookWorld/schema, Flutter analyze/widget (в том числе 320dp и масштаб текста 200%), Windows portable, Android APK. M0 **41573524543 completed/success**, тот же проверенный HEAD. В первом запуске тесты старой NPC-страницы не имели подмены отдельного multiscene repository; исправлено, добавлен отдельный негативный тест повреждённого черновика без потери NPC.
- В многосценном редакторе за spoiler gate работает карта статических переходов с навигацией, диагностикой недостижимых/пустых/битых сцен, флагов и возможных флешбэков. Полная причинность остаётся в старом `PrivateAdaptationPreflight`; карта не ослабляет требования двух достижимых концовок.
- NPC-просмотр — только `stage_npc` ID, привязка к точным source mentions, предупреждения о ролях/мотивациях/неоднозначных именах и будущих цитатах. Никакие секреты/знания автоматически не раскрываются игроку/ИИ; нет игрового NPC и изменения BookWorld, SQLite, `.bwsave` или книг. Повреждённый сценарий не удаляется.
- Подробности: `docs/M2E5B3A_GRAPH_AND_NPC_AUDIT_RU.md`. Физические Windows/Android E2E, большая реальная книга и 20–100+ ходов — всё ещё **SKIP**, не PASS. Последняя опубликованная release на момент слияния — `test-build-329` (M2e5b2); сборка `main` после PR #33 запущена отдельно.
- **Далее M2e5b3b:** полный UX/UI аудит основного меню/книги/сцен/NPC при 320dp/200% текста, редактор явных правил знания/секретов и runtime Actor adapter без автоматического канона, стресс-кейсы длинного сценария и сохранений. Затем device QA Windows/Android; только после этого **M2f** — consent, ключи BYOK, лимиты/провайдеры локального и облачного ИИ. Live ИИ ещё не подключён.


## 2026-11-03 — M2e5b3b1: правила знаний NPC, CODE / CI PENDING

- База `main` `1ab9434e`: M2e5b3a PR #33, CI `41573524717`, M0 `41573524543` PASS, опубликована `test-build-332` (Windows/Android).
- Рабочая ветка `feature/m2e5b3b1-npc-knowledge-rules-20261103`. Реализованы `npc_knowledge_rulebook.dart`, `npc_knowledge_rules_page.dart`, `npc_knowledge_world_bridge.dart`, отдельный атомарный `SourceCheckpointScope.npcKnowledgeRules`.
- Пользователь вручную связывает подтверждённые заметки NPC `knowledge/secret` с выбором многосценной RPG и получателем знания. Для игрока — галочка + отдельный диалог согласия. Изменения цитат, SAME/DIFFERENT, заметки/перехода блокируют устаревшие правила без удаления данных.
- К существующему частному компилятору подключена опция `multi-use-npc-rules`, **по умолчанию выключена**. При включении валидируются отдельные правила/NPC/identity, затем создаются реальные `npc_<hash>` Actor ID, `fact_<hash>` IDs и `learn_fact` эффекты в существующем `story_core`. Текст заметок и секретов не копируется в .bworld. Старый режим, старые книги, worlds/SQLite/`.bwsave` не мигрируют.
- Новые тесты `npc_knowledge_rulebook_test.dart` (в том числе 135 игровых шагов + replay и tamper), `npc_knowledge_rules_page_test.dart` (вкл. 320dp/200%), `npc_knowledge_compiler_integration_test.dart` (private .bworld writer/importer), усилены `multi_scene_editor_page_test.dart`. Подробности `docs/M2E5B3B1_NPC_KNOWLEDGE_RULES_RU.md`.
- **НЕ МЕРЖИТЬ** до exact-head PASS Python/Dart/schema/Flutter/widget/Windows/Android и M0. Физическая приёмка устройств/реальный длинный роман/полные AI диалоги SKIP.
- После этого M2e5b3b2: `knows_fact` условия и правила разговора, проверка долгих кампаний SQLite/`.bwsave`, UX/UI аудит всех страниц, затем M2f (безопасные локальная/облачная ИИ конфигурации, BYOK и лимиты). ИИ ещё отключён.


## 2026-11-03 — M2e5b3b1 ПРИНЯТ в main; следующий M2e5b3b2

- **PR #34 MERGED**: `main` `109b3508c9b772f410d517897c45ae9bd9e51fde`; exact verified head `01067bb88a3ddbb4ed0f01fd28a1cadf6c7ff4fc`.
- CI `41576672489` **COMPLETED/SUCCESS (6/6)**: Python reference, Dart engine, BookWorld/schema, Flutter analyze+widget, Windows portable, Android APK. M0 `41576672474` **COMPLETED/SUCCESS**, тот же exact head. Первый CI падал на строгом импортёре, принимавшем только `set_flag`; исправлено безопасным allowlist `learn_fact`, отдельным тестом запрета тайных начальных знаний/недопустимых эффектов и новой полновесной приёмкой.
- Реализованы отдельный атомарный `npcKnowledgeRules`, редактор правил knowledge/secret, привязка к точной исходной цитате, сохранённой SAME/Different группе, заметке и выбору; для передачи знания игроку требуются галочка и второе явное подтверждение. Изменение источника/заметки/сценария -> fail-closed без перезаписи.
- В существующем приватном компиляторе **опция opt-in выключена по умолчанию**. По явному включению создаёт реальные типизированные Actor ID `npc_…`, непрозрачные fact ID `fact_…` и эффект `learn_fact` в `story_core`. Тексты секретов в .bworld не включаются. Запуск исходной версии не меняется; старые книги, BookWorld, кампании SQLite и `.bwsave` не мигрируют.
- Тесты: 135 действий с хэшами/replay/подменой, строгий writer+importer, UI 320dp/200%, повреждённый checkpoint, отсутствие согласия, source-future; отчёт `docs/M2E5B3B1_NPC_KNOWLEDGE_RULES_RU.md`.
- Физические Windows/Android E2E и длинное прохождение с реальным SQLite/`.bwsave` остаются **SKIP**, не PASS. Последний подтверждённый релиз перед merge — `test-build-332`; main CI с новым кодом `41577494842` запущен отдельно, не объявлять новый опубликованный релиз до завершения.
- **Далее M2e5b3b2:** типизированные `knows_fact` условия в полностью проверяемом state-graph (не добавлять без нового causal proof), редактор взаимодействий и знаний NPC, long-running 20–100+ действий в настоящих кампаниях SQLite/`.bwsave`, полный UX/UI аудит меню/библиотеки/чтения/редакторов с 320dp/200%, проверка реальных Windows и Android устройств. После этого **M2f**: consent, BYOK, локальные и облачные ИИ-провайдеры, ключи, лимиты, аудит запросов. Live ИИ ещё не подключён.


### 2026-11-03 — подтверждённый установочный релиз M2e5b3b1

- **test-build-339**: https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/test-build-339 — подтверждённый опубликованный релиз для принятого squash-коммита `109b3508c9b772f410d517897c45ae9bd9e51fde` (PR #34, M2e5b3b1).
- Post-merge main CI `41577494842` **completed/success**, Python/Dart/BookWorld/schema/Flutter widget/Windows portable/Android debug APK/PUBLISH PASS. В релизе есть `AI-Story-RPG-Windows-portable.zip`, `AI-Story-RPG-Android-debug.apk` и `SHA256SUMS.txt`.
- Это автоматические CI-бинарники, **не** результат физического E2E на Windows/Android: реальное тестирование устройств и длительных кампаний SQLite/.bwsave остаётся PENDING. Live AI по-прежнему выключен; следующий этап — **M2e5b3b2**, затем M2f.


## 2026-11-03 — M2e5b3b2a принят; следующий SQLite stress M2e5b3b2b1

- PR #35 MERGED: `5b74a9c225a668557c352b633eb497913446cfff`; exact-head `329cfad19d119276459b26cccbab1212ff305a17`; CI `41580693590` Python/Dart/schema/Flutter/Windows/Android PASS, M0 `41580693511` PASS. AI offline. Физическое E2E SKIP.
- Новая ветка `feature/m2e5b3b2b1-npc-sqlite-transfer-20261103`: реальный SQLite + BookWorld + portable v2 стресс тест 120 ходов, повторное открытие, изолированный импорт и проверка tamper. До нового exact-head CI — **CODE / QA PENDING**, не называть успешным или опубликованным. Подробности `docs/M2E5B3B2B1_SQLITE_STRESS_RU.md`.


## 2026-11-03 — M2e5b3b2b2: GUI условий `knows_fact` (CODE / CI PENDING)

- Ветка `feature/m2e5b3b2b2-npc-gates-20261103` продолжает PR #36 без изменения исходных книг, библиотек и SQLite/.bwsave.
- Редактор проверяемых `knows_fact` на уже принятых правилах `learn_fact`, source+rule+choice digest; v1 когда gates пусты и строгое v2 когда добавлены. Условия идут в существующий `NpcKnowledgeWorldBridge` и импортёр с causal proof. Нет автоматического раскрытия секрета, AI и новой схемы сохранений.
- Подробности `docs/M2E5B3B2B2_NPC_KNOWLEDGE_GATES_RU.md`. Статус CODE / EXACT-HEAD QA PENDING — пока без доказанной приёмки или нового релиза. Ручные Windows/Android, полный UI/UX аудит и настройки BYOK остаются отдельными блокерами.


## 2026-11-03 — M2e5b3b2b1 ПРИНЯТ (точная приёмка)

- PR #36 **MERGED**, squash `a8ff96279f32bff5c276669861d16dd61900cb76`. Exact branch head `7f562c2100b607e7104b4da38e91d1ef347d6a42`, GitHub Actions `41581807005` **COMPLETED/SUCCESS**: Python, Dart, schema/BookWorld, Flutter analyze+widget, Windows portable, Android APK PASS; M0 `41581807148` PASS. Это тест двух отдельных SQLite каталогов в CI, физические устройства SKIP. `M2e5b3b2b2` остаётся CODE / exact-head CI PENDING до отдельного полного прогона.

## 2026-11-03 — PR #37 принят, реальная FB2 как тестовый источник M2e5c1

- PR #37 M2e5b3b2b2 MERGED: `f143f110f9a00cd645b29a38489c66107bb1a254` (exact head `16ce4f83d782dccad7423eab92572a32a5070d0a`); CI `41582827470` SUCCESS Python/Dart/BookWorld/Flutter/Windows/Android; M0 `41582827425` SUCCESS. Windows/Android физически не тестировались.
- M2e5c1: подключение раздельной «Свинопас» FB2 для приватного smoke. Файл пользователя не публиковать. Локальная независимая XML/Pillow проверка: 1 рассказ, 57 p, 5/5 реальных JPEG, размер 356051 bytes, SHA256 `bd2488a29fb3b5029c59a6c929cc67df3681e8086df8a4bbd3963f7c7995c123`. Старый event regex = 0.
- Добавлены ограниченные source-cited role mentions/actions в offline pipeline; UI «Подготовить к RPG» различает количество событий и предупреждает, если находок ноль. Авторское подтверждение обязательно. Приватный smoke Dart `AI_RPG_PRIVATE_FB2_PATH` в CI без книги официально SKIP. Детали `docs/M2E5C1_REAL_BOOK_SMOKE_RU.md`. Новая ветка `feature/m2e5c1-real-svinopas-prep-20261103` — CODE / EXACT-HEAD CI PENDING; не выдавать за релиз.


## 2026-11-03 — M2e5c1 ПРИНЯТ: реальный FB2 подготовлен как приватный тест

- M2e5c1 PR #38 **MERGED**: squash `a7d9ad24fde1042663aa2bd8015d0141f4f0d3bc`. Exact tested branch head `8604f1fd33d399c86ed2e61a48d8971d10f8a880`; GitHub Actions full CI `41585455196` COMPLETED/SUCCESS (Python/Dart/BookWorld/schema/Flutter analyze & widget/Windows portable/Android APK 6/6), M0 `41585455126` COMPLETED/SUCCESS. Flutter: **292 PASS, 1 SKIP** (приватная FB2 не загружается в публичный GitHub). Установочный test-release на push(main) проверять отдельно; PR сам release не публикует.
- Отдельная «Свинопас»: Python XML + Pillow проверили 356051 bytes, 57 p, 1 сказку, 5 JPEG, 5 корректных ссылок; реальный Dart/Windows/Android запуск по этой книге **SKIP**. Синтетические тесты/CI не подменяют его.
- Код: строго source-cited inferred роли/глаголы и UI с честным числом предложенных событий/0-совпадений; нет автоматического канона, смешения NPC, публикации книги/иллюстраций, миграции старых сохранений, ИИ. Опциональный приватный тест `apps/story_reader/test/private_real_fb2_smoke_test.dart` по `AI_RPG_PRIVATE_FB2_PATH`. Отчёт `docs/M2E5C1_REAL_BOOK_SMOKE_RU.md`.
- NEXT M2e5c2: полный UX/UI аудит на Windows/Android + 320dp/200%; проверить реальную книгу через библиотеку, импорт, иллюстрации, локальную подготовку, принятие цитат, продолжение, ограничения сцен/концовок, восстановление игр. Только затем M2f конфигурация ИИ и безопасность, без включения по умолчанию.


## 2026-11-03 — M2e5c2a: аудит ещё пяти FB2, CODE / QA PENDING

- 5 реальных FB2 проверены локально Python XML/Pillow: **61/61 изображение**, все ссылки без потерь, 3 сноски по месту, в пределах лимита импорта. Старый narrow event regex даёт 1, 1, 0, 0, 0 совпадений. Тексты/изображения не выкладывались в публичный репозиторий.
- **Установлена ошибка структуры**: семь внутренних рассказов «Снежной королевы» представлены одним <section> и обычными <p>; ранее все индексировались как одна сюжетная глава. Новый строго последовательный numbered-part splitter ожидает 7 сюжетных глав + 1 notes; к старым импортам не применяется без повторного добавления FB2.
- Добавлены животные/второстепенные роли только как source-cited INFERRED, не канон; тесты на оригинальных синтетических данных + локально опциональный test(private Andersen five) через AI_RPG_PRIVATE_FAIRYTALES_DIR. Отсутствующий в CI пользовательский источник => SKIP, не PASS.
- Проверить полный exact-head CI и M0 перед merge. Потом M2e5c2b UX/UI 320dp/200% и Windows/Android E2E, затем M2f BYOK/consent. Подробности docs/M2E5C2A_FIVE_BOOK_AUDIT_RU.md.

## 2026-11-03 — M2e5c2a MERGED, M2e5c2b reader UX CODE / CI PENDING

- PR #40 accepted: squash `200ad07c0a5f585492fe79ecfd41045edfbfb4e0`; exact `7cac35824364c1238eba61ad15a28394b9f7ec93`, CI `41590983213` PASS (6/6), M0 `41590983332` PASS. Flutter 295 PASS, 2 private-FB2 SKIP. Release on push(main) not yet confirmed; latest prior published release was test-build-351.
- Пользователь ручным сообщением подтвердил BASIC OPEN PASS без точной версии и книги; device E2E для всех 5 FB2 ещё не выполнен.
- M2e5c2b: аудит выявил реальное отсутствие имён «Рассказ 1–7» в оглавлении после корректного разделения «Снежной королевы» на 7 сюжетных глав + notes. В `BookReaderPage` теперь подписи по тому же номерному парсеру, что и в `BookImporter`; отдельный widget-test 320dp/200% с переходом к 7/8 и 8/8. Нет изменений SQLite/.bwsave, текстов пользовательских файлов или автоматически признанных фактов. Документ `docs/M2E5C2B_UX_AUDIT_RU.md`.
- Осталось exact-head CI/M0 нового PR, полный visual/physical Windows/Android 320dp/200%, затем готовность к M2f.

- PR #41 первоначальный CI `41592292664` Flutter FAIL из-за неверного глобального finder текста («Рассказ первый» был и в ридере, и в открытом оглавлении). Проверка скорректирована с ограничением `BottomSheet` и запретом ложных совпадений; production BookImporter/BookReader неизменны. Следующий exact-head CI ещё не пройден. Android/Windows skipped в провальном прогоне.

- CI PR #41 `41592911307`: Flutter FAIL по тесту 7-й главы (после исправления глобального finder заголовок 7/8 успешно виден; текстовый абзац находился вне viewport и не был смонтирован в lazy SliverList при 200%). Тест уточнён: источник не потерян и элемент проверяется после реальной прокрутки. Повторная exact-head проверка нужна; не мержить до PASS.

- PR #41 третье падение widget-test в `41593281832`: у «Примечания» после lazy scroll центр y=672 вне 640px; нажатие было пропущено. Тест теперь реально доводит ListTile до hit-test области перед tap (`ensureVisible` + `hitTestable`). Это не изменение FB2, чтения или сохранений; новый exact-head CI обязателен.


## 2026-11-03 — M2e5c2b принят (точная CI-приёмка)

- PR #41 MERGED: `386aaef7be9e80551b1631c8958e9ec7c5a7b8d0`; exact head `af5d1df11e78655193043bd4bbd6270d08fa7920`; CI run `41593740031` **SUCCESS 6/6** (Python/Dart/BookWorld/Flutter 296 PASS+2 private-FB2 SKIP/Windows/Android), M0 `41593740280` SUCCESS. Предыдущие три Flutter failure — неверные **тестовые** ожидания для 320dp/200%, устранены. Новое оглавление использует заголовки рассказов, notes остаются отдельной главой; настоящая книга не включена в CI. Проверить отдельную публикацию test-build на post-merge main.
- Дальше M2e5c2c: полный UX/UI и физический Windows/Android E2E по шести личным FB2, семи частям «Снежной королевы», подготовке RPG, NPC, настройкам и сохранениям. Реальный физический E2E всё ещё SKIP, несмотря на CI PASS; live AI пока OFF.


## 2026-11-03 — M2e5c2c UX и подготовка книги: CODE / CI PENDING

- На коде `main` `83b3c05af8dd29a8a84228247db78cd3ae73c522` статически инвентаризированы все основные пользовательские экраны и их обработчики (17 экранных модулей, карта `docs/M2E5C2C_UX_CONTROL_AUDIT_RU.md`); не считать отдельной физической проверкой каждого элемента.
- `SourceIndexPreviewPage`: исправлены ошибочное заявление об отсутствующем компиляторе, непонятное дублирование ручного поиска и основной подготовки, ложный статус завершения после сброса имён, повторная остановка после порции и возможность параллельно менять цитаты при записи checkpoint. Добавлена Flutter регрессия полного цикла подготовки и reset (narrative/catalog не удаляются); обновлены существующие UX тексты тестов.
- Дальше exact-head CI+M0, Windows/Android сборки; затем ручной device QA всех 6 FB2, responsive 320dp/200%, verify/checkpoints/editor/NPC/campaigns. `main` не менять до приёмки, AI offline/local/cloud provisioning не включён.

- Добавлены новые 320dp/200% smoke-тесты MultiSceneEditorPage (создать черновик) и NpcEditorialPage (выбор NPC и доступная кнопка карточки). Результат до exact-head CI PENDING, реальные устройства всё ещё не проверены.

- Дополнительно в `LibraryPage` закрыт двойной Navigator.push после повторного нажатия кнопок «Читать»/«Подготовить к RPG»: `_openingBook` до закрытия дочернего маршрута; тест двойного callback → один Back → вновь доступное чтение. Новый exact-head CI обязателен.
