# E6h — source-locked v4 expansion, 203+ сцен и начальное состояние

**Дата:** 9 ноября 2026. Только внешняя ветка генератора; `main`, PR #133,
Flutter, native Dart и `tools/bookworld` не изменяются. Версия `0.3.0a7`.

## Новый крупный функциональный пакет

- `build-extended --extension PRIVATE.json` (явно и только v4) принимает
  подписанный конкретными редакторскими решениями JSON. Сначала строго
  собирается прежний проверенный v3-проект, далее по заданным **оригинальным
  переходам** вставляются сцены с точными `assertion_ids`. Каждая сцена
  содержит цитату в уже анализированной части книги, chapter индекс,
  пометку `SOURCE_PASSAGE` или `EXPLICIT_ADAPTATION`, заголовок и
  один проходной выбор. Новые сцены **не добавляют произвольные эффекты**.
  Начальный и конечный акты ребра не могут быть переставлены.
- Проверяются источник/StoryPlan/enrichment/базовый blueprint SHA,
  явная редакторская проверка причинности, граница ≤1024 сцен, глобально
  уникальные имена сцен и решений, ссылки на точные UTF-16 цитаты,
  монотонный порядок глав и согласованная provenance.
- Необязательный `initial_state` позволяет указать начальные предметы,
  знания конкретных actor IDs и tick. Предметы/знания должны существовать
  в проверенном каталоге и ссылаться на `SOURCE_PASSAGE` с видимой
  цитатой из главы 0. `initial_state_review` создаётся в точном
  формате native v4; формула литературного канона остаётся `false`.
- `audit-extended` делает автономный read-only preflight на проверенном
  E6g проекте. Не вызывает Dart, не пишет архив и **не выдаёт**
  литературный/игровой сертификат.
- Реальную причинность всего мира, предел 8000 состояний, 2 финала,
  private ZIP/SQLite/replay и начальную проверку выполняет только
  встроенный `packages/story_authoring/bin/author_book.dart` v4.

## Частный manifest расширения — точная форма

```json
{
  "format": "rpg_author_v4_extension_v1",
  "source_fingerprint": "<64-символьный SHA>",
  "story_sha256": "<64-символьный SHA>",
  "enrichment_sha256": "<64-символьный SHA>",
  "base_blueprint_sha256": "<SHA канонического принятого v3 blueprint>",
  "editorial_review": {
    "user_confirmed": true,
    "transition_causality_reviewed": true,
    "literary_canon_verified": false
  },
  "insertions": [
    {
      "after_choice_id": "existing_choice",
      "scenes": [
        {
          "id": "additional_scene_1",
          "title": "Глава",
          "text": "Подтверждённый игровой текст.",
          "chapter_index": 0,
          "origin": "SOURCE_PASSAGE",
          "assertion_ids": ["source_assertion_from_exact_chunk"],
          "choice_id": "additional_continue_1",
          "choice_label": "Далее"
        }
      ]
    }
  ],
  "initial_state": {
    "tick": 0,
    "items": [{"item_id": "existing_item", "assertion_id": "chapter_zero_assertion"}],
    "facts": [{"actor_id": "player", "fact_id": "known_fact",
               "assertion_id": "chapter_zero_assertion"}]
  }
}
```

Если начальных грантов нет, `initial_state` ставится **null**, а не
пустым объектом. Все хеши/цитаты берутся только из фактически принятых
приватных контрольных точек, не из названия книги. В общем случае
нужен литературный осмотр и свободное исправление текста вручную.

```sh
python3 -m tools.rpg_author audit-extended --project /private/project \
  --enrichment /private/enrichment.json --extension /private/extension.json
python3 -m tools.rpg_author build-extended --project /private/project \
  --enrichment /private/enrichment.json --extension /private/extension.json \
  --output /private/game_v4.bworld
python3 -m tools.rpg_author verify-extended --input /private/game_v4.bworld \
  --attribution /private/game_v4.attribution.json
```

## Не считать готовым

Это **способ ввести больше 192 проверяемых сцен**, а не автоматическое
создание литературы на все главы. Новые проходные сцены не создают
свободного AI-GM, CANON, новых возможностей персонажа, предметного
графа или автоматического редакторского качества. Возможны пропуски
глав, о них честно пишет `audit-extended`. Старые снимки E6d/E6f/E6g
не мигрировать — идентификатор инструмента изменён. Приватные книги
не загружать в публичные Actions. Физический Windows/Android E2E и
две настоящие русские FB2 ещё остаются.

## Подтверждённая приёмка E6h

Внешняя ветка, **исполняемый код SHA c4334298c3e3eb5b512a73631d6c11281d0a1cba**.
[GitHub Actions #42516846711](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42516846711): **COMPLETED SUCCESS**, оба задания author-tests и dart-parity.

Dart parity фактически сообщил **native_v4_203_source_locked_scenes_replayed=true** и **native_v4_initial_item_and_tick_review_verified=true**. Тест проверил 203 сцены, достижимость двух финалов, штатные Dart v4 writer/importer и начальные предмет/время. Старые Python rich v3, NPC social v5, SQLite restart/fork, .bwsave и негативные атрибуции также остались успешны.

**Ограничение:** 199 переходных синтетических сцен имеют один исходный фрагмент; повторяющиеся цитаты проверяют транспорт/ёмкость/реплей, но НЕ 199 уникальных событий или литературный смысл. Реальные главы, оригинальные события, взаимоотношения NPC и полноценный свободный сюжет требуют отдельной проверки. Редакторское user_confirmed не является криптографическим аттестатом. На момент этой приёмки pinned upstream native SHA остаётся 233c6c3; последний PR #133 менялся, его совместимость требуется проверять отдельно.

**Следующий функциональный этап E6i:** source-locked многоглавные акты с реально подтверждёнными событиями и выбором, причинные последствия NPC/предметов/знаний, отдельная проверка повторов/спойлеров/событий и полноценные сценарии реальных книг. Не изменять native Dart и старые сохраняемые форматы без отдельного согласования.
