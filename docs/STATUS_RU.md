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

- Сквозной UX/UI-аудит текущего Flutter-приложения (Windows/Android) оформлен в [docs/UI_UX_FINAL_AUDIT_M174C3_RU.md](docs/UI_UX_FINAL_AUDIT_M174C3_RU.md): все 12 основных пользовательских маршрутов, 17 устранённых замечаний, проверка старой M1.6 и новой BookWorld архитектуры, доступность, навигация, сохранения и ошибки.
- PR [#4](https://github.com/shonentez-afk/AI-Story-RPG/pull/4) **merged/squash** в `main`: **кодовый SHA `88a7c42091888bb81a62c68db49b7cd26f60f5e3`**. Проверенный HEAD PR: `92acae96aa016fb8638dc7dd6c6f77afe1216977`.
- GitHub Actions [#170 — run 41380322453](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41380322453): **completed/success, все 6/6 jobs PASS**, Flutter analyze **PASS**, Flutter widget/unit **92/92 PASS**, core/SQLite/BookWorld, Dart, Python **PASS**, Android debug APK **PASS**, Windows portable release **PASS**. Артефакты `AI-Story-RPG-Android-debug`, `AI-Story-RPG-Windows-portable`, `AI-Story-RPG-BookWorld-demo` присутствовали в run #170.
- В одном «Мои прохождения» доступен **один импорт .bwsave** (v1 пилот или v2 BookWorld по `format`); v2 проходит read-only preview + повторную native валидацию и добавляет только новый слот. Отсутствующий exact BookWorld объясняется без записи. Главное «Продолжить» ориентируется на фактический свежий timestamp двух сто́ров. Одна библиотека и одна CTA «Добавить книгу» (TXT/FB2/.bworld), исправлены общая сортировка/поиск/empty states, отзывчивость загрузки и ошибок, русские характеристики, reader chrome F11/Esc для книги/пилота/BookWorld, WCAG >=7:1 для четырёх основных читательских палитр.
- Старые `CampaignStore`, `SaveStore`, `GameProgress`, `.bwsave v1`, `.bwsave v2`, SQLite schema и исходные TXT/FB2 не конвертировались и не перезаписывались. **Не внедрять** вторую библиотеку, альтернативный импорт книг, новый пилотный storage, автоматическую legacy миграцию или другое несогласованное главное меню.
- **Ручные QA gates / SKIP:** настоящий Android/Windows FilePicker, запись и повторное открытие резервного файла после экспорта, двусторонний перенос по отдельным устройствам, отсутствие переполнения/артефактов на физическом телефоне и Windows, Tab/Shift+Tab/Enter/F11/Esc с настоящей клавиатурой, TalkBack/Narrator, rotation/200%, power-loss recovery. Перечень и критерии: `docs/M174C3_PORTABILITY_RECOVERY_RU.md` и полный аудит. Статус физического QA не повышать на основании CI.
- Известный старый читательский долг: сохранение позиции в длинном TXT/FB2 после смены шрифта/ориентации использует pixel offset; source-paragraph anchor остаётся отдельным улучшением при расширении читалки, не условием возврата к общему редизайну. Новый M2 Book Compiler/AI пока не реализован и должен добавлять функции в **существующий** единый импорт/Library и отдельный мастер конверсии, не выдавая TXT/FB2 за готовую RPG.
- **Следующий функциональный этап M2:** сначала прочитать `docs/TZ_RU.md`, `docs/ROADMAP_RU.md`, `docs/UI_UX_FINAL_AUDIT_M174C3_RU.md`, `docs/M174C3_PORTABILITY_RECOVERY_RU.md`; начинать с настоящего HEAD `main`. Построить Book Compiler (TXT/FB2 → source chunks/anchors/provenance → coverage → blueprint → проверенный .bworld) по принципу fail-closed; сохранять все существующие функции и обновлять этот handoff.
