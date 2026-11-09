# E6g — согласование внешнего RPG-автора с самостоятельным движком PR #133

**ИСТОРИЧЕСКИЙ baseline E6g 0.3.0a5.** Для текущего E6g `0.3.0a6` с реально исполняемым native v4 `build-extended` / `verify-extended` см. [E6G_NATIVE_V4_BRIDGE_RU_2026-11-08.md](E6G_NATIVE_V4_BRIDGE_RU_2026-11-08.md). Утверждение ниже «v4 не реализован» относится исключительно к старой редакции и не должно использоваться как текущий статус. Ограничение E6g StoryPlan ≤192 и отсутствие source-reviewed initial-state v4 остаются.

**Дата:** 8 ноября 2026. **Генератор:** `0.3.0a5`. **База независимого движка:** [7c4401c25b77e4643cf23000c28a717cb22dabca](https://github.com/shonentez-afk/AI-Story-RPG/commit/7c4401c25b77e4643cf23000c28a717cb22dabca) — рабочая ветка [PR #133](https://github.com/shonentez-afk/AI-Story-RPG/pull/133), **Draft**, не main. **Интеграционная ветка:** [feature/external-rpg-author-e6g-pr133-compat-20261108](https://github.com/shonentez-afk/AI-Story-RPG/tree/feature/external-rpg-author-e6g-pr133-compat-20261108).

## Изменения в коде (только независимый внешний генератор)

1. Взяты **существующие E6f исходники и тесты** из ветки `feature/external-rpg-author-e6f-npc-social-v5-20261107` (функциональный E6f исходник SHA `2d6b94e`, далее планы/документация), затем перенесены в **новую** интеграционную ветку, основанную непосредственно на PR #133. Не переписывали, не копировали и не модифицировали основное `story_core`, Flutter `apps/`, `packages/` и `tools/bookworld/`.
2. [tests/rpg_author/dart/probe.dart](../../tests/rpg_author/dart/probe.dart) больше **не импортирует** старые `apps/story_reader/lib/book_import.dart` / `book_source_index.dart`: теперь используется настоящий независимый `package:story_authoring/story_authoring.dart`. Его `pubspec.yaml` ссылается непосредственно на `../../../packages/story_authoring`. Это устраняет реальный сбой `Couldn't resolve package 'story_authoring'` в предыдущем PR #133 CI.
3. [compatibility.py](compatibility.py) поддерживает **обратно совместимый v1 SHA-256** и **новый v2 content-addressed Git blob SHA-1** для GitHub OID `blob <length>\\0<bytes>`. В [compatibility.json](compatibility.json) закреплены **26 реальных файлов** с конкретными хешами из кодовой базы PR #133: исходный API `packages/story_authoring/lib/src`, тонкие Flutter-экспорты, Python/Dart BookWorld writer/importer, NPC/social, SQLite и runtime adapter. `doctor` проверяет **байты** и останавливается с `contract_drift` при несоответствии: не добавлять новый SHA без разборки изменённого API.
4. Добавлен регрессионный тест проверки v2 lock и отказа на изменении любого из наиболее важных файлов: `story_authoring` importer/index, BookWorld import/writer.
5. Версия генератора повышена до `0.3.0a5`. Старые проекты с иным `toolchain_sha256` по-прежнему **fail closed**; не подменять исходный `project.json` или lock. Прежняя E6f версия остаётся для старых проектов и сравнения.

## Степень совместимости — не завышать

- **Работает по контракту:** внешний Python-автор E6f создаёт *source-bound PRIVATE* `.bworld format_version=3`; действующие Python writer/reader и реальный Dart `RichPrivateBookworldImporter` PR #133 должны согласованно принимать его. Его NPC social v5, ownership, knowledge, replay, SQLite restart/fork и `.bwsave` проверяются на **синтетических** сценариях.
- **Новый v4 в native:** PR #133 добавил `format_version=4` с расширенными лимитами, временем и подтверждённым исходным состоянием. **E6g НЕ выдаёт v4 и не повышает v3 автоматически:** он по умолчанию по-прежнему собирает проверенный v3. Для настоящего v4 нужен отдельный опциональный source-reviewed writer/adaptor к native `story_authoring`, расширение Python schema и независимые негативные тесты; не маскировать v3 как v4. Текущий native CLI `build-extended` используется отдельно, не подменяется Python.
- **Режимы:** `PROTAGONIST / ALTER_FATE / CLASSIC`. Нет нового `CANON`, `BOOK_CHARACTER`, `CUSTOM`, `AI_FREEFORM`, walkable Flame или свободной генерации оригинальных миров из-за одной лишь синхронизации исходников.
- **Интеграционный фикс не означает:** полную литературную проверку реальной книги, живой GLM, физическую приёмку APK/Windows, разрешение на публикацию или криптографическую аттестацию ИИ.

## Верификация

- [Базовый E6f CI #42341605734](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42341605734): SUCCESS (Python автор + Dart parity, SQLite, social v5) на **старом main**.
- [Новый E6g CI #42492729690](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42492729690): **COMPLETED SUCCESS** — `author-tests` и `dart-parity` на **реальной ветке PR #133** после замены импортов и контентного замка. Точный SHA `a38aa1be67461cc8fa5bb2fb6013b72d18f78700`.
- [Полный E6g 0.3.0a5 + lock-regression CI #42493017684](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42493017684): точный SHA `3e0d7c6e2124f2dfe4e57b5e31889cc6842cc336`; **COMPLETED SUCCESS** — `author-tests` и `dart-parity` оба SUCCESS. Подтверждённый exact-code SHA `3e0d7c6e2124f2dfe4e57b5e31889cc6842cc336`.
- Основной PR #133 держать Draft; его самостоятельный Android/Windows/Flutter CI зависит от отдельной native работы и **не является целью E6g**.

## Что делать дальше

1. Дождаться и проверить точный head E6g `author-tests` и `dart-parity`. При ошибке исправить её **только** в `tools/rpg_author/` или `tests/rpg_author/`.
2. Когда CI зелёный, сделать один согласованный PR **E6g → текущая feature-ветка PR #133**, не `main`. В PR — только внешний генератор и его тесты. Не нажимать Merge до подтверждения основного native ответственного потока.
3. Когда PR #133 изменится, сравнить реальные 26 upstream-файлов; если байты и API те же, pin остаётся доказанным. При разрыве сначала исследовать код, затем обновлять pin и повторять Python/Dart parity; **не** менять хеши ради зелёного CI.
4. Встроенный ChatGPT-навык `ai-story-book-to-rpg` по-прежнему bootstrap-pinned к **E6d `9849c22…` / `0.3.0a2`**. Он автоматически **не** стал E6g; обновление его bootstrap/instructions — отдельная явная процедура после приёмки генератора.
5. Не выводить личную FB2, литературу или приватные модели в GitHub Actions. Реальный E2E на двух русских книгах и устройствах — отдельный обязательный QA.

**Инвариант:** независимый `story_core` остаётся единственным исполнителем фактов и событий; Python не клонирует WorldEvent, SQLite и права NPC. E6g — привязка внешнего автора к совместимому API, **не второй движок**.
