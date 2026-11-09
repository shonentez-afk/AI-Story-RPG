> **Новый функциональный пакет, ожидает новый CI:** добавлены `confirm_suggestion` (replay + настоящее согласие + неизменный fingerprint/expected_revision), `journal_page` (revision, cursor, page, state_hash), `export_bundle / inspect_bundle / import_bundle` для одного **локального** переносимого private `.bworld + .bwsave`. Перенос содержит hash, replay/checksum; при пустой библиотеке `inspect_bundle` показывает `save_replay_verified: false` до реального импорта с согласия. В отличие от генераторского E6m `snapshot-private` он НЕ содержит приватные запросы ChatGPT Skill. Содержимое архива — приватно, никогда не выкладывать в GitHub Actions. [Полная матрица готовности](RPG_ENGINE_CLIENT_AUTONOMY_AUDIT_RU_2026-11-09.md).

# AI Story RPG — единый протокол клиентов v1 (код нового пакета, ожидание exact CI)

9 ноября 2026. Функциональный пакет для Draft PR #133. **До завершения exact-head GitHub Actions код НЕ объявлять принятым.** Ссылки и окончательный status обновить после CI.

## Назначение и неизменяемые границы

- Есть **один** игровой исполнитель: story_core / story_runtime_adapter / campaign_manager / rpg_gameplay, доступ через rpg_api. Ни Python, ни HTTP-сервер не считают игровые правила, не подписывают выдуманные события, не пишут SQLite самостоятельно.
- rpg_api содержит независимый от транспорта RpgClientProtocol с **единым safe-JSON представлением**: текущая сцена, проверенный origin текущей главы, герой, предметы только в наличии, встреченные NPC, подтверждённая память/доверие, диалоги, выборы и журнал. **Нельзя** выгружать blueprint целиком, будущие сцены или непроверенную приватную биографию NPC.
- CLI и HTTP используют один RpgClientProtocol.projectView. Публичный protocol теперь также предлагает read-only world intake/causal audit и безопасную подсказку разрешённого хода. Старый CLI сохраняет существующие команды и основные поля.
- apps/rpg_cli/lib/rpg_loopback_server.dart — **только платформенный адаптер**. Открывает один private SQLite store, запускает LocalRpgGameApi, serializes requests и принимает только POST /v1/rpg.
- apps/rpg_cli/python_client.py — **настоящий клиент другого языка**, использует стандартную библиотеку Python и JSON. Код игры в нём отсутствует.

## Запуск

Из apps/rpg_cli:

    dart pub get
    dart run bin/rpg_server.dart --store /PRIVATE/rpg-db --port 0

Ответ запуска (stdout) — JSON с endpoint, token и protocol; сохранить токен как секрет текущей сессии. Можно предварительно задать AI_RPG_HOST_TOKEN длиной не менее 32 символов. Для ручного Python-клиента:

    python3 python_client.py --endpoint http://127.0.0.1:PORT/v1/rpg \
      --token SECRET --op capabilities

Нельзя запускать на внешнем сетевом интерфейсе. Отсутствуют CORS/Origin разрешения: браузерная страница не может незаметно использовать локальный сервер. Другой локальный клиент должен предоставить секретный x-rpg-token. Токен и содержимое приватных книг никогда не логируются в HTTP host. Проверять права доступа к каталогу SQLite — обязанность запускающего пользователя. На этом этапе **это не публичный облачный API и не полноценный Web runtime**.

## Запрос и ответ

Все запросы: Content-Type: application/json, Header: x-rpg-token: SECRET, POST /v1/rpg.

    {"version":"ai_story_rpg_client_v1","op":"capabilities","args":{}}

Успех:

    {"version":"ai_story_rpg_client_v1","ok":true,"result":{...}}

Отказ (без стека и путей):

    {"version":"ai_story_rpg_client_v1","ok":false,"error":{"code":"invalid_input"}}

Коды: unsupported_version, invalid_input, invalid_state, engine_error. HTTP host также отвечает 401 unauthorized, 403 forbidden_origin, 404 not_found, 405 method_not_allowed, 413 request_too_large и 415 invalid_content_type. Protocol version независим от package sdk_version=0.1.0; менять несовместимо без v2 и тестов миграции.

Основные op:

| Операция | Аргументы | Результат |
|---|---|---|
| capabilities, worlds | нет | Политика доступных режимов / список установленных миров |
| inspect_world | archive_base64, readiness_json? | Read-only native intake: SHA, главы, сцены, NPC, предметы и правдивые generator claims; не выдаёт литературную аттестацию |
| audit_world | archive_base64, max_states?, max_moves? | Настоящий StoryWorld causal audit со статусом playable/blocked/inconclusive; inconclusive — не успех |
| suggest_action | campaign_id, text | Только подсказки существующих разрешённых choiceId по текущему verified view; **не** динамический AI-GM |
| install_world | archive_base64 | Verified native BookWorld; source/gameplay rules не дублируются |
| export_world, delete_world | world_hash | Приватный архив / подтверждение удаления |
| campaigns | world_hash? | Список с revision |
| start | world_hash, parent_id? | Новая игровая сессия и полный safe-view |
| view | campaign_id | Safe-view из проверенного SQLite-replay |
| choose | campaign_id, action_id, choice_id, expected_revision | applied/duplicate/reason и актуальная верифицированная проекция |
| delete_campaign | campaign_id, expected_revision | Подтверждение удаления |
| export_save | campaign_id | Приватный .bwsave JSON |
| preview_save, import_save | world_hash, save_text | Безопасный предпросмотр / новая сохранённая кампания |
| prepare_book | filename, book_base64, selected_chapter? | Offline indexed source status, **не** обещание готовой RPG |
| inspect_creation | intent, source_fingerprint? | Реальная политика режима; CANON/free-world/AI freeform пока честно запрещены |

Все строковые IDs и поля аргументов проверяются; неиспользуемые ключи запрещены. Сохранения лимитированы 2 МБ, книги 16 МБ для этого JSON adapter, архивы 64 МБ в core protocol; HTTP-host принимает не более 24 МБ в одном POST (для больших приватных архивов нужен stream/chunked adapter отдельным E2E). Это ограничения **транспорта**, не ограничения core BookWorld v4.

## Приёмка

- apps/rpg_cli/test/rpg_loopback_server_test.dart: действительный SQLite, приватный rich-v3, HTTP и прямой RpgClientProtocol, одинаковые безопасные решения/NPC/предметы/журнал, idempotent action, save/restore, отказ чужого hash; 401/403/version негативные проверки.
- apps/rpg_cli/test_python_client.py: **Python subprocess** запускает настоящий Dart server, устанавливает проверенный мир, исполняет wait, проверяет NPC/журнал, создаёт и импортирует portable save через реальный SQLite, проверяет fail-closed несоответствие world_hash.
- .github/workflows/android-ci.yml запускает Dart-тесты CLI, server --help и реальный Python cross-language E2E после генерации синтетического fixture.
- tools/ci_check_engine_boundaries.py запрещает потерю чистой API-границы и скрытый второй RPG runtime в host.
- Flutter widget-тесты приведены к новой единой кнопке «Добавить книгу или RPG».

**Не закрывается этим пакетом:** настоящий литературный CANON, роль BOOK_CHARACTER, динамический AI-GM, весь авторский многоактный GUI workflow, Browser/JS runtime, 2 настоящие RU FB2 и физические Win/Android испытания. Следующий большой шаг — режимы и книжная причинность, а не новые кнопки.

См. общий план docs/RPG_ENGINE_FULL_AUTONOMY_MULTICLIENT_PLAN_RU_2026-11-09.md.
