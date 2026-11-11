> **ОБНОВЛЕНИЕ ПОСЛЕ CI:** код `46308802b15be6ed6afc2c191ae902ba24322aa5` [CI #1090 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42562198099). Устранён обнаруженный ранее непосредственный FORMAT→Flutter разрыв: **все три**, а не два, вызова `RichPrivateBookworldImporter().inspect` в `whole_book_npc_campaign_page.dart` перенесены на `LocalRpgAuthoringApi().inspectPrivateWorld`. Игровой `WorldGameView` теперь сам выдаёт source-reviewed постоянную личность книжного героя; начальные вещи/знания и условные действия компилирует native v4 authoring с истинным source SHA и consent. Функциональность переносима через JSON SDK. Остальная матрица ограничений ниже актуальна: полный CANON, динамический AI-GM, все authoring DTO и Browser/FFI не реализованы. Генератор 0.3.0a18, отдельный CI #429 PASS, native author #430 FAIL.

> **ЗАКЛЮЧЕНИЕ И ПРИЁМКА:** code SHA `071ed2b07bec9cc863aa22583288688337ed9eae`, [AI Story RPG CI #1087](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128159) **COMPLETED SUCCESS**, [M0 #1172](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42558128175) SUCCESS; все новые чистые SDK/SQLite/HTTP/Python и BookWorld v4 transfer tests PASS, Flutter, Windows/Android сборки PASS. Формулировки ниже «пакет ожидает CI» — исторический план на момент написания; текущая приёмка завершена. **Дополнительный реальный архитектурный разрыв:** Flutter `apps/story_reader/lib/whole_book_npc_campaign_page.dart` дважды вызывает `RichPrivateBookworldImporter().inspect` напрямую (примерно 625 и 682 строки), вместо публичного `RpgAuthoringApi.inspectPrivateWorld`. Это read-only форматная проверка, **не второй движок**, но требуется вынести из клиентского мастера в следующем большом блоке. Проекция игры/SQLite остаётся независимой. Генератор уже E6m/0.3.0a16, [CI #420 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42556984326); native external pinned author CI #423 FAIL. **Полной литературной RPG по любой книге нет.**

# Аудит самостоятельности движка и пригодности для других клиентов — 2026-11-09

**Аудит по исходникам native Draft PR #133.** Базовый проверенный SHA: \`43930247ef0d2b3e67de7d05ac629fe5a9dd45a4\`, [CI #1084 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42555732659). Новый общий пакет переноса и атомарно проверяемых команд **считать принятым только после exact-head CI**. Отдельная верификация на настоящих устройствах требуется независимо от сборочного CI.

## 1. Как теперь устроена независимость

**Один авторитетный игровой исполнитель** — \`story_core\` + \`story_runtime_adapter\` + \`campaign_manager\` + \`rpg_gameplay\`. В этих пакетах: состояния, реальные разрешённые переходы, NPC память/отношения/знания/жизненные статусы, передача предметов, причинность, replay, SQLite, \`.bwsave\`, герой и журнал. Публичный \`rpg_api\` предоставляет game/authoring/workflow/creation/intake/audit и чистый \`RpgClientProtocol\`. Ему не требуются Flutter, модель, HTTP или доступ к GUI.

- Flutter — первый клиент. Его UI и платформенная сеть/согласия могут использовать публичный Dart API; внутрь UI не должны возвращаться игровые правила.
- \`apps/rpg_cli\` — второй клиент: команды установки, прохождения, переноса save, подготовки книги без Flutter.
- \`RpgLoopbackServer\` — **адаптер**, не движок: доверенный локальный процесс открывает приватный SQLite store и сериализует обращения к единому \`RpgClientProtocol\`.
- \`apps/rpg_cli/python_client.py\` — клиент другого языка. Для безопасности он принудительно игнорирует HTTP_PROXY, допускает только loopback и требует секретный \`x-rpg-token\`. Нет собственного интерпретатора \`StoryWorld\`, SQL-правил, генератора выбора или NPC-кода.
- Генератор **E6m / 0.3.0a16** — отдельный ChatGPT Skill-first автор/валидатор; [его CI #420 SUCCESS](https://github.com/shonentez-afk/AI-Story-RPG/actions/runs/42556984326) по SHA \`ce221f0454a5be61de6bc39297e11cc070342680\`. Его личный \`snapshot-private\` (исходная книга, задания и ответы) **НЕ** подменяет перенос игровой кампании между клиентами.

## 2. Последний крупный пакет — прямые последствия аудита

| Разрыв до пакета | Решение в автономном API | Отрицательная приёмка |
|---|---|---|
| \`.bwsave\` без установленного \`.bworld\` невозможно открыть в чистом клиенте | \`RpgCampaignTransfer\`: самоописательный **приватный** \`ai_story_rpg_campaign_transfer_v1\` с точными исходными ZIP и save, digest, stateHash; \`export_bundle / inspect_bundle / import_bundle\` | Tamper-proof envelope, отдельное явное согласие, fail-closed replay, rollback при новой невалидной установке, не заменять старые кампании |
| Предложение свободного текста и сам ход — разные операции клиента | \`confirm_suggestion\` снова получает state из SQLite, сверяет revision, head fingerprint, исходный текст и ровно один включённый \`choiceId\`, требует \`user_confirmed\`, только после этого использует \`RpgGameApi.choose\` | Скрытый выбор, чужой fingerprint, устаревшая ревизия и отсутствие согласия не меняют игру |
| У стороннего клиента нет дешёвого безопасного доказательства текущего состояния | \`WorldGameView.stateHash\` прямо из \`story_core\`, \`state_hash\` в общем JSON DTO | В v3/v4 исходник и новый клиент получают одинаковый state hash после точного replay |
| Полный журнал передаётся целиком | \`journal_page\` c \`after_sequence/limit\`, revision/CAS, stateHash и \`has_more\` | Неверный курсор, revision mismatch и limit > 100 отклоняются |
| Риск утечки приватного архива при системной настройке HTTP_PROXY | Python-клиент использует \`build_opener(ProxyHandler({}))\`, только loopback | Тест запрета перенаправления и повторный HTTPS/HTTP транспортный guard |
| Миграция и совместимость v4 между устройствами не доказаны | Два отдельных SQLite-хранилища, перенос через Python → HTTP → Dart; новый Dart smoke для v4 с повторным открытием SQLite | Нет источника/мира → перенос проверяется до записи и только после явного подтверждения |

**Важная квалификация:** \`inspect_bundle\` в **пустой** библиотеке проверяет ZIP и SHA envelope, но **не** утверждает, что save replay проверен. Оно показывает \`save_replay_verified: false\`; полная проверка выполняется при \`import_bundle\`, когда оригинальный мир установлен в локальном доверенном хранилище. \`RpgCampaignTransfer\` — локальная переносимость, не цифровая подпись от издателя и не лицензия на распространение.

## 3. Формальная матрица готовности (честная, не маркетинговая)

| Область | Текущий вывод |
|---|---|
| Правила игры и SQLite работают без Flutter | **Да**, многократно покрыто native CI |
| Независимый клиент на Dart и реальный Python по HTTP | **Да**, локально на том же устройстве; нет второго rule engine |
| Private BookWorld v3/v4, NPC, item custody, journal, save transfer | **Да** для протестированных сценариев; на новых переносимых bundles требуется новый exact-head CI |
| Устойчивый API с revisions, action IDs, state digest и пагинацией | **Реализуется текущим пакетом**; версия \`ai_story_rpg_client_v1\` добавляет необязательные операции/поля |
| Полный перенос игры в пустую библиотеку без потери причинности | **Реализуется текущим пакетом**; нет обещания атомарного восстановления целой коллекции многотысячных кампаний |
| Адаптер к любому языку через локальный JSON | **Да**, при возможности запустить Dart-host; нет обещания публичного cloud API |
| Нативный браузер без dart:io/SQLite, FFI или удалённый многопользовательский сервер | **Нет**, это отдельные платформенные адаптеры и безопасность, а не повторный игровой движок |
| Все authoring/editor API в плоском JSON для не-Dart клиентов | **Нет**. Source-locked authoring/prose/NPC workflow на Dart API есть, но перенос типизированных редакторских моделей и длительные операции через JSON неполон |
| Любой книжный CANON, полноценная BOOK_CHARACTER с достоверными исходными фактами/предметами | **Нет**, режимы не должны ложно объявляться поддерживаемыми |
| Dynamic AI-GM, произвольное новое действие, подписанное story_core последствие | **Нет**. Сейчас safe free text работает только с уже существующими разрешёнными choice IDs |
| Media/портреты в self-contained game transfer, автоматическое предоставление литературно проверенной игры | **Нет**. Flutter local portrait storage не равен обязательному archive manifest |
| Комплексная native ↔ генератор E6m совместимость | **Нет**. Отдельная генераторская ветка CI PASS, а прежний native PR External author CI #415 FAIL с pinned contract_drift и stale Dart parity |
| Два реальных русских FB2 с литературной проверкой и физический Windows/Android E2E | **Нет**. CI сборок не заменяет независимое литературное и ручное тестирование |

## 4. Следующий **один большой** блок без микро-PR

**Приоритет — закрытие книжной RPG-семантики, а не новые кнопки.** Пройти source-reviewed настоящий CANON без ложного второго канонического финала, BOOK_CHARACTER с допустимыми начальными знаниями/предметами и source-revision binding, проверяемый свободный AI-input -> typed proposal -> human consent -> story_core commit/replay. Обеспечить тот же контракт через \`rpg_api\` и уже созданный JSON protocol, не создавать «второй движок» в Flutter/Python.

Затем завершить единый authoring workflow для произвольной большой книги, согласовать точные E6m native pins и независимый parity не ослабляя doctor, провести 2 реальные русские FB2, физическое Win/Android прохождение, перенос уже созданного \`.bworld\` и игрового состояния. Только после этого можно считать **основное направление** завершённым.

Документы: [START_NEW_CHAT_RU](../START_NEW_CHAT_RU.md), [полный план](RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md), [v1 протокол](RPG_CLIENT_PROTOCOL_V1_RU_2026-11-09.md). **Одно PR #133, без микро-PR; main и генераторную ветку не менять**.
