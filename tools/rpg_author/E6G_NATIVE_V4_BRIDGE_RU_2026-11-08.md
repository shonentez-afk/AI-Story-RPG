# E6g 0.3.0a6 — реальная native Dart сборка private BookWorld v4

**Дата:** 8 ноября 2026. **Ветка:** [feature/external-rpg-author-e6g-pr133-compat-20261108](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6g-pr133-compat-20261108). **Зависимость:** точный native PR [#133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), база `7c4401c25b77e4643cf23000c28a717cb22dabca`. Этот документ описывает **реально реализованный opt-in**; не заявление о полных 1024 литературно проверенных сценах.

## Результат

- [native_v4_bridge.py](native_v4_bridge.py): исходный E6g проект сначала проходит **весь существующий Python source-locked StoryPlan, rich-v3 game rules, NPC и review-пайплайн**. Проверенный blueprint/provenance извлекается из реального v3; исходный оригинал читается из подтверждённого приватного checkpoint через `load_project` и SHA. Временные исходник и JSON помещаются **только во внешнюю приватную временную директорию**.
- В этой директории вызывается **штатный самостоятельный** `packages/story_authoring/bin/author_book.dart build-extended`. Не создаётся отдельный Python writer для v4, не обходятся `BookAuthoringEngine.buildReviewedPrivateWorld` и `RichPrivateBookworldImporter`. Передаётся оригинальное имя TXT, а не абсолютный временный путь, иначе native fingerprint **обоснованно** отвергал проект; ошибка была обнаружена CI #42495478060 и исправлена без изменения правил.
- `build-extended` возвращает **реально прочитанный native v4 архив** (`format_version=4`, `private_extended_structural`), независимо проверяет 4 ZIP_STORED члена/хеши/SHA, source fingerprint и private-only модель. Отдельная `verify-extended` дополнительно запускает реальный Dart `verify-world` и проверяет точную атрибуцию. Проверяемый sidecar отличает `version=4.0` от `3.0`, и подмена модели отвергается.
- `build` / `verify` для старого rich-v3 **не затронуты**, по умолчанию `format_version=3`. Версия внешнего генератора **0.3.0a6**; старые project checkpoints блокируются по честному `toolchain_changed`, без подмены истории проекта.
- Native Dart script `packages/story_authoring/bin/author_book.dart` добавлен в строгий совместимый upstream lock (**27** files: original engines, rich Python/Dart, standalone authoring, SQLite/NPC, companion UI facade). Изменение любого pinned байта даёт `contract_drift`; проверяемая версия PR #133 не приравнивается к `main`. Старый E6f остаётся для своих проектов.
- Команда исполняет Dart VM с pinned `package_config.json`, сначала ищет `packages/story_authoring/.dart_tool/package_config.json`, затем изолированный `tests/rpg_author/dart`. Рабочая директория — приватный каталог книги. Поэтому **весь приватный текст остаётся вне checkout**, а название TXT не меняется при переупаковке.

## Вызов внешнего автора (после проверенного StoryPlan и enrichment)

Нужен установленный Dart SDK и заранее разрешённые локальные зависимости:
```sh
cd packages/story_authoring
dart pub get
cd ../..
python3 -m tools.rpg_author doctor
python3 -m tools.rpg_author build-extended --project /private/project --enrichment /private/enrichment.json --npc-review /private/npc_review.json --output /private/game_v4.bworld
python3 -m tools.rpg_author verify-extended --input /private/game_v4.bworld --attribution /private/game_v4.attribution.json
```
Аргумент `--npc-review` необязателен; личные книги, YAML/JSON редакторской проверки и итоговые миры должны оставаться приватными. Не менять source после зафиксированного литературного анализа. Команды возвращают машинно-читаемые ошибки/ненулевой exit code при неверных источниках и неподдерживаемых возможностях. **Не запускать build-extended вместо finalize, literary-review или gameplay/dialogue-audit**: для готовой игры эти проверки всё ещё обязательны.

## Доказательства (синтетика, не приватная книга)

- [CI #42495808223](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42495808223), точный code SHA `3c06489798fd74b5281488a935b8210b7661f99a`: **COMPLETED SUCCESS**, оба `author-tests` и `dart-parity`. Native Dart `build-extended` после исходного Python v3+source check; import strict v4; два терминальных исхода; replay; SQLite restart, fork и portable save; v5 NPC memory/knowledge; отказ при forged attribution.
- [CI #42495478060](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42495478060): FAIL *с полезным подтверждением защиты* — без фикса имени TXT native editor вернул отказ «Авторский проект не привязан к полной исходной редакции книги». Код исправлен с сохранением строгой проверки; это не тест, который был выключен.
- Новый набор [test_native_v4_bridge.py](../../tests/rpg_author/test_native_v4_bridge.py): отдельный явный CLI, сохранение имени из приватной cwd, отклонение неверных путей, нестандартной разбивки книги и подмены v3→v4. **Точный final CI для 0.3.0a6 перепроверять после последнего кодового коммита.**

## Честные пределы интеграции

1. **Это v4-пакетирование E6g StoryPlan старого масштаба**, а не доказательство автоматической генерации 1024 сцен. Механическая ёмкость v4 и литературная полнота — разные задачи. Новые v4-only `initial_state_review` (начальные владения/знания/tick), `tick_at_least`, `advance_time`, 1024 scenes **пока нельзя создавать этим Python-адаптером**: для них нужны source-reviewed v4 schema и расширенные проверяющие authoring/logic gates или использование отдельно согласованных native `build-draft-extended` checkpoints.
2. **Никаких изменений `main`, `apps/`, `packages/`, `tools/bookworld/`, нативного CI.** Аудит разрешённой области — только `tools/rpg_author/`, `tests/rpg_author/`.
3. **CI тестирует синтетический мир.** Автоматическая литературная адаптация двух реальных FB2, выбор реального героя, реальные финалы, GLM, Windows/Android E2E и права публикации не подтверждены.
4. **Установленный навык ChatGPT `ai-story-book-to-rpg`** по-прежнему bootstrap-pinned к E6d `9849c22d…` / `0.3.0a2`: новый рабочий код **не устанавливается в навык автоматически**. При обновлении навыка необходимы отдельные bootstrap, SHA и end-to-end acceptance.

## Следующий функциональный шаг

Согласовать расширенный, source-locked **StoryPlan v4** с реальным native `build-draft-extended` (без перемещения собственной логики `story_core` в Python); подать через новый адаптер 203+ подтверждённых сцен и реальные исходные состояния, проверить reject без initial-state review, два финала, подписанные NPC и чистый import на Windows/Android. Изменять native пакеты только по отдельному явному разрешению. Приоритет реальной книжной P0-приёмки сохраняется.
