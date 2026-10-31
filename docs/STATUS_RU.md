# Текущий статус AI Story RPG
**Дата:** 2026-11-01. **Состояние:** PROJECT_BOOTSTRAP / SPECIFICATION.

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
