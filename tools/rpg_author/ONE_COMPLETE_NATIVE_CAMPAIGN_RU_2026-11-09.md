## ЕДИНАЯ ПРИЁМКА: полный проверяемый книжный мир, 9 ноября 2026

**Доказанная точная версия кода:** `658eac6ab4cc324cd2f22417c54936935610e68c`
**Actions #42547920109:** https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42547920109
**COMPLETED SUCCESS** на одной версии: `author-tests=SUCCESS` (155 основных
+ 37 дополнительных Python тестов), `dart-parity=SUCCESS`.
Задание Dart публикует `complete_private_book_two_native_ending_routes_verified=true`.
Все прежние rich-v3, v4, multi-act, 203-scene, NPC-Social, knowledge,
dialogue redaction, item custody и SQLite-регрессии оставались успешны.

Нативный Dart действительно сформировал и импортировал приватный
BookWorld v4 с 3 главами исходной авторской синтетической FB2 и 8 сценами.
Один `finalize-extended` сначала сформировал source-locked pending-шаблон
для литературного прохода, не создав игру. Затем авторская фикстура
заполнила его, и та же команда провела РОВНО ДВА РАЗНЫХ законченных
игровых маршрута через `LocalRpgGameApi`, проверила различные концовки
и целостность переносимых SQLite-сохранений, после чего записала
`game.bworld`, `game.attribution.json`, `game.readiness.json`.

Обновлённый native pinned commit PR #133:
`b7581f71d8a14f4fd4679979ef0be94ae412f11b`. Из 27
закреплённых зависимостей изменён **один** файл
`packages/story_authoring/lib/story_authoring.dart`,
в нём только два новых публичных экспорта; по сравнению с предыдущим
pin игровой core/importer не менялись. Пины обновлены после
проверки точных Git blob SHA, а не принудительно.
Код E6 major-block не затрагивал `main`, Flutter, packages или
основной CI, всё сделано только в `tools/rpg_author/` и
`tests/rpg_author/`, без мелких PR.

**Важные НЕ закрытые критерии конечного продукта:**
генератор пока НЕ выполняет сам по одному вызову ни полный анализ
литературы моделью, ни самостоятельное составление всех мировых
событий и NPC, ни смысловую независимую проверку; для этих задач
нужны входные editorial/extension данные либо внешний агент ChatGPT.
Синтетическая QA на 3 главы ≠ проверка на 2 реальных русских FB2.
Нет Windows/Android physical E2E, настоящей литературной правки
и свободного AI GM. `user_ready=false`, `literary_truth_attested=false`.
Установленный ChatGPT skill закреплён на старом E6d,
его обновление является частью дальнейшей единой приёмки.

**Следующий ОДИН большой пакет, без микро-PR:** сквозное автоматическое
производство авторских данных из полной книги с использованием уже
готовых чистых Dart `RpgCreationPolicy` / `RpgMultiActTrialApi`,
`RpgProposalReviewApi`, `RpgCampaignProseApi`; полная приватная
литературная и игровая приёмка на двух настоящих FB2, затем
обновление установленного навыка и проверка Windows/Android клиента.
Не возвращаться к отделению полей, кнопок и отдельных мини-этапов.

---
# AI Story RPG — единый процесс завершения всей частной RPG

**9 ноября 2026 | внешний генератор `0.3.0a11` | единая функциональная приёмка**

## Зачем сделано

Ранее наружный генератор умел отдельно создавать v3/v4, авторить NPC
в двух актах, подписывать говорящих, передавать предметы и выполнять
раздельные аудиты, но не имел одного воспроизводимого условия завершения
ВСЕЙ RPG из книги. В этой поставке один финализатор проверяет
всё вместе — без микро-PR и без подмены двигателя Python-копией.

## Граница ответственности

- `tools/rpg_author`: сохраняемые source-locked checkpoints книги,
  независимая декларативная редакторская проверка и локальная CLI-обвязка;
- `packages/story_authoring` + `bookworld_format`: штатная сборка и
  независимо проверенный исходник `.bworld v4`;
- `packages/rpg_api`, `rpg_gameplay`, `story_core`, `campaign_manager`:
  единственный исполняющий правила интерфейс и SQLite-сохранения;
- Flutter, Dart CLI или будущий сервис — клиенты одного API.

Внешний Dart probe `tools/rpg_author/dart/route_probe.dart` выполняет
две законченные партии через `LocalRpgGameApi`, сверяет доступность
каждого выбора, разные реальные концовки, целостность stateHash,
перенос каждого `.bwsave`. Никаких своих правил боя, NPC, свободного
текста, inventory или knowledge в Python нет. После проверки
probe удаляет локальные приватные временные каталоги.

## Вход одной команды

1. Уже полностью проанализированный приватный FB2/TXT проект
   `init → accept-analysis (ВСЕ chunks) → accept-story`.
2. `rich_enrichment_v1` + при NPC отдельный `--npc-review` v5.
3. `rpg_author_v4_acts_v1/v2/v3`, созданный при авторской
   source-locked проверке; минимум два акта и одна исходная игровая
   сцена в каждой физической главе исходника.
4. `--review`: один отдельный `rpg_author_complete_multi_act_review_v1`.
   Он содержит `format`, `source_fingerprint`, `extension_sha256`,
   `blueprint_sha256`, `user_confirmed=true`,
   `review_method=independent_ai_pass`, `review_completed=true`,
   `literary_canon_verified=false`, `aspects` с шестью значениями `pass`,
   пустой массив `issues`, `scenes`, `routes`.

`scenes` — ОДНА запись для каждой скомпилированной сцены, включая
старые сцены, NPC-разговоры и дополнительные акты:
`{scene_id,origin,verdict:"pass",notes,source_quote_sha256:[...]}`.
Значение `origin` ОБЯЗАТЕЛЬНО совпадает с `SOURCE_PASSAGE`
или `EXPLICIT_ADAPTATION` в подписанном BookWorld: нельзя выдавать
игровую выдумку за фразу оригинального произведения.
Список SHA-256 обязан ТОЧНО совпадать с подписанными
`provenance.scene_origins[*].source_refs`. Ни одного непроверенного
фрагмента книги или пропущенной главы.

`routes` — две записи `{id,choice_ids,expected_ending_scene_id,notes}`
по 2–512 действий, без прежнего искусственного лимита 24 ходов. Концовки должны быть разными и терминальными;
редактор не может объявить пути пройденными, не передав их в настоящий
игровой API. Декларация PASS не доказывает качество художественной
интерпретации, поэтому результат не ставит `user_ready=true`.

### Два прохода одной команды, без обязательной ручной разметки SHA

Если `--review` ещё не существует, первый вызов выполняет исходную
проверку и native v4-компиляцию во временной папке, затем создаёт
ТОЛЬКО приватный `whole-book-editorial-review.json` с SHA всех
подписанных сцен и статусами `pending`; исходы и литературные
оценки остаются НЕ подтверждены, `routes=[]`, `user_ready=false`.
CLI возвращает код `3` как обозначение незаконченной приёмки и
**не записывает** `.bworld`, `.attribution` и `.readiness`.

ChatGPT/редактор выполняет отдельный смысловой проход по книге,
заполняет `aspects`, `scenes` с проверенными `notes/verdict`,
две настоящие маршрутизации `routes`, подтверждает приватный
использовательский review. Повторный вызов ТОЙ ЖЕ команды проводит
оба пути через штатный API и выдаёт три файла лишь при полном PASS.
Не разрешено автоматически превращать исходный `pending` в `pass`.
## Запуск

Сначала разрешить Dart зависимости (`dart pub get` в
`packages/story_authoring` и в `tools/rpg_author/dart`, либо для CI
в `tests/rpg_author/dart`). Все исходники и результаты — вне checkout.

```bash
python3 -m tools.rpg_author doctor
python3 -m tools.rpg_author finalize-extended \
  --project /private/author-project \
  --enrichment /private/enrichment.json \
  --npc-review /private/npc-base.json \
  --extension /private/fully-reviewed-multi-act-v3.json \
  --review /private/whole-book-editorial-review.json \
  --no-interactive-questions \
  --output /private/game.bworld
python3 -m tools.rpg_author verify-extended \
  --input /private/game.bworld \
  --attribution /private/game.attribution.json
```

Если есть интерактивные вопросы (отличны от сценарных подписанных
реплик NPC), передать `--dialogues` вместе с независимым
`--question-inventory` вместо `--no-interactive-questions`.
Декларация отсутствия вопросов не является независимым доказательством.

Результат после ВСЕХ успешных проверок: `game.bworld`,
`game.attribution.json`, `game.readiness.json`. Существующие
файлы не перезаписываются. Если хоть один путь нельзя пройти
или сохранение не восстановилось, файлы игры не публикуются.

## Приёмка и честные ограничения

Тест: авторская русская синтетическая FB2 «Три берега», 3 физические
главы, 2 акта, 8 подписанных сцен, действующий NPC с постоянным
character_id и памятью, два сценария с разными финалами,
source-locked цитаты, реальное владение верёвкой, закрытые/открытые
реплики и SQLite .bwsave. Все проверки Python и Dart на одном SHA
обязательны до заявления о приёмке.

Это **не** доказательство того, что ИИ теперь способен
самостоятельно сочинить хорошую RPG из произвольного романа.
Прежний навык ChatGPT закреплён на E6d; в рамках этого кода
он не устанавливался и не изменялся. Нет реального
литературного/модельного E2E на двух пользовательских русских FB2,
нет Windows/Android device playtest и нет проверки качества
свободной генерации диалогов ИИ в приложении.

## Следующий большой блок (не микро-PR)

После этой приёмки — единый генеративный маршрут от исходной книги:
объединить анализ всей книги, главы/события/паспорта NPC,
авторство маршрутов и исходно подтверждённый сценарий с
`RpgMultiActTrialApi`, `RpgProposalReviewApi` и `RpgCampaignProseApi`.
Потом одно сквозное испытание на двух настоящих FB2 и клиентах.
Не возвращаться к PR на отдельное поле, кнопку, цитату или экран.
