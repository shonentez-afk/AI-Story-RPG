# M1.7.3 — формат BookWorld ZIP/SQLite, офлайн-компилятор и импорт

**Базовый коммит:** `c89e230fe89a9e45611bc07cf332a9ffbda2b7c0` (документация поверх PASS-кода M1.7.2 `8fef115`). **Новые исходники:** `7c3923492118a7aef9c9ecda3e0c319a2961499f`.

## 1. Что реально реализовано

ТЗ `docs/TZ_RU.md` §7.1 требует `.bworld` ZIP, manifest.json, world.sqlite, безопасный импорт; §7.3 запрещает зависимости runtime от Python.

- **Python-компилятор офлайн:** `tools/bookworld/bookworld.py`, команды `build` и `verify`. Из подготовленного `shared_schemas/fixtures/manor_world_m17.json` формирует реальный SQLite и ZIP. Python работает ТОЛЬКО при компиляции/диагностике, не нужен игре.
- **Dart runtime-пакет:** `packages/bookworld_format`, `BookworldImporter.inspect(Uint8List)` возвращает `VerifiedBookworld` с проверенным `StoryBlueprint`. Отдельный пакет; его пока **нет в текущем GUI**. Он читает собранный Python пакет напрямую, затем успешный тест запускает `StoryEngineCoordinator.start(...)`, применяет ход и восстанавливает checkpoint.
- **Манифест версии 1:** `shared_schemas/v1/bookworld_manifest.schema.json`. Идентификатор, название, автор, язык ru, engine_min_version, source_fingerprint, rights_status, versioned scenario, supported_modes, build_tool, model_provenance, build_status, размеры, SHA-256 обоих payload и hash точного blueprint.
- **Настоящая нормализованная `world.sqlite`:** 9 таблиц `world_meta`, `scenes`, `choices`, `actors`, `items`, `canon_facts`, `source_refs`, `event_dependencies`, `templates`. В original-demo таблицы исходных цитат/зависимостей/шаблонов остаются пустыми — нельзя выдавать несуществующие ссылки на главы за реальные. Строки сцен, переходов, условий, эффектов и каталоги сравниваются с точным JSON blueprint; повторный `PRAGMA integrity_check`, `foreign_key_check`, `application_id`, `user_version` и защита от неожиданных таблиц/триггеров/представлений.
- **ZIP v1 — предельно узкий и проверяемый поднабор:** ровно `manifest.json`, `scenario/blueprint.json`, `world.sqlite` в фиксированном порядке. Записи только `ZIP_STORED` без шифрования, Zip64, compression ratio, ссылок, data-descriptors, extra fields, комментариев, directory traversal, абсолютных путей и неоднозначных локальных/центральных заголовков. Архив максимум **12 МиБ**, один payload максимум **8 МиБ**, общий declared payload максимум **16 МиБ**. Данные не распаковываются в произвольный пользовательский путь; временная копия SQLite создаётся в приватной временной директории и обязательно удаляется.
- **Ограничение правового статуса:** v1 принимает ТОЛЬКО наш собственный тестовый сценарий с `rights_status=original_demo`, `source_fingerprint=null`, `model_provenance={provider:none,model_id:null}`; только `PROTAGONIST/CANON/CLASSIC`. В пакет не включается текст чужой книги или картинки с неизвестными правами. Это намеренное ограничение версии 1. Поля rights_status и model_provenance являются декларациями сборщика, а не криптографическим доказательством авторских прав; SHA-256 выявляет изменение содержимого, но без подписи не доказывает происхождение пакета.

## 2. Где исходники и сценарий

```text
tools/bookworld/bookworld.py                    # Python build/verify
tools/bookworld/tests/test_bookworld.py         # вредоносные/повреждённые архивы
packages/bookworld_format/lib/bookworld_format.dart  # Dart импорт/manifest
packages/bookworld_format/lib/src/zip_v1.dart       # строгий ZIP reader
packages/bookworld_format/lib/src/sqlite_v1.dart    # read-only SQLite audit
packages/bookworld_format/test/bookworld_import_test.dart
shared_schemas/v1/bookworld_manifest.schema.json
shared_schemas/tests/test_bookworld_manifest_schema.py
shared_schemas/fixtures/manor_world_m17.json  # собственные 8 сцен
```

## 3. Как воспроизвести без Android и GUI

Из корня репозитория (Python 3.11+, компилятор использует только стандартную библиотеку):

```bash
mkdir -p artifacts/bookworld
python3 tools/bookworld/bookworld.py build --blueprint shared_schemas/fixtures/manor_world_m17.json --output artifacts/bookworld/manor_m17_original_demo.bworld
python3 tools/bookworld/bookworld.py verify --input artifacts/bookworld/manor_m17_original_demo.bworld
python3 -m unittest discover -s tools/bookworld/tests -v
python3 -m pip install jsonschema==4.23.0
python3 -m unittest discover -s shared_schemas/tests -v
cd packages/bookworld_format
dart pub get
dart analyze
dart test --reporter expanded
```

CI по пути `.github/workflows/android-ci.yml` делает это автоматически в блокирующем job `story-core` ДО Android/Windows. Готовый `.bworld` и `SHA256SUMS.txt` доступны как artifact `AI-Story-RPG-BookWorld-demo` у успешного workflow (если job artifact upload завершился).

## 4. Security/QA матрица

- Позитивные: одинаковый пакет на повторной компиляции; 8 сцен/15 вариантов, читаемая реальная база SQLite; Python и Dart самостоятельно проверяют ZIP+CRC+хеши, метаданные, таблицы, правила; Dart передаёт мир в реальный `story_engine` через `StoryEngineCoordinator`.
- Негативные: обрезанный ZIP, лишние байты/entry, запрещённые пути, сжатый ZIP, битый CRC, неверные версии, подмена прав/режимов, неверный SHA, изменённые сцены при пересчитанных SHA, подложный SQLite, trigger, удалённое metadata, отсутствующая сцена, повтор choice ID.
- **Неисполнено в v1:** streaming ZIP и сжатые/большие вложения; любые `assets/`, `source/`, EPUB/PDF/FB2→сценарий; полный перенос первоисточников и provenance/coverage, FTS5, реальные книги, Unicode paths в ZIP.
- **Неисполнено в пользовательском UI:** кнопка «Импортировать .bworld», локальное постоянное хранение BookWorld, SQLite/Drift кампания с транзакционным восстановлением и миграцией M1.6. По ТЗ это M1.7.4 и M2. Нельзя выдавать автономный Dart импорт за уже работающий UI-импорт на Android/Windows.
- **Детерминированный .bworld ZIP hash** проверен на одной версии Python+SQLite; между разными SQLite версиями сериализованные байты могут отличаться при одинаковых данных, поэтому совместимость определяется версии/schema, SHA-256 конкретного пакета и проверкой содержимого, а не универсальным одинаковым бинарным хешем при любых компиляторах.
- Отдельные тесты Dart импорта в CI выполняются на **Linux**. Android/Windows jobs сейчас собирают прежний Flutter app, который новый пакет не импортирует. Реальный импорт/запуск того же .bworld на физическом Android и Windows **SKIP** до интеграции.

## 5. Приоритет следующего этапа M1.7.4

1. Реальное долговременное `BookworldStore` на платформенном SQLite/Drift, безопасный импорт через file picker и копирование после проверки в приватный каталог с атомарным rename/rollback.
2. Сохранение `StoryRuntimeAdapter` и `WorldState` + event log в одной SQLite транзакции с подтверждённым head и recovery; перезапуск/сбой питания.
3. Параллельное сохранение legacy `CampaignStore`, `GameProgress`, `rulesVersion=0/1` и `.bwsave`, без потери пользовательских книг и прохождений; миграция с бэкапом и тестами.
4. UI мастер запуска и список миров **без второй библиотеки и второй кнопки импорта**; минимум 20 игровых ходов, полноценный Android/Windows E2E и экспорт/импорт сохранения.
5. Только затем M2 Compiler (настоящие источники, coverage, provenance) и AI/HYBRID.

**QA текущего SHA:** результаты Python/Dart/Flutter, Android/Windows и артефакт следует заполнять только по GitHub Actions этого коммита. Если здесь нет подтверждённого PASS — нельзя писать, что весь этап принят.

## QA M1.7.3 — подтверждённый CI PASS (2026-11-02)

- **Проверенный SHA исходников:** `7c3923492118a7aef9c9ecda3e0c319a2961499f`.
- **GitHub Actions #143:** [run `41338634157`](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/41338634157) — **completed / success**, 6/6 заданий PASS.
- **Python-компилятор и безопасность ZIP/SQLite:** **12/12 PASS**.
- **JSON Schema:** **9/9 PASS** (6 старых blueprint+3 новых manifest).
- **Dart `story_core`:** **10/10 PASS**, `story_runtime_adapter`: **9/9 PASS**, новый `bookworld_format`: **5/5 PASS**; все `dart analyze` без замечаний.
- **Flutter analyze:** PASS, **Flutter widget tests: 71/71 PASS**, другие Dart M0 и Python reference tests PASS.
- **Windows portable bundle:** PASS, artifact `AI-Story-RPG-Windows-portable`.
- **Android debug APK:** PASS, artifact `AI-Story-RPG-Android-debug`; [GitHub prerelease `android-build-143`](https://github.com/shonentez-afk/AI-Story-RPG/releases/tag/android-build-143) с `AI-Story-RPG-M1-debug.apk` и `SHA256SUMS.txt`.
- **Собранный демомир:** artifact `AI-Story-RPG-BookWorld-demo` в run #143, файлы `manor_m17_original_demo.bworld` и `SHA256SUMS.txt`. Размер архива мал (8 сцен, 15 choices), содержимое реально проверено Python и Dart.
- **Контрольная сумма .bworld:** `e150d4c4b004106d162ed323843cc78fdacf2eaa0316d3651ab447a7d45fa9a4`. **SHA canonical blueprint:** `85beede9694a277bf48fc256ad75f4c4d32aab1c412e9181f2990f3bdff9a815`.
- **SKIP:** Android/Windows native execution `BookworldImporter` в UI, device accessibility, SQLite/Drift сохранения кампаний, M1.6 миграция, передача `.bwsave`, импорт произвольной книги и FTS5. Сборки Flutter успешны, но пока не включают `bookworld_format` как пользовательскую функцию.

**Решение:** M1.7.3 **принят как формат+компилятор+изолированный Dart-импорт по автоматическим контрактам**. Это не приёмка M1.7.4 и не доказательство работы пользовательского импорта `.bworld` на Android/Windows.
