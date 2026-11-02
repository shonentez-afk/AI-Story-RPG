# M2d — приватный BookWorld v2: типизированный перевод, архив и независимая проверка

Дата: 2026-11-02. Предыдущие принятые блоки: M2b4a, M2b4b/M2c (#21–22), однокнопочная подготовка (#23), M2d preflight (#24).

## Реализовано на ЭТОЙ ветке (до CI — только CODE)

1. `private_classic_scenario_translator.dart` проверяет index/evidence/catalog/editorial/draft через `PrivateAdaptationPreflight`, разрешает только права `privateUse` и переводит M2c `requires/forbids/adds/removes` в typed `flag_is/set_flag` движка. Делает отдельный `ai_story_private_provenance_v1` со ссылками на главы, chunk ID, UTF-16 offsets, quote SHA256, хешами каталога и сценария. В сырых данных не сохраняются ключи, сетевые настройки и копия всей книги.
2. `StoryBlueprint.fromJson` принимает **отдельный** `private_adaptation` с SHA fingerprint и только `PROTAGONIST / ALTER_FATE / CLASSIC`. Исторический `original_demo` по-прежнему строго требует null fingerprint и `CANON / CLASSIC`.
3. Новый `.bworld` **формат 2**: ровно четыре безопасных ZIP_STORED entry: `manifest.json`, `scenario/blueprint.json`, `source/provenance.json`, `world.sqlite`. Приватная лицензия только `private_use_only`, `publication_authorized=false`, модель `none`, статус `private_classic_structural`. Старый v1 ZIP с тремя файлами не менялся.
4. Python `tools/bookworld/private_bookworld.py`: детерминированный `build`/строгий `verify`, повторное доказательство каждой цитаты по локальному исходному `BookSourceIndex` с правильной UTF-16 разбивкой, без помещения исходного текста в архив. Верификатор проверяет также ZIP local/central, отсутствие traversal, корректный SQLite, точность provenance, права, двух достижимых концовок и отсутствие безвыходных циклов.
5. Независимый Dart `PrivateBookworldImporter` строго проверяет тот же ZIP+manifest+source refs+SQLite и повторно симулирует причинный граф; `BookworldImporter` v1 **не принимает** v2. `BookworldCampaignStore` сохраняет оба формата в старой SQLite-библиотеке, без миграции, с отдельными кампаниями и прежним `.bwsave`.
6. `shared_schemas/fixtures/private_classic_sample.json` — только собственный тестовый материал: точные hash цитат из двух глав, две концовки, 20 повторных ходов. Тесты Python, Dart importer, story_core, campaign_manager: условия, последствия, восстановление после рестарта, перенос сейва в другую приватную папку, legacy parity и негативные ZIP/rights/citation/causality тесты.
7. CI `.github/workflows/android-ci.yml` создаёт реальный v2 ZIP/SQLite **после независимой Python-проверки** и перед Dart `bookworld_format`/campaign tests. В этом PR пока нет релизной поддержки новой функции на пользовательском экране — это отдельный этап.

## Как собрать локально для проверки

Это программный CLI, не пользовательский мастер. На входе **обязательно** должны быть результаты предыдущего доверенного Dart-пайплайна, а не придуманные JSON от LLM:

```bash
python3 -m tools.bookworld.private_bookworld build \
  --blueprint private_blueprint.json \
  --provenance private_provenance.json \
  --index private_source_index.json \
  --output my_private_story.bworld
python3 -m tools.bookworld.private_bookworld verify --input my_private_story.bworld
```

`source_index` используется только локально во время сборки и проверяет, что SHA цитаты соответствует **точному диапазону UTF-16** книги. Портативный архив не содержит исходную книгу целиком: повторная проверка на другом устройстве обеспечивает лишь **структурную целостность пакета и заявленных хешей**, а не независимое доказательство исторической истины, лицензионных прав или подлинности цитат без оригинала. SHA256 **не электронная подпись**.

## Что НЕ реализовано и что блокирует полноценную пользовательскую подготовку

- Автоматический реальный литературный семантический анализ — нет реальной модели, только локальные предположения; нет проверенной объединённой идентичности персонажей, NPC knowledge, мотивов, всего таймлайна.
- Редактор канона/сцен с видимыми объяснениями конфликтов и ручной подготовкой **игровых** действий; UI для экспорта v2 из одной кнопки отсутствует. Временная программа-автор требует одобрения сценария.
- Native Dart/Flutter writer v2 для прямой сборки архива на Android (пока Python CLI доступен на ПК; Android может импортировать готовый пакет); безопасное разрешение прав/публикации отдельно.
- Ручной Windows/Android E2E на физическом устройстве, нагрузка больших книг, доступность и сложные альтернативные сценарии.
- Облачная отправка текста, BYOK, настройки провайдера, тарифы и AI_FREEFORM — **запрещены** до отдельного согласия и QA.

## Gates

Статус этого PR: CODE / **CI PENDING**. Требуется exact SHA Flutter analyze+full tests, Dart/Python, `story_core`, Windows portable, Android APK и M0; после merge ещё push(main) CI и фактический Release. Без завершения этого процесса не объявлять v2 готовым для установки.

Следующий этап: привязать один мастер к проверке редактора, безопасному локальному builder на обеих платформах, показать реальные blockers и кнопку «Начать игру» только для успешно импортированного v2 мира; полный E2E на авторском рассказе. Потом уже подключать модель.
